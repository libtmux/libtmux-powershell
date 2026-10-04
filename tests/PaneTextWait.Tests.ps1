param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: installed pane text observation on an owned tmux server.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$module = Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1'
Import-Module $module
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-PaneTextWait([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Pane text wait: $Message" }
}

$command = Get-Command 'LibTmux\Wait-TmuxPaneText' -ErrorAction SilentlyContinue
Assert-PaneTextWait ($null -ne $command) 'installed module has no native Wait-TmuxPaneText command'
Assert-PaneTextWait ($command.OutputType.Type -contains [LibTmux.PaneWaitResult]) 'cmdlet does not declare the native result type'
Assert-PaneTextWait ($command.Parameters['Pane'].ParameterType -eq [LibTmux.Pane]) 'pane input lost its native type'
Assert-PaneTextWait ($command.Parameters['Timeout'].ParameterType -eq [double]) 'timeout must use seconds'

function New-CaptureSignallingPane {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates only fixture-owned test resources; confirmation would break deterministic setup.')]
    param($Fixture, [string] $Name, [string] $Program)
    $captureSignal = 'pane-text-baseline-' + [Guid]::NewGuid().ToString('N')
    $captureScript = Join-Path $Fixture.DirectoryPath ('capture-signal-' + [Guid]::NewGuid().ToString('N') + '.sh')
    $captureFile = "$captureScript.capture"
    $tmux = "'" + $Fixture.TmuxPath.Replace("'", "'\''") + "'"
    $socket = "'" + $Fixture.SocketPath.Replace("'", "'\''") + "'"
    $capturePath = "'" + $captureFile.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
if [ ! -e $capturePath ]; then
    printf 'captured\n' > $capturePath
    $tmux -S $socket wait-for -S '$captureSignal'
fi
"@ | Set-Content -LiteralPath $captureScript

    $programFile = Join-Path $Fixture.DirectoryPath ($Name + '.sh')
    [IO.File]::WriteAllText($programFile, $Program)
    $quotedProgram = "'" + $programFile.Replace("'", "'\''") + "'"
    $null = Invoke-OwnedTmux $Fixture -Arguments @('new-session', '-d', '-s', $Name,
        '-x', '80', '-y', '24', "/bin/sh $quotedProgram")
    $quotedCapture = "'" + $captureScript.Replace("'", "'\''") + "'"
    $captureCommand = "/bin/sh $quotedCapture"
    $hook = 'run-shell "' + $captureCommand.Replace('\', '\\').Replace('"', '\"') + '"'
    # The native hook observes capture over either process or control transport.
    $null = Invoke-OwnedTmux $Fixture -Arguments @('set-hook', '-t', $Name,
        'after-capture-pane', $hook)
    $server = LibTmux\New-TmuxServer -SocketPath $Fixture.SocketPath -TmuxBinaryPath $Fixture.TmuxPath
    $pane = $server | LibTmux\Get-TmuxSession -Name $Name | LibTmux\Get-TmuxPane
    Assert-PaneTextWait ($pane -is [LibTmux.Pane]) "could not select native pane for $Name"
    [pscustomobject]@{ Pane = $pane; Signal = $captureSignal; CaptureFile = $captureFile }
}

function Start-PaneTextWait {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Starts only a test runspace and pipeline; the tested cmdlet owns confirmation.')]
    param($Module, $Pane, [hashtable] $Parameters)
    $initial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $initial.ImportPSModule(@($Module))
    $runspace = [RunspaceFactory]::CreateRunspace($initial)
    $pipeline = [PowerShell]::Create()
    try {
        $runspace.Open()
        $pipeline.Runspace = $runspace
        $null = $pipeline.AddCommand('LibTmux\Wait-TmuxPaneText').AddParameter('Pane', $Pane)
        foreach ($entry in $Parameters.GetEnumerator()) {
            $null = $pipeline.AddParameter($entry.Key, $entry.Value)
        }
        $invocation = $pipeline.BeginInvoke()
        [pscustomobject]@{ Runspace = $runspace; Pipeline = $pipeline; Invocation = $invocation }
    } catch {
        $pipeline.Dispose()
        $runspace.Dispose()
        throw
    }
}

function Complete-PaneTextWait($Running) {
    Assert-PaneTextWait ($Running.Invocation.AsyncWaitHandle.WaitOne($HangGuardMilliseconds)) 'pending wait did not complete after pane activity'
    $result = @($Running.Pipeline.EndInvoke($Running.Invocation))
    Assert-PaneTextWait ($Running.Pipeline.Streams.Error.Count -eq 0) 'wait emitted an operation error'
    return $result
}

function Close-PaneTextWait($Running) {
    try {
        if (!$Running.Invocation.IsCompleted) {
            $stop = $Running.Pipeline.BeginStop($null, $null)
            Assert-PaneTextWait ($stop.AsyncWaitHandle.WaitOne($HangGuardMilliseconds)) 'failed wait did not stop during cleanup'
            $Running.Pipeline.EndStop($stop)
        }
    } finally {
        $Running.Pipeline.Dispose()
        $Running.Runspace.Dispose()
    }
}

function Assert-NoObservationClient($Server, [string] $When) {
    Assert-PaneTextWait (@($Server | LibTmux\Get-TmuxClient).Count -eq 0) "$When left a control client attached"
}

Invoke-WithOwnedTmux {
    param($fixture)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $anchor = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:0.0',
            '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}')).StdOut.Trim()
    $marker = [Guid]::NewGuid().ToString('N')

    $present = $server | LibTmux\Get-TmuxSession -Name fixture | LibTmux\Get-TmuxPane
    $completed = $present | LibTmux\Invoke-TmuxPaneCommand -Command "printf 'PRESENT-$marker\n'" `
        -Timeout $HangGuardSeconds -Confirm:$false -ErrorAction Stop
    Assert-PaneTextWait ($completed.ExitStatus -eq 0) 'present-at-entry producer did not complete'
    $entry = $present | LibTmux\Wait-TmuxPaneText -Pattern "^PRESENT-$marker`$" `
        -Timeout $HangGuardSeconds -Confirm:$false -ErrorAction Stop
    Assert-PaneTextWait ($entry -is [LibTmux.PaneWaitResult] -and
        $entry.Outcome -eq [LibTmux.PaneWaitOutcome]::PresentAtEntry -and
        $entry.PaneId -eq $present.Id -and $entry.EventsDropped -eq 0 -and
        !$entry.PollingFallback) 'text already rendered at entry did not return its native outcome'
    $defaultView = $entry | Out-String
    Assert-PaneTextWait ($defaultView.Contains('PresentAtEntry') -and
        $defaultView.Contains('Missed') -and !$defaultView.Contains($marker)) `
        'default result view omitted outcome/loss or exposed matched text'
    $ignoreCase = $present | LibTmux\Wait-TmuxPaneText -Pattern "present-$marker" `
        -SimpleMatch -Timeout $HangGuardSeconds -Confirm:$false -ErrorAction Stop
    Assert-PaneTextWait ($ignoreCase.Outcome -eq [LibTmux.PaneWaitOutcome]::PresentAtEntry) `
        'literal matching lost its default case-insensitive behavior'
    $caseSensitive = $present | LibTmux\Wait-TmuxPaneText -Pattern "present-$marker" `
        -SimpleMatch -CaseSensitive -Timeout 0.025 -Confirm:$false -ErrorAction Stop
    # .NET timers use whole milliseconds; stopwatch measurements retain fractions.
    $timerResolution = [TimeSpan]::FromMilliseconds(1)
    Assert-PaneTextWait ($caseSensitive.Outcome -eq [LibTmux.PaneWaitOutcome]::TimedOut -and
        $caseSensitive.EffectiveTimeout -eq [TimeSpan]::FromMilliseconds(25) -and
        ($caseSensitive.Elapsed + $timerResolution) -ge $caseSensitive.EffectiveTimeout) `
        'CaseSensitive matched differently cased text or ended before its budget'
    $stoppedAtEntry = $present | LibTmux\Wait-TmuxPaneText -Pattern "^PRESENT-$marker`$" `
        -StopPattern "^PRESENT-$marker`$" -Timeout $HangGuardSeconds -Confirm:$false -ErrorAction Stop
    Assert-PaneTextWait ($stoppedAtEntry.Outcome -eq [LibTmux.PaneWaitOutcome]::Stopped) `
        'wanted text took precedence over a stop pattern already visible at entry'
    Assert-NoObservationClient $server 'present-at-entry wait'

    $prefixSignal = 'pane-text-prefix-' + [Guid]::NewGuid().ToString('N')
    $releaseSignal = 'pane-text-release-' + [Guid]::NewGuid().ToString('N')
    $tmuxPath = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    $socketPath = "'" + $fixture.SocketPath.Replace("'", "'\''") + "'"
    $readyProgram = "IFS= read -r trigger || exit 1`nprintf 'REA'`n" +
        "$tmuxPath -S $socketPath wait-for -S $prefixSignal`n" +
        "$tmuxPath -S $socketPath wait-for $releaseSignal`n" +
        "printf 'DY-$marker\n'`nexec /bin/cat`n"
    $ready = New-CaptureSignallingPane $fixture 'pane-text-ready' $readyProgram
    Assert-PaneTextWait (@($ready.Pane | LibTmux\Wait-TmuxPaneText -Pattern "^READY-$marker`$" `
            -WhatIf).Count -eq 0 -and !(Test-Path -LiteralPath $ready.CaptureFile)) `
        'WhatIf captured the pane or emitted a result'
    Assert-NoObservationClient $server 'WhatIf preview'
    $pending = Start-PaneTextWait $module $ready.Pane @{
        Pattern = @("^READY-$marker`$"); Timeout = $HangGuardSeconds; Confirm = $false
    }
    try {
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', $ready.Signal)
        Assert-PaneTextWait (Test-Path -LiteralPath $ready.CaptureFile) 'baseline capture barrier did not fire'
        $fastList = @($server | LibTmux\Get-TmuxSession -Name fixture)
        Assert-PaneTextWait ($fastList.Count -eq 1 -and !$pending.Invocation.IsCompleted) `
            'waiting blocked an independent tmux listing'
        $ready.Pane | LibTmux\Send-TmuxText -Text go -Enter -Confirm:$false -ErrorAction Stop
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', $prefixSignal)
        Assert-PaneTextWait (!$pending.Invocation.IsCompleted) 'split prefix alone matched the complete line'
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', '-S', $releaseSignal)
        $matched = @(Complete-PaneTextWait $pending)
        Assert-PaneTextWait ($matched.Count -eq 1 -and
            $matched[0] -is [LibTmux.PaneWaitResult] -and
            $matched[0].Outcome -eq [LibTmux.PaneWaitOutcome]::Matched -and
            $matched[0].Pattern -ceq "^READY-$marker`$" -and
            $matched[0].PaneId -eq $ready.Pane.Id -and
            $matched[0].EventsDropped -eq 0 -and !$matched[0].PollingFallback) `
            'split producer output did not match as one rendered line'
    } finally {
        Close-PaneTextWait $pending
    }
    Assert-NoObservationClient $server 'matched wait'

    $anyReadySignal = 'pane-text-any-ready-' + [Guid]::NewGuid().ToString('N')
    $anyProgram = "stty -echo || exit 1`n" +
        "$tmuxPath -S $socketPath wait-for -S $anyReadySignal`n" +
        "IFS= read -r trigger || exit 1`nprintf 'ANY-$marker\n'`nexec /bin/cat`n"
    foreach ($case in @(
            @{ Name = 'stop'; Program = "IFS= read -r trigger || exit 1`nprintf 'STOP-$marker\n'`nexec /bin/cat`n";
                Parameters = @{ Pattern = @('NEVER-READY'); StopPattern = @("^STOP-$marker`$"); Timeout = $HangGuardSeconds };
                Outcome = [LibTmux.PaneWaitOutcome]::Stopped; Pattern = "^STOP-$marker`$" },
            @{ Name = 'any'; Program = $anyProgram;
                Parameters = @{ Timeout = $HangGuardSeconds }; Outcome = [LibTmux.PaneWaitOutcome]::AnyOutput; Pattern = $null },
            @{ Name = 'death'; Program = "IFS= read -r trigger || exit 1`nexit 0`n";
                Parameters = @{ Pattern = @('NEVER-READY'); Timeout = $HangGuardSeconds };
                Outcome = [LibTmux.PaneWaitOutcome]::PaneExited; Pattern = $null }
        )) {
        $owner = New-CaptureSignallingPane $fixture ('pane-text-' + $case.Name) $case.Program
        if ($case.Name -eq 'death') {
            $null = Invoke-OwnedTmux $fixture -Arguments @('set-window-option', '-t',
                "pane-text-$($case.Name):0", 'remain-on-exit', 'on')
        }
        if ($case.Name -eq 'any') {
            $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', $anyReadySignal)
        }
        $running = Start-PaneTextWait $module $owner.Pane $case.Parameters
        try {
            $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', $owner.Signal)
            $owner.Pane | LibTmux\Send-TmuxText -Text go -Enter -Confirm:$false -ErrorAction Stop
            $observed = @(Complete-PaneTextWait $running)
            Assert-PaneTextWait ($observed.Count -eq 1 -and
                $observed[0].Outcome -eq $case.Outcome -and
                $observed[0].Pattern -ceq $case.Pattern -and
                $observed[0].PaneId -eq $owner.Pane.Id) "unexpected $($case.Name) outcome"
            if ($case.Name -eq 'any') {
                Assert-PaneTextWait ($observed[0].Tail -ccontains "ANY-$marker") `
                    'any-output wait returned input echo instead of producer output'
            }
        } finally {
            Close-PaneTextWait $running
        }
        Assert-NoObservationClient $server "$($case.Name) wait"
    }

    $quiet = $server | LibTmux\Get-TmuxSession -Name fixture | LibTmux\Get-TmuxPane
    $timedOut = $quiet | LibTmux\Wait-TmuxPaneText -Pattern 'NEVER-READY' -Timeout 0.025 `
        -Confirm:$false -ErrorAction Stop
    Assert-PaneTextWait ($timedOut.Outcome -eq [LibTmux.PaneWaitOutcome]::TimedOut -and
        $timedOut.PaneId -eq $quiet.Id -and
        $timedOut.EffectiveTimeout -eq [TimeSpan]::FromMilliseconds(25) -and
        ($timedOut.Elapsed + $timerResolution) -ge $timedOut.EffectiveTimeout) 'timeout lost its native budget or ended early'
    Assert-NoObservationClient $server 'timed-out wait'

    $cancelProgram = "IFS= read -r trigger || exit 1`nprintf 'CANCEL-$marker\n'`nexec /bin/cat`n"
    $cancel = New-CaptureSignallingPane $fixture 'pane-text-cancel' $cancelProgram
    $running = Start-PaneTextWait $module $cancel.Pane @{
        Pattern = @('NEVER-READY'); Timeout = $HangGuardSeconds
    }
    try {
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', $cancel.Signal)
        $stop = $running.Pipeline.BeginStop($null, $null)
        Assert-PaneTextWait ($stop.AsyncWaitHandle.WaitOne($HangGuardMilliseconds)) 'pipeline stop did not cancel the wait promptly'
        $running.Pipeline.EndStop($stop)
        Assert-PaneTextWait ($running.Invocation.AsyncWaitHandle.WaitOne($HangGuardMilliseconds)) 'stopped wait remained active'
        $stopped = $false
        try { $null = $running.Pipeline.EndInvoke($running.Invocation) } catch {
            if ($_.Exception.InnerException -isnot [Management.Automation.PipelineStoppedException]) { throw }
            $stopped = $true
        }
        Assert-PaneTextWait ($stopped -and $running.Pipeline.Streams.Error.Count -eq 0) `
            'cancellation became a result or ordinary error'
    } finally {
        $running.Pipeline.Dispose()
        $running.Runspace.Dispose()
    }
    Assert-NoObservationClient $server 'cancelled wait'

    Remove-Item -LiteralPath $ready.CaptureFile -ErrorAction SilentlyContinue
    foreach ($invalid in @(0, -1, 86401, [double]::NaN, [double]::PositiveInfinity)) {
        $rejected = $false
        try { $ready.Pane | LibTmux\Wait-TmuxPaneText -Timeout $invalid -WhatIf | Out-Null } catch {
            if ($_.FullyQualifiedErrorId -notlike 'Tmux.InvalidTimeout,*') { throw }
            $rejected = $true
        }
        Assert-PaneTextWait $rejected 'invalid timeout passed WhatIf validation'
    }
    foreach ($invalid in @('', '[', '(?=x)', ('x' * 1000))) {
        $rejected = $false
        try { $ready.Pane | LibTmux\Wait-TmuxPaneText -Pattern @($invalid) -WhatIf | Out-Null } catch {
            if ($_.FullyQualifiedErrorId -notlike 'Tmux.InvalidPaneTextRequest,*') { throw }
            $rejected = $true
        }
        Assert-PaneTextWait $rejected 'invalid pattern passed WhatIf validation'
    }
    foreach ($patterns in @(
            @{ Pattern = @('ready') * 33 },
            @{ Pattern = @('ready') * 17; StopPattern = @('fatal') * 16 }
        )) {
        $rejected = $false
        try { $ready.Pane | LibTmux\Wait-TmuxPaneText @patterns -WhatIf | Out-Null } catch {
            if ($_.FullyQualifiedErrorId -notlike 'Tmux.InvalidPaneTextRequest,*') { throw }
            $rejected = $true
        }
        Assert-PaneTextWait $rejected 'oversized pattern lists lost native validation errors'
    }
    foreach ($name in @('TailLines', 'MaxOutputBytes')) {
        $rejected = $false
        try { $ready.Pane | LibTmux\Wait-TmuxPaneText -WhatIf -ErrorAction Stop @{ $name = 0 } | Out-Null } catch {
            if ($_.Exception -isnot [Management.Automation.ParameterBindingException]) { throw }
            $rejected = $true
        }
        Assert-PaneTextWait $rejected "invalid $name passed parameter binding"
    }
    Assert-PaneTextWait (!(Test-Path -LiteralPath $ready.CaptureFile)) `
        'invalid preview captured rendered pane text'
    Assert-NoObservationClient $server 'validation preview'
    $after = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:0.0',
            '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}')).StdOut.Trim()
    Assert-PaneTextWait ($after -ceq $anchor) 'pane wait changed the borrowed fixture pane'
}

'PASS pane-text wait: rendered baseline, split output, stop, any output, timeout, death, cancellation, validation and owned observer cleanup'
