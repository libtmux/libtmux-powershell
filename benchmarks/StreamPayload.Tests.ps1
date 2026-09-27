[CmdletBinding()]
param(
    [string] $PackageRoot,
    [string] $ReviewRoot,
    [string] $TmuxBinaryPath,
    [string] $BodyLineCounts = '12',
    [ValidateRange(100, 3000)] [int] $ObservationTimeoutMilliseconds = 1000
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/StreamPayload.Checks.psm1" -Force

$begin = 'LTSP_BEGIN_abcd'
$end = 'LTSP_END_abcd'
$payload = "$begin`nline-01-abcdef`nline-02-ghijkl`n$end"
$valid = @{
    beginMarker = $begin; endMarker = $end; payload = $payload
    expectedPaneId = '%1'; eventPaneId = '%1'
    eventRaw = "prefix`r`n$($payload.Replace("`n", "`r`n"))`r`n"
    captureText = "shell-prompt`n$payload`n"
    markerTicks = 10L; pollerReadyTicks = 20L; startTicks = 30L
    producerDoneTicks = 35L; eventTicks = 40L; captureTicks = 50L; deadlineTicks = 100L
    eventFragments = 2; captureAttempts = 2; dropped = $false; initialAbsent = $true
}
$checked = Assert-StreamPayloadRound -Observation $valid -Lane 'positive'
if (!$checked -or !$checked.payloadSha256) { throw 'Valid payload produced no checked result.' }

$defaultSizes = @(Assert-StreamPayloadSizePlan '12')
$scaleSizes = @(Assert-StreamPayloadSizePlan '12,256,768')
if ($defaultSizes.Count -ne 1 -or $defaultSizes[0] -ne 12 -or
    ($scaleSizes -join ',') -cne '12,256,768') {
    throw 'The size plan changed the default or reordered the requested payloads.'
}
foreach ($invalidSizes in @('', '12,12', '256,12', '0', '769', '12,256,768,769', '12,nan')) {
    $rejected = $false
    try { $null = Assert-StreamPayloadSizePlan $invalidSizes } catch { $rejected = $true }
    if (!$rejected) { throw "The size plan accepted '$invalidSizes'." }
}
$rate = Get-StreamPayloadEffectiveBytesPerSecond -PayloadBytes 1024 -CompletionNanoseconds 1000000000
if ($rate -ne 1024) { throw 'The effective observation rate used the wrong units.' }
foreach ($invalidRate in @(@{ bytes = 0; nanoseconds = 1 }, @{ bytes = 1; nanoseconds = 0 })) {
    $rejected = $false
    try {
        $null = Get-StreamPayloadEffectiveBytesPerSecond -PayloadBytes $invalidRate.bytes `
            -CompletionNanoseconds $invalidRate.nanoseconds
    } catch { $rejected = $true }
    if (!$rejected) { throw 'The effective observation rate accepted an invalid denominator or byte count.' }
}

foreach ($case in @(
    @{ name = 'truncated event'; key = 'eventRaw'; value = "$begin`r`nline-01-abcdef`r`n$end" },
    @{ name = 'reordered event'; key = 'eventRaw'; value = "$begin`r`nline-02-ghijkl`r`nline-01-abcdef`r`n$end" },
    @{ name = 'missing captured line'; key = 'captureText'; value = "$begin`nline-01-abcdef`n$end" },
    @{ name = 'duplicate captured block'; key = 'captureText'; value = "$payload`n$payload" },
    @{ name = 'wrong pane'; key = 'eventPaneId'; value = '%2' },
    @{ name = 'dropped output'; key = 'dropped'; value = $true },
    @{ name = 'unready watcher'; key = 'markerTicks'; value = 0L },
    @{ name = 'poller armed after production'; key = 'pollerReadyTicks'; value = 31L },
    @{ name = 'event before production'; key = 'eventTicks'; value = 29L },
    @{ name = 'event after deadline'; key = 'eventTicks'; value = 101L },
    @{ name = 'capture after deadline'; key = 'captureTicks'; value = 101L },
    @{ name = 'empty event'; key = 'eventFragments'; value = 0 },
    @{ name = 'no capture attempts'; key = 'captureAttempts'; value = 0 }
)) {
    $invalid = @{} + $valid
    $invalid[$case.key] = $case.value
    $rejected = $false
    try { $null = Assert-StreamPayloadRound -Observation $invalid -Lane $case.name } catch { $rejected = $true }
    if (!$rejected) { throw "Stream payload check accepted $($case.name)." }
}
'PASS stream payload negative controls'

if ($PackageRoot) {
    $output = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-stream-payload-' +
        [Guid]::NewGuid().ToString('N') + '.json')
    try {
        $arguments = @{ PackageRoot = $PackageRoot; OutputPath = $output;
            WarmupRounds = 0; SampleRounds = 2; BodyLineCounts = $BodyLineCounts;
            ObservationTimeoutMilliseconds = $ObservationTimeoutMilliseconds }
        if ($TmuxBinaryPath) { $arguments.TmuxBinaryPath = $TmuxBinaryPath }
        if ($ReviewRoot) { $arguments.ReviewRoot = $ReviewRoot }
        & "$PSScriptRoot/StreamPayload.ps1" @arguments
        $report = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        $expectedSizes = @(Assert-StreamPayloadSizePlan $BodyLineCounts)
        if ($report.status -cne 'PASS' -or @($report.samples).Count -ne (2 * $expectedSizes.Count) -or
            !$report.cleanup.controlDisconnected -or !$report.cleanup.fixtureRemoved -or
            !$report.provenance.corePackageVersion -or !$report.provenance.packageSha256 -or
            $report.provenance.sourceProvenance -cne $(if ($ReviewRoot) { 'verified' } else { 'unverified' })) {
            throw 'The installed stream payload smoke omitted observations, identity or cleanup.'
        }
        foreach ($record in $report.samples) {
            if ($record.payloadSha256 -cne $record.eventPayloadSha256 -or
                $record.payloadSha256 -cne $record.capturePayloadSha256 -or
                $record.eventFragments -lt 1 -or $record.captureAttempts -lt 1 -or
                $record.bodyLines -notin $expectedSizes -or $record.eventEffectiveBytesPerSecond -le 0 -or
                $record.captureEffectiveBytesPerSecond -le 0) {
                throw 'The installed stream payload smoke omitted exact payload proof.'
            }
        }
        foreach ($size in $expectedSizes) {
            if (@($report.samples | Where-Object bodyLines -EQ $size).Count -ne 2) {
                throw "The installed stream payload smoke omitted a $size-line sample."
            }
        }
    } finally {
        Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
    }
    'PASS installed stream payload smoke'
}
