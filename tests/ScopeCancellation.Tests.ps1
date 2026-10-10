param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: native runspace cancellation must leave the scope's cleanup path available.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$manifest = "$ModuleRoot/LibTmux/0.1.0/LibTmux.psd1"
Import-Module $manifest
$server = New-TmuxServer
$checks = 0
foreach ($fault in @('', 'cleanup')) {
    $entered = [Threading.ManualResetEventSlim]::new($false)
    $state = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $state.ImportPSModule(@($manifest))
    $state.Variables.Add([Management.Automation.Runspaces.SessionStateVariableEntry]::new('entered', $entered, 'Scope entry signal'))
    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
    $runspace.Open()
    $pipeline = [Management.Automation.PowerShell]::Create()
    $pipeline.Runspace = $runspace
    $name = 'cancellation-' + [Guid]::NewGuid().ToString('N')
    try {
        $null = $pipeline.AddScript({
            param($name)
            $ErrorActionPreference = 'Stop'
            $global:acceptedOwner = New-TmuxServer |
                New-TmuxSession -Owned -Name $name
            $global:acceptedOwner | Invoke-TmuxScope {
                param($session)
                $entered.Set()
                $session.Server | Wait-TmuxChannel -Channel 'scope-cancel' -Timeout 20
            }
        }).AddArgument($name)
        $pending = $pipeline.BeginInvoke()
        if (!$entered.Wait([TimeSpan]::FromSeconds(2))) { throw 'Scope body did not reach its cancellation signal.' }
        [IO.File]::WriteAllText($env:LIBTMUX_SCOPE_FAULT, $fault)
        $stop = $pipeline.BeginStop($null, $null)
        if (!$stop.AsyncWaitHandle.WaitOne(7000)) { throw 'Pipeline cancellation did not finish bounded cleanup.' }
        $pipeline.EndStop($stop)
        $failure = $null
        try { $pipeline.EndInvoke($pending) } catch { $failure = $_.Exception }
        if ($null -eq $failure) { throw 'Stopped scope completed without a cancellation error.' }
        $checks++
        [IO.File]::WriteAllText($env:LIBTMUX_SCOPE_FAULT, '')
        $owner = $runspace.SessionStateProxy.GetVariable('acceptedOwner')
        $remaining = @($server | Get-TmuxSession -Name $name)
        if ($fault) {
            if ($remaining.Count -ne 1) { throw 'Cancellation cleanup injection did not retain the known session.' }
            $record = $owner | Get-TmuxScopeFailure
            if (!$record -or !$record.CleanupFailure.ToString().Contains('injected scope cleanup failure') -or
                $null -eq $record.BodyFailure -or
                ![object]::ReferenceEquals($record.Owner, $owner)) {
                throw 'Stopped pipeline lost its paired failure or retry owner.'
            }
            $owner | Close-TmuxScope
            $checks++
        } elseif ($remaining.Count -ne 0) { throw 'Stopped scope left its session alive.' }
        if (@($server | Get-TmuxSession -Name $name).Count -ne 0) { throw 'Cancellation retry left its session alive.' }
        $checks++
    } finally {
        [IO.File]::WriteAllText($env:LIBTMUX_SCOPE_FAULT, '')
        $pipeline.Dispose()
        $runspace.Dispose()
        $entered.Dispose()
    }
}
foreach ($fault in @('', 'cleanup')) {
    $name = 'handoff-' + [Guid]::NewGuid().ToString('N')
    $failure = $null
    [IO.File]::WriteAllText($env:LIBTMUX_SCOPE_FAULT, $fault)
    try {
        $server | New-TmuxSession -Name $name -Owned |
            ForEach-Object { throw 'downstream handoff sentinel' }
    } catch { $failure = $_.Exception }
    finally { [IO.File]::WriteAllText($env:LIBTMUX_SCOPE_FAULT, '') }
    if (!$failure -or !$failure.ToString().Contains('downstream handoff sentinel')) { throw 'Downstream error disappeared.' }
    if ($fault) {
        $retry = $null
        $cleanup = $null
        for ($item = $failure; $null -ne $item; $item = $item.InnerException) {
            if (!$retry) { $retry = $item.Data['LibTmux.PowerShell.Owner'] }
            if (!$cleanup) { $cleanup = [LibTmux.OwnedScope]::CleanupFailure($item) }
        }
        if (!$retry -or !$cleanup -or !$cleanup.ToString().Contains('injected scope cleanup failure')) {
            throw 'Failed handoff lost its paired cleanup failure or retry owner.'
        }
        $retry | Close-TmuxScope
        $checks++
    }
    if (@($server | Get-TmuxSession -Name $name).Count) { throw 'Failed owner handoff leaked its session.' }
    $checks++
}
# Stop a downstream receiver before the caller can save the owner. Cleanup failure
# must retain a public retry route even when PowerShell replaces its exception.
$entered = [Threading.ManualResetEventSlim]::new($false)
$state = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
$state.ImportPSModule(@($manifest))
$state.Variables.Add([Management.Automation.Runspaces.SessionStateVariableEntry]::new('entered', $entered, 'Handoff entry signal'))
$runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
$runspace.Open()
$pipeline = [Management.Automation.PowerShell]::Create()
$pipeline.Runspace = $runspace
$name = 'unreceived-' + [Guid]::NewGuid().ToString('N')
try {
    $null = $pipeline.AddScript({
        param($name)
        $ErrorActionPreference = 'Stop'
        New-TmuxServer | New-TmuxSession -Owned -Name $name |
            ForEach-Object { $entered.Set(); Start-Sleep -Seconds 20 }
    }).AddArgument($name)
    $pending = $pipeline.BeginInvoke()
    if (!$entered.Wait([TimeSpan]::FromSeconds(2))) { throw 'Owner handoff did not reach its cancellation signal.' }
    [IO.File]::WriteAllText($env:LIBTMUX_SCOPE_FAULT, 'cleanup')
    $stop = $pipeline.BeginStop($null, $null)
    if (!$stop.AsyncWaitHandle.WaitOne(7000)) { throw 'Owner handoff cancellation did not finish bounded cleanup.' }
    $pipeline.EndStop($stop)
    $failure = $null
    try { $pipeline.EndInvoke($pending) } catch { $failure = $_.Exception }
    if (!$failure -or @($server | Get-TmuxSession -Name $name).Count -ne 1) { throw 'Canceled handoff did not retain its known failed-cleanup session.' }
    $records = @(Get-TmuxScopeFailure -Pending | Where-Object { $_.Owner.Value.Name -ceq $name })
    if ($records.Count -ne 1 -or !$records[0].BodyFailure -or
        !$records[0].CleanupFailure.ToString().Contains('injected scope cleanup failure')) {
        throw 'Canceled handoff lost its unreceived owner or either error.'
    }
    [IO.File]::WriteAllText($env:LIBTMUX_SCOPE_FAULT, '')
    $records[0].Owner | Close-TmuxScope
    if (@($server | Get-TmuxSession -Name $name).Count -or @(Get-TmuxScopeFailure -Pending).Count) {
        throw 'Successful retry left a session or an unresolved failure record.'
    }
    $checks += 3
} finally {
    [IO.File]::WriteAllText($env:LIBTMUX_SCOPE_FAULT, '')
    $pipeline.Dispose()
    $runspace.Dispose()
    $entered.Dispose()
}
[pscustomobject] @{ Passed = $true; Assertions = $checks } | ConvertTo-Json -Compress
