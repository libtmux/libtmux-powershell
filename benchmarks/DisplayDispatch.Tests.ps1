[CmdletBinding()]
param(
    [string] $PackageRoot,
    [string] $ReviewRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/DisplayDispatch.Checks.psm1" -Force

$expected = [string[]] @('first', 'second')
$inOrder = @(
    [pscustomobject]@{ index = 0; reply = 'first' }
    [pscustomobject]@{ index = 1; reply = 'second' }
)
$reversed = @($inOrder[1], $inOrder[0])
$negative = @(
    @{ name = 'wrong reply'; observed = @($inOrder[0], [pscustomobject]@{ index = 1; reply = 'wrong' }); ordered = $false }
    @{ name = 'missing reply'; observed = @($inOrder[0]); ordered = $false }
    @{ name = 'duplicate index'; observed = @($inOrder[0], $inOrder[0]); ordered = $false }
    @{ name = 'serial reorder'; observed = $reversed; ordered = $true }
)
foreach ($case in $negative) {
    $rejected = $false
    try {
        Assert-BenchmarkDisplayReplySet -Expected $expected -Observed $case.observed -Lane $case.name -RequireOrder:$case.ordered
    } catch {
        $rejected = $_.Exception.Message.Contains($case.name)
    }
    if (!$rejected) { throw "Display dispatch equality accepted $($case.name)." }
}
Assert-BenchmarkDisplayReplySet -Expected $expected -Observed $inOrder -Lane 'serial positive' -RequireOrder
Assert-BenchmarkDisplayReplySet -Expected $expected -Observed $reversed -Lane 'concurrent positive'

if ($PackageRoot) {
    $output = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-display-dispatch-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & "$PSScriptRoot/DisplayDispatch.ps1" -PackageRoot $PackageRoot -ReviewRoot $ReviewRoot `
            -TmuxBinaryPath $TmuxBinaryPath -OutputPath $output -WarmupRounds 1 -SampleRounds 2
        $report = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        $receipt = if ($ReviewRoot) {
            Get-Content -LiteralPath (Join-Path $ReviewRoot 'bootstrap.json') -Raw | ConvertFrom-Json
        }
        if ($report.status -cne 'PASS' -or $report.shape.panes -ne 1 -or
            @($report.expectedReplies).Count -ne 8 -or @($report.lanes).Count -ne 5 -or
            @($report.firstCalls).Count -ne 5 -or @($report.samples).Count -ne 10 -or
            !$report.cleanup.controlDisconnected -or !$report.cleanup.borrowedSessionAlive -or
            !$report.cleanup.ownedFixtureRemoved -or !$report.cleanup.extractedPackageRemoved) {
            throw 'The display dispatch report omitted a lane, reply, sample, or cleanup check.'
        }
        if ($report.provenance.runnerSha256 -cne (Get-FileHash "$PSScriptRoot/DisplayDispatch.ps1").Hash.ToLowerInvariant() -or
            $report.provenance.checksSha256 -cne (Get-FileHash "$PSScriptRoot/DisplayDispatch.Checks.psm1").Hash.ToLowerInvariant() -or
            $report.provenance.packageIdentitySha256 -cne (Get-FileHash "$PSScriptRoot/PackageIdentity.psm1").Hash.ToLowerInvariant() -or
            $report.provenance.packageSha256 -cne (Get-FileHash (Join-Path $PackageRoot 'LibTmux.0.1.0-alpha2.nupkg')).Hash.ToLowerInvariant() -or
            !$report.provenance.corePackageVersion -or !$report.provenance.coreAssemblySha256 -or
            !$report.provenance.cmdletAssemblySha256 -or
            $report.provenance.sourceProvenance -cne $(if ($ReviewRoot) { 'verified' } else { 'unverified' }) -or
            ($ReviewRoot -and ($report.provenance.corePackageVersion -cne $receipt.version -or
                $report.provenance.reviewCoreRevision -cne $receipt.coreRevision -or
                $report.provenance.reviewPortRevision -cne $receipt.portRevision)) -or
            (!$ReviewRoot -and ($report.provenance.reviewCoreRevision -or $report.provenance.reviewPortRevision))) {
            throw 'The display dispatch report did not identify the exact benchmark source and dependency.'
        }
        foreach ($sample in $report.samples) {
            if (@($sample.replies).Count -ne 8 -or @($sample.observedCompletionOrder).Count -ne 8 -or
                $sample.stateBefore -cne $sample.stateAfter) {
                throw "The $($sample.lane) sample omitted replies, ordering, or state equality."
            }
        }
        & (Join-Path $PSHOME 'pwsh') -NoLogo -NoProfile -File `
            "$PSScriptRoot/DisplayDispatch.Failure.Tests.ps1" -PackageRoot $PackageRoot `
            -ReviewRoot $ReviewRoot -TmuxBinaryPath $TmuxBinaryPath
        if ($LASTEXITCODE -ne 0) { throw 'The installed-package failure dispatch check failed.' }
    } finally {
        Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue
    }
}

if ($PackageRoot) {
    'PASS display dispatch: unequal replies rejected; five live lanes and cleanup agree'
} else {
    'PASS display dispatch: unequal replies rejected'
}
