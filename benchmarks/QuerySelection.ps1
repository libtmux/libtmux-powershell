[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $ReviewRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source,
    [ValidateRange(0, 20)] [int] $WarmupRounds = 3,
    [ValidateRange(1, 100)] [int] $SampleRounds = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-PlacementIdentity($Rows) {
    @($Rows | ForEach-Object { "$($_.Session.Id)/$($_.Window.Id)/$($_.Window.Index)/$($_.Id)" })
}

function Assert-CompleteQueryGraph($Snapshot, [string] $SharedWindowId, [string] $TargetPaneId) {
    if ($Snapshot.Sessions.Count -ne 3 -or $Snapshot.Windows.Count -ne 11 -or
        $Snapshot.Panes.Count -ne 33 -or
        @($Snapshot.Windows | ForEach-Object { $_.Id.ToString() } | Select-Object -Unique).Count -ne 9 -or
        @($Snapshot.Panes | ForEach-Object { $_.Id.ToString() } | Select-Object -Unique).Count -ne 27) {
        throw 'The captured graph has incomplete session, window, or pane placements.'
    }
    $shared = @($Snapshot.Windows | Where-Object { $_.Id.ToString() -ceq $SharedWindowId })
    $selected = @($Snapshot.Panes | Where-Object { $_.Id.ToString() -ceq $TargetPaneId })
    if ($shared.Count -ne 3 -or $selected.Count -ne 3 -or
        @($shared | Where-Object { $_.LinkedSessions.Count -ne 2 -or $_.Panes.Count -ne 3 }).Count -ne 0) {
        throw 'The captured graph lost linked window or pane placements.'
    }
    foreach ($session in $Snapshot.Sessions) {
        if (![object]::ReferenceEquals($session.Server, $Snapshot)) {
            throw 'A captured session escaped the snapshot root.'
        }
    }
    foreach ($window in $Snapshot.Windows) {
        if (![object]::ReferenceEquals($window.Server, $Snapshot) -or
            ![object]::ReferenceEquals($window.Session.Server, $Snapshot)) {
            throw 'A captured window escaped the snapshot root.'
        }
    }
    foreach ($pane in $Snapshot.Panes) {
        if (![object]::ReferenceEquals($pane.Server, $Snapshot) -or
            ![object]::ReferenceEquals($pane.Window.Server, $Snapshot) -or
            ![object]::ReferenceEquals($pane.Session, $pane.Window.Session)) {
            throw 'A captured pane escaped its parent placement.'
        }
    }
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

$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) { throw 'PackageRoot must contain LibTmux.0.1.0.nupkg.' }
$binary = (Resolve-Path -LiteralPath $TmuxBinaryPath).Path
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $destination) { throw 'OutputPath already exists; choose a new report path.' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-query-selection-' + [Guid]::NewGuid().ToString('N'))
$fixture = $null
$report = $null
$null = New-Item -ItemType Directory -Path $temporary
try {
    $extractWatch = [Diagnostics.Stopwatch]::StartNew()
    $module = Join-Path $temporary 'LibTmux/0.1.0'
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $module)
    $extractWatch.Stop()
    Import-Module "$PSScriptRoot/PackageIdentity.psm1" -Force
    $identity = Get-BenchmarkPackageIdentity -PackageRoot $PackageRoot -ModuleRoot $module -ReviewRoot $ReviewRoot
    $importWatch = [Diagnostics.Stopwatch]::StartNew()
    Import-Module (Join-Path $module 'LibTmux.psd1') -ErrorAction Stop
    $importWatch.Stop()
    Import-Module "$PSScriptRoot/QuerySelection.Checks.psm1" -Force
    . "$PSScriptRoot/../tests/support/OwnedTmux.ps1"

    $setupWatch = [Diagnostics.Stopwatch]::StartNew()
    $fixture = New-OwnedTmuxFixture -TmuxPath $binary
    $targetPaneId = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:0.0',
        '#{pane_id}')).StdOut.Trim()
    $sharedWindowId = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:0',
        '#{window_id}')).StdOut.Trim()
    foreach ($session in @('bench1', 'bench2')) {
        $null = Invoke-OwnedTmux $fixture -Arguments @('new-session', '-d', '-s', $session, 'exec /bin/cat')
    }
    foreach ($session in @('fixture', 'bench1', 'bench2')) {
        foreach ($window in 1..2) {
            $null = Invoke-OwnedTmux $fixture -Arguments @('new-window', '-d', '-t', "${session}:",
                '-n', "query-$session-$window", 'exec /bin/cat')
        }
        foreach ($window in 0..2) {
            foreach ($pane in 1..2) {
                $null = Invoke-OwnedTmux $fixture -Arguments @('split-window', '-d', '-t',
                    "${session}:$window", 'exec /bin/cat')
            }
        }
    }
    $null = Invoke-OwnedTmux $fixture -Arguments @('link-window', '-d', '-s', 'fixture:0', '-t', 'fixture:5')
    $null = Invoke-OwnedTmux $fixture -Arguments @('link-window', '-d', '-s', 'fixture:0', '-t', 'bench1:5')
    Register-OwnedTmuxPane $fixture
    $setupWatch.Stop()
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $binary -ConfigurationFile '/dev/null'
    $tmuxVersion = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()
    $daemonVersion = [LibTmux.TmuxVersion]::Parse($tmuxVersion)
    $native = (Invoke-OwnedTmux $fixture -Arguments @('list-panes', '-a', '-F',
        '#{session_id}/#{window_id}/#{window_index}/#{pane_id}')).StdOut.TrimEnd("`r", "`n").Split("`n")
    $nativePlacements = [string[]] @($native | Where-Object { $_.EndsWith("/$targetPaneId", [StringComparison]::Ordinal) })
    if ($native.Count -ne 33 -or $nativePlacements.Count -ne 3) {
        throw 'Native tmux did not expose thirty-three pane placements and three linked target placements.'
    }
    $captureWatch = [Diagnostics.Stopwatch]::StartNew()
    $captured = $server | LibTmux\Get-TmuxSnapshot -Depth Panes -ErrorAction Stop
    $captureWatch.Stop()
    Assert-CompleteQueryGraph $captured $sharedWindowId $targetPaneId
    $queryWatch = [Diagnostics.Stopwatch]::StartNew()
    $query = LibTmux\New-TmuxQuery -Target Pane -Criteria @{ Id = $targetPaneId }
    $plans = @{}
    $gaps = [Collections.Generic.List[object]]::new()
    $queryWatch.Stop()
    $reference = [string[]] @(Get-PlacementIdentity @($captured.Panes | Where-Object {
                $_.Id.ToString() -ceq $targetPaneId }))
    Assert-BenchmarkQuerySelection -ExpectedPlacements $nativePlacements -ObservedPlacements $reference `
        -ExpectedSessions 3 -ObservedSessions $captured.Sessions.Count `
        -ExpectedWindows 11 -ObservedWindows $captured.Windows.Count `
        -ExpectedPanes 33 -ObservedPanes $captured.Panes.Count -Lane 'native/captured reference'
    $preflight = [Collections.Generic.List[object]]::new()
    foreach ($mode in @('Never', 'Auto', 'Require')) {
        $planWatch = [Diagnostics.Stopwatch]::StartNew()
        try {
            $plan = $query | LibTmux\Get-TmuxQueryPlan -DaemonVersion $daemonVersion -Pushdown $mode -ErrorAction Stop
        } catch [LibTmux.UnsupportedQueryExpressionException] {
            if ($mode -ne 'Require') { throw }
            $gaps.Add(@{ mode = $mode; reason = 'Exact source pushdown is unsupported';
                detail = $_.Exception.Message })
            continue
        }
        $planWatch.Stop()
        $result = $server | LibTmux\Invoke-TmuxQuery -Plan $plan -AsResult -ErrorAction Stop
        Assert-CompleteQueryGraph $result.Snapshot $sharedWindowId $targetPaneId
        $identities = [string[]] @(Get-PlacementIdentity $result)
        Assert-BenchmarkQuerySelection -ExpectedPlacements $reference -ObservedPlacements $identities `
            -ExpectedSessions 3 -ObservedSessions $result.Snapshot.Sessions.Count `
            -ExpectedWindows 11 -ObservedWindows $result.Snapshot.Windows.Count `
            -ExpectedPanes 33 -ObservedPanes $result.Snapshot.Panes.Count -Lane "preflight/$mode"
        $plans[$mode] = $plan
        $preflight.Add(@{ mode = $mode; status = 'equivalent';
            planNanoseconds = [long] [Math]::Round(
                $planWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            pushed = $null -ne $plan.PushedPredicate; residual = $null -ne $plan.ResidualPredicate;
            fallbackReasons = @($plan.FallbackReasons);
            placements = $identities })
    }

    $lanes = @('where-object', 'structured-local') + @($plans.Keys | Sort-Object | ForEach-Object { "source-$_" })
    $operations = @{
        'where-object' = { [pscustomobject]@{ rows = @($captured.Panes | Where-Object {
                        $_.Id.ToString() -ceq $targetPaneId }); snapshot = $captured } }
        'structured-local' = { [pscustomobject]@{ rows = @($captured.Panes |
                    LibTmux\Select-TmuxPane -Query $query -ErrorAction Stop); snapshot = $captured } }
    }
    foreach ($mode in $plans.Keys) {
        $selectedMode = $mode
        $operations["source-$mode"] = {
            $result = $server | LibTmux\Invoke-TmuxQuery -Plan $plans[$selectedMode] -AsResult -ErrorAction Stop
            [pscustomobject]@{ rows = $result; snapshot = $result.Snapshot }
        }.GetNewClosure()
    }
    $firstCalls = [Collections.Generic.List[object]]::new()
    $warmups = [Collections.Generic.List[object]]::new()
    $samples = [Collections.Generic.List[object]]::new()
    foreach ($phase in @('firstCall', 'warmup', 'sample')) {
        $rounds = switch ($phase) {
            firstCall { 1 }
            warmup { $WarmupRounds }
            sample { $SampleRounds }
        }
        for ($round = 0; $round -lt $rounds; $round++) {
            for ($position = 0; $position -lt $lanes.Count; $position++) {
                $lane = if ($phase -eq 'firstCall') { $lanes[$position] } else {
                    $lanes[($round + $position) % $lanes.Count]
                }
                $watch = [Diagnostics.Stopwatch]::StartNew()
                $actual = & $operations[$lane]
                $watch.Stop()
                Assert-CompleteQueryGraph $actual.snapshot $sharedWindowId $targetPaneId
                $placements = [string[]] @(Get-PlacementIdentity $actual.rows)
                $local = $lane -in @('where-object', 'structured-local')
                Assert-BenchmarkQuerySelection -ExpectedPlacements $reference -ObservedPlacements $placements `
                    -ExpectedSessions 3 -ObservedSessions $actual.snapshot.Sessions.Count `
                    -ExpectedWindows 11 -ObservedWindows $actual.snapshot.Windows.Count `
                    -ExpectedPanes 33 -ObservedPanes $actual.snapshot.Panes.Count `
                    -Lane "$phase/$round/$lane" -RequireOrder:$local
                if ($local) {
                    $rows = @($actual.rows)
                    $nativeRows = @($captured.Panes | Where-Object { $_.Id.ToString() -ceq $targetPaneId })
                    for ($index = 0; $index -lt $rows.Count; $index++) {
                        if (![object]::ReferenceEquals($rows[$index], $nativeRows[$index])) {
                            throw "$phase/$round/$lane replaced a captured object reference."
                        }
                    }
                }
                $record = @{ round = $round; position = $position; lane = $lane;
                    elapsedNanoseconds = [long] [Math]::Round(
                        $watch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
                    placements = $placements; graphComplete = $true;
                    graph = @{ sessions = $actual.snapshot.Sessions.Count;
                        windowPlacements = $actual.snapshot.Windows.Count;
                        panePlacements = $actual.snapshot.Panes.Count };
                    sameCapturedSnapshot = [object]::ReferenceEquals($actual.snapshot, $captured) }
                switch ($phase) {
                    firstCall { $firstCalls.Add($record) }
                    warmup { $warmups.Add($record) }
                    sample { $samples.Add($record) }
                }
            }
        }
    }

    $borrowedSessionAlive = @($server | LibTmux\Get-TmuxSession -Name 'fixture' -ErrorAction Stop).Count -eq 1 -and
        !$fixture.ServerProcess.HasExited
    if (!$borrowedSessionAlive) { throw 'Query selection changed the borrowed session or daemon.' }
    $summary = foreach ($lane in $lanes) {
        $values = [long[]] @($samples | Where-Object lane -EQ $lane | ForEach-Object elapsedNanoseconds)
        @{ lane = $lane; scope = $(if ($lane.StartsWith('source-')) {
                    'fresh source acquisition and selection'
                } else { 'selection over one captured snapshot' }); timing = (Get-TimingSummary $values) }
    }
    $sourceCommit = (git -C (Split-Path $PSScriptRoot) rev-parse HEAD).Trim()
    $sourceDirty = @((git -C (Split-Path $PSScriptRoot) status --porcelain --untracked-files=all)).Count -gt 0
    $report = [ordered]@{
        schema = 1
        status = $(if ($gaps.Count -eq 0) { 'PASS' } else { 'PARTIAL' })
        recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        workload = 'select one linked pane ID across a complete three-session graph'
        lanes = $lanes
        gaps = $gaps.ToArray()
        preflight = $preflight.ToArray()
        shape = @{ sessions = 3; uniqueWindows = 9; windowPlacements = 11;
            uniquePanes = 27; panePlacements = 33; addedWindowLinks = 2 }
        parameters = @{ warmupRounds = $WarmupRounds; sampleRounds = $SampleRounds;
            sampling = 'serial, rotating lane order';
            localSnapshotReused = $true; sourceQueriesAcquireFreshSnapshots = $true }
        semantics = @{ local = 'Where-Object and Select-TmuxPane receive the same captured pane objects';
            source = 'Never/Auto/Require join only after exact placement and complete graph preflight';
            timing = 'local filter cost and fresh source acquisition cost are different scopes' }
        provenance = @{ sourceCommit = $sourceCommit; sourceDirty = $sourceDirty;
            runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();
            checksSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/QuerySelection.Checks.psm1" -Algorithm SHA256).Hash.ToLowerInvariant();
            packageVersion = (Get-Module LibTmux).Version.ToString();
            corePackageVersion = $identity.corePackageVersion;
            packageSha256 = $identity.packageSha256;
            coreAssemblySha256 = $identity.coreAssemblySha256;
            cmdletAssemblySha256 = $identity.cmdletAssemblySha256;
            sourceProvenance = $identity.sourceProvenance;
            reviewCoreRevision = $identity.reviewCoreRevision;
            reviewPortRevision = $identity.reviewPortRevision;
            packageIdentitySha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/PackageIdentity.psm1" -Algorithm SHA256).Hash.ToLowerInvariant();
            tmuxVersion = $tmuxVersion;
            tmuxSha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant();
            powerShellVersion = $PSVersionTable.PSVersion.ToString();
            dotnetRuntimeVersion = [Environment]::Version.ToString();
            os = [Runtime.InteropServices.RuntimeInformation]::OSDescription;
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();
            coreAssemblyMvid = [LibTmux.Server].Assembly.ManifestModule.ModuleVersionId.ToString();
            cmdletAssemblyMvid = [LibTmux.PowerShell.SelectTmuxPaneCommand].Assembly.ManifestModule.ModuleVersionId.ToString() }
        timing = @{ packageExtractNanoseconds = [long] [Math]::Round(
                $extractWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            moduleImportNanoseconds = [long] [Math]::Round(
                $importWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            fixtureSetupNanoseconds = [long] [Math]::Round(
                $setupWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            snapshotCaptureNanoseconds = [long] [Math]::Round(
                $captureWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            queryConstructionNanoseconds = [long] [Math]::Round(
                $queryWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            firstCallsIncludeJit = $true; warmSamplesExcludeSetupAndFirstCalls = $true }
        targetPaneId = $targetPaneId
        sharedWindowId = $sharedWindowId
        expectedPlacements = $reference
        nativePlacements = $nativePlacements
        cleanup = @{ borrowedSessionAlive = $borrowedSessionAlive }
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
$report.cleanup.ownedFixtureRemoved = $fixture.Closed -and !(Test-Path -LiteralPath $fixture.DirectoryPath)
$report.cleanup.extractedPackageRemoved = !(Test-Path -LiteralPath $temporary)
if (!$report.cleanup.ownedFixtureRemoved -or !$report.cleanup.extractedPackageRemoved) {
    throw 'Query selection cleanup did not remove the owned fixture and extracted package.'
}
$parent = Split-Path $destination
if (!(Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -NoNewline
"$($report.status) query selection: $SampleRounds rounds per lane; report: $destination"
