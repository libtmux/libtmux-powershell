[CmdletBinding()]
param(
    [string] $PackageRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/PaneEnumeration.Checks.psm1" -Force

$rejected = $false
try {
    Assert-BenchmarkPaneIdentity -Reference @('%1', '%2') -Observed @('%1', '%3') -Lane 'negative control'
} catch {
    $rejected = $_.Exception.Message.Contains('negative control')
}
if (!$rejected) { throw 'The benchmark accepted unequal pane IDs.' }
Assert-BenchmarkPaneIdentity -Reference @('%2', '%1') -Observed @('%1', '%2') -Lane 'positive control'

if ($PackageRoot) {
    $output = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-benchmark-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & "$PSScriptRoot/PaneEnumeration.ps1" -PackageRoot $PackageRoot -TmuxBinaryPath $TmuxBinaryPath `
            -OutputPath $output -WarmupRounds 1 -SampleRounds 2
        $report = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        if ($report.status -cne 'PASS' -or $report.shape.panes -ne 16 -or
            @($report.lanes).Count -ne 3 -or @($report.samples).Count -ne 6 -or
            @($report.firstCalls).Count -ne 3 -or @($report.expectedPaneIds).Count -ne 16) {
            throw 'The live benchmark omitted a lane, sample, or pane.'
        }
        if ($report.provenance.runnerSha256 -cne (Get-FileHash "$PSScriptRoot/PaneEnumeration.ps1").Hash.ToLowerInvariant() -or
            $report.provenance.checksSha256 -cne (Get-FileHash "$PSScriptRoot/PaneEnumeration.Checks.psm1").Hash.ToLowerInvariant()) {
            throw 'The report did not identify the exact benchmark source.'
        }
    } finally {
        Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue
    }
}

if ($PackageRoot) {
    'PASS pane enumeration benchmark: unequal IDs rejected; live lanes agree'
} else {
    'PASS pane enumeration benchmark: unequal IDs rejected'
}
