param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: exact example source, redirected only through child environments.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-Lifecycle([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Example lifecycle: $Message" }
}

function Assert-ExampleRemoved($Fixture) {
    $sessions = Invoke-OwnedTmux $Fixture -Arguments @('-N', 'list-sessions', '-F', '#{session_name}')
    Assert-Lifecycle ($sessions.StdOut.Trim() -ceq 'fixture') 'the example leaked its session'
}

foreach ($case in @(
    @{ Endpoint = 'Path'; Mode = 'Success' },
    @{ Endpoint = 'Name'; Mode = 'Success' },
    @{ Endpoint = 'Path'; Mode = 'Body' },
    @{ Endpoint = 'Name'; Mode = 'Cleanup' },
    @{ Endpoint = 'Path'; Mode = 'Both' },
    @{ Endpoint = 'Name'; Mode = 'Rename' },
    @{ Endpoint = 'Path'; Mode = 'NoCleanup' }
)) {
    $fixture = New-OwnedTmuxFixture -NamedSocket:($case.Endpoint -eq 'Name')
    $process = $null
    $bodyError = $null
    try {
        $bin = New-Item -ItemType Directory (Join-Path $fixture.DirectoryPath 'bin')
        $python = (Get-Command python3 -CommandType Application | Select-Object -First 1).Source
        $wrapper = Join-Path $bin.FullName 'tmux'
        ("#!$python`n" + [IO.File]::ReadAllText("$PSScriptRoot/support/lifecycle_tmux.py")) |
            Set-Content -LiteralPath $wrapper
        [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode] 448)
        $trace = Join-Path $fixture.DirectoryPath 'calls.jsonl'
        $shadow = New-Item -ItemType Directory (Join-Path $fixture.DirectoryPath 'shadow/LibTmux/99.0.0')
        New-ModuleManifest -Path (Join-Path $shadow.FullName 'LibTmux.psd1') -ModuleVersion '99.0.0'
        $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.WorkingDirectory = $root
        $start.Environment['PATH'] = $bin.FullName + [IO.Path]::PathSeparator + $env:PATH
        $start.Environment['PSModulePath'] = (Join-Path $fixture.DirectoryPath 'shadow') +
            [IO.Path]::PathSeparator + $ModuleRoot
        $start.Environment['LIBTMUX_SOCKET_PATH'] = $(if ($case.Endpoint -eq 'Path') { $fixture.SocketPath } else { '' })
        $start.Environment['LIBTMUX_SOCKET_NAME'] = $(if ($case.Endpoint -eq 'Name') { 'socket' } else { '../ignored' })
        $start.Environment['TMUX_TMPDIR'] = $fixture.DirectoryPath
        $start.Environment['TMUX'] = 'ignored malformed context'
        $start.Environment['TMUX_PANE'] = '%987654'
        $start.Environment['LIBTMUX_LIFECYCLE_SOCKET'] = $fixture.SocketPath
        $start.Environment['LIBTMUX_LIFECYCLE_BINARY'] = $fixture.TmuxPath
        $start.Environment['LIBTMUX_LIFECYCLE_MODE'] = $case.Mode
        $start.Environment['LIBTMUX_LIFECYCLE_TRACE'] = $trace
        foreach ($argument in @('-NoLogo', '-NoProfile', '-File', "$PSScriptRoot/support/SessionCleanupChild.ps1",
            '-ModuleRoot', $ModuleRoot)) { $start.ArgumentList.Add($argument) }
        $process = [Diagnostics.Process]::Start($start)
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(10000)) { throw 'Example child exceeded its deadline.' }
        if ($process.ExitCode) { throw "Example child failed: $($errors.GetAwaiter().GetResult())" }
        $result = ConvertFrom-Json -InputObject $output.GetAwaiter().GetResult()
        Assert-Lifecycle ($result.SourceSha256 -ceq (Get-FileHash "$root/examples/SessionCleanup.ps1").Hash) 'child ran another example source'
        $expectedFailures = $(if ($case.Mode -eq 'Both') { 2 } elseif ($case.Mode -in @('Body', 'Cleanup')) { 1 } else { 0 })
        Assert-Lifecycle ($result.Errors.Count -eq $expectedFailures) "wrong failure count for $($case.Mode): $($result.Errors -join '; ')"
        if ($case.Mode -in @('Body', 'Both')) {
            Assert-Lifecycle ($result.Errors[0] -match 'injected example body failure') 'body error was lost'
        }
        if ($case.Mode -in @('Cleanup', 'Both')) {
            Assert-Lifecycle ($result.Errors[-1] -match 'injected example cleanup failure') 'cleanup error was lost'
        }
        if ($case.Mode -eq 'Both') {
            Assert-Lifecycle ($result.ErrorType -ceq 'System.AggregateException') 'dual failure did not retain native grouped errors'
        }
        $calls = @(Get-Content -LiteralPath $trace | ConvertFrom-Json)
        $cleanup = @($calls | Where-Object { $_.arguments -contains 'kill-session' })
        Assert-Lifecycle ($cleanup.Count -eq 1 -and $cleanup[0].target -match '^\$[0-9]+$') 'cleanup did not target the captured session ID'
        if ($case.Mode -notin @('Body', 'Both')) {
            Assert-Lifecycle (($cleanup[0].windows -join ',') -ceq 'editor:2,logs:1' -and
                $cleanup[0].panes.Count -eq 3) 'native tmux did not contain the example graph before cleanup'
        }
        if (!$expectedFailures) {
            Assert-Lifecycle ($result.Windows.Count -eq 2 -and $result.Windows[0].Name -ceq 'editor' -and
                $result.Windows[0].PaneIds.Count -eq 2 -and $result.Windows[1].Name -ceq 'logs' -and
                $result.Windows[1].PaneIds.Count -eq 1) 'captured native graph was lost after cleanup'
        }
        if ($case.Mode -eq 'NoCleanup') {
            $rejected = $false
            try { Assert-ExampleRemoved $fixture } catch {
                if ($_.Exception.Message -cne 'Example lifecycle: the example leaked its session') { throw }
                $rejected = $true
            }
            Assert-Lifecycle $rejected 'leak assertion accepted deliberately skipped cleanup'
        } elseif ($case.Mode -in @('Cleanup', 'Both')) {
            $leaked = Invoke-OwnedTmux $fixture -Arguments @('has-session', '-t', 'demo')
            Assert-Lifecycle ($leaked.ExitCode -eq 0) 'cleanup injection did not leave a real resource for harness recovery'
        } else { Assert-ExampleRemoved $fixture }
        "PASS exact SessionCleanup $($case.Endpoint)/$($case.Mode)"
    } catch {
        $bodyError = $_
        throw
    } finally {
        try {
            if ($process -and !$process.HasExited) {
                $process.Kill($true)
                if (!$process.WaitForExit(1000)) { throw 'Example child survived termination.' }
            }
            Remove-OwnedTmuxFixture $fixture
            Assert-Lifecycle $fixture.ExitConfirmedBeforeDirectoryRemoval 'directory removal preceded daemon-exit proof'
            Assert-Lifecycle (!(Test-Path -LiteralPath $fixture.DirectoryPath)) 'owned directory remains after cleanup'
        } catch {
            if ($bodyError) {
                throw [AggregateException]::new('Example test and teardown failed.',
                    [Exception[]] @($bodyError.Exception, $_.Exception))
            }
            throw
        } finally { if ($process) { $process.Dispose() } }
    }
}
