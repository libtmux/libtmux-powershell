param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [Parameter(Mandatory)] [ValidateSet('absent', 'running')] [string] $InitialState,
    [Parameter(Mandatory)] [string] $OutputPath
)

# Outer integration: exercise public startup and failed handoff inside the shared supervisor.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$manifest = "$ModuleRoot/LibTmux/0.1.0/LibTmux.psd1"
Import-Module $manifest
. "$PSScriptRoot/support/HelpExampleAssertions.ps1"
$checks = 0
$endpoint = New-TmuxServer
function Assert-Start([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Server startup: $Message" }
    $script:checks++
}
function Find-Current { $endpoint.InspectAsync().GetAwaiter().GetResult() }
function Stop-Current {
    $live = Find-Current
    if ($live) { $live | ConvertTo-TmuxOwnedResource | Close-TmuxScope }
    Assert-Start ($null -eq (Find-Current)) 'test-owned daemon remains after explicit cleanup'
}
$beforeWhatIf = if (Test-Path -LiteralPath $env:LIBTMUX_ORDINARY_TRACE) {
    [IO.File]::ReadAllLines($env:LIBTMUX_ORDINARY_TRACE).Length
} else { 0 }
$empty = @(Start-TmuxServer -WhatIf)
$afterWhatIf = if (Test-Path -LiteralPath $env:LIBTMUX_ORDINARY_TRACE) {
    [IO.File]::ReadAllLines($env:LIBTMUX_ORDINARY_TRACE).Length
} else { 0 }
Assert-Start ($beforeWhatIf -eq $afterWhatIf) 'WhatIf dispatched tmux'
Assert-Start ($empty.Count -eq 0) 'WhatIf emitted a server'
if ($InitialState -eq 'absent') { Assert-Start ($null -eq (Find-Current)) 'WhatIf started an absent daemon' }
$initialOptions = if ($InitialState -eq 'running') {
    ($endpoint | Invoke-TmuxCommand -Arguments @('show-options', '-s')).StandardOutputLines -join "`n"
}
$help = Get-Help Start-TmuxServer -Full
$helpCode = Get-HelpExampleCode $help.examples.example[0] 'Start-TmuxServer'
Assert-Start ($helpCode.Trim() -ceq "Import-Module LibTmux`nStart-TmuxServer") 'packaged startup example drifted'
$first = & ([scriptblock]::Create($helpCode))
Assert-Start ($first -is [LibTmux.Server] -and $first.IsMaterialized) 'startup did not return an ordinary materialized server'
if ($InitialState -eq 'absent') {
    Assert-Start (@($first | Get-TmuxSession).Count -eq 0) 'startup left a bootstrap session'
} else {
    Assert-Start ((($first | Invoke-TmuxCommand -Arguments @('show-options', '-s')).StandardOutputLines -join "`n") -ceq $initialOptions) 'startup changed existing server options'
}
[GC]::Collect()
[GC]::WaitForPendingFinalizers()
$repeated = $endpoint | Start-TmuxServer
Assert-Start ($repeated.Generation -eq $first.Generation) 'repeated startup replaced the daemon'
$session = $first | New-TmuxSession -Name start-preserve -WindowName work
$null = $session | New-TmuxWindow -Name logs
$null = $first | Invoke-TmuxCommand -Arguments @('set-option', '-s', 'exit-empty', 'on')
$before = $first | Get-TmuxSnapshot
$setting = ($first | Invoke-TmuxCommand -Arguments @('show-options', '-sv', 'exit-empty')).StandardOutputLines -join ''
$again = $first | Start-TmuxServer
$after = $again | Get-TmuxSnapshot
Assert-Start (($before.Panes.Id -join ',') -ceq ($after.Panes.Id -join ',') -and
    ($before.Windows.Id -join ',') -ceq ($after.Windows.Id -join ',') -and
    ($before.Sessions.Id -join ',') -ceq ($after.Sessions.Id -join ',')) 'reuse changed the existing graph'
Assert-Start (($again | Invoke-TmuxCommand -Arguments @('show-options', '-sv', 'exit-empty')).StandardOutputLines[0] -ceq $setting) 'reuse reset exit-empty'
$priorToken = ($endpoint | Invoke-TmuxCommand -Arguments @('show-options', '-sv', '@libtmux_owner_generation')).StandardOutputLines -join ''
foreach ($token in @('0123456789abcdef0123456789abcdef', 'malformed-owner-token')) {
    $null = $endpoint | Invoke-TmuxCommand -Arguments @('set-option', '-s', '@libtmux_owner_generation', $token)
    $selected = Start-TmuxServer
    Assert-Start ($selected.Generation -eq $first.Generation) 'existing token caused replacement'
    Assert-Start (($endpoint | Invoke-TmuxCommand -Arguments @('show-options', '-sv', '@libtmux_owner_generation')).StandardOutputLines[0] -ceq $token) 'ensure rewrote an existing ownership token'
}
$null = $endpoint | Invoke-TmuxCommand -Arguments @('set-option', '-s', '@libtmux_owner_generation', $priorToken)
Stop-Current

foreach ($existing in @($false, $true)) {
    foreach ($cancel in @($false, $true)) {
        foreach ($injectCleanup in @($false, $true)) {
            $baseline = $null
            if ($existing) {
                $baseline = Start-TmuxServer
                $null = $baseline | New-TmuxSession -Name keep-on-failure -WindowName keep
            }
            $entered = [Threading.ManualResetEventSlim]::new($false)
            $state = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
            $state.ImportPSModule(@($manifest))
            $state.Variables.Add([Management.Automation.Runspaces.SessionStateVariableEntry]::new('entered', $entered, 'Handoff signal'))
            $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
            $runspace.Open()
            $pipeline = [Management.Automation.PowerShell]::Create()
            $pipeline.Runspace = $runspace
            try {
                $null = $pipeline.AddScript({
                    param($cancel, $injectCleanup)
                    $ErrorActionPreference = 'Stop'
                    Start-TmuxServer | ForEach-Object {
                        $global:receivedServer = $_
                        if ($injectCleanup) { [IO.File]::WriteAllText($env:LIBTMUX_ORDINARY_FAULT, 'cleanup') }
                        $entered.Set()
                        if ($cancel) { $_ | Wait-TmuxChannel -Channel 'startup-handoff-cancel' -Timeout 20 }
                        else { throw 'startup downstream handoff sentinel' }
                    }
                }).AddArgument($cancel).AddArgument($injectCleanup)
                $pending = $pipeline.BeginInvoke()
                if (!$entered.Wait([TimeSpan]::FromSeconds(3))) { throw 'Startup did not enter downstream handoff.' }
                if ($cancel) {
                    $stop = $pipeline.BeginStop($null, $null)
                    if (!$stop.AsyncWaitHandle.WaitOne(7000)) { throw 'Startup handoff cancellation exceeded its deadline.' }
                    $pipeline.EndStop($stop)
                }
                $failure = $null
                try { $pipeline.EndInvoke($pending) } catch { $failure = $_.Exception }
                Assert-Start ($null -ne $failure) 'failed downstream handoff returned success'
                if (!$cancel) { Assert-Start ($failure.ToString().Contains('startup downstream handoff sentinel')) 'downstream error was lost' }
                $received = $runspace.SessionStateProxy.GetVariable('receivedServer')
                Assert-Start ($received -is [LibTmux.Server]) 'receiver got an owner instead of a server'
                $live = Find-Current
                $records = @(Get-TmuxScopeFailure -Pending)
                if ($existing) {
                    Assert-Start ($live.Generation -eq $baseline.Generation -and
                        @($live | Get-TmuxSession -Name keep-on-failure).Count -eq 1) 'failed handoff destroyed borrowed state'
                    Assert-Start ($records.Count -eq 0) 'borrowed handoff recorded destruction authority'
                } elseif ($injectCleanup) {
                    Assert-Start ($null -ne $live -and $records.Count -eq 1) 'cleanup failure lost its live daemon or retry owner'
                    Assert-Start ($null -ne $records[0].BodyFailure -and
                        $records[0].CleanupFailure.ToString().Contains('injected ordinary startup cleanup failure')) 'paired failure was lost'
                    [IO.File]::WriteAllText($env:LIBTMUX_ORDINARY_FAULT, '')
                    $records[0].Owner | Close-TmuxScope
                    Assert-Start ($null -eq (Find-Current) -and @(Get-TmuxScopeFailure -Pending).Count -eq 0) 'retry left a daemon or pending record'
                } else { Assert-Start ($null -eq $live) 'failed handoff leaked its new daemon' }
            } finally {
                [IO.File]::WriteAllText($env:LIBTMUX_ORDINARY_FAULT, '')
                $pipeline.Dispose()
                $runspace.Dispose()
                $entered.Dispose()
                Stop-Current
            }
        }
    }
}
[pscustomobject] @{ Passed = $true; Assertions = $checks; InitialState = $InitialState } |
    ConvertTo-Json | Set-Content -LiteralPath $OutputPath
