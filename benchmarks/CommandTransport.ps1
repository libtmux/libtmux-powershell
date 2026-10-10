[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source,
    [ValidateRange(0, 20)] [int] $WarmupRounds = 3,
    [ValidateRange(1, 100)] [int] $SampleRounds = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-NativeCommandReply($Fixture) {
    $start = [Diagnostics.ProcessStartInfo]::new($Fixture.TmuxPath)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $Fixture.DirectoryPath
    $null = $start.Environment.Remove('TMUX')
    $null = $start.Environment.Remove('TMUX_PANE')
    foreach ($argument in @('-S', $Fixture.SocketPath, '-f', '/dev/null',
            'display-message', '-p', '#{session_name}')) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        try {
            $null = $process.WaitForExitAsync().WaitAsync([TimeSpan]::FromSeconds(1)).GetAwaiter().GetResult()
        } catch {
            if (!$process.HasExited) {
                $process.Kill($true)
                $null = $process.WaitForExit(1000)
            }
            throw 'Native display-message exceeded one second.'
        }
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Native display-message failed ($($process.ExitCode)): $errorText" }
        $stdout.GetAwaiter().GetResult().TrimEnd("`r", "`n")
    } finally {
        $process.Dispose()
    }
}

function Get-ProcessCommandReply($Server) {
    $reply = $Server | LibTmux\Invoke-TmuxCommand -Arguments @('display-message', '-p', '#{session_name}') -ErrorAction Stop
    if ($reply -isnot [LibTmux.TmuxCommandResult] -or $reply.StandardOutputLines.Count -ne 1) {
        throw 'The process-backed cmdlet did not return one native output line.'
    }
    $reply.StandardOutputLines[0]
}

function Get-ControlCommandReply($Control, $Command) {
    $reply = @($Control | LibTmux\Invoke-TmuxControlCommand -Command $Command -ErrorAction Stop)
    if ($reply.Count -ne 1 -or $reply[0] -isnot [string]) {
        throw 'The reused control client did not return one native output line.'
    }
    $reply[0]
}

$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0-alpha2.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) { throw 'PackageRoot must contain LibTmux.0.1.0-alpha2.nupkg.' }
$binary = (Resolve-Path -LiteralPath $TmuxBinaryPath).Path
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $destination) { throw 'OutputPath already exists; choose a new report path.' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-benchmark-' + [Guid]::NewGuid().ToString('N'))
$fixture = $null
$control = $null
$null = New-Item -ItemType Directory -Path $temporary
try {
    $module = Join-Path $temporary 'LibTmux/0.1.0'
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $module)
    $importWatch = [Diagnostics.Stopwatch]::StartNew()
    Import-Module (Join-Path $module 'LibTmux.psd1') -ErrorAction Stop
    $importWatch.Stop()
    Import-Module "$PSScriptRoot/CommandTransport.Checks.psm1" -Force
    . "$PSScriptRoot/../tests/support/OwnedTmux.ps1"

    $fixture = New-OwnedTmuxFixture -TmuxPath $binary
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $binary -ConfigurationFile '/dev/null'
    $tmuxVersion = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()
    $command = LibTmux\New-TmuxCommand -Name 'display-message' -Arguments @('-p', '#{session_name}')
    $connectWatch = [Diagnostics.Stopwatch]::StartNew()
    $control = $server | LibTmux\Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
    $connectWatch.Stop()
    if (!$control.IsRunning) { throw 'The benchmark control client did not start.' }

    $lanes = @('native', 'process-cmdlet', 'control-cmdlet')
    $operations = @{
        native = { Get-NativeCommandReply $fixture }
        'process-cmdlet' = { Get-ProcessCommandReply $server }
        'control-cmdlet' = { Get-ControlCommandReply $control $command }
    }
    $expected = 'fixture'
    $firstCalls = [Collections.Generic.List[object]]::new()
    $warmups = [Collections.Generic.List[object]]::new()
    $samples = [Collections.Generic.List[object]]::new()

    foreach ($lane in $lanes) {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $actual = & $operations[$lane]
        $watch.Stop()
        Assert-BenchmarkCommandReply -Expected $expected -Observed $actual -Lane $lane
        $firstCalls.Add(@{ lane = $lane; elapsedNanoseconds = [long] [Math]::Round(
                    $watch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency) })
    }

    foreach ($phase in @('warmup', 'sample')) {
        $rounds = if ($phase -eq 'warmup') { $WarmupRounds } else { $SampleRounds }
        for ($round = 0; $round -lt $rounds; $round++) {
            for ($position = 0; $position -lt $lanes.Count; $position++) {
                $lane = $lanes[($round + $position) % $lanes.Count]
                $watch = [Diagnostics.Stopwatch]::StartNew()
                $actual = & $operations[$lane]
                $watch.Stop()
                Assert-BenchmarkCommandReply -Expected $expected -Observed $actual -Lane "$phase/$round/$lane"
                $record = @{ round = $round; position = $position; lane = $lane;
                    elapsedNanoseconds = [long] [Math]::Round(
                        $watch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency) }
                if ($phase -eq 'warmup') { $warmups.Add($record) } else { $samples.Add($record) }
            }
        }
    }

    $disconnectWatch = [Diagnostics.Stopwatch]::StartNew()
    $control | LibTmux\Disconnect-TmuxControl -Confirm:$false -ErrorAction Stop
    $disconnectWatch.Stop()
    $controlDisconnected = !$control.IsRunning -and @($server | LibTmux\Get-TmuxClient -ErrorAction Stop).Count -eq 0
    $borrowedSessionAlive = @($server | LibTmux\Get-TmuxSession -Name 'fixture' -ErrorAction Stop).Count -eq 1 -and
        !$fixture.ServerProcess.HasExited
    if (!$controlDisconnected -or !$borrowedSessionAlive) {
        throw 'Control cleanup changed the borrowed tmux session or left a client attached.'
    }

    $summary = foreach ($lane in $lanes) {
        $values = [long[]] @($samples | Where-Object lane -EQ $lane | ForEach-Object elapsedNanoseconds)
        [Array]::Sort($values)
        $middle = [int] [Math]::Floor($values.Length / 2)
        $median = if ($values.Length % 2) { $values[$middle] } else { ($values[$middle - 1] + $values[$middle]) / 2.0 }
        @{ lane = $lane; samples = $values.Length; medianMilliseconds = $median / 1000000.0;
            p95Milliseconds = $(if ($values.Length -ge 20) {
                    $values[[int] [Math]::Ceiling($values.Length * 0.95) - 1] / 1000000.0
                } else { $null }) }
    }
    $sourceCommit = (git -C (Split-Path $PSScriptRoot) rev-parse HEAD).Trim()
    $sourceDirty = @((git -C (Split-Path $PSScriptRoot) status --porcelain --untracked-files=all)).Count -gt 0
    $report = [ordered]@{
        schema = 1
        status = 'PASS'
        recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        workload = 'display the sole owned session name'
        expectedReply = $expected
        lanes = $lanes
        operations = @(
            @{ lane = 'native'; command = 'tmux -S <owned socket> -f /dev/null display-message -p #{session_name}' },
            @{ lane = 'process-cmdlet'; command = 'Server | LibTmux\Invoke-TmuxCommand -Arguments display-message,-p,#{session_name}' },
            @{ lane = 'control-cmdlet'; command = 'Control | LibTmux\Invoke-TmuxControlCommand -Command display-message,-p,#{session_name}' }
        )
        shape = @{ sessions = 1; windows = 1; panes = 1; linkedWindows = 0 }
        parameters = @{ warmupRounds = $WarmupRounds; sampleRounds = $SampleRounds;
            sampling = 'serial, rotating lane order'; timeoutSecondsPerNativeCall = 1 }
        provenance = @{ sourceCommit = $sourceCommit; sourceDirty = $sourceDirty;
            runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();
            checksSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/CommandTransport.Checks.psm1" -Algorithm SHA256).Hash.ToLowerInvariant();
            packageVersion = (Get-Module LibTmux).Version.ToString();
            corePackageVersion = (Get-Content -LiteralPath (Join-Path $module 'dependencies.json') -Raw |
                ConvertFrom-Json).corePackageVersion;
            packageSha256 = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant();
            tmuxVersion = $tmuxVersion;
            tmuxSha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant();
            powerShellVersion = $PSVersionTable.PSVersion.ToString();
            dotnetRuntimeVersion = [Environment]::Version.ToString();
            os = [Runtime.InteropServices.RuntimeInformation]::OSDescription;
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }
        timing = @{ moduleImportNanoseconds = [long] [Math]::Round(
                $importWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            controlConnectNanoseconds = [long] [Math]::Round(
                $connectWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            controlDisconnectNanoseconds = [long] [Math]::Round(
                $disconnectWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            firstCallsIncludeJit = $true; warmSamplesExcludeImportAndFixtureSetup = $true;
            controlConnectionReused = $true }
        cleanup = @{ controlDisconnected = $controlDisconnected; borrowedSessionAlive = $borrowedSessionAlive }
        firstCalls = $firstCalls.ToArray()
        warmups = $warmups.ToArray()
        samples = $samples.ToArray()
        summary = @($summary)
    }
    $parent = Split-Path $destination
    if (!(Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -NoNewline
    "PASS command transport: $SampleRounds rounds per lane; report: $destination"
} finally {
    if ($control) { $null = $control.DisposeAsync().AsTask().GetAwaiter().GetResult() }
    if ($fixture) { Remove-OwnedTmuxFixture $fixture }
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
