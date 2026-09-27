[CmdletBinding()]
param(
    [string] $PackageRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/EventStream.Checks.psm1" -Force

$events = @(
    [pscustomobject]@{ kind = 'dropped'; count = 7L; totalDropped = 17L }
    [pscustomobject]@{ kind = 'notification'; name = 'window-renamed'; arguments = @('@1', 'final') }
)
$cases = @(
    @{ name = 'wrong loss'; events = @([pscustomobject]@{ kind = 'dropped'; count = 6L; totalDropped = 16L }, $events[1]); state = 'final' }
    @{ name = 'wrong latest event'; events = @($events[0], [pscustomobject]@{ kind = 'notification'; name = 'window-renamed'; arguments = @('@1', 'older') }); state = 'final' }
    @{ name = 'wrong state'; events = $events; state = 'older' }
    @{ name = 'wrong cumulative loss'; events = @([pscustomobject]@{ kind = 'dropped'; count = 7L; totalDropped = 18L }, $events[1]); state = 'final' }
)
foreach ($case in $cases) {
    $rejected = $false
    try {
        $null = Assert-BenchmarkEventBurst -ExpectedBurst 8 -ExpectedWindowId '@1' -ExpectedFinalName 'final' `
            -Events $case.events -ObservedFinalName $case.state -PreviousTotalDropped 10 -Lane $case.name
    } catch {
        $rejected = $_.Exception.Message.Contains($case.name)
    }
    if (!$rejected) { throw "Event stream equality accepted $($case.name)." }
}
$accepted = Assert-BenchmarkEventBurst -ExpectedBurst 8 -ExpectedWindowId '@1' -ExpectedFinalName 'final' `
    -Events $events -ObservedFinalName 'final' -PreviousTotalDropped 10 -Lane 'positive control'
if ($accepted.produced -ne 8 -or $accepted.dropped -ne 7 -or $accepted.delivered -ne 1 -or
    $accepted.totalDropped -ne 17) { throw 'Event stream equality returned incorrect loss accounting.' }

if ($PackageRoot) {
    $output = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-event-stream-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & "$PSScriptRoot/EventStream.ps1" -PackageRoot $PackageRoot -TmuxBinaryPath $TmuxBinaryPath `
            -OutputPath $output -WarmupRounds 1 -SampleRounds 2
        $report = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        if ($report.status -cne 'PASS' -or $report.shape.panes -ne 1 -or
            @($report.cells).Count -ne 2 -or @($report.firstCalls).Count -ne 2 -or
            @($report.samples).Count -ne 4 -or !$report.cleanup.controlDisconnected -or
            !$report.cleanup.borrowedSessionAlive -or !$report.cleanup.ownedFixtureRemoved -or
            !$report.cleanup.extractedPackageRemoved) {
            throw 'The event stream report omitted a burst, sample, or cleanup check.'
        }
        if ($report.provenance.runnerSha256 -cne (Get-FileHash "$PSScriptRoot/EventStream.ps1").Hash.ToLowerInvariant() -or
            $report.provenance.checksSha256 -cne (Get-FileHash "$PSScriptRoot/EventStream.Checks.psm1").Hash.ToLowerInvariant() -or
            $report.provenance.corePackageVersion -cne '0.0.0-alpha.16.ps.2') {
            throw 'The event stream report did not identify exact benchmark source and dependency.'
        }
        foreach ($sample in $report.samples) {
            if ($sample.produced -ne $sample.delivered + $sample.dropped -or
                @($sample.events).Count -ne 2 -or $sample.finalName -cne $sample.nativeFinalName) {
                throw 'An event stream sample lost accounting, raw events, or native final state.'
            }
        }
    } finally {
        Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue
    }
}

if ($PackageRoot) {
    'PASS event stream: wrong loss and final state rejected; installed pressure samples agree'
} else {
    'PASS event stream: wrong loss and final state rejected'
}
