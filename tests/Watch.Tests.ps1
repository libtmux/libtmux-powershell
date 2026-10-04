param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: installed callbacks, runspace lifecycle and owned real tmux.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$module = Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1'
Import-Module $module

function Assert-Watch([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Watch: $Message" }
}
Assert-Watch ($null -ne (Get-Command 'LibTmux\Watch-TmuxEvent' -ErrorAction SilentlyContinue)) 'installed module has no native Watch-TmuxEvent command'
$references = @([LibTmux.Server].Assembly.Location) + @(Get-ChildItem "$PSHOME/ref/*.dll" | Select-Object -ExpandProperty FullName)
Add-Type -Path "$PSScriptRoot/support/WatchProbe.cs" -ReferencedAssemblies $references -CompilerOptions '/nowarn:1701'

$offline = New-TmuxServer -SocketName watch-preview -TmuxBinaryPath '/missing-watch-preview'
Assert-Watch (@($offline | Watch-TmuxEvent -Target fixture -WhatIf).Count -eq 0) 'owned preview contacted tmux'
$preview = [LibTmux.Testing.WatchProbe]::new()
Assert-Watch (@($preview | Watch-TmuxEvent -WhatIf).Count -eq 0 -and !$preview.Subscribed.IsSet) 'borrowed preview consumed events'
foreach ($parameter in @('MaxEventBytes', 'MaxEvents', 'MaxOutputBytes')) {
    $invalid = @{ $parameter = 0 }
    $failed = $false
    try { $offline | Watch-TmuxEvent -Target fixture @invalid } catch {
        if ($_.Exception -isnot [Management.Automation.ParameterBindingException]) { throw }
        $failed = $true
    }
    Assert-Watch $failed 'invalid watch limit reached the endpoint'
}

function Get-WatchOutput([string] $Text) { [LibTmux.TmuxOutputEvent]::new([LibTmux.PaneId]::Parse('%1'), $Text) }
$probe = [LibTmux.Testing.WatchProbe]::new()
foreach ($text in @('one', 'two', 'three')) { $probe.Write((Get-WatchOutput $text)) }
$result = @($probe | Watch-TmuxEvent -MaxEvents 2 -MaxOutputBytes 100 | ForEach-Object { $probe.RecordCallback(); $_ })
Assert-Watch ($result.Count -eq 2 -and $result[0].Data -ceq 'one' -and $result[1].Data -ceq 'two' -and
    $probe.Reads -eq 2 -and $probe.EnumeratorDisposals -eq 1 -and $probe.ConnectionDisposals -eq 0) 'count limit, acknowledged delivery or borrowed ownership failed'

$probe = [LibTmux.Testing.WatchProbe]::new()
$probe.Write((Get-WatchOutput 'buffered'))
$failure = [IO.IOException]::new('injected watch stream failure')
$probe.Complete($failure)
$errors = @()
$result = @($probe | Watch-TmuxEvent -ErrorAction Continue -ErrorVariable errors 2>$null)
Assert-Watch ($result.Count -eq 1 -and $result[0].Data -ceq 'buffered' -and $errors.Count -eq 1 -and
    [object]::ReferenceEquals($errors[0].Exception, $failure) -and [object]::ReferenceEquals($errors[0].TargetObject, $probe) -and
    $probe.EnumeratorDisposals -eq 1 -and $probe.IsRunning) 'buffered output or original terminal error was lost'

$probe = [LibTmux.Testing.WatchProbe]::new()
$probe.Write((Get-WatchOutput 'cleanup'))
$probe.EnumerationCleanupFailure = [OperationCanceledException]::new('injected unrelated disposal cancellation')
$errors = @()
$result = @($probe | Watch-TmuxEvent -MaxEvents 1 -ErrorAction Continue -ErrorVariable errors 2>$null)
Assert-Watch ($result.Count -eq 1 -and $errors.Count -eq 1 -and
    [object]::ReferenceEquals($errors[0].Exception, $probe.EnumerationCleanupFailure)) 'unrelated enumerator disposal cancellation was swallowed'

foreach ($case in @('Event', 'Total')) {
    $probe = [LibTmux.Testing.WatchProbe]::new()
    $probe.Write((Get-WatchOutput ([string] [char] 0x00e9)))
    $probe.Write((Get-WatchOutput ([string] [char] 0x00e9)))
    $parameters = if ($case -eq 'Event') { @{ MaxEventBytes = 3 } } else { @{ MaxOutputBytes = 6 } }
    $errors = @()
    $result = @($probe | Watch-TmuxEvent @parameters -ErrorAction Continue -ErrorVariable errors 2>$null)
    $count = if ($case -eq 'Event') { 0 } else { 1 }
    Assert-Watch ($result.Count -eq $count -and $errors.Count -eq 1 -and $errors[0].Exception -is [IO.InvalidDataException] -and
        $probe.EnumeratorDisposals -eq 1 -and $probe.ConnectionDisposals -eq 0) "UTF-8 $case byte budget or cleanup failed"
}

$probe = [LibTmux.Testing.WatchProbe]::new()
$initial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
$initial.ImportPSModule(@($module))
$runspace = [RunspaceFactory]::CreateRunspace($initial)
$pipeline = [PowerShell]::Create()
try {
    $runspace.Open()
    $pipeline.Runspace = $runspace
    $null = $pipeline.AddCommand('LibTmux\Watch-TmuxEvent').AddParameter('Connection', $probe)
    $invocation = $pipeline.BeginInvoke()
    Assert-Watch ($probe.Subscribed.Wait(10000)) 'pending watch did not subscribe'
    $errors = @()
    $result = @($probe | Watch-TmuxEvent -MaxEvents 1 -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-Watch ($result.Count -eq 0 -and $errors.Count -eq 1 -and $errors[0].Exception -is [InvalidOperationException]) 'competing package watcher consumed the stream'
    $stop = $pipeline.BeginStop($null, $null)
    Assert-Watch ($stop.AsyncWaitHandle.WaitOne(1000)) 'pending watch did not stop promptly'
    $pipeline.EndStop($stop)
    Assert-Watch ($invocation.AsyncWaitHandle.WaitOne(1000)) 'stopped watch invocation stayed active'
    $stopped = $false
    try { $null = $pipeline.EndInvoke($invocation) } catch {
        if ($_.Exception.InnerException -isnot [Management.Automation.PipelineStoppedException]) { throw }
        $stopped = $true
    }
    Assert-Watch ($stopped -and $pipeline.Streams.Error.Count -eq 0 -and $probe.EnumeratorDisposals -eq 1 -and $probe.IsRunning) 'stop lost cancellation or disposed borrowed connection'
    $probe.Write((Get-WatchOutput 'after-stop'))
    Assert-Watch (($probe | Watch-TmuxEvent -MaxEvents 1).Data -ceq 'after-stop') 'stop did not release the single-reader lease'
} finally { $pipeline.Dispose(); $runspace.Dispose() }
'PASS watch: acknowledged callback handoff, event/count/UTF-8 budgets, buffered error, single-reader ownership and stop'

$probe = [LibTmux.Testing.WatchProbe]::new()
foreach ($index in 1..16) {
    $probe.Write((Get-WatchOutput ('payload-' + [char] 0x00e9 + '-' + $index.ToString('D2'))))
}
$probe.Complete()
$job = $null
try {
    $job = Start-ThreadJob -ScriptBlock {
        Import-Module LibTmux
        $using:probe | Watch-TmuxEvent -MaxEvents 100 -MaxOutputBytes 100
    }
    # Inspect retained streams only after completion; never Receive-Job.
    $null = $job | Wait-Job
    $bytes = 0
    foreach ($outputEvent in $job.Output) {
        $bytes += [Text.Encoding]::UTF8.GetByteCount($outputEvent.PaneId.ToString())
        $bytes += [Text.Encoding]::UTF8.GetByteCount($outputEvent.Data)
    }
    Assert-Watch ($job.State -eq 'Completed' -and $job.Output.Count -eq 6 -and $bytes -le 100 -and
        $job.Error.Count -eq 1 -and $job.Error[0].Exception -is [IO.InvalidDataException] -and
        $probe.Reads -eq 7 -and $probe.EnumeratorDisposals -eq 1 -and $probe.IsRunning) `
        'never-received job retained more event text than its byte budget'
} finally {
    if ($job) { $job | Stop-Job; $job | Remove-Job }
}

$foreign = [LibTmux.Testing.WatchProbe]::new()
$local = [LibTmux.Testing.WatchProbe]::new()
$local.Write((Get-WatchOutput 'remove-module'))
$local.Write((Get-WatchOutput 'must-not-prefetch'))
$runspace = [RunspaceFactory]::CreateRunspace($initial)
$pipeline = [PowerShell]::Create()
try {
    $runspace.Open()
    $pipeline.Runspace = $runspace
    $null = $pipeline.AddCommand('LibTmux\Watch-TmuxEvent').AddParameter('Connection', $foreign).AddParameter('MaxEvents', 1)
    $invocation = $pipeline.BeginInvoke()
    Assert-Watch ($foreign.Subscribed.Wait(10000)) 'other runspace did not subscribe'
    $errors = @()
    $result = @($local | Watch-TmuxEvent -ErrorAction Continue -ErrorVariable errors 2>$null | ForEach-Object {
            Remove-Module LibTmux -Force
            $_
        })
    Assert-Watch ($result.Count -eq 1 -and $local.EnumeratorDisposals -eq 1 -and $local.Reads -eq 1 -and
        $local.ConnectionDisposals -eq 0 -and $errors.Count -eq 1 -and $errors[0].Exception -is [OperationCanceledException]) 'module removal did not cancel only its active reader'
    Assert-Watch (!$invocation.IsCompleted -and $foreign.EnumeratorDisposals -eq 0 -and $foreign.IsRunning) 'module removal cancelled another runspace'
    $foreign.Write((Get-WatchOutput 'other-runspace'))
    Assert-Watch ($invocation.AsyncWaitHandle.WaitOne(1000)) 'other runspace did not remain usable'
    $output = @($pipeline.EndInvoke($invocation))
    Assert-Watch ($output.Count -eq 1 -and $output[0].Data -ceq 'other-runspace') 'other runspace lost its event'
} finally {
    $pipeline.Dispose()
    $runspace.Dispose()
    Import-Module $module
}

. "$PSScriptRoot/support/OwnedTmux.ps1"
Invoke-WithOwnedTmux {
    param($fixture)
    $byteOptions = [LibTmux.ServerConnectionOptions] @{
        SocketPath = $fixture.SocketPath
        TmuxBinaryPath = $fixture.TmuxPath
        ControlModeEventBufferCapacity = 4096
        ControlModeEventBufferMaxBytes = 1
    }
    $byteServer = [LibTmux.Server]::Open($byteOptions)
    $byteControl = $byteServer | Connect-TmuxControl -Target fixture
    try {
        $null = $byteControl | Invoke-TmuxControlCommand -Command (New-TmuxCommand -Name 'rename-window' -Arguments @('exceeds-byte-budget'))
        $events = @($byteControl | Watch-TmuxEvent -MaxEvents 1 -MaxOutputBytes 100)
        Assert-Watch ($events.Count -eq 1 -and $events[0] -is [LibTmux.TmuxEventsDroppedEvent] -and
            $events[0].Count -gt 0 -and $events[0].Count -lt 4096) 'native byte ceiling did not disclose loss below the count limit'
        Assert-Watch (($byteControl | Invoke-TmuxControlCommand -Command (New-TmuxCommand -Name 'display-message' -Arguments @('-p', 'after-byte-loss'))) -ceq 'after-byte-loss') 'native byte overflow blocked command replies'
    } finally { $byteControl | Disconnect-TmuxControl -Confirm:$false }
    $options = [LibTmux.ServerConnectionOptions] @{
        SocketPath = $fixture.SocketPath
        TmuxBinaryPath = $fixture.TmuxPath
        ControlModeEventBufferCapacity = 1
    }
    $server = [LibTmux.Server]::Open($options)
    $control = $server | Connect-TmuxControl -Target fixture
    try {
        foreach ($name in @('first-watch-name', 'second-watch-name')) {
            $null = $control | Invoke-TmuxControlCommand -Command (New-TmuxCommand -Name 'rename-window' -Arguments @($name))
        }
        $sent = [Collections.Generic.List[string]]::new()
        $events = @($control | Watch-TmuxEvent -MaxEvents 2 -MaxOutputBytes 1048576 | ForEach-Object {
                $reply = $control | Invoke-TmuxControlCommand -Command (New-TmuxCommand -Name 'display-message' -Arguments @('-p', 'during-output'))
                $sent.Add($reply)
                $_
            })
        Assert-Watch ($events.Count -eq 2 -and $events[0] -is [LibTmux.TmuxEventsDroppedEvent] -and
            $events[0].Count -gt 0 -and $events[1] -is [LibTmux.TmuxNotificationEvent] -and
            [string]::Join('|', $sent) -ceq 'during-output|during-output' -and $control.IsRunning) 'loss reporting or downstream reentrant send stalled'
        $null = $control | Invoke-TmuxControlCommand -Command (New-TmuxCommand -Name 'rename-window' -Arguments @('after-limit'))
        $events = @($control | Watch-TmuxEvent | Select-Object -First 1)
        Assert-Watch ($events.Count -eq 1 -and $control.IsRunning) 'early pipeline exit disposed the borrowed client'
        Assert-Watch (($control | Invoke-TmuxControlCommand -Command (New-TmuxCommand -Name 'display-message' -Arguments @('-p', 'after-early-exit'))) -ceq 'after-early-exit') 'borrowed client unusable after early exit'
    } finally { $control | Disconnect-TmuxControl -Confirm:$false }
    $events = @($server | Watch-TmuxEvent -Target fixture -MaxEvents 1 -MaxOutputBytes 1048576)
    Assert-Watch ($events.Count -eq 1 -and @($server | Get-TmuxClient).Count -eq 0 -and
        @($server | Get-TmuxSession -Name fixture).Count -eq 1) 'owned watcher leaked its client or removed the borrowed session'

    $failed = $false
    try { $server | Watch-TmuxEvent -Target fixture | ForEach-Object { throw 'injected watch consumer failure' } } catch {
        if ($_.Exception.Message -notlike '*injected watch consumer failure*') { throw }
        $failed = $true
    }
    Assert-Watch ($failed -and @($server | Get-TmuxClient).Count -eq 0) 'consumer failure leaked an owned watch client'

    $ready = [Threading.ManualResetEventSlim]::new($false)
    $runspace = [RunspaceFactory]::CreateRunspace($initial)
    $pipeline = [PowerShell]::Create()
    try {
        $runspace.Open()
        $pipeline.Runspace = $runspace
        $null = $pipeline.AddScript('param($server, $ready) $server | LibTmux\Watch-TmuxEvent -Target fixture | ForEach-Object { $ready.Set() }').AddArgument($server).AddArgument($ready)
        $invocation = $pipeline.BeginInvoke()
        Assert-Watch ($ready.Wait(10000)) 'owned live watcher did not emit its initial event'
        $stop = $pipeline.BeginStop($null, $null)
        Assert-Watch ($stop.AsyncWaitHandle.WaitOne(1000)) 'owned live watcher did not stop promptly'
        $pipeline.EndStop($stop)
        Assert-Watch ($invocation.AsyncWaitHandle.WaitOne(1000)) 'owned stopped watch did not finish'
        $stopped = $false
        try { $null = $pipeline.EndInvoke($invocation) } catch {
            if ($_.Exception.InnerException -isnot [Management.Automation.PipelineStoppedException]) { throw }
            $stopped = $true
        }
        Assert-Watch ($stopped -and $pipeline.Streams.Error.Count -eq 0 -and @($server | Get-TmuxClient).Count -eq 0 -and
            @($server | Get-TmuxSession -Name fixture).Count -eq 1) 'stopped owned watcher leaked a client or changed borrowed lifetime'
    } finally { $pipeline.Dispose(); $runspace.Dispose(); $ready.Dispose() }

    $sources = & "$PSScriptRoot/../examples/Guides.ps1"
    $job = $null
    try {
        . $sources['watch.job-create'].Code
        # Await completion without receiving output; cold runspace startup is not the output bound.
        $null = $job | Wait-Job
        Assert-Watch ($job.State -eq 'Completed' -and $job.Output.Count -eq 1 -and
            $job.Output[0] -is [LibTmux.TmuxEvent] -and @($server | Get-TmuxClient).Count -eq 0) 'never-received job exceeded its bound or leaked its client'
    } finally {
        if ($job) { $job | Stop-Job; $job | Remove-Job }
    }
    $ready = [Threading.ManualResetEventSlim]::new($false)
    $job = $null
    try {
        $job = Start-ThreadJob -ScriptBlock {
            Import-Module LibTmux
            $signal = $using:ready
            [LibTmux.Server]::Open($using:options) | Watch-TmuxEvent -Target fixture -MaxEvents 100 -MaxOutputBytes 4096 |
                ForEach-Object { $signal.Set(); $_ }
        }
        Assert-Watch ($ready.Wait(10000)) 'owned job did not start watching'
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $job | Stop-Job
        Assert-Watch ($watch.ElapsedMilliseconds -lt 1000 -and $job.State -eq 'Stopped' -and
            @($server | Get-TmuxClient).Count -eq 0) 'Stop-Job did not promptly remove its owned control client'
    } finally {
        if ($job) { $job | Stop-Job; $job | Remove-Job }
        $ready.Dispose()
    }
}
'PASS watch: scoped module removal, native loss events, downstream send, early exit, owned stop and client cleanup'

Invoke-WithOwnedTmux {
    param($fixture)
    $server = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $ready = [Threading.ManualResetEventSlim]::new($false)
    $runspace = [RunspaceFactory]::CreateRunspace($initial)
    $pipeline = [PowerShell]::Create()
    try {
        $runspace.Open()
        $pipeline.Runspace = $runspace
        $null = $pipeline.AddScript('param($server, $ready) $server | LibTmux\Watch-TmuxEvent -Target fixture | ForEach-Object { $ready.Set(); $_ }').AddArgument($server).AddArgument($ready)
        $invocation = $pipeline.BeginInvoke()
        Assert-Watch ($ready.Wait(10000)) 'server-loss watcher did not attach'
        $null = Invoke-OwnedTmux $fixture -Arguments @('kill-server')
        Assert-Watch ($invocation.AsyncWaitHandle.WaitOne(1000)) 'server exit left the watcher running'
        $output = @($pipeline.EndInvoke($invocation))
        Assert-Watch ($pipeline.Streams.Error.Count -eq 0 -and $output.Count -gt 0 -and
            $output[-1] -is [LibTmux.TmuxExitEvent]) 'native server exit was hidden or converted into a success sentinel'
    } finally { $pipeline.Dispose(); $runspace.Dispose(); $ready.Dispose() }
}
'PASS watch: real daemon exit is the final native event'
