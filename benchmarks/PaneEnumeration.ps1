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

function Get-NativePaneIdentity($Fixture) {
    $start = [Diagnostics.ProcessStartInfo]::new($Fixture.TmuxPath)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $Fixture.DirectoryPath
    $null = $start.Environment.Remove('TMUX')
    $null = $start.Environment.Remove('TMUX_PANE')
    foreach ($argument in @('-S', $Fixture.SocketPath, '-f', '/dev/null', 'list-panes', '-a', '-F', '#{pane_id}')) {
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
            throw 'Native pane listing exceeded one second.'
        }
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Native pane listing failed ($($process.ExitCode)): $errorText" }
        $stdout.GetAwaiter().GetResult().Split("`n", [StringSplitOptions]::RemoveEmptyEntries) |
            ForEach-Object { $_.TrimEnd("`r") }
    } finally {
        $process.Dispose()
    }
}

function Get-CmdletPaneIdentity($Server) {
    $Server | LibTmux\Get-TmuxPane | ForEach-Object { $_.Id.ToString() }
}

function Get-HostedCorePaneIdentity($Server) {
    $snapshot = $Server.CaptureSnapshotAsync([LibTmux.SnapshotDepth]::Panes).GetAwaiter().GetResult()
    $snapshot.Panes | ForEach-Object { $_.Id.ToString() }
}

$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0-alpha1.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) { throw 'PackageRoot must contain LibTmux.0.1.0-alpha1.nupkg.' }
$binary = (Resolve-Path -LiteralPath $TmuxBinaryPath).Path
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $destination) { throw 'OutputPath already exists; choose a new report path.' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-benchmark-' + [Guid]::NewGuid().ToString('N'))
$fixture = $null
$null = New-Item -ItemType Directory -Path $temporary
try {
    $module = Join-Path $temporary 'LibTmux/0.1.0'
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $module)
    $importWatch = [Diagnostics.Stopwatch]::StartNew()
    Import-Module (Join-Path $module 'LibTmux.psd1') -ErrorAction Stop
    $importWatch.Stop()
    Import-Module "$PSScriptRoot/PaneEnumeration.Checks.psm1" -Force
    $coreAssembly = [LibTmux.Server].Assembly
    $cmdletAssembly = [LibTmux.PowerShell.GetTmuxPaneCommand].Assembly
    . "$PSScriptRoot/../tests/support/OwnedTmux.ps1"

    $fixture = New-OwnedTmuxFixture -TmuxPath $binary
    for ($window = 1; $window -lt 4; $window++) {
        $null = Invoke-OwnedTmux $fixture -Arguments @('new-window', '-d', '-t', 'fixture', '-n', "bench$window", 'exec /bin/cat')
    }
    for ($window = 0; $window -lt 4; $window++) {
        for ($pane = 1; $pane -lt 4; $pane++) {
            $null = Invoke-OwnedTmux $fixture -Arguments @('split-window', '-d', '-v', '-l', '25%', '-t', "fixture:$window", 'exec /bin/cat')
        }
    }
    Register-OwnedTmuxPane $fixture
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $binary
    $tmuxVersion = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()
    $lanes = @('native', 'cmdlet', 'hosted-core')
    $operations = @{
        native = { Get-NativePaneIdentity $fixture }
        cmdlet = { Get-CmdletPaneIdentity $server }
        'hosted-core' = { Get-HostedCorePaneIdentity $server }
    }
    $firstCalls = [Collections.Generic.List[object]]::new()
    $warmups = [Collections.Generic.List[object]]::new()
    $samples = [Collections.Generic.List[object]]::new()
    $expected = @()

    foreach ($lane in $lanes) {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $actual = @(& $operations[$lane])
        $watch.Stop()
        if ($lane -eq 'native') {
            $expected = $actual
            if ($expected.Count -ne 16 -or @($expected | Select-Object -Unique).Count -ne 16 -or
                @($expected | Where-Object { $_ -cnotmatch '^%[0-9]+$' }).Count -ne 0) {
                throw 'The owned tmux fixture did not expose sixteen distinct pane IDs.'
            }
        }
        Assert-BenchmarkPaneIdentity -Reference $expected -Observed $actual -Lane $lane
        $firstCalls.Add(@{ lane = $lane; elapsedNanoseconds = [long] [Math]::Round(
                    $watch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency) })
    }

    foreach ($phase in @('warmup', 'sample')) {
        $rounds = if ($phase -eq 'warmup') { $WarmupRounds } else { $SampleRounds }
        for ($round = 0; $round -lt $rounds; $round++) {
            for ($position = 0; $position -lt $lanes.Count; $position++) {
                $lane = $lanes[($round + $position) % $lanes.Count]
                $watch = [Diagnostics.Stopwatch]::StartNew()
                $actual = @(& $operations[$lane])
                $watch.Stop()
                Assert-BenchmarkPaneIdentity -Reference $expected -Observed $actual -Lane "$phase/$round/$lane"
                $record = @{ round = $round; position = $position; lane = $lane;
                    elapsedNanoseconds = [long] [Math]::Round(
                        $watch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency) }
                if ($phase -eq 'warmup') { $warmups.Add($record) } else { $samples.Add($record) }
            }
        }
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
        workload = 'enumerate pane IDs from one owned tmux server'
        lanes = $lanes
        operations = @(
            @{ lane = 'native'; command = 'tmux -S <owned socket> -f /dev/null list-panes -a -F #{pane_id}' },
            @{ lane = 'cmdlet'; command = 'Server | LibTmux\Get-TmuxPane | pane.Id' },
            @{ lane = 'hosted-core'; command = 'Server.CaptureSnapshotAsync(Panes).Panes | pane.Id' }
        )
        shape = @{ sessions = 1; windows = 4; panes = 16; linkedWindows = 0 }
        parameters = @{ warmupRounds = $WarmupRounds; sampleRounds = $SampleRounds;
            sampling = 'serial, rotating lane order'; timeoutSecondsPerNativeCall = 1 }
        provenance = @{ sourceCommit = $sourceCommit; sourceDirty = $sourceDirty;
            runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();
            checksSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/PaneEnumeration.Checks.psm1" -Algorithm SHA256).Hash.ToLowerInvariant();
            packageVersion = (Get-Module LibTmux).Version.ToString();
            corePackageVersion = (Get-Content -LiteralPath (Join-Path $module 'dependencies.json') -Raw |
                ConvertFrom-Json).corePackageVersion;
            packageSha256 = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant();
            tmuxVersion = $tmuxVersion;
            tmuxSha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant();
            powerShellVersion = $PSVersionTable.PSVersion.ToString();
            dotnetRuntimeVersion = [Environment]::Version.ToString();
            os = [Runtime.InteropServices.RuntimeInformation]::OSDescription;
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();
            coreAssemblyMvid = $coreAssembly.ManifestModule.ModuleVersionId.ToString();
            cmdletAssemblyMvid = $cmdletAssembly.ManifestModule.ModuleVersionId.ToString() }
        timing = @{ moduleImportNanoseconds = [long] [Math]::Round(
                $importWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            firstCallsIncludeJit = $true; warmSamplesExcludeImportAndFixtureSetup = $true;
            hostedCore = 'PowerShell calls the LibTmux .NET API; this is not a standalone C# process' }
        expectedPaneIds = @($expected | Sort-Object -CaseSensitive)
        firstCalls = $firstCalls.ToArray()
        warmups = $warmups.ToArray()
        samples = $samples.ToArray()
        summary = @($summary)
    }
    $parent = Split-Path $destination
    if (!(Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -NoNewline
    "PASS pane enumeration: 16 panes; $SampleRounds rounds per lane; report: $destination"
} finally {
    if ($fixture) { Remove-OwnedTmuxFixture $fixture }
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
