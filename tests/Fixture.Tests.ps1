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

$registrationFixture = New-OwnedTmuxFixture
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
