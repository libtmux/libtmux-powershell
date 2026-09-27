[CmdletBinding()]
param(
    [string] $PackageRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/CaptureSize.Checks.psm1" -Force

$rejected = $false
try {
    Assert-BenchmarkCaptureEqual -Reference "first`nsecond" -Observed "first`nchanged" -Lane 'negative control'
} catch {
    $rejected = $_.Exception.Message.Contains('negative control')
}
if (!$rejected) { throw 'Capture equality accepted changed text.' }
Assert-BenchmarkCaptureEqual -Reference "first`nsecond" -Observed "first`nsecond" -Lane 'positive control'

$rejected = $false
try {
    Assert-BenchmarkCaptureFixture -ExpectedLines @('first', 'second') -Observed "first`nchanged" -Size 'negative control'
} catch {
    $rejected = $_.Exception.Message.Contains('negative control')
}
if (!$rejected) { throw 'Capture fixture check accepted changed payload text.' }
Assert-BenchmarkCaptureFixture -ExpectedLines @('first', 'second') -Observed "first`nsecond`n" -Size 'positive control'

if ($PackageRoot) {
    $output = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-capture-size-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & "$PSScriptRoot/CaptureSize.ps1" -PackageRoot $PackageRoot -TmuxBinaryPath $TmuxBinaryPath `
            -OutputPath $output -WarmupRounds 1 -SampleRounds 2
        $report = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        if ($report.status -cne 'PASS' -or @($report.cells).Count -ne 3 -or
            @($report.firstCalls).Count -ne 6 -or @($report.warmups).Count -ne 6 -or
            @($report.samples).Count -ne 12 -or !$report.cleanup.fixtureRemoved -or
            !$report.cleanup.extractedPackageRemoved) {
            throw 'The live capture benchmark omitted a size, sample, or cleanup check.'
        }
        if ($report.provenance.runnerSha256 -cne (Get-FileHash "$PSScriptRoot/CaptureSize.ps1").Hash.ToLowerInvariant() -or
            $report.provenance.checksSha256 -cne (Get-FileHash "$PSScriptRoot/CaptureSize.Checks.psm1").Hash.ToLowerInvariant()) {
            throw 'The capture report did not identify the exact benchmark source.'
        }
        $bytes = @($report.cells | ForEach-Object captureBytes)
        if (!($bytes[0] -gt 0 -and $bytes[0] -lt $bytes[1] -and $bytes[1] -lt $bytes[2])) {
            throw 'The capture fixture sizes did not increase.'
        }
        foreach ($sample in $report.samples) {
            $cell = $report.cells | Where-Object size -CEQ $sample.size | Select-Object -First 1
            if ($sample.captureBytes -ne $cell.captureBytes) {
                throw 'A capture sample returned a changed payload size.'
            }
        }
    } finally {
        Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue
    }
}

if ($PackageRoot) {
    'PASS capture size: unequal text rejected; installed lanes and cleanup agree'
} else {
    'PASS capture size: unequal text rejected'
}
