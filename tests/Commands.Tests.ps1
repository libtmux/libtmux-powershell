param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: typed argv, chains and native control clients need owned tmux.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$module = Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1'
Import-Module $module
. "$PSScriptRoot/support/OwnedTmux.ps1"
. "$PSScriptRoot/support/InputReceiver.ps1"

function Assert-Command([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Commands: $Message" }
}

foreach ($name in @('New-TmuxCommand', 'Invoke-TmuxChain', 'Connect-TmuxControl', 'Invoke-TmuxControlCommand', 'Disconnect-TmuxControl')) {
    Assert-Command ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "installed module has no $name"
}
$arguments = [string[]] @('-p', 'a b', '', '$literal; "quotes"')
$value = New-TmuxCommand -Name 'display-message' -Arguments $arguments
$arguments[1] = 'changed'
Assert-Command ($value -is [LibTmux.TmuxCommand] -and $value.Arguments.Count -eq 4 -and $value.Arguments[1] -ceq 'a b' -and
    $value.Arguments[2] -ceq '' -and $value.Arguments[3] -ceq '$literal; "quotes"') 'typed command lost argv boundaries or borrowed mutable input'
Assert-Command ((New-TmuxCommand -Name 'list-sessions').Arguments.Count -eq 0) 'command without arguments failed'
$offline = New-TmuxServer -SocketName 'command-preview' -TmuxBinaryPath '/missing-command-preview'
Assert-Command (@($offline | Connect-TmuxControl -Target fixture -WhatIf).Count -eq 0) 'connect preview contacted tmux'
Assert-Command (@($offline | Invoke-TmuxChain -Command $value -WhatIf).Count -eq 0) 'chain preview contacted tmux'
foreach ($name in @('', ' ', '-L', "bad`0command")) {
    $failed = $false
    try { New-TmuxCommand -Name $name } catch { $failed = $true }
    Assert-Command $failed 'invalid command name was accepted'
}
foreach ($call in @(
    { $offline | Invoke-TmuxChain -Command @($value, $value) -MaxCommands 1 },
    { $offline | Invoke-TmuxChain -Command $value -MaxInputBytes 1 },
    { $offline | Invoke-TmuxChain -Command ([LibTmux.TmuxCommand]::Create('-L', [string[]] @('other'))) }
)) {
    $failed = $false
    try { & $call } catch { $failed = $true; Assert-Command ($_.Exception -is [ArgumentException]) 'admission error reached the missing executable' }
    Assert-Command $failed 'invalid chain was admitted'
}

Invoke-WithOwnedTmux {
    param($fixture)
    $server = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $session = $server | Get-TmuxSession -Name fixture
    $commands = @(
        New-TmuxCommand -Name 'display-message' -Arguments @('-p', 'first value')
        New-TmuxCommand -Name 'display-message' -Arguments @('-p', '$second; value')
    )
    $nativeSecond = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '$second; value')).StdOut.TrimEnd("`r", "`n")
    $reply = $server | Invoke-TmuxChain -Command $commands
    Assert-Command ($reply -is [LibTmux.TmuxCommandResult] -and $reply.ExitCode -eq 0 -and
        [string]::Join('|', $reply.StandardOutputLines) -ceq "first value|$nativeSecond") 'chain lost merged order or native output'
    $errors = @()
    $failedChain = @(
        New-TmuxCommand -Name 'set-option' -Arguments @('-t', $session.Id.ToString(), '@chain-prefix', 'kept')
        New-TmuxCommand -Name 'select-pane' -Arguments @('-t', '%999999999')
        New-TmuxCommand -Name 'set-option' -Arguments @('-t', $session.Id.ToString(), '@chain-tail', 'wrong')
    )
    $output = @($server | Invoke-TmuxChain -Command $failedChain -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-Command ($output.Count -eq 0 -and $errors.Count -eq 1 -and $errors[0].Exception -is [LibTmux.TmuxCommandException] -and
        [object]::ReferenceEquals($errors[0].TargetObject, $server)) 'failed chain lost original native error or owner'
    Assert-Command (($session | Get-TmuxOption -Name '@chain-prefix').Value.Raw -ceq 'kept' -and
        @($session | Get-TmuxOption -Name '@chain-tail' -Quiet).Count -eq 0) 'chain did not retain prefix and skip tail'
    $window = $session | New-TmuxWindow -Name guarded -Index 5 -Command 'exec /bin/cat'
    Register-OwnedTmuxPane $fixture
    $move = ([LibTmux.MoveWindowRequest] @{ Destination = '7'; NoSelect = $true }).ToCommand($window)
    $null = Invoke-OwnedTmux $fixture -Arguments @('move-window', '-s', 'fixture:5', '-t', 'fixture:6')
    $errors = @()
    $null = $server | Invoke-TmuxChain -Command $move -ErrorAction Continue -ErrorVariable errors 2>$null
    Assert-Command ($errors.Count -eq 1 -and
        (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:6', '#{window_id}')).StdOut.Trim() -ceq $window.Id.ToString()) 'chain discarded the native window placement guard'
    $receiver = New-InputReceiver $fixture $session 2
    $request = [LibTmux.SendKeysRequest] @{ Text = 'x'; Literal = $true; Enter = $true }
    $null = $server | Invoke-TmuxChain -Command $request.ToCommands($receiver.Pane)
    Assert-Received $fixture $receiver ([byte[]] @(120, 13))

    $recipe = Join-Path $PSScriptRoot '../examples/ConcurrentCommands.ps1'
    $ordered = @(& $recipe -Server $server -Command $commands -MaxPending 2)
    Assert-Command (($ordered.Index -join '|') -ceq '0|1' -and
        ($ordered.StandardOutputLines -join '|') -ceq "first value|$nativeSecond" -and
        ($ordered | Measure-Object Utf8Bytes -Sum).Sum -le 65536) 'concurrent process results lost input order, attribution or byte accounting'
    $blocked = New-TmuxCommand -Name 'if-shell' -Arguments @(
        '-F', '1', 'wait-for concurrent-release ; display-message -p delayed')
    $completion = [Collections.Generic.List[object]]::new()
    try {
        & $recipe -Server $server -Command @($blocked, $commands[0]) -MaxPending 2 -CompletionOrder |
            ForEach-Object {
                $completion.Add($_)
                if ($_.Index -eq 1) {
                    $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', '-S', 'concurrent-release')
                }
            }
    } finally {
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', '-S', 'concurrent-release')
    }
    Assert-Command (($completion.Index -join '|') -ceq '1|0' -and
        ($completion.StandardOutputLines -join '|') -ceq 'first value|delayed') 'completion mode waited for input order or misattributed a native reply'
    $cancel = [Threading.CancellationTokenSource]::new()
    $cancelBlocked = New-TmuxCommand -Name 'wait-for' -Arguments @('concurrent-cancel-release')
    $cancelled = $false
    $cancelledResults = [Collections.Generic.List[object]]::new()
    try {
        & $recipe -Server $server -Command @($commands[0], $cancelBlocked) -MaxPending 2 -CompletionOrder -CancellationToken $cancel.Token |
            ForEach-Object { $cancelledResults.Add($_); $cancel.Cancel() }
    } catch {
        $cancelError = $_.Exception
        while ($null -ne $cancelError.InnerException) { $cancelError = $cancelError.InnerException }
        Assert-Command ($cancelError -is [OperationCanceledException]) 'concurrent cancellation lost its native cancellation cause'
        $cancelled = $true
    } finally {
        $cancel.Dispose()
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', '-S', 'concurrent-cancel-release')
    }
    Assert-Command ($cancelled -and $cancelledResults.Count -eq 1 -and $cancelledResults[0].Index -eq 0) 'concurrent cancellation emitted an unfinished result'
    $failed = $false
    try { & $recipe -Server $server -Command $move } catch {
        Assert-Command ($_.Exception.Data['LibTmux.ConcurrentCommandIndex'] -eq 0) 'concurrent process error lost submitted index'
        $failed = $true
    }
    Assert-Command $failed 'concurrent process lane discarded the native placement guard'

    $control = $server | Connect-TmuxControl -Target $session.Id.ToString()
    try {
        Assert-Command ($control -is [LibTmux.IControlModeSession] -and $control.IsRunning) 'connect did not return a running native control client'
        $reply = @($control | Invoke-TmuxControlCommand -Command $commands[1])
        Assert-Command ($reply.Count -eq 1 -and $reply[0] -is [string] -and $reply[0] -ceq $nativeSecond) 'control reply lost native text'
        $concurrent = @(& $recipe -Connection $control -Command $commands -MaxPending 2)
        Assert-Command (($concurrent.Index -join '|') -ceq '0|1' -and
            ($concurrent.StandardOutputLines -join '|') -ceq "first value|$nativeSecond" -and $control.IsRunning) 'concurrent control replies lost input order or disposed their borrowed client'
        $empty = New-TmuxCommand -Name 'set-option' -Arguments @('-t', $session.Id.ToString(), '@concurrent', 'kept')
        $emptyResult = @(& $recipe -Connection $control -Command $empty)
        Assert-Command ($emptyResult.Count -eq 1 -and $emptyResult[0].StandardOutputLines.Count -eq 0) 'empty control reply became a false output line'
        $unicode = New-TmuxCommand -Name 'display-message' -Arguments @('-p', 'é')
        $budget = [Text.Encoding]::UTF8.GetByteCount('display-message') + 3
        $failed = $false
        try { & $recipe -Connection $control -Command $unicode -MaxResultBytes $budget } catch {
            Assert-Command ($_.Exception.Message -like '*MaxResultBytes*' -and
                $_.Exception.Data['LibTmux.ConcurrentCommandIndex'] -eq 0) 'UTF-8 result budget error lost its cause or submitted index'
            $failed = $true
        }
        Assert-Command ($failed -and $control.IsRunning -and
            ($control | Invoke-TmuxControlCommand -Command $commands[0]) -ceq 'first value') 'UTF-8 over-budget result was admitted or borrowed client was damaged'
        $tasks = @(foreach ($n in 1..8) {
                $control.SendAsync((New-TmuxCommand -Name 'display-message' -Arguments @('-p', "reply-$n")))
            })
        for ($n = 0; $n -lt $tasks.Count; $n++) {
            Assert-Command ([string]::Join('|', $tasks[$n].GetAwaiter().GetResult()) -ceq "reply-$($n + 1)") 'concurrent control replies were miscorrelated'
        }
        Invoke-WithOwnedTmux {
            param($other)
            $otherPane = New-TmuxServer -SocketPath $other.SocketPath -TmuxBinaryPath $other.TmuxPath | Get-TmuxPane
            $guarded = ([LibTmux.CapturePaneRequest] @{}).ToCommand($otherPane)
            $errors = @()
            $null = $control | Invoke-TmuxControlCommand -Command $guarded -ErrorAction Continue -ErrorVariable errors 2>$null
            Assert-Command ($errors.Count -eq 1 -and $errors[0].Exception -is [LibTmux.StaleServerGenerationException]) 'control command lost its native generation guard'
        }
        $receiver = New-InputReceiver $fixture $session 2
        foreach ($command in $request.ToCommands($receiver.Pane)) {
            Assert-Command (@($control | Invoke-TmuxControlCommand -Command $command).Count -eq 0) 'input control command emitted a success sentinel'
        }
        Assert-Received $fixture $receiver ([byte[]] @(120, 13))
        $errors = @()
        $null = $control | Invoke-TmuxControlCommand -Command $failedChain[1] -ErrorAction Continue -ErrorVariable errors 2>$null
        Assert-Command ($errors.Count -eq 1 -and $errors[0].Exception -is [LibTmux.ControlModeCommandException] -and
            [object]::ReferenceEquals($errors[0].TargetObject, $control)) 'control error lost native exception or connection'
        $initial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
        $initial.ImportPSModule(@($module))
        $runspace = [RunspaceFactory]::CreateRunspace($initial)
        $pipeline = [PowerShell]::Create()
        # -F runs the selected tmux command list without a foreground shell.
        $blocking = New-TmuxCommand -Name 'if-shell' -Arguments @('-F', '1', 'wait-for -S command-started ; wait-for command-release')
        try {
            $runspace.Open()
            $pipeline.Runspace = $runspace
            $null = $pipeline.AddCommand('LibTmux\Invoke-TmuxControlCommand').AddParameter('Connection', $control).AddParameter('Command', $blocking)
            $invocation = $pipeline.BeginInvoke()
            $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', 'command-started')
            $stop = $pipeline.BeginStop($null, $null)
            Assert-Command ($stop.AsyncWaitHandle.WaitOne(1000)) 'control command stop did not complete promptly'
            $pipeline.EndStop($stop)
            Assert-Command ($invocation.AsyncWaitHandle.WaitOne(1000)) 'stopped control invocation stayed active'
            $stopped = $false
            try { $null = $pipeline.EndInvoke($invocation) } catch {
                if ($_.Exception.InnerException -isnot [Management.Automation.PipelineStoppedException]) { throw }
                $stopped = $true
            }
            Assert-Command ($stopped -and $pipeline.Streams.Error.Count -eq 0 -and $control.IsRunning) 'cancelled send faulted or disposed the borrowed client'
        } finally {
            $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', '-S', 'command-release')
            $pipeline.Dispose()
            $runspace.Dispose()
        }
        Assert-Command (($control | Invoke-TmuxControlCommand -Command $commands[0]) -ceq 'first value') 'cancelled reply consumed a subsequent command reply'
        $control | Disconnect-TmuxControl -WhatIf
        Assert-Command $control.IsRunning 'disconnect preview stopped the client'
        Assert-Command (@($control | Disconnect-TmuxControl -Confirm:$false).Count -eq 0) 'disconnect emitted a success sentinel'
        Assert-Command (!$control.IsRunning) 'disconnect left its control client running'
    } finally { $null = $control.DisposeAsync().AsTask().GetAwaiter().GetResult() }
    Assert-Command (@($server | Get-TmuxClient).Count -eq 0 -and @($server | Get-TmuxSession -Name fixture).Count -eq 1) 'control cleanup removed a borrowed daemon/session or leaked the client'

    $failed = $false
    try { $server | Connect-TmuxControl -Target fixture | ForEach-Object { throw 'injected control consumer failure' } } catch {
        Assert-Command ($_.Exception.Message -like '*injected control consumer failure*') 'unexpected connect consumer failure'
        $failed = $true
    }
    Assert-Command ($failed -and @($server | Get-TmuxClient).Count -eq 0) 'failed output transfer leaked a newly attached control client'
}
'PASS commands: typed argv, bounded chain, prefix failure, composite input, native control replies, ownership and cleanup'
