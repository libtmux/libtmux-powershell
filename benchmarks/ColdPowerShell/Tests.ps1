[CmdletBinding()]
param(
    [string] $PackageRoot,
    [string] $ExpectedPackageSha256,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop |
        Select-Object -First 1).Source
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/Checks.psm1" -Force -ErrorAction Stop

$valid = [pscustomobject]@{
    paneIds = @('%1', '%2')
    importNanoseconds = 100
    serverConstructionNanoseconds = 100
    firstSnapshotNanoseconds = 100
    moduleVersion = '0.1.0'
    coreAssemblyMvid = 'core-mvid'
    cmdletAssemblyMvid = 'cmdlet-mvid'
}
$expected = [string[]] @('%1', '%2')
Assert-ColdPowerShellResult -Result $valid -ExpectedPaneIds $expected -Lane 'positive'

foreach ($case in @(
    @{ name = 'wrong pane'; ids = @('%1', '%3'); import = 100 },
    @{ name = 'duplicate pane'; ids = @('%1', '%1'); import = 100 },
    @{ name = 'missing pane'; ids = @('%1'); import = 100 },
    @{ name = 'invalid import duration'; ids = @('%1', '%2'); import = 0 }
)) {
    $observed = [pscustomobject]@{
        paneIds = $case.ids
        importNanoseconds = $case.import
        serverConstructionNanoseconds = 100
        firstSnapshotNanoseconds = 100
        moduleVersion = '0.1.0'
        coreAssemblyMvid = 'core-mvid'
        cmdletAssemblyMvid = 'cmdlet-mvid'
    }
    $rejected = $false
    try {
        Assert-ColdPowerShellResult -Result $observed -ExpectedPaneIds $expected -Lane $case.name
    } catch {
        $rejected = $_.Exception.Message.Contains($case.name)
    }
    if (!$rejected) { throw "The benchmark accepted $($case.name)." }
}

if ($PackageRoot) {
    if (!$ExpectedPackageSha256) { throw 'ExpectedPackageSha256 is required for the live smoke.' }
    $output = Join-Path ([IO.Path]::GetTempPath()) (
        'libtmux-powershell-cold-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & "$PSScriptRoot/Run.ps1" -PackageRoot $PackageRoot -OutputPath $output `
            -ExpectedPackageSha256 $ExpectedPackageSha256 -TmuxBinaryPath $TmuxBinaryPath `
            -WarmupRounds 0 -SampleRounds 1
        $report = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        if ($report.status -cne 'PASS' -or $report.shape.panes -ne 16 -or
            @($report.firstCalls).Count -ne 1 -or @($report.samples).Count -ne 1 -or
            @($report.expectedPaneIds).Count -ne 16 -or
            $report.provenance.packageSha256 -cne $ExpectedPackageSha256.ToLowerInvariant() -or
            !$report.cleanup.fixtureRemoved -or !$report.cleanup.extractedPackageRemoved) {
            throw 'The cold PowerShell smoke omitted a sample, identity, or cleanup check.'
        }
    } finally {
        if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output }
    }
    'PASS cold PowerShell negative controls and installed smoke'
} else {
    'PASS cold PowerShell negative controls'
}
