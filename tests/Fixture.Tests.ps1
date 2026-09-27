param([switch] $Child)

# Integration: real tmux lifecycles and a fresh PowerShell host exercise isolation.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Child) {
    $start = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    foreach ($argument in @('-NoProfile', '-File', $PSCommandPath, '-Child')) {
        $start.ArgumentList.Add($argument)
    }
    $start.Environment['TMUX'] = '/borrowed/server,123,0'
    $start.Environment['TMUX_PANE'] = '%999'
    $process = [System.Diagnostics.Process]::Start($start)
    try {
        if (-not $process.WaitForExit(30000)) {
            throw 'The owned tmux fixture self-check exceeded its deadline.'
        }
        exit $process.ExitCode
    } finally {
        if (-not $process.HasExited) {
            $process.Kill($true)
            $null = $process.WaitForExit(1000)
        }
        $process.Dispose()
    }
}

. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-CleanedUp($Fixture) {
    Assert-True (-not (Test-Path -LiteralPath $Fixture.DirectoryPath)) 'Owned directory remains.'
    foreach ($processId in $Fixture.OwnedProcessIds) {
        $remaining = Get-Process -Id $processId -ErrorAction SilentlyContinue
        try {
            Assert-True ($null -eq $remaining) "Owned process $processId remains alive."
        } finally {
            if ($remaining) { $remaining.Dispose() }
        }
    }
}

$fixture = New-OwnedTmuxFixture
try {
    Assert-True (Test-Path -LiteralPath $fixture.SocketPath) 'Fixture did not start an owned tmux server.'
    $sessions = Invoke-OwnedTmux $fixture -Arguments @('list-sessions', '-F', '#{session_name}')
    Assert-True ($sessions.StdOut.Trim() -eq 'fixture') 'Fixture session was not created.'
    $automaticRename = Invoke-OwnedTmux $fixture -Arguments @('show-window-options', '-v', '-t', 'fixture:0', 'automatic-rename')
    Assert-True ($automaticRename.StdOut.Trim() -ceq 'off') 'Owned fixture permits an asynchronous anchor window rename.'
    Assert-True ($fixture.ServerPid -eq $fixture.ServerProcess.Id) 'Fixture did not retain the actual daemon process.'
    $createdPane = Invoke-OwnedTmux $fixture -Arguments @('split-window', '-d', '-P', '-F', '#{pane_pid}', 'exec /bin/sh')
    $createdPanePid = [int] $createdPane.StdOut.Trim()
    foreach ($name in @('TMUX', 'TMUX_PANE')) {
        $environment = Invoke-OwnedTmux $fixture -Arguments @('show-environment', '-g', $name) -AllowFailure
        Assert-True ($environment.ExitCode -ne 0) "Owned server inherited $name."
    }
    Assert-True ($env:TMUX -eq '/borrowed/server,123,0') 'Fixture mutated parent TMUX.'
    Assert-True ($env:TMUX_PANE -eq '%999') 'Fixture mutated parent TMUX_PANE.'
} finally {
    Remove-OwnedTmuxFixture $fixture
}
Assert-CleanedUp $fixture
Assert-True ($fixture.OwnedProcessIds.Contains($createdPanePid)) 'Teardown did not track the later-created pane process.'
Remove-OwnedTmuxFixture $fixture

$emptyFixture = New-OwnedTmuxFixture
try {
    $null = Invoke-OwnedTmux $emptyFixture -Arguments @('set-option', '-g', 'exit-empty', 'off')
    $null = Invoke-OwnedTmux $emptyFixture -Arguments @('kill-session', '-t', 'fixture')
    Assert-True (-not $emptyFixture.ServerProcess.HasExited) 'Empty-server test lost its owned daemon.'
    $sessions = Invoke-OwnedTmux $emptyFixture -Arguments @('-N', 'list-sessions', '-F', '#{session_id}')
    Assert-True ($sessions.StdOut.Trim().Length -eq 0) 'Empty-server test retained a session.'
} finally {
    Remove-OwnedTmuxFixture $emptyFixture
}
Assert-CleanedUp $emptyFixture

$registrationFixture = New-OwnedTmuxFixture
$script:OriginalInvokeOwnedTmux = (Get-Command Invoke-OwnedTmux).ScriptBlock
$falseEmptyFailure = $null
try {
    Set-Item Function:\Invoke-OwnedTmux -Value {
        [CmdletBinding()]
        param($Fixture, [string[]] $Arguments, [switch] $AllowFailure,
            [Threading.CancellationToken] $CancellationToken)

        if ($Arguments[0] -ceq 'list-panes') {
            [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'no current target' }
            return
        }
        & $script:OriginalInvokeOwnedTmux $Fixture -Arguments $Arguments -AllowFailure:$AllowFailure `
            -CancellationToken $CancellationToken
    }
    try { Register-OwnedTmuxPane $registrationFixture }
    catch { $falseEmptyFailure = $_ }
} finally {
    Set-Item Function:\Invoke-OwnedTmux -Value $script:OriginalInvokeOwnedTmux
    Remove-Variable OriginalInvokeOwnedTmux -Scope Script
}
Assert-True ($null -ne $falseEmptyFailure -and
    $falseEmptyFailure.Exception.Message -eq 'tmux list-panes failed (1): no current target') `
    'Pane registration accepted a failed list while the owned session was present.'

$originalRegister = (Get-Command Register-OwnedTmuxPane).ScriptBlock
$registrationFailure = $null
try {
    Set-Item Function:\Register-OwnedTmuxPane -Value { throw 'injected pane registration failure' }
    try {
        Remove-OwnedTmuxFixture $registrationFixture
    } catch {
        $registrationFailure = $_
    }
} finally {
    Set-Item Function:\Register-OwnedTmuxPane -Value $originalRegister
    if (-not $registrationFixture.Closed) { Remove-OwnedTmuxFixture $registrationFixture }
}
Assert-True ($null -ne $registrationFailure) 'Teardown accepted pane registration failure.'
Assert-True ($registrationFailure.Exception.Message -eq 'injected pane registration failure') `
    'Teardown masked the pane registration failure.'
Assert-CleanedUp $registrationFixture

$script:OriginalStartInfo = (Get-Command New-OwnedTmuxStartInfo).ScriptBlock
$script:OriginalRemoveFixture = (Get-Command Remove-OwnedTmuxFixture).ScriptBlock
$setupFailure = $null
try {
    Set-Item Function:\New-OwnedTmuxStartInfo -Value { throw 'injected fixture setup failure' }
    Set-Item Function:\Remove-OwnedTmuxFixture -Value {
        param($Fixture)
        & $script:OriginalRemoveFixture $Fixture
        throw 'injected fixture cleanup failure'
    }
    try { New-OwnedTmuxFixture | Out-Null } catch { $setupFailure = $_ }
} finally {
    Set-Item Function:\New-OwnedTmuxStartInfo -Value $script:OriginalStartInfo
    Set-Item Function:\Remove-OwnedTmuxFixture -Value $script:OriginalRemoveFixture
    Remove-Variable OriginalStartInfo, OriginalRemoveFixture -Scope Script
}
Assert-True ($null -ne $setupFailure) 'Fixture accepted injected setup failure.'
Assert-True ($setupFailure.Exception.Message -eq 'injected fixture setup failure') 'Fixture cleanup masked the setup failure.'
Assert-True ($setupFailure.Exception.Data['OwnedTmuxCleanupFailure'].Message -eq 'injected fixture cleanup failure') 'Fixture did not retain the cleanup failure.'
Assert-CleanedUp $setupFailure.Exception.Data['OwnedTmuxFixture']

$borrowed = New-OwnedTmuxFixture
try {
    $failed = $false
    $state = @{ Fixture = $null }
    try {
        Invoke-WithOwnedTmux {
            param($owned)
            $state.Fixture = $owned
            throw 'deliberate test failure'
        }
    } catch {
        $failed = $_.Exception.Message -eq 'deliberate test failure'
    }
    Assert-True $failed 'Scoped fixture swallowed the test failure.'
    Assert-CleanedUp $state.Fixture
    $result = Invoke-OwnedTmux $borrowed -Arguments @('has-session', '-t', 'fixture')
    Assert-True ($result.ExitCode -eq 0) 'Cleanup affected a borrowed server.'
} finally {
    Remove-OwnedTmuxFixture $borrowed
}
Assert-CleanedUp $borrowed

$setupState = @{ Fixture = $null }
$failed = $false
try {
    Invoke-WithOwnedTmux -Setup {
        param($owned)
        $setupState.Fixture = $owned
        Invoke-OwnedTmux $owned -Arguments @('not-a-tmux-command') | Out-Null
    } -Body { throw 'Body ran after setup failed.' }
} catch {
    $failed = $_.Exception.Message -match 'not-a-tmux-command'
}
Assert-True $failed 'Scoped fixture did not report setup failure.'
Assert-CleanedUp $setupState.Fixture

foreach ($badExecutable in @('/bin/false', '/nonexistent-libtmux-powershell')) {
    $bootstrapState = $null
    try {
        New-OwnedTmuxFixture -TmuxPath $badExecutable | Out-Null
        throw 'Fixture accepted a server that failed to start.'
    } catch {
        $bootstrapState = $_.Exception.Data['OwnedTmuxFixture']
    }
    Assert-True ($null -ne $bootstrapState) 'Failed server startup did not provide cleanup evidence.'
    Assert-CleanedUp $bootstrapState
}

# Integration: a real owned socket must become usable even when its watcher
# never reports creation, as observed on macOS.
$missedSignal = [System.Threading.Tasks.TaskCompletionSource[bool]]::new()
$missedFixture = New-OwnedTmuxFixture -SocketReadyTask $missedSignal.Task
try {
    $identity = Invoke-OwnedTmux $missedFixture -Arguments @('-N', 'display-message', '-p', '#{pid}')
    Assert-True ([int] $identity.StdOut.Trim() -eq $missedFixture.ServerPid) `
        'A silent socket watcher did not retain the owned daemon identity.'
} finally {
    Remove-OwnedTmuxFixture $missedFixture
}
Assert-CleanedUp $missedFixture

# Integration: a live owned daemon without a socket must retain timeout diagnostics.
$fakeDirectory = Join-Path '/tmp' ('libtmux-powershell-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fakeDirectory
$fakeTmux = Join-Path $fakeDirectory 'fake-tmux'
try {
    [IO.File]::WriteAllText($fakeTmux, @'
#!/bin/sh
for arg in "$@"; do
    if [ "$arg" = '-D' ]; then exec /bin/sleep 30; fi
done
printf 'fake client unavailable\n' >&2
exit 9
'@, [Text.UTF8Encoding]::new($false))
    [IO.File]::SetUnixFileMode($fakeTmux, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $readinessFailure = $null
    try { New-OwnedTmuxFixture -TmuxPath $fakeTmux | Out-Null }
    catch { $readinessFailure = $_.Exception }
    Assert-True ($readinessFailure -is [TimeoutException]) 'Missing socket did not preserve the timeout.'
    Assert-True ($readinessFailure.InnerException -is [TimeoutException]) 'Readiness diagnostics replaced the original timeout.'
    Assert-True ($readinessFailure.Message -match 'socketExists=False') 'Timeout omitted socket state.'
    Assert-True ($readinessFailure.Message -match 'daemonExited=False') 'Timeout omitted daemon state.'
    Assert-True ($readinessFailure.Message -match 'daemonExitCode=pending; daemonStderr=pending') 'Timeout omitted daemon exit and stderr state.'
    Assert-True ($readinessFailure.Message -match 'watcherCreated=0; watcherErrors=0') 'Timeout omitted watcher counts.'
    Assert-True ($readinessFailure.Message -match 'clientProbe=skipped \(socket absent\)') 'Timeout did not explain the skipped client probe.'
    Assert-CleanedUp $readinessFailure.Data['OwnedTmuxFixture']

    $originalDiagnostic = (Get-Command Get-OwnedTmuxReadinessDiagnostic).ScriptBlock
    try {
        Set-Item Function:\Get-OwnedTmuxReadinessDiagnostic -Value { throw 'injected diagnostic failure' }
        $diagnosticFailure = $null
        try { New-OwnedTmuxFixture -TmuxPath $fakeTmux | Out-Null }
        catch { $diagnosticFailure = $_.Exception }
        Assert-True ($diagnosticFailure -is [TimeoutException] -and
            $diagnosticFailure.InnerException -is [TimeoutException]) 'A failed diagnostic replaced the readiness timeout.'
        Assert-True ($diagnosticFailure.Data['OwnedTmuxDiagnosticFailure'].Message -eq
            'injected diagnostic failure') 'The diagnostic failure was lost.'
        Assert-CleanedUp $diagnosticFailure.Data['OwnedTmuxFixture']
    } finally {
        Set-Item Function:\Get-OwnedTmuxReadinessDiagnostic -Value $originalDiagnostic
    }
} finally {
    Remove-Item -LiteralPath $fakeDirectory -Recurse -Force
}

$cancellation = [System.Threading.CancellationTokenSource]::new()
$cancelState = @{ Fixture = $null }
$cancelled = $false
try {
    Invoke-WithOwnedTmux -CancellationToken $cancellation.Token {
        param($owned)
        $cancelState.Fixture = $owned
        Invoke-OwnedTmux $owned -Arguments @('wait-for', 'never-signalled') -OnStarted {
            param($client)
            Assert-True (-not $client.HasExited) 'Cancellation did not reach a running client.'
            $cancellation.Cancel()
        } | Out-Null
    }
} catch {
    $cancelled = $_.Exception -is [System.OperationCanceledException]
} finally {
    $cancellation.Dispose()
}
Assert-True $cancelled 'Scoped fixture did not propagate cancellation.'
Assert-CleanedUp $cancelState.Fixture

'PASS: owned tmux setup, success, failure, cancellation, isolation, and teardown'
