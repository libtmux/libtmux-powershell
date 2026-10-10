[CmdletBinding()]
param(
    [string] $PackageRoot,
    [string] $ReviewRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/ResourceCancellation.Checks.psm1" -Force

$good = [pscustomobject]@{
    lane = 'timeout'; clientStartAcknowledged = $true; activeClientAlive = $true;
    clientExited = $true; outputCount = 0; nextSignalObserved = $true;
    identityAfter = '$1|@1|%1|123'; pipelineState = 'Completed'; errorCount = 1;
    errorType = 'System.TimeoutException'; errorCategory = 'OperationTimeout';
    errorId = 'Tmux.ChannelWaitFailed,LibTmux.PowerShell.WaitTmuxChannelCommand';
    stopExceptionType = $null;
    clientCount = @{ before = 0; active = 1; after = 0 };
    processCount = @{ before = 2; active = 3; after = 2 };
    rssBytes = @{ beforePowerShell = 1L; afterPowerShell = 1L;
        beforeServer = 1L; afterServer = 1L; activeClient = 1L };
    timingNanoseconds = @{ startToClientMarker = 1L; triggerToCompletion = 1L }
}
if (!(Assert-ResourceCancellationRecord -Record $good -ExpectedIdentity '$1|@1|%1|123' `
            -BaselineClientCount 0 -Lane 'positive timeout')) { throw 'Valid timeout record was rejected.' }

$bad = @(
    @{ name = 'live process'; property = 'clientExited'; value = $false },
    @{ name = 'lost signal'; property = 'nextSignalObserved'; value = $false },
    @{ name = 'wrong identity'; property = 'identityAfter'; value = 'different' },
    @{ name = 'success output'; property = 'outputCount'; value = 1 },
    @{ name = 'wrong error'; property = 'errorType'; value = 'System.OperationCanceledException' }
)
foreach ($case in $bad) {
    $record = $good.PSObject.Copy()
    $record.($case.property) = $case.value
    $rejected = $false
    try {
        $null = Assert-ResourceCancellationRecord -Record $record -ExpectedIdentity '$1|@1|%1|123' `
            -BaselineClientCount 0 -Lane $case.name
    } catch { $rejected = $_.Exception.Message.Contains($case.name) }
    if (!$rejected) { throw "Resource equality accepted $($case.name)." }
}
foreach ($case in @(
        @{ name = 'retained process'; property = 'processCount'; value = @{ before = 2; active = 3; after = 3 } },
        @{ name = 'retained tmux client'; property = 'clientCount'; value = @{ before = 0; active = 1; after = 1 } }
    )) {
    $record = $good.PSObject.Copy()
    $record.($case.property) = $case.value
    $rejected = $false
    try {
        $null = Assert-ResourceCancellationRecord -Record $record -ExpectedIdentity '$1|@1|%1|123' `
            -BaselineClientCount 0 -Lane $case.name
    } catch { $rejected = $_.Exception.Message.Contains($case.name) }
    if (!$rejected) { throw "Resource equality accepted $($case.name)." }
}
$stopped = $good.PSObject.Copy()
$stopped.lane = 'pipeline-stop'
$stopped.pipelineState = 'Stopped'
$stopped.errorCount = 0
$stopped.stopExceptionType = 'System.Management.Automation.PipelineStoppedException'
if (!(Assert-ResourceCancellationRecord -Record $stopped -ExpectedIdentity '$1|@1|%1|123' `
            -BaselineClientCount 0 -Lane 'positive stop')) { throw 'Valid stopped record was rejected.' }

if ($PackageRoot) {
    $output = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-resource-cancellation-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & "$PSScriptRoot/ResourceCancellation.ps1" -PackageRoot $PackageRoot -ReviewRoot $ReviewRoot `
            -TmuxBinaryPath $TmuxBinaryPath `
            -OutputPath $output -WarmupRounds 0 -SampleRounds 2 -TimeoutSeconds 0.25
        $report = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        if ($report.status -cne 'PASS' -or @($report.firstCalls).Count -ne 2 -or
            @($report.samples).Count -ne 4 -or @($report.summary).Count -ne 2 -or
            !$report.cleanup.ownedFixtureRemoved -or !$report.cleanup.extractedPackageRemoved) {
            throw 'The resource cancellation report omitted samples or cleanup checks.'
        }
        if ($report.provenance.runnerSha256 -cne (Get-FileHash "$PSScriptRoot/ResourceCancellation.ps1").Hash.ToLowerInvariant() -or
            $report.provenance.checksSha256 -cne (Get-FileHash "$PSScriptRoot/ResourceCancellation.Checks.psm1").Hash.ToLowerInvariant() -or
            $report.provenance.packageIdentitySha256 -cne (Get-FileHash "$PSScriptRoot/PackageIdentity.psm1").Hash.ToLowerInvariant() -or
            $report.provenance.packageSha256 -cne (Get-FileHash (Join-Path $PackageRoot 'LibTmux.0.1.0.nupkg')).Hash.ToLowerInvariant() -or
            !$report.provenance.corePackageVersion -or !$report.provenance.coreAssemblySha256 -or
            !$report.provenance.cmdletAssemblySha256 -or
            $report.provenance.sourceProvenance -cne $(if ($ReviewRoot) { 'verified' } else { 'unverified' }) -or
            ($ReviewRoot -and (!$report.provenance.reviewCoreRevision -or !$report.provenance.reviewPortRevision)) -or
            (!$ReviewRoot -and ($report.provenance.reviewCoreRevision -or $report.provenance.reviewPortRevision))) {
            throw 'The resource cancellation report did not identify its runner and checks.'
        }
    } finally {
        if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output }
    }
}
if ($PackageRoot) { 'PASS resource cancellation negative controls and installed smoke' }
else { 'PASS resource cancellation negative controls' }
