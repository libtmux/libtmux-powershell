[CmdletBinding()]
param(
    [string] $PackageRoot,
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

if ($PackageRoot) {
    $output = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-query-selection-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & "$PSScriptRoot/QuerySelection.ps1" -PackageRoot $PackageRoot -TmuxBinaryPath $TmuxBinaryPath `
            -OutputPath $output -WarmupRounds 1 -SampleRounds 2
        $report = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        $laneCount = @($report.lanes).Count
        if ($report.status -notin @('PASS', 'PARTIAL') -or $laneCount -ne 2 + @($report.preflight).Count -or
            @($report.gaps).Count + @($report.preflight).Count -ne 3 -or
            @($report.samples).Count -ne 2 * $laneCount -or @($report.firstCalls).Count -ne $laneCount -or
            @($report.expectedPlacements).Count -ne 3 -or $report.shape.panePlacements -ne 33 -or
            !$report.cleanup.ownedFixtureRemoved -or !$report.cleanup.extractedPackageRemoved) {
            throw 'The query report omitted a lane, placement, sample, or cleanup check.'
        }
        if ($report.provenance.runnerSha256 -cne (Get-FileHash "$PSScriptRoot/QuerySelection.ps1").Hash.ToLowerInvariant() -or
            $report.provenance.checksSha256 -cne (Get-FileHash "$PSScriptRoot/QuerySelection.Checks.psm1").Hash.ToLowerInvariant() -or
            $report.provenance.corePackageVersion -cne '0.0.0-alpha.16.ps.2') {
            throw 'The query report did not identify exact benchmark source and dependency.'
        }
        foreach ($sample in $report.samples) {
            if (@($sample.placements).Count -ne 3 -or !$sample.graphComplete) {
                throw 'A query sample lost placements or a complete graph.'
            }
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
