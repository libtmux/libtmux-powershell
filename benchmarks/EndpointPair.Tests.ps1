[CmdletBinding()]
param(
    [string] $PackageRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/EndpointPair.Checks.psm1" -Force

$expected = [string[]] @('server-A|pane-A', 'server-B|pane-B')
$ordered = @(
    [pscustomobject]@{ index = 0; reply = $expected[0] }
    [pscustomobject]@{ index = 1; reply = $expected[1] }
)
$reversed = @($ordered[1], $ordered[0])
$cases = @(
    @{ name = 'wrong socket reply'; observed = @([pscustomobject]@{ index = 0; reply = $expected[1] }, $ordered[1]); state = $expected; serial = $false },
    @{ name = 'duplicate endpoint'; observed = @($ordered[0], $ordered[0]); state = $expected; serial = $false },
    @{ name = 'missing endpoint'; observed = @($ordered[0]); state = $expected; serial = $false },
    @{ name = 'changed topology'; observed = $ordered; state = @($expected[0], 'different'); serial = $false },
    @{ name = 'serial reordering'; observed = $reversed; state = $expected; serial = $true }
)
foreach ($case in $cases) {
    $rejected = $false
    try {
        Assert-EndpointPairReplySet -Expected $expected -Observed $case.observed -StateAfter $case.state `
            -Lane $case.name -RequireOrder:$case.serial
    } catch { $rejected = $_.Exception.Message.Contains($case.name) }
    if (!$rejected) { throw "Endpoint equality accepted $($case.name)." }
}
Assert-EndpointPairReplySet -Expected $expected -Observed $ordered -StateAfter $expected -Lane 'serial positive' -RequireOrder
Assert-EndpointPairReplySet -Expected $expected -Observed $reversed -StateAfter $expected -Lane 'concurrent positive'

if ($PackageRoot) {
    $output = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-endpoint-pair-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & "$PSScriptRoot/EndpointPair.ps1" -PackageRoot $PackageRoot -TmuxBinaryPath $TmuxBinaryPath `
            -OutputPath $output -WarmupRounds 0 -SampleRounds 2
        $report = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        if ($report.status -cne 'PASS' -or @($report.expectedReplies).Count -ne 2 -or
            @($report.lanes).Count -ne 3 -or @($report.firstCalls).Count -ne 3 -or
            @($report.samples).Count -ne 6 -or !$report.cleanup.firstFixtureRemoved -or
            !$report.cleanup.secondFixtureRemoved -or !$report.cleanup.extractedPackageRemoved) {
            throw 'The endpoint pair report omitted a lane, sample, identity, or cleanup check.'
        }
        if ($report.provenance.runnerSha256 -cne (Get-FileHash "$PSScriptRoot/EndpointPair.ps1").Hash.ToLowerInvariant() -or
            $report.provenance.checksSha256 -cne (Get-FileHash "$PSScriptRoot/EndpointPair.Checks.psm1").Hash.ToLowerInvariant() -or
            $report.provenance.corePackageVersion -cne '0.0.0-alpha.16.ps.2') {
            throw 'The endpoint pair report did not identify its runner, checks, or core package.'
        }
    } finally {
        if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output }
    }
    'PASS endpoint pair negative controls and installed smoke'
} else {
    'PASS endpoint pair negative controls'
}
