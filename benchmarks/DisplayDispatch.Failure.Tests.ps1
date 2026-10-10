[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [string] $ReviewRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop |
        Select-Object -First 1).Source
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-FailureDispatch([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Display dispatch failure: $Message" }
}

function Get-OwnedPaneState($Fixture) {
    (Invoke-OwnedTmux $Fixture -Arguments @('list-panes', '-a', '-F',
        '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}')).StdOut.TrimEnd("`r", "`n")
}

function Get-OptionValue($Fixture, [string] $Name) {
    (Invoke-OwnedTmux $Fixture -Arguments @('show-options', '-qv', '-t', 'fixture', $Name) `
        -AllowFailure).StdOut.TrimEnd("`r", "`n")
}

function Assert-Reply([int] $Index, $Lines, [string] $Lane) {
    $actual = @($Lines)
    if ($Index -in @(0, 7)) {
        Assert-FailureDispatch ($actual.Count -eq 0) "$Lane/$Index emitted output from set-option"
    } else {
        Assert-FailureDispatch ($actual.Count -eq 1 -and $actual[0] -ceq $expected[$Index]) `
            "$Lane/$Index lost its indexed display reply"
    }
}

function Invoke-SerialFailure([string] $Lane, $Server, $Control, [object[]] $ArgumentSets,
    [object[]] $Commands) {
    $status = [string[]]::new(8)
    for ($index = 0; $index -lt 8; $index++) {
        $errors = @()
        if ($Lane -ceq 'direct-serial') {
            $result = @($Server | LibTmux\Invoke-TmuxCommand -Arguments $ArgumentSets[$index] `
                -ErrorAction Continue -ErrorVariable errors 2>$null)
            if ($index -ne 3) {
                Assert-FailureDispatch ($result.Count -eq 1 -and $errors.Count -eq 0 -and
                    $result[0].ExitCode -eq 0) "$Lane/$index was not successful"
                Assert-Reply $index $result[0].StandardOutputLines $Lane
            } else {
                Assert-FailureDispatch ($result.Count -eq 0 -and $errors.Count -eq 1 -and
                    $errors[0].Exception -is [LibTmux.TmuxCommandException] -and
                    $errors[0].Exception.Result.ExitCode -ne 0 -and
                    [object]::ReferenceEquals($errors[0].TargetObject, $Server)) `
                    "$Lane did not preserve the failed command result and owner"
            }
        } else {
            $lines = @($Control | LibTmux\Invoke-TmuxControlCommand -Command $Commands[$index] `
                -ErrorAction Continue -ErrorVariable errors 2>$null)
            if ($index -ne 3) {
                Assert-FailureDispatch ($errors.Count -eq 0) "$Lane/$index was not successful"
                Assert-Reply $index $lines $Lane
            } else {
                Assert-FailureDispatch ($lines.Count -eq 0 -and $errors.Count -eq 1 -and
                    $errors[0].Exception -is [LibTmux.ControlModeCommandException] -and
                    [object]::ReferenceEquals($errors[0].TargetObject, $Control) -and
                    $errors[0].Exception.ErrorLines.Count -gt 0) `
                    "$Lane did not preserve the failed control command and owner"
            }
        }
        $status[$index] = if ($index -eq 3) { 'failure' } else { 'success' }
        if ($index -eq 3) { break }
    }
    for ($index = 4; $index -lt 8; $index++) { $status[$index] = 'skipped' }
    $status
}

function Invoke-ConcurrentFailure([string] $Lane, $Server, $Control, [object[]] $ArgumentSets,
    [object[]] $Commands) {
    $status = [string[]]::new(8)
    for ($offset = 0; $offset -lt 8; $offset += 4) {
        $cancellation = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(1))
        try {
            $tasks = @(
                for ($index = $offset; $index -lt $offset + 4; $index++) {
                    if ($Lane -ceq 'direct-concurrent') {
                        $Server.ExecuteCommandAsync([string[]] $ArgumentSets[$index], $cancellation.Token)
                    } else {
                        $Control.SendAsync($Commands[$index], $cancellation.Token)
                    }
                }
            )
            for ($position = 0; $position -lt 4; $position++) {
                $index = $offset + $position
                try {
                    $reply = $tasks[$position].WaitAsync([TimeSpan]::FromSeconds(1)).GetAwaiter().GetResult()
                    if ($Lane -ceq 'direct-concurrent') {
                        Assert-FailureDispatch ($reply -is [LibTmux.TmuxCommandResult]) `
                            "$Lane/$index did not return a native result"
                        if ($index -eq 3) {
                            Assert-FailureDispatch ($reply.ExitCode -ne 0 -and
                                $reply.StandardErrorLines.Count -gt 0) `
                                "$Lane did not retain the nonzero result at its submitted index"
                        } else {
                            Assert-FailureDispatch ($reply.ExitCode -eq 0) "$Lane/$index failed"
                            Assert-Reply $index $reply.StandardOutputLines $Lane
                        }
                    } else {
                        Assert-FailureDispatch ($index -ne 3) "$Lane returned success for the failing command"
                        Assert-Reply $index $reply $Lane
                    }
                    $status[$index] = if ($index -eq 3) { 'failure' } else { 'success' }
                } catch {
                    $exception = $_.Exception
                    if ($exception -is [Management.Automation.MethodInvocationException] -and $exception.InnerException) {
                        $exception = $exception.InnerException
                    }
                    if ($Lane -cne 'control-concurrent' -or $index -ne 3 -or
                        $exception -isnot [LibTmux.ControlModeCommandException] -or
                        $exception.ErrorLines.Count -eq 0 -or
                        ![object]::ReferenceEquals($exception.Command, $Commands[$index])) { throw }
                    $status[$index] = 'failure'
                }
            }
        } finally {
            $cancellation.Cancel()
            $cancellation.Dispose()
        }
    }
    $status
}

$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0-alpha1.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) {
    throw 'PackageRoot must contain LibTmux.0.1.0-alpha1.nupkg.'
}
$binary = (Resolve-Path -LiteralPath $TmuxBinaryPath).Path
$temporary = Join-Path ([IO.Path]::GetTempPath()) (
    'libtmux-powershell-display-failure-' + [Guid]::NewGuid().ToString('N'))
$fixture = $null
$control = $null
$null = New-Item -ItemType Directory -Path $temporary
try {
    $module = Join-Path $temporary 'LibTmux/0.1.0'
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $module)
    Import-Module "$PSScriptRoot/PackageIdentity.psm1" -Force
    $null = Get-BenchmarkPackageIdentity -PackageRoot $PackageRoot -ModuleRoot $module -ReviewRoot $ReviewRoot
    Import-Module (Join-Path $module 'LibTmux.psd1') -ErrorAction Stop
    . "$PSScriptRoot/../tests/support/OwnedTmux.ps1"

    $fixture = New-OwnedTmuxFixture -TmuxPath $binary
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $binary `
        -ConfigurationFile '/dev/null'
    $state = Get-OwnedPaneState $fixture
    Assert-FailureDispatch (@($state.Split("`n")).Count -eq 1) 'fixture is not one pane'
    $expected = @{}
    $argumentSets = [Collections.Generic.List[object]]::new()
    $commands = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt 8; $index++) {
        $arguments = switch ($index) {
            0 { [string[]] @('set-option', '-t', 'fixture', '@dispatch-prefix', 'ran') }
            3 { [string[]] @('select-pane', '-t', '%999999999') }
            7 { [string[]] @('set-option', '-t', 'fixture', '@dispatch-tail', 'ran') }
            default {
                $format = "reply-$($index.ToString('D2'))|#{session_id}|#{window_id}|#{pane_id}"
                [string[]] @('display-message', '-p', '-t', 'fixture', $format)
            }
        }
        $argumentSets.Add($arguments)
        $commands.Add((LibTmux\New-TmuxCommand -Name $arguments[0] -Arguments $arguments[1..($arguments.Count - 1)]))
        if ($index -in @(0, 3, 7)) { continue }
        $expected[$index] = (Invoke-OwnedTmux $fixture -Arguments $arguments).StdOut.TrimEnd("`r", "`n")
    }
    $nativeFailure = Invoke-OwnedTmux $fixture -Arguments $argumentSets[3] -AllowFailure
    Assert-FailureDispatch ($nativeFailure.ExitCode -ne 0 -and $nativeFailure.StdErr.Length -gt 0) `
        'the injected command did not fail in native tmux'

    $control = $server | LibTmux\Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
    Assert-FailureDispatch $control.IsRunning 'control client did not connect'
    foreach ($lane in @('direct-serial', 'direct-concurrent', 'control-serial', 'control-concurrent', 'chained')) {
        foreach ($marker in @('@dispatch-prefix', '@dispatch-tail')) {
            $null = Invoke-OwnedTmux $fixture -Arguments @('set-option', '-u', '-t', 'fixture', $marker)
            Assert-FailureDispatch ((Get-OptionValue $fixture $marker) -ceq '') "$lane began with $marker set"
        }
        Assert-FailureDispatch ((Get-OwnedPaneState $fixture) -ceq $state) "$lane changed the fixture before dispatch"
        switch ($lane) {
            'direct-serial' {
                $status = @(Invoke-SerialFailure $lane $server $control $argumentSets.ToArray() $commands.ToArray())
            }
            'control-serial' {
                $status = @(Invoke-SerialFailure $lane $server $control $argumentSets.ToArray() $commands.ToArray())
            }
            'direct-concurrent' {
                $status = @(Invoke-ConcurrentFailure $lane $server $control $argumentSets.ToArray() $commands.ToArray())
            }
            'control-concurrent' {
                $status = @(Invoke-ConcurrentFailure $lane $server $control $argumentSets.ToArray() $commands.ToArray())
            }
            chained {
                $errors = @()
                $output = @($server | LibTmux\Invoke-TmuxChain -Command $commands.ToArray() `
                    -ErrorAction Continue -ErrorVariable errors 2>$null)
                Assert-FailureDispatch ($output.Count -eq 0 -and $errors.Count -eq 1 -and
                    $errors[0].Exception -is [LibTmux.TmuxCommandException] -and
                    $errors[0].Exception.Result.ExitCode -ne 0 -and
                    [object]::ReferenceEquals($errors[0].TargetObject, $server)) `
                    'chain did not expose one failed aggregate result'
                $merged = @($errors[0].Exception.Result.StandardOutputLines)
                Assert-FailureDispatch ($merged.Count -eq 2 -and $merged[0] -ceq $expected[1] -and
                    $merged[1] -ceq $expected[2]) 'chain did not preserve successful prefix output'
                # The merged result cannot identify per-command errors; only effects and output prove the prefix and tail.
            }
        }
        if ($lane -cne 'chained') {
            $expectedStatus = if ($lane.EndsWith('serial')) {
                @('success', 'success', 'success', 'failure', 'skipped', 'skipped', 'skipped', 'skipped')
            } else {
                @('success', 'success', 'success', 'failure', 'success', 'success', 'success', 'success')
            }
            Assert-FailureDispatch ([string]::Join(',', $status) -ceq [string]::Join(',', $expectedStatus)) `
                "$lane lost a known command outcome"
        }
        Assert-FailureDispatch ((Get-OptionValue $fixture '@dispatch-prefix') -ceq 'ran') `
            "$lane did not run the prefix"
        $tail = Get-OptionValue $fixture '@dispatch-tail'
        Assert-FailureDispatch ($tail -ceq $(if ($lane -match 'concurrent') { 'ran' } else { '' })) `
            "$lane did not preserve the expected tail outcome"
        Assert-FailureDispatch ((Get-OwnedPaneState $fixture) -ceq $state -and
            !$fixture.ServerProcess.HasExited) "$lane changed or killed the borrowed topology"
    }
    $control | LibTmux\Disconnect-TmuxControl -Confirm:$false -ErrorAction Stop
    Assert-FailureDispatch (!$control.IsRunning -and
        @($server | LibTmux\Get-TmuxClient -ErrorAction Stop).Count -eq 0 -and
        @($server | LibTmux\Get-TmuxSession -Name 'fixture' -ErrorAction Stop).Count -eq 1 -and
        (Get-OwnedPaneState $fixture) -ceq $state) 'control cleanup changed the borrowed session'
} finally {
    try {
        if ($control) { $null = $control.DisposeAsync().AsTask().GetAwaiter().GetResult() }
    } finally {
        try {
            if ($fixture) { Remove-OwnedTmuxFixture $fixture }
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
        }
    }
}
Assert-FailureDispatch ($fixture.Closed -and !(Test-Path -LiteralPath $fixture.DirectoryPath) -and
    !(Test-Path -LiteralPath $temporary)) 'owned fixture or package extraction remained after cleanup'
'PASS display dispatch failure: four per-command lanes, aggregate chain, borrowed state and cleanup'
