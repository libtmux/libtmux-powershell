param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [Parameter(Mandatory)] [string] $OutputPath,
    [ValidateSet('startup', 'session', 'window', 'pane', 'unknown', 'cancel', 'replacement')]
    [string] $Case = 'startup'
)

# Outer integration: real creation receipts must retain cleanup before an owner is returned.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$manifest = "$ModuleRoot/LibTmux/0.1.0/LibTmux.psd1"
Import-Module $manifest
$checks = 0
function Assert-Recovery([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Acquisition recovery: $Message" }
    $script:checks++
}
function Set-Fault([string] $Value) {
    [IO.File]::WriteAllText($env:LIBTMUX_ORDINARY_FAULT, $Value)
    foreach ($extension in @('.created', '.entered')) {
        $marker = [IO.Path]::ChangeExtension($env:LIBTMUX_ORDINARY_FAULT, $extension)
        if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker }
    }
}
function Assert-Record($Record) {
    Assert-Recovery ($null -ne $Record.BodyFailure) 'original acquisition failure was lost'
    Assert-Recovery ($Record.CleanupFailure.ToString().Contains('injected acquisition rollback failure')) 'rollback failure was lost'
    $owners = [LibTmux.OwnedScope]::CleanupOwners($Record.BodyFailure)
    Assert-Recovery (@($owners | Where-Object { [object]::ReferenceEquals($_, $Record.Owner) }).Count -eq 1) 'record did not retain the accepted core owner'
    Assert-Recovery ([object]::ReferenceEquals(($Record.Owner | Get-TmuxScopeFailure), $Record)) 'owner query returned a different failure'
}
Set-Fault ''
Assert-Recovery (@(Get-TmuxScopeFailure -Pending).Count -eq 0) 'test began with pending failures'
$endpoint = New-TmuxServer
if ($Case -eq 'startup') {
    Set-Fault 'startup'
    $failure = $null
    try { $null = Start-TmuxServer -ErrorAction Stop } catch { $failure = $_.Exception }
    Assert-Recovery ($failure -and $failure.ToString().Contains('injected acquisition startup failure')) 'startup error was replaced'
    $records = @(Get-TmuxScopeFailure -Pending)
    Assert-Recovery ($records.Count -eq 1) 'pre-result startup lost its retry owner'
    Assert-Record $records[0]
    Assert-Recovery ($null -ne $endpoint.InspectAsync().GetAwaiter().GetResult()) 'failed rollback did not leave its daemon'
    Set-Fault ''
    $records[0].Owner | Close-TmuxScope
    $records[0].Owner | Close-TmuxScope
    Assert-Recovery ($null -eq $endpoint.InspectAsync().GetAwaiter().GetResult()) 'startup retry left its daemon'
    Assert-Recovery ([object]::ReferenceEquals(($records[0].Owner | Get-TmuxScopeFailure), $records[0])) 'successful retry removed history'
} else {
    $server = Start-TmuxServer
    $keeper = $server | New-TmuxSession -Name keeper -WindowName keeper
    $window = $keeper | Get-TmuxWindow | Select-Object -First 1
    $pane = $window | Get-TmuxPane | Select-Object -First 1
    $failure = $null
    if ($Case -eq 'cancel') {
        Add-Type -Path "$PSScriptRoot/support/SocketCreatedSignal.cs"
        $marker = [IO.Path]::ChangeExtension($env:LIBTMUX_ORDINARY_FAULT, '.entered')
        Set-Fault 'cancel-session'
        $signal = [LibTmux.Testing.SocketCreatedSignal]::new((Split-Path $marker), (Split-Path $marker -Leaf))
        $state = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
        $state.ImportPSModule(@($manifest))
        $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
        $runspace.Open()
        $pipeline = [Management.Automation.PowerShell]::Create()
        $pipeline.Runspace = $runspace
        try {
            $null = $pipeline.AddScript({
                $ErrorActionPreference = 'Stop'
                New-TmuxServer | New-TmuxSession -Name canceled-acquisition -Owned
            })
            $pending = $pipeline.BeginInvoke()
            if (!$signal.Ready.Wait(5000)) { throw 'Acquisition did not reach readback cancellation.' }
            $stop = $pipeline.BeginStop($null, $null)
            if (!$stop.AsyncWaitHandle.WaitOne(7000)) { throw 'Acquisition cancellation exceeded its deadline.' }
            $pipeline.EndStop($stop)
            try { $pipeline.EndInvoke($pending) } catch { $failure = $_.Exception }
        } finally {
            $pipeline.Dispose()
            $runspace.Dispose()
            $signal.Dispose()
        }
    } else {
        $kind = if ($Case -in @('unknown', 'replacement')) { 'session' } else { $Case }
        $fault = if ($Case -eq 'unknown') { 'unknown-session' } else { "readback-$kind" }
        Set-Fault $fault
        try {
            switch ($kind) {
                session { $null = $server | New-TmuxSession -Name first-recovery -Owned }
                window { $null = $keeper | New-TmuxWindow -Name first-recovery -Owned }
                pane { $null = $pane | Split-TmuxPane -Owned }
            }
        } catch { $failure = $_.Exception }
    }
    Assert-Recovery ($null -ne $failure) 'injected acquisition returned success'
    $records = @(Get-TmuxScopeFailure -Pending)
    if ($Case -eq 'unknown') {
        Assert-Recovery ($records.Count -eq 0) 'unknown receipt invented cleanup authority'
        Set-Fault ''
        Assert-Recovery (@($server | Get-TmuxSession -Name first-recovery).Count -eq 1) 'unknown creation was not observed'
    } else {
        Assert-Recovery ($records.Count -eq 1) 'pre-result child failure lost its retry owner'
        Assert-Record $records[0]
        if ($Case -eq 'cancel') {
            Assert-Recovery ($records[0].BodyFailure -is [OperationCanceledException]) 'cancellation error was replaced in the record'
        } else {
            Assert-Recovery ($records[0].BodyFailure.ToString().Contains('injected acquisition readback failure')) 'readback failure was replaced'
        }
        Assert-Recovery ($records[0].Owner.GetType().FullName -ceq 'LibTmux.Internal.OwnedCleanup') 'test did not reach a raw receipt owner'
        Set-Fault ''
        if ($Case -eq 'replacement') {
            $process = [Diagnostics.Process]::GetProcessById($server.Generation.ProcessId)
            try {
                $server | ConvertTo-TmuxOwnedResource | Close-TmuxScope
                Assert-Recovery ($process.WaitForExit(5000)) 'accepted old daemon did not exit'
            } finally { $process.Dispose() }
            $replacement = Start-TmuxServer
            $next = $replacement | New-TmuxSession -Name preserved
            $failed = $false
            try { $records[0].Owner | Close-TmuxScope } catch {
                $failed = $true
                Assert-Recovery ($_.Exception -is [LibTmux.StaleServerGenerationException]) 'stale cleanup lost its identity error'
            }
            Assert-Recovery $failed 'raw recovery accepted a replacement daemon'
            Assert-Recovery (@($replacement | Get-TmuxSession -Name preserved).Count -eq 1) 'stale retry destroyed replacement state'
            Assert-Recovery (@(Get-TmuxScopeFailure -Pending).Count -eq 1) 'failed stale retry lost its pending owner'
        } else {
            $records[0].Owner | Close-TmuxScope
            $records[0].Owner | Close-TmuxScope
            Assert-Recovery ([object]::ReferenceEquals(($records[0].Owner | Get-TmuxScopeFailure), $records[0])) 'raw retry removed history'
            Assert-Recovery (@($server | Get-TmuxSession -Name keeper).Count -eq 1) 'child retry removed its parent or sibling'
            Assert-Recovery (@($server | Get-TmuxSession).Count -eq 1 -and
                @($keeper | Get-TmuxWindow).Count -eq 1 -and @($window | Get-TmuxPane).Count -eq 1) 'child retry left its resource'
        }
    }
}
if ($Case -ne 'replacement') {
    Assert-Recovery (@(Get-TmuxScopeFailure -Pending).Count -eq 0) 'successful retry left a pending record'
}
$borrowedRejected = $false
try { $endpoint | Close-TmuxScope } catch { $borrowedRejected = $_.Exception -is [ArgumentException] }
Assert-Recovery $borrowedRejected 'borrowed server gained cleanup authority'
[pscustomobject] @{ Passed = $true; Assertions = $checks; Case = $Case } |
    ConvertTo-Json | Set-Content -LiteralPath $OutputPath
