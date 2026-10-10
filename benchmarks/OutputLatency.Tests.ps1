[CmdletBinding()]
param(
    [string] $PackageRoot,
    [string] $ReviewRoot,
    [string] $TmuxBinaryPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/OutputLatency.Checks.psm1" -Force

$valid = @{
    token = 'LTB-expected'; expectedPaneId = '%1'; eventPaneId = '%1'
    eventText = "LTB-expected`r`n"; captureText = 'LTB-expected'
    markerTicks = 10L; pollerReadyTicks = 20L; startTicks = 30L
    eventTicks = 40L; captureTicks = 50L; deadlineTicks = 100L
    eventFragments = 1; captureAttempts = 2
    dropped = $false; initialAbsent = $true
}
Assert-OutputLatencyRound -Observation $valid -Lane 'positive'

foreach ($case in @(
    @{ name = 'wrong output token'; key = 'eventText'; value = 'other' },
    @{ name = 'wrong captured token'; key = 'captureText'; value = 'other' },
    @{ name = 'wrong pane'; key = 'eventPaneId'; value = '%2' },
    @{ name = 'dropped output'; key = 'dropped'; value = $true },
    @{ name = 'token already present'; key = 'initialAbsent'; value = $false },
    @{ name = 'unready watcher'; key = 'markerTicks'; value = 0L },
    @{ name = 'poller armed after send'; key = 'pollerReadyTicks'; value = 31L },
    @{ name = 'event before send'; key = 'eventTicks'; value = 29L },
    @{ name = 'event after deadline'; key = 'eventTicks'; value = 101L },
    @{ name = 'capture after deadline'; key = 'captureTicks'; value = 101L },
    @{ name = 'empty output'; key = 'eventFragments'; value = 0 },
    @{ name = 'no capture attempts'; key = 'captureAttempts'; value = 0 }
)) {
    $invalid = @{} + $valid
    $invalid[$case.key] = $case.value
    $rejected = $false
    try { Assert-OutputLatencyRound -Observation $invalid -Lane $case.name } catch { $rejected = $true }
    if (!$rejected) { throw "Output latency check accepted $($case.name)." }
}
'PASS output latency negative controls'

if ($PackageRoot) {
    # Outer integration: two real-tmux observations through the installed package.
    $output = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-output-latency-' +
        [Guid]::NewGuid().ToString('N') + '.json')
    try {
        $arguments = @{ PackageRoot = $PackageRoot; OutputPath = $output;
            WarmupRounds = 0; SampleRounds = 2 }
        if ($TmuxBinaryPath) { $arguments.TmuxBinaryPath = $TmuxBinaryPath }
        if ($ReviewRoot) { $arguments.ReviewRoot = $ReviewRoot }
        & "$PSScriptRoot/OutputLatency.ps1" @arguments
        $report = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        if ($report.status -cne 'PASS' -or @($report.samples).Count -ne 2 -or
            !$report.cleanup.controlDisconnected -or !$report.cleanup.fixtureRemoved -or
            !$report.provenance.corePackageVersion -or !$report.provenance.packageSha256 -or
            $report.provenance.sourceProvenance -cne $(if ($ReviewRoot) { 'verified' } else { 'unverified' })) {
            throw 'The installed output latency smoke omitted observations, identity or cleanup.'
        }
    } finally {
        Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
    }
    'PASS installed output latency smoke'
}
