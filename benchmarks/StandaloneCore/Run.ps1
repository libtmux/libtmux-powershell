[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [Parameter(Mandatory)] [string] $PreparedRoot,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $ReviewRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source,
    [ValidateRange(0, 20)] [int] $WarmupRounds = 3,
    [ValidateRange(1, 100)] [int] $SampleRounds = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-StandaloneTiming([Diagnostics.Stopwatch] $Watch) {
    [long] [Math]::Round($Watch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency)
}

function Invoke-StandaloneCore($Fixture, [string] $Dotnet, [string] $Application,
    [string[]] $ExpectedIds, [string] $Mode, [int] $Warmups, [int] $Samples,
    [System.Threading.CancellationToken] $CancellationToken) {
    $start = [Diagnostics.ProcessStartInfo]::new($Dotnet)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $Fixture.DirectoryPath
    $null = $start.Environment.Remove('TMUX')
    $null = $start.Environment.Remove('TMUX_PANE')
    foreach ($argument in @($Application, $Mode, $Fixture.SocketPath, $Fixture.TmuxPath,
            ($ExpectedIds -join ','))) {
        $start.ArgumentList.Add($argument)
    }
    if ($Mode -eq 'warm') {
        $start.ArgumentList.Add([string] $Warmups)
        $start.ArgumentList.Add([string] $Samples)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $null = $process.Start()
        $errorOutput = $process.StandardError.ReadToEndAsync()
        $lineCount = if ($Mode -eq 'once') { 2 } else { 2 + $Warmups + $Samples }
        $lines = [Collections.Generic.List[string]]::new()
        for ($index = 0; $index -lt $lineCount; $index++) {
            $line = $process.StandardOutput.ReadLineAsync($CancellationToken).GetAwaiter().GetResult()
            if ($null -eq $line) {
                $null = $process.WaitForExitAsync($CancellationToken).GetAwaiter().GetResult()
                $errorText = $errorOutput.GetAwaiter().GetResult()
                throw "Standalone $Mode process closed output after $index of $lineCount records: $errorText"
            }
            $lines.Add($line)
        }
        $null = $process.WaitForExitAsync($CancellationToken).GetAwaiter().GetResult()
        $watch.Stop()
        $errorText = $errorOutput.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or $errorText) {
            throw "Standalone $Mode process failed ($($process.ExitCode)): $errorText"
        }
        $events = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
        $captureCount = $lineCount - 1
        for ($index = 0; $index -lt $captureCount; $index++) {
            $captureEvent = $events[$index]
            $phase = if ($index -eq 0) { 'first' } elseif ($Mode -eq 'warm' -and $index -le $Warmups) {
                'warmup'
            } else { 'sample' }
            $round = if ($phase -eq 'warmup') { $index - 1 } elseif ($phase -eq 'sample') {
                $index - 1 - $Warmups
            } else { 0 }
            if ($captureEvent.kind -cne 'capture' -or $captureEvent.phase -cne $phase -or
                $captureEvent.round -ne $round -or $captureEvent.elapsedNanoseconds -le 0) {
                throw "Standalone $Mode process returned an invalid $phase/$round record."
            }
            Assert-BenchmarkPaneIdentity -Reference $ExpectedIds -Observed @($captureEvent.paneIds) -Lane "$Mode/$phase/$round"
        }
        $complete = $events[$captureCount]
        if ($complete.kind -cne 'complete' -or $complete.processId -ne $process.Id -or
            !$complete.runtimeVersion -or
            !$complete.coreAssemblyMvid -or !$complete.benchmarkAssemblyMvid) {
            throw "Standalone $Mode process omitted its completion identity."
        }
        [pscustomobject]@{ processElapsedNanoseconds = (Get-StandaloneTiming $watch);
            processId = $process.Id; events = $events; completion = $complete }
    } finally {
        if (!$process.HasExited) {
            $process.Kill($true)
            if (!$process.WaitForExit(1000)) { throw 'Standalone C# process did not exit after cleanup.' }
        }
        $process.Dispose()
    }
}

function Get-StandaloneSummary([long[]] $Values, [string] $Metric) {
    [Array]::Sort($Values)
    $middle = [int] [Math]::Floor($Values.Length / 2)
    $median = if ($Values.Length % 2) { $Values[$middle] } else { ($Values[$middle - 1] + $Values[$middle]) / 2.0 }
    @{ metric = $Metric; samples = $Values.Length; medianMilliseconds = $median / 1000000.0;
        p95Milliseconds = $(if ($Values.Length -ge 20) {
                $Values[[int] [Math]::Ceiling($Values.Length * 0.95) - 1] / 1000000.0
            } else { $null }) }
}

$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0-alpha1.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) { throw 'PackageRoot must contain LibTmux.0.1.0-alpha1.nupkg.' }
$prepared = (Resolve-Path -LiteralPath $PreparedRoot).Path
$manifest = Get-Content -LiteralPath (Join-Path $prepared 'manifest.json') -Raw | ConvertFrom-Json
$app = Join-Path $prepared 'bin/LibTmux.StandaloneCoreBenchmark.dll'
$project = Join-Path $PSScriptRoot 'StandaloneCore.csproj'
$binary = (Resolve-Path -LiteralPath $TmuxBinaryPath).Path
$dotnet = (Get-Command dotnet -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $destination) { throw 'OutputPath already exists; choose a new report path.' }
$identityModule = Join-Path $PSScriptRoot '../PackageIdentity.psm1'
Import-Module $identityModule -Force
$identity = Get-BenchmarkPackageIdentity -PackageRoot $PackageRoot -ModuleRoot (Join-Path $prepared 'package') -ReviewRoot $ReviewRoot
if ($manifest.status -cne 'PASS' -or
    $manifest.corePackageVersion -cne $identity.corePackageVersion -or
    $manifest.packageSha256 -cne $identity.packageSha256 -or
    $manifest.sourceProvenance -cne $identity.sourceProvenance -or
    $manifest.reviewCoreRevision -cne $identity.reviewCoreRevision -or
    $manifest.reviewPortRevision -cne $identity.reviewPortRevision -or
    $manifest.dependenciesSha256 -cne (Get-FileHash -LiteralPath (Join-Path $prepared 'package/dependencies.json') -Algorithm SHA256).Hash.ToLowerInvariant() -or
    $manifest.benchmarkSha256 -cne (Get-FileHash -LiteralPath $app -Algorithm SHA256).Hash.ToLowerInvariant()) {
    throw 'Prepared standalone benchmark does not match the supplied package and binary.'
}
foreach ($source in @(
    @{ path = $project; hash = $manifest.sourceSha256.project },
    @{ path = (Join-Path $PSScriptRoot 'Program.cs'); hash = $manifest.sourceSha256.program },
    @{ path = $identityModule; hash = $manifest.sourceSha256.packageIdentity },
    @{ path = (Join-Path $PSScriptRoot 'Prepare.ps1'); hash = $manifest.sourceSha256.prepare }
)) {
    if ((Get-FileHash -LiteralPath $source.path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $source.hash) {
        throw 'Prepared standalone benchmark source changed after compilation.'
    }
}
foreach ($entry in $manifest.assemblies) {
    foreach ($directory in @('package/lib', 'bin')) {
        $copy = Join-Path $prepared "$directory/$($entry.assembly).dll"
        if ((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.sha256) {
            throw "Prepared standalone $($entry.assembly) assembly changed."
        }
    }
}
Import-Module "$PSScriptRoot/../PaneEnumeration.Checks.psm1" -Force
. "$PSScriptRoot/../../tests/support/OwnedTmux.ps1"
$fixture = $null
$report = $null
$budget = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromMinutes(9))
try {
    $fixture = New-OwnedTmuxFixture -TmuxPath $binary -CancellationToken $budget.Token
    for ($window = 1; $window -lt 4; $window++) {
        $null = Invoke-OwnedTmux $fixture -Arguments @('new-window', '-d', '-t', 'fixture', '-n', "bench$window", 'exec /bin/cat')
    }
    for ($window = 0; $window -lt 4; $window++) {
        for ($pane = 1; $pane -lt 4; $pane++) {
            $null = Invoke-OwnedTmux $fixture -Arguments @('split-window', '-d', '-v', '-l', '25%',
                '-t', "fixture:$window", 'exec /bin/cat')
        }
    }
    Register-OwnedTmuxPane $fixture
    $expectedIds = [string[]] @((Invoke-OwnedTmux $fixture -Arguments @('list-panes', '-a', '-F', '#{pane_id}')).StdOut.Split(
            "`n", [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.TrimEnd("`r") })
    if ($expectedIds.Length -ne 16 -or @($expectedIds | Select-Object -Unique).Count -ne 16 -or
        @($expectedIds | Where-Object { $_ -cnotmatch '^%[0-9]+$' }).Count -ne 0) {
        throw 'The owned fixture did not expose sixteen distinct pane IDs.'
    }
    $tmuxVersion = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()

    $preflight = Invoke-StandaloneCore $fixture $dotnet $app $expectedIds 'once' 0 0 $budget.Token
    $wrongIds = [string[]] $expectedIds.Clone()
    $maximumId = 0
    foreach ($id in $expectedIds) { $maximumId = [Math]::Max($maximumId, [int] $id.Substring(1)) }
    $wrongIds[0] = '%' + ($maximumId + 1)
    $rejected = $false
    $negativeFailure = $null
    try {
        $null = Invoke-StandaloneCore $fixture $dotnet $app $wrongIds 'once' 0 0 $budget.Token
    } catch {
        $negativeFailure = $_.Exception.Message
        $rejected = $negativeFailure.Contains('returned different pane IDs')
    }
    if (!$rejected) { throw "Standalone core did not reject unequal pane IDs for the expected reason: $negativeFailure" }
    $coldWarmups = [Collections.Generic.List[object]]::new()
    $coldSamples = [Collections.Generic.List[object]]::new()
    for ($round = 0; $round -lt $WarmupRounds; $round++) {
        $run = Invoke-StandaloneCore $fixture $dotnet $app $expectedIds 'once' 0 0 $budget.Token
        if ($run.completion.coreAssemblyMvid -cne $preflight.completion.coreAssemblyMvid -or
            $run.completion.benchmarkAssemblyMvid -cne $preflight.completion.benchmarkAssemblyMvid) {
            throw 'Cold process loaded a different assembly identity.'
        }
        $coldWarmups.Add(@{ round = $round; processElapsedNanoseconds = $run.processElapsedNanoseconds;
                captureElapsedNanoseconds = $run.events[0].elapsedNanoseconds;
                paneIds = @($run.events[0].paneIds) })
    }
    for ($round = 0; $round -lt $SampleRounds; $round++) {
        $run = Invoke-StandaloneCore $fixture $dotnet $app $expectedIds 'once' 0 0 $budget.Token
        if ($run.completion.coreAssemblyMvid -cne $preflight.completion.coreAssemblyMvid -or
            $run.completion.benchmarkAssemblyMvid -cne $preflight.completion.benchmarkAssemblyMvid) {
            throw 'Cold process loaded a different assembly identity.'
        }
        $coldSamples.Add(@{ round = $round; processElapsedNanoseconds = $run.processElapsedNanoseconds;
                captureElapsedNanoseconds = $run.events[0].elapsedNanoseconds;
                paneIds = @($run.events[0].paneIds) })
    }

    $warmRun = Invoke-StandaloneCore $fixture $dotnet $app $expectedIds 'warm' $WarmupRounds $SampleRounds $budget.Token
    if ($warmRun.completion.coreAssemblyMvid -cne $preflight.completion.coreAssemblyMvid -or
        $warmRun.completion.benchmarkAssemblyMvid -cne $preflight.completion.benchmarkAssemblyMvid) {
        throw 'Warm process loaded a different assembly identity.'
    }
    $warmEvents = @($warmRun.events | Where-Object kind -CEQ 'capture')
    $summary = @(
        Get-StandaloneSummary -Values ([long[]] @($coldSamples | ForEach-Object processElapsedNanoseconds)) -Metric 'cold process launch through exit'
        Get-StandaloneSummary -Values ([long[]] @($coldSamples | ForEach-Object captureElapsedNanoseconds)) -Metric 'first capture within each cold process'
        Get-StandaloneSummary -Values ([long[]] @($warmEvents | Where-Object phase -CEQ 'sample' | ForEach-Object elapsedNanoseconds)) -Metric 'warm capture in reused process'
    )
    $sourceCommit = (git -C (Split-Path (Split-Path $PSScriptRoot)) rev-parse HEAD).Trim()
    $sourceDirty = @((git -C (Split-Path (Split-Path $PSScriptRoot)) status --porcelain --untracked-files=all)).Count -gt 0
    $report = [ordered]@{
        schema = 1
        status = 'PASS'
        recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        workload = 'pane-depth snapshot of sixteen panes on one owned tmux socket'
        shape = @{ sessions = 1; windows = 4; panes = 16; linkedWindows = 0 }
        expectedPaneIds = @($expectedIds | Sort-Object -CaseSensitive)
        parameters = @{ warmupRounds = $WarmupRounds; sampleRounds = $SampleRounds;
            cold = 'new dotnet process per capture; parent times launch through exit';
            warm = 'one reused dotnet process; C# times each snapshot call';
            sampling = 'serial cold launches, then one warm process'; maximumBenchmarkMinutes = 9 }
        provenance = @{ sourceCommit = $sourceCommit; sourceDirty = $sourceDirty;
            runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();
            paneChecksSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/../PaneEnumeration.Checks.psm1" -Algorithm SHA256).Hash.ToLowerInvariant();
            fixtureSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/../../tests/support/OwnedTmux.ps1" -Algorithm SHA256).Hash.ToLowerInvariant();
            packageSha256 = $manifest.packageSha256; corePackageVersion = $manifest.corePackageVersion;
            sourceProvenance = $manifest.sourceProvenance;
            reviewCoreRevision = $manifest.reviewCoreRevision;
            reviewPortRevision = $manifest.reviewPortRevision;
            assemblies = @($manifest.assemblies); benchmarkSha256 = $manifest.benchmarkSha256;
            benchmarkAssemblyMvid = $preflight.completion.benchmarkAssemblyMvid;
            coreAssemblyMvid = $preflight.completion.coreAssemblyMvid;
            prepareSourceSha256 = $manifest.sourceSha256; sdkVersion = $manifest.sdkVersion;
            dotnetLauncherSha256 = (Get-FileHash -LiteralPath $dotnet -Algorithm SHA256).Hash.ToLowerInvariant();
            dotnetRuntimeVersion = $preflight.completion.runtimeVersion;
            tmuxVersion = $tmuxVersion;
            tmuxSha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant();
            powerShellVersion = $PSVersionTable.PSVersion.ToString();
            os = [Runtime.InteropServices.RuntimeInformation]::OSDescription;
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }
        firstCalls = @{ cold = @{ processElapsedNanoseconds = $preflight.processElapsedNanoseconds;
                captureElapsedNanoseconds = $preflight.events[0].elapsedNanoseconds;
                paneIds = @($preflight.events[0].paneIds) };
            warm = $warmEvents[0] }
        negativeControl = 'wrong pane ID reference rejected by standalone core'
        coldWarmups = $coldWarmups.ToArray()
        coldSamples = $coldSamples.ToArray()
        warmEvents = $warmEvents
        summary = $summary
    }
} finally {
    try {
        if ($fixture) { Remove-OwnedTmuxFixture $fixture }
    } finally {
        $budget.Dispose()
    }
}
$report.cleanup = @{ fixtureRemoved = !(Test-Path -LiteralPath $fixture.DirectoryPath);
    preparedPackageRetained = (Test-Path -LiteralPath $prepared) }
if (!$report.cleanup.fixtureRemoved) { throw 'Standalone-core benchmark left its owned tmux fixture.' }
$parent = Split-Path $destination
if (!(Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -NoNewline
"PASS standalone core: $SampleRounds cold launches and warm captures; report: $destination"
