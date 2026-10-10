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

function Get-NativeCapture($Fixture, [string] $PaneId) {
    $result = Invoke-OwnedTmux $Fixture -Arguments @('capture-pane', '-p', '-S', '-', '-t', $PaneId)
    if (!$result.StdOut.EndsWith("`n", [StringComparison]::Ordinal)) {
        throw "Native capture of $PaneId omitted its final line terminator."
    }
    # The fixture has no trailing blank payload lines; omit tmux's final
    # line terminator and blank screen padding for the raw cmdlet comparison.
    $result.StdOut.TrimEnd("`r", "`n")
}

function Get-CmdletCapture($Pane) {
    $result = @($Pane | LibTmux\Get-TmuxPaneContent -History -Raw -ErrorAction Stop)
    if ($result.Count -ne 1 -or $result[0] -isnot [string]) {
        throw 'Get-TmuxPaneContent -History -Raw did not return one string.'
    }
    $result[0]
}

function Get-CaptureTiming([Diagnostics.Stopwatch] $Watch) {
    [long] [Math]::Round($Watch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency)
}

$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0-alpha1.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) { throw 'PackageRoot must contain LibTmux.0.1.0-alpha1.nupkg.' }
$binary = (Resolve-Path -LiteralPath $TmuxBinaryPath).Path
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $destination) { throw 'OutputPath already exists; choose a new report path.' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-benchmark-' + [Guid]::NewGuid().ToString('N'))
$fixture = $null
$report = $null
$null = New-Item -ItemType Directory -Path $temporary
try {
    $module = Join-Path $temporary 'LibTmux/0.1.0'
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $module)
    $importWatch = [Diagnostics.Stopwatch]::StartNew()
    Import-Module (Join-Path $module 'LibTmux.psd1') -ErrorAction Stop
    $importWatch.Stop()
    Import-Module "$PSScriptRoot/CaptureSize.Checks.psm1" -Force
    . "$PSScriptRoot/../tests/support/OwnedTmux.ps1"

    $fixture = New-OwnedTmuxFixture -TmuxPath $binary
    $null = Invoke-OwnedTmux $fixture -Arguments @('set-option', '-g', 'history-limit', '2000')
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $binary -ConfigurationFile '/dev/null'
    $tmuxVersion = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()
    $quotedBinary = "'" + $binary.Replace("'", "'\''") + "'"
    $quotedSocket = "'" + $fixture.SocketPath.Replace("'", "'\''") + "'"
    $sizes = @(
        [pscustomobject]@{ name = 'small'; payloadLines = 24 },
        [pscustomobject]@{ name = 'medium'; payloadLines = 256 },
        [pscustomobject]@{ name = 'large'; payloadLines = 1024 }
    )
    $lanes = @('native', 'cmdlet')
    $cells = [Collections.Generic.List[object]]::new()
    $jobs = [Collections.Generic.List[object]]::new()
    $firstCalls = [Collections.Generic.List[object]]::new()
    $warmups = [Collections.Generic.List[object]]::new()
    $samples = [Collections.Generic.List[object]]::new()

    foreach ($size in $sizes) {
        $expectedLines = [string[]] @(for ($index = 0; $index -lt $size.payloadLines; $index++) {
                $prefix = '{0}-{1:D4}-' -f $size.name, $index
                $prefix + ('x' * (64 - $prefix.Length))
            })
        $payload = Join-Path $fixture.DirectoryPath "$($size.name).txt"
        [IO.File]::WriteAllLines($payload, $expectedLines, [Text.Encoding]::ASCII)
        $script = Join-Path $fixture.DirectoryPath "$($size.name).sh"
        @"
#!/bin/sh
/bin/cat '$payload'
$quotedBinary -S $quotedSocket -f /dev/null wait-for -S ready-$($size.name)
exec /bin/cat
"@ | Set-Content -LiteralPath $script
        $created = Invoke-OwnedTmux $fixture -Arguments @('new-window', '-d', '-P', '-F', '#{pane_id}',
            '-t', 'fixture', '-n', $size.name, "/bin/sh '$script'")
        $paneId = $created.StdOut.Trim()
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', "ready-$($size.name)")
        $dimensions = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $paneId,
                '#{pane_width} #{pane_height}')).StdOut.Trim()
        if ($dimensions -cne '80 24') { throw "$($size.name) pane is $dimensions; expected 80 24." }
        $pane = $server | LibTmux\Get-TmuxPane -Id $paneId -ErrorAction Stop
        if ($null -eq $pane -or $pane.Id.ToString() -cne $paneId) {
            throw "$($size.name) pane selection returned the wrong pane."
        }

        $watch = [Diagnostics.Stopwatch]::StartNew()
        $reference = Get-NativeCapture $fixture $paneId
        $watch.Stop()
        Assert-BenchmarkCaptureFixture -ExpectedLines $expectedLines -Observed $reference -Size $size.name
        $referenceBytes = [Text.Encoding]::UTF8.GetBytes($reference)
        $referenceHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($referenceBytes)).ToLowerInvariant()
        $firstCalls.Add(@{ size = $size.name; lane = 'native'; elapsedNanoseconds = (Get-CaptureTiming $watch);
                captureBytes = $referenceBytes.Length })
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $cmdletReply = Get-CmdletCapture $pane
        $watch.Stop()
        Assert-BenchmarkCaptureEqual -Reference $reference -Observed $cmdletReply -Lane "$($size.name)/cmdlet preflight"
        $firstCalls.Add(@{ size = $size.name; lane = 'cmdlet'; elapsedNanoseconds = (Get-CaptureTiming $watch);
                captureBytes = $referenceBytes.Length })
        $cells.Add(@{ size = $size.name; payloadLines = $size.payloadLines; columns = 80; rows = 24;
                captureBytes = $referenceBytes.Length; captureSha256 = $referenceHash; paneId = $paneId })
        foreach ($lane in $lanes) {
            $jobs.Add([pscustomobject]@{ size = $size.name; lane = $lane; paneId = $paneId;
                    pane = $pane; reference = $reference; captureBytes = $referenceBytes.Length })
        }
    }
    Register-OwnedTmuxPane $fixture

    foreach ($phase in @('warmup', 'sample')) {
        $rounds = if ($phase -eq 'warmup') { $WarmupRounds } else { $SampleRounds }
        for ($round = 0; $round -lt $rounds; $round++) {
            for ($position = 0; $position -lt $jobs.Count; $position++) {
                $job = $jobs[($round + $position) % $jobs.Count]
                $watch = [Diagnostics.Stopwatch]::StartNew()
                $actual = if ($job.lane -eq 'native') {
                    Get-NativeCapture $fixture $job.paneId
                } else {
                    Get-CmdletCapture $job.pane
                }
                $watch.Stop()
                Assert-BenchmarkCaptureEqual -Reference $job.reference -Observed $actual `
                    -Lane "$phase/$round/$($job.size)/$($job.lane)"
                $record = @{ round = $round; position = $position; size = $job.size; lane = $job.lane;
                    elapsedNanoseconds = (Get-CaptureTiming $watch);
                    captureBytes = [Text.Encoding]::UTF8.GetByteCount($actual) }
                if ($phase -eq 'warmup') { $warmups.Add($record) } else { $samples.Add($record) }
            }
        }
    }

    $summary = foreach ($size in $sizes) {
        foreach ($lane in $lanes) {
            $values = [long[]] @($samples | Where-Object { $_.size -ceq $size.name -and $_.lane -ceq $lane } |
                    ForEach-Object elapsedNanoseconds)
            [Array]::Sort($values)
            $middle = [int] [Math]::Floor($values.Length / 2)
            $median = if ($values.Length % 2) { $values[$middle] } else { ($values[$middle - 1] + $values[$middle]) / 2.0 }
            @{ size = $size.name; lane = $lane; samples = $values.Length;
                medianMilliseconds = $median / 1000000.0;
                p95Milliseconds = $(if ($values.Length -ge 20) {
                        $values[[int] [Math]::Ceiling($values.Length * 0.95) - 1] / 1000000.0
                    } else { $null }) }
        }
    }
    $sourceCommit = (git -C (Split-Path $PSScriptRoot) rev-parse HEAD).Trim()
    $sourceDirty = @((git -C (Split-Path $PSScriptRoot) status --porcelain --untracked-files=all)).Count -gt 0
    $report = [ordered]@{
        schema = 1
        status = 'PASS'
        recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        workload = 'capture complete history from three fixed 80-column panes'
        lanes = $lanes
        operations = @(
            @{ lane = 'native'; command = 'tmux -S <owned socket> -f /dev/null capture-pane -p -S - -t <pane ID>' },
            @{ lane = 'cmdlet'; command = 'Pane | LibTmux\Get-TmuxPaneContent -History -Raw' }
        )
        cells = $cells.ToArray()
        parameters = @{ warmupRounds = $WarmupRounds; sampleRounds = $SampleRounds;
            sampling = 'serial, rotating six-cell order'; timeoutSecondsPerNativeCall = 1 }
        provenance = @{ sourceCommit = $sourceCommit; sourceDirty = $sourceDirty;
            runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();
            checksSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/CaptureSize.Checks.psm1" -Algorithm SHA256).Hash.ToLowerInvariant();
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
            coreAssemblyMvid = [LibTmux.Server].Assembly.ManifestModule.ModuleVersionId.ToString();
            cmdletAssemblyMvid = [LibTmux.PowerShell.GetTmuxPaneContentCommand].Assembly.ManifestModule.ModuleVersionId.ToString() }
        timing = @{ moduleImportNanoseconds = (Get-CaptureTiming $importWatch);
            firstCallsIncludeJit = $true; samplesExcludeImportFixtureAndPaneSelection = $true }
        firstCalls = $firstCalls.ToArray()
        warmups = $warmups.ToArray()
        samples = $samples.ToArray()
        summary = @($summary)
    }
} finally {
    try {
        if ($fixture) { Remove-OwnedTmuxFixture $fixture }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    }
}

$report.cleanup = @{ fixtureRemoved = !(Test-Path -LiteralPath $fixture.DirectoryPath);
    extractedPackageRemoved = !(Test-Path -LiteralPath $temporary) }
if (!$report.cleanup.fixtureRemoved -or !$report.cleanup.extractedPackageRemoved) {
    throw 'Capture benchmark left an owned fixture or extracted package.'
}
$parent = Split-Path $destination
if (!(Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -NoNewline
"PASS capture size: $SampleRounds rounds per lane and size; report: $destination"
