[CmdletBinding()]
param(
    [string] $PackageRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/CommandTransport.Checks.psm1" -Force

$rejected = $false
try {
    Assert-BenchmarkCommandReply -Expected 'fixture' -Observed 'other' -Lane 'negative control'
} catch {
    $rejected = $_.Exception.Message.Contains('negative control')
}
if (!$rejected) { throw 'The command benchmark accepted an unequal reply.' }
Assert-BenchmarkCommandReply -Expected 'fixture' -Observed 'fixture' -Lane 'positive control'

if ($PackageRoot) {
    $output = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-benchmark-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & "$PSScriptRoot/CommandTransport.ps1" -PackageRoot $PackageRoot -TmuxBinaryPath $TmuxBinaryPath `
            -OutputPath $output -WarmupRounds 1 -SampleRounds 2
        $report = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        if ($report.status -cne 'PASS' -or $report.expectedReply -cne 'fixture' -or
            @($report.lanes).Count -ne 3 -or @($report.samples).Count -ne 6 -or
            @($report.firstCalls).Count -ne 3 -or !$report.cleanup.controlDisconnected -or
            !$report.cleanup.borrowedSessionAlive) {
            throw 'The live command benchmark omitted a lane, sample, or cleanup check.'
        }
        if ($report.provenance.runnerSha256 -cne (Get-FileHash "$PSScriptRoot/CommandTransport.ps1").Hash.ToLowerInvariant() -or
            $report.provenance.checksSha256 -cne (Get-FileHash "$PSScriptRoot/CommandTransport.Checks.psm1").Hash.ToLowerInvariant()) {
            throw 'The command report did not identify its exact source.'
        }
    } finally {
        Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue
    }
}

if ($PackageRoot) {
    'PASS command transport benchmark: unequal reply rejected; live lanes and cleanup agree'
} else {
    'PASS command transport benchmark: unequal reply rejected'
}
