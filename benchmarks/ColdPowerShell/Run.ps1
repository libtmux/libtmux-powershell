[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $ReviewRoot,
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string] $ExpectedPackageSha256,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop |
        Select-Object -First 1).Source,
    [ValidateRange(0, 5)] [int] $WarmupRounds = 2,
    [ValidateRange(1, 60)] [int] $SampleRounds = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertTo-NanosecondCount([long] $Ticks) {
    [long] [Math]::Round($Ticks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency)
}

function Get-TimingSummary([long[]] $Values) {
    $sorted = [long[]] $Values.Clone()
    [Array]::Sort($sorted)
    $middle = [int] [Math]::Floor($sorted.Length / 2)
    $median = if ($sorted.Length % 2) { $sorted[$middle] } else {
        ($sorted[$middle - 1] + $sorted[$middle]) / 2.0
    }
    @{ samples = $sorted.Length; medianMilliseconds = $median / 1000000.0;
        p95Milliseconds = $(if ($sorted.Length -ge 20) {
                $sorted[[int] [Math]::Ceiling($sorted.Length * 0.95) - 1] / 1000000.0
            } else { $null }) }
}

function Get-NativePaneIdentity($Fixture) {
    $result = Invoke-OwnedTmux $Fixture -Arguments @('list-panes', '-a', '-F', '#{pane_id}')
    if ($result.StdErr) { throw "Native pane listing returned stderr: $($result.StdErr.Trim())" }
    [string[]] @($result.StdOut.Split("`n", [StringSplitOptions]::RemoveEmptyEntries) |
        ForEach-Object { $_.TrimEnd("`r") })
}

function Invoke-FreshPowerShell {
    param(
        [Parameter(Mandatory)] [string] $Executable,
        [Parameter(Mandatory)] [string] $ChildPath,
        [Parameter(Mandatory)] [string] $ModulePath,
        [Parameter(Mandatory)] [string] $SocketPath,
        [Parameter(Mandatory)] [string] $TmuxPath,
        [Parameter(Mandatory)] [string] $WorkingDirectory,
        [Parameter(Mandatory)] [string[]] $ExpectedPaneIds,
        [Parameter(Mandatory)] [string] $Phase,
        [Parameter(Mandatory)] [int] $Round,
        [Parameter(Mandatory)] [Threading.CancellationToken] $CancellationToken
    )

    $start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $WorkingDirectory
    $null = $start.Environment.Remove('TMUX')
    $null = $start.Environment.Remove('TMUX_PANE')
    foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $ChildPath,
        '-ModulePath', $ModulePath, '-SocketPath', $SocketPath, '-TmuxBinaryPath', $TmuxPath)) {
        $start.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $started = $false
    $watch = [Diagnostics.Stopwatch]::new()
    try {
        $watch.Start()
        $started = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $null = $process.WaitForExitAsync($CancellationToken).GetAwaiter().GetResult()
        $watch.Stop()
        $errorText = $stderr.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0 -or $errorText) {
            throw "$Phase/$Round fresh PowerShell exited $($process.ExitCode): $errorText"
        }
        $output = $stdout.GetAwaiter().GetResult().Trim()
        if (!$output) { throw "$Phase/$Round fresh PowerShell returned no result." }
        try { $result = $output | ConvertFrom-Json -ErrorAction Stop }
        catch { throw "$Phase/$Round fresh PowerShell returned invalid JSON: $($_.Exception.Message)" }

        $lane = "$Phase/$Round"
        Assert-ColdPowerShellResult -Result $result -ExpectedPaneIds $ExpectedPaneIds -Lane $lane
        if ($result.moduleBase -cne (Split-Path $ModulePath)) {
            throw "$lane loaded LibTmux outside the extracted package."
        }
        if ($result.moduleVersion -cne '0.1.0') {
            throw "$lane loaded an unexpected LibTmux version."
        }
        if ($result.powerShellVersion -cne $PSVersionTable.PSVersion.ToString() -or
            $result.dotnetRuntimeVersion -cne [Environment]::Version.ToString()) {
            throw "$lane used a different PowerShell or .NET runtime."
        }
        $launchNanoseconds = ConvertTo-NanosecondCount $watch.ElapsedTicks
        if ($launchNanoseconds -le 0 -or
            $launchNanoseconds -le ($result.importNanoseconds +
                $result.serverConstructionNanoseconds + $result.firstSnapshotNanoseconds)) {
            throw "$lane returned inconsistent launch and child timings."
        }
        [pscustomobject]@{
            record = [ordered]@{
                phase = $Phase
                round = $Round
                launchToExitNanoseconds = $launchNanoseconds
                importNanoseconds = [long] $result.importNanoseconds
                serverConstructionNanoseconds = [long] $result.serverConstructionNanoseconds
                firstSnapshotNanoseconds = [long] $result.firstSnapshotNanoseconds
                paneIds = [string[]] @($result.paneIds)
            }
            coreAssemblyMvid = [string] $result.coreAssemblyMvid
            cmdletAssemblyMvid = [string] $result.cmdletAssemblyMvid
        }
    } finally {
        if ($started -and !$process.HasExited) {
            $process.Kill($true)
            if (!$process.WaitForExit(1000)) {
                throw "$Phase/$Round fresh PowerShell survived forced cleanup."
            }
        }
        $process.Dispose()
    }
}

$runWatch = [Diagnostics.Stopwatch]::StartNew()
$budget = [Threading.CancellationTokenSource]::new([TimeSpan]::FromMinutes(8))
$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) {
    throw 'PackageRoot must contain LibTmux.0.1.0.nupkg.'
}
$packageHash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
if ($packageHash -cne $ExpectedPackageSha256.ToLowerInvariant()) {
    throw 'The package hash does not match ExpectedPackageSha256.'
}
$binary = (Resolve-Path -LiteralPath $TmuxBinaryPath).Path
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $destination) { throw 'OutputPath already exists; choose a new report path.' }
$pwsh = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$childPath = (Resolve-Path -LiteralPath "$PSScriptRoot/Child.ps1").Path
$temporary = Join-Path ([IO.Path]::GetTempPath()) (
    'libtmux-powershell-cold-' + [Guid]::NewGuid().ToString('N'))
$module = Join-Path $temporary 'LibTmux/0.1.0'
$modulePath = Join-Path $module 'LibTmux.psd1'
$fixture = $null
$report = $null
$cleanup = [ordered]@{ fixtureRemoved = $false; extractedPackageRemoved = $false }
$null = New-Item -ItemType Directory -Path $temporary
try {
    $extractWatch = [Diagnostics.Stopwatch]::StartNew()
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $module)
    $extractWatch.Stop()
    Import-Module "$PSScriptRoot/../PackageIdentity.psm1" -Force
    $identity = Get-BenchmarkPackageIdentity -PackageRoot $PackageRoot -ModuleRoot $module -ReviewRoot $ReviewRoot
    Import-Module "$PSScriptRoot/Checks.psm1" -Force
    Import-Module "$PSScriptRoot/../PaneEnumeration.Checks.psm1" -Force
    . "$PSScriptRoot/../../tests/support/OwnedTmux.ps1"

    $fixtureWatch = [Diagnostics.Stopwatch]::StartNew()
    $fixture = New-OwnedTmuxFixture -TmuxPath $binary -CancellationToken $budget.Token
    for ($window = 1; $window -lt 4; $window++) {
        $null = Invoke-OwnedTmux $fixture -Arguments @('new-window', '-d', '-t', 'fixture',
            '-n', "bench$window", 'exec /bin/cat')
    }
    for ($window = 0; $window -lt 4; $window++) {
        for ($pane = 1; $pane -lt 4; $pane++) {
            $null = Invoke-OwnedTmux $fixture -Arguments @('split-window', '-d', '-v',
                '-l', '25%', '-t', "fixture:$window", 'exec /bin/cat')
        }
    }
    Register-OwnedTmuxPane $fixture
    $expected = Get-NativePaneIdentity $fixture
    $fixtureWatch.Stop()
    if ($expected.Count -ne 16 -or @($expected | Select-Object -Unique).Count -ne 16 -or
        @($expected | Where-Object { $_ -cnotmatch '^%[0-9]+$' }).Count -ne 0) {
        throw 'The owned tmux fixture did not expose sixteen distinct pane IDs.'
    }
    $tmuxVersion = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p',
        '#{version}')).StdOut.Trim()

    $first = Invoke-FreshPowerShell -Executable $pwsh -ChildPath $childPath `
        -ModulePath $modulePath -SocketPath $fixture.SocketPath -TmuxPath $binary `
        -WorkingDirectory $fixture.DirectoryPath -ExpectedPaneIds $expected `
        -Phase 'first' -Round 0 -CancellationToken $budget.Token
    $firstCalls = [Collections.Generic.List[object]]::new()
    $firstCalls.Add($first.record)
    $warmups = [Collections.Generic.List[object]]::new()
    $samples = [Collections.Generic.List[object]]::new()
    foreach ($phase in @('warmup', 'sample')) {
        $rounds = if ($phase -ceq 'warmup') { $WarmupRounds } else { $SampleRounds }
        for ($round = 0; $round -lt $rounds; $round++) {
            $child = Invoke-FreshPowerShell -Executable $pwsh -ChildPath $childPath `
                -ModulePath $modulePath -SocketPath $fixture.SocketPath -TmuxPath $binary `
                -WorkingDirectory $fixture.DirectoryPath -ExpectedPaneIds $expected `
                -Phase $phase -Round $round -CancellationToken $budget.Token
            if ($child.coreAssemblyMvid -cne $first.coreAssemblyMvid -or
                $child.cmdletAssemblyMvid -cne $first.cmdletAssemblyMvid) {
                throw "$phase/$round loaded different core or cmdlet assembly bytes."
            }
            if ($phase -ceq 'warmup') { $warmups.Add($child.record) }
            else { $samples.Add($child.record) }
        }
    }
    $after = Get-NativePaneIdentity $fixture
    Assert-BenchmarkPaneIdentity -Reference $expected -Observed $after -Lane 'topology after samples'

    $summary = [ordered]@{}
    foreach ($field in @('launchToExitNanoseconds', 'importNanoseconds',
        'serverConstructionNanoseconds', 'firstSnapshotNanoseconds')) {
        $summary[$field] = Get-TimingSummary ([long[]] @($samples | ForEach-Object { $_[$field] }))
    }
    $sourceRoot = Split-Path (Split-Path $PSScriptRoot)
    $report = [ordered]@{
        schema = 1
        status = 'PASS'
        recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        workload = 'fresh PowerShell process, package import, first sixteen-pane snapshot'
        shape = @{ sessions = 1; windows = 4; panes = 16; linkedWindows = 0 }
        parameters = @{ warmupRounds = $WarmupRounds; sampleRounds = $SampleRounds;
            perRunBudgetMinutes = 8; allSamplesUseFreshProcesses = $true }
        operation = 'pwsh -NoLogo -NoProfile -File Child.ps1; Import-Module; New-TmuxServer; Get-TmuxPane'
        provenance = @{
            sourceCommit = (git -C $sourceRoot rev-parse HEAD).Trim()
            sourceDirty = @((git -C $sourceRoot status --porcelain --untracked-files=all)).Count -gt 0
            runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
            childSha256 = (Get-FileHash -LiteralPath $childPath -Algorithm SHA256).Hash.ToLowerInvariant()
            checksSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/Checks.psm1" -Algorithm SHA256).Hash.ToLowerInvariant()
            packageSha256 = $identity.packageSha256
            packageVersion = '0.1.0'
            corePackageVersion = $identity.corePackageVersion
            coreAssemblySha256 = $identity.coreAssemblySha256
            cmdletAssemblySha256 = $identity.cmdletAssemblySha256
            sourceProvenance = $identity.sourceProvenance
            reviewCoreRevision = $identity.reviewCoreRevision
            reviewPortRevision = $identity.reviewPortRevision
            packageIdentitySha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/../PackageIdentity.psm1" -Algorithm SHA256).Hash.ToLowerInvariant()
            coreAssemblyMvid = $first.coreAssemblyMvid
            cmdletAssemblyMvid = $first.cmdletAssemblyMvid
            powerShellVersion = $PSVersionTable.PSVersion.ToString()
            powerShellSha256 = (Get-FileHash -LiteralPath $pwsh -Algorithm SHA256).Hash.ToLowerInvariant()
            dotnetRuntimeVersion = [Environment]::Version.ToString()
            tmuxVersion = $tmuxVersion
            tmuxSha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
            os = [Runtime.InteropServices.RuntimeInformation]::OSDescription
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
            logicalProcessorCount = [Environment]::ProcessorCount
        }
        timing = @{ packageExtractionNanoseconds = ConvertTo-NanosecondCount $extractWatch.ElapsedTicks;
            fixtureSetupNanoseconds = ConvertTo-NanosecondCount $fixtureWatch.ElapsedTicks;
            totalBeforeReportWriteNanoseconds = ConvertTo-NanosecondCount $runWatch.ElapsedTicks;
            launchTiming = 'parent Process.Start through child exit';
            childTiming = 'in-process stopwatch; import, server construction, then first snapshot';
            sampleScope = 'excludes package extraction and tmux fixture setup' }
        expectedPaneIds = [string[]] @($expected | Sort-Object -CaseSensitive)
        nativePaneIdsAfter = [string[]] @($after | Sort-Object -CaseSensitive)
        firstCalls = $firstCalls.ToArray()
        warmups = $warmups.ToArray()
        samples = $samples.ToArray()
        summary = $summary
        cleanup = $cleanup
    }
} finally {
    try {
        if ($fixture) {
            Remove-OwnedTmuxFixture $fixture
            $cleanup.fixtureRemoved = !(Test-Path -LiteralPath $fixture.DirectoryPath)
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Recurse -Force
        }
        $cleanup.extractedPackageRemoved = !(Test-Path -LiteralPath $temporary)
        $budget.Dispose()
    }
}

if (!$cleanup.fixtureRemoved -or !$cleanup.extractedPackageRemoved) {
    throw 'Cold PowerShell benchmark did not remove its owned fixture and package extraction.'
}
$parent = Split-Path $destination
if (!(Test-Path -LiteralPath $parent)) {
    $null = New-Item -ItemType Directory -Path $parent -Force
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -NoNewline
"PASS cold PowerShell: $SampleRounds fresh-process samples; report: $destination"
