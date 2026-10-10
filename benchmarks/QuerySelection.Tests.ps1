[CmdletBinding()]
param(
    [string] $PackageRoot,
    [string] $ReviewRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/QuerySelection.Checks.psm1" -Force

$expected = [string[]] @('$0/@0/0/%0', '$0/@0/5/%0', '$1/@0/5/%0')
$cases = @(
    @{ name = 'wrong placement'; rows = @($expected[0], $expected[1], '$1/@1/5/%0'); windows = 11; order = $false }
    @{ name = 'duplicate placement'; rows = @($expected[0], $expected[0], $expected[2]); windows = 11; order = $false }
    @{ name = 'incomplete graph'; rows = $expected; windows = 10; order = $false }
    @{ name = 'local reorder'; rows = @($expected[2], $expected[1], $expected[0]); windows = 11; order = $true }
)
foreach ($case in $cases) {
    $rejected = $false
    try {
        Assert-BenchmarkQuerySelection -ExpectedPlacements $expected -ObservedPlacements $case.rows `
            -ExpectedSessions 3 -ObservedSessions 3 -ExpectedWindows 11 -ObservedWindows $case.windows `
            -ExpectedPanes 33 -ObservedPanes 33 -Lane $case.name -RequireOrder:$case.order
    } catch {
        $rejected = $_.Exception.Message.Contains($case.name)
    }
    if (!$rejected) { throw "Query selection accepted $($case.name)." }
}
Assert-BenchmarkQuerySelection -ExpectedPlacements $expected -ObservedPlacements $expected `
    -ExpectedSessions 3 -ObservedSessions 3 -ExpectedWindows 11 -ObservedWindows 11 `
    -ExpectedPanes 33 -ObservedPanes 33 -Lane 'local positive' -RequireOrder
Assert-BenchmarkQuerySelection -ExpectedPlacements $expected -ObservedPlacements @($expected[2], $expected[1], $expected[0]) `
    -ExpectedSessions 3 -ObservedSessions 3 -ExpectedWindows 11 -ObservedWindows 11 `
    -ExpectedPanes 33 -ObservedPanes 33 -Lane 'source positive'

$graph = @{
    sessions = [string[]] @('$0', '$1', '$2')
    windows = [string[]] @('$0/@0/0', '$0/@1/1', '$1/@0/5')
    panes = [string[]] @('$0/@0/0/%0', '$0/@1/1/%1', '$1/@0/5/%0')
}
Assert-BenchmarkQueryGraph -ExpectedSessionIds $graph.sessions -ObservedSessionIds @('$2', '$0', '$1') `
    -ExpectedWindowPlacements $graph.windows -ObservedWindowPlacements $graph.windows `
    -ExpectedPanePlacements $graph.panes -ObservedPanePlacements $graph.panes -Lane 'graph positive'
$graphCases = @(
    @{ name = 'wrong session'; sessions = @('$0', '$1', '$3'); windows = $graph.windows; panes = $graph.panes }
    @{ name = 'wrong window'; sessions = $graph.sessions;
        windows = @('$0/@0/0', '$0/@1/1', '$1/@0/6'); panes = $graph.panes }
    @{ name = 'wrong pane'; sessions = $graph.sessions; windows = $graph.windows;
        panes = @('$0/@0/0/%0', '$0/@1/1/%1', '$1/@0/5/%2') }
    @{ name = 'duplicate pane'; sessions = $graph.sessions; windows = $graph.windows;
        panes = @('$0/@0/0/%0', '$0/@1/1/%1', '$0/@1/1/%1') }
)
foreach ($case in $graphCases) {
    $rejected = $false
    try {
        Assert-BenchmarkQueryGraph -ExpectedSessionIds $graph.sessions -ObservedSessionIds $case.sessions `
            -ExpectedWindowPlacements $graph.windows -ObservedWindowPlacements $case.windows `
            -ExpectedPanePlacements $graph.panes -ObservedPanePlacements $case.panes -Lane $case.name
    } catch {
        $rejected = $_.Exception.Message.Contains($case.name)
    }
    if (!$rejected) { throw "Query graph accepted $($case.name)." }
}

if ($PackageRoot) {
    $output = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-query-selection-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & "$PSScriptRoot/QuerySelection.ps1" -PackageRoot $PackageRoot -ReviewRoot $ReviewRoot `
            -TmuxBinaryPath $TmuxBinaryPath -OutputPath $output -WarmupRounds 1 -SampleRounds 2
        $report = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        $receipt = if ($ReviewRoot) {
            Get-Content -LiteralPath (Join-Path $ReviewRoot 'bootstrap.json') -Raw | ConvertFrom-Json
        }
        if ($report.status -notin @('PASS', 'PARTIAL') -or @($report.shapes).Count -ne 2 -or
            !$report.cleanup.ownedFixtureRemoved -or !$report.cleanup.extractedPackageRemoved) {
            throw 'The query report omitted a topology or cleanup check.'
        }
        $expectedShapes = @{
            baseline = @{ sessions = 3; uniqueWindows = 9; windowPlacements = 11;
                uniquePanes = 27; panePlacements = 33; addedWindowLinks = 2 }
            expanded = @{ sessions = 5; uniqueWindows = 25; windowPlacements = 29;
                uniquePanes = 75; panePlacements = 87; addedWindowLinks = 4 }
        }
        foreach ($shape in $report.shapes) {
            $expectedShape = $expectedShapes[$shape.name]
            if (!$expectedShape) { throw "Query report has unexpected topology $($shape.name)." }
            foreach ($key in $expectedShape.Keys) {
                if ($shape.shape.$key -ne $expectedShape[$key]) {
                    throw "Query report topology $($shape.name) has wrong $key."
                }
            }
            $laneCount = @($shape.lanes).Count
            if ($laneCount -ne 2 + @($shape.preflight).Count -or
                @($shape.gaps).Count + @($shape.preflight).Count -ne 3 -or
                @($shape.samples).Count -ne 2 * $laneCount -or
                @($shape.firstCalls).Count -ne $laneCount -or
                @($shape.expectedPlacements).Count -ne $expectedShape.sessions -or
                @($shape.nativeGraph.sessions).Count -ne $expectedShape.sessions -or
                @($shape.nativeGraph.windows).Count -ne $expectedShape.windowPlacements -or
                @($shape.nativeGraph.panes).Count -ne $expectedShape.panePlacements -or
                !$shape.cleanup.ownedFixtureRemoved) {
                throw "Query report topology $($shape.name) omitted a lane, identity, or cleanup check."
            }
            foreach ($sample in $shape.samples) {
                if (@($sample.placements).Count -ne $expectedShape.sessions -or !$sample.graphComplete -or
                    $sample.graph.sessions -ne $expectedShape.sessions -or
                    $sample.graph.windowPlacements -ne $expectedShape.windowPlacements -or
                    $sample.graph.panePlacements -ne $expectedShape.panePlacements) {
                    throw "Query sample lost topology $($shape.name) placements or complete graph."
                }
            }
            $null = $expectedShapes.Remove($shape.name)
        }
        if ($expectedShapes.Count -ne 0) { throw 'Query report repeated a topology or omitted the expanded graph.' }
        if ($report.provenance.runnerSha256 -cne (Get-FileHash "$PSScriptRoot/QuerySelection.ps1").Hash.ToLowerInvariant() -or
            $report.provenance.checksSha256 -cne (Get-FileHash "$PSScriptRoot/QuerySelection.Checks.psm1").Hash.ToLowerInvariant() -or
            $report.provenance.packageIdentitySha256 -cne (Get-FileHash "$PSScriptRoot/PackageIdentity.psm1").Hash.ToLowerInvariant() -or
            $report.provenance.packageSha256 -cne (Get-FileHash (Join-Path $PackageRoot 'LibTmux.0.1.0.nupkg')).Hash.ToLowerInvariant() -or
            !$report.provenance.corePackageVersion -or !$report.provenance.coreAssemblySha256 -or
            !$report.provenance.cmdletAssemblySha256 -or
            $report.provenance.sourceProvenance -cne $(if ($ReviewRoot) { 'verified' } else { 'unverified' }) -or
            ($ReviewRoot -and ($report.provenance.corePackageVersion -cne $receipt.version -or
                $report.provenance.reviewCoreRevision -cne $receipt.coreRevision -or
                $report.provenance.reviewPortRevision -cne $receipt.portRevision)) -or
            (!$ReviewRoot -and ($report.provenance.reviewCoreRevision -or $report.provenance.reviewPortRevision))) {
            throw 'The query report did not identify exact benchmark source and dependency.'
        }
    } finally {
        Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue
    }
}

if ($PackageRoot) {
    'PASS query selection: wrong placements and graph rejected; installed lanes agree or disclose gaps'
} else {
    'PASS query selection: wrong placements and graph rejected'
}
