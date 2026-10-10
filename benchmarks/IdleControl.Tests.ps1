[CmdletBinding()]
param(
    [string] $PackageRoot,
    [string] $ReviewRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/IdleControl.Checks.psm1" -Force

function Get-SyntheticSample([int] $Index, [bool] $WithClient) {
    $counter = @{ cpuStartTicks = 1L; cpuEndTicks = 2L; cpuDeltaNanoseconds = 100L;
        rssStartBytes = 4096L; rssEndBytes = 4096L }
    @{ index = $Index; intervalNanoseconds = 250000000L;
        allocatedStartBytes = 10L; allocatedEndBytes = 20L; allocatedDeltaBytes = 10L;
        powerShell = $counter; tmuxServer = $counter;
        controlClient = $(if ($WithClient) { $counter } else { $null }) }
}

$good = @{
    phases = @(
        @{ name = 'before'; identity = '$1|@1|%1|123'; identityAtEnd = '$1|@1|%1|123';
            nativeClientCount = 0; nativeClientCountAtEnd = 0;
            aliveOwnedProcessCount = 2; aliveOwnedProcessCountAtEnd = 2;
            connectionRunning = $false; connectionRunningAtEnd = $false;
            controlClientPid = $null; controlClientPidAtEnd = $null;
            samples = @((Get-SyntheticSample 0 $false), (Get-SyntheticSample 1 $false)) },
        @{ name = 'during'; identity = '$1|@1|%1|123'; identityAtEnd = '$1|@1|%1|123';
            nativeClientCount = 1; nativeClientCountAtEnd = 1;
            aliveOwnedProcessCount = 3; aliveOwnedProcessCountAtEnd = 3;
            connectionRunning = $true; connectionRunningAtEnd = $true;
            controlClientPid = 456; controlClientPidAtEnd = 456;
            samples = @((Get-SyntheticSample 0 $true), (Get-SyntheticSample 1 $true)) },
        @{ name = 'after'; identity = '$1|@1|%1|123'; identityAtEnd = '$1|@1|%1|123';
            nativeClientCount = 0; nativeClientCountAtEnd = 0;
            aliveOwnedProcessCount = 2; aliveOwnedProcessCountAtEnd = 2;
            connectionRunning = $false; connectionRunningAtEnd = $false;
            controlClientPid = $null; controlClientPidAtEnd = $null;
            samples = @((Get-SyntheticSample 0 $false), (Get-SyntheticSample 1 $false)) }
    )
    cleanup = @{ controlClientExited = $true; controlDisconnected = $true;
        nativeClientCount = 0; borrowedSessionAlive = $true;
        ownedFixtureRemoved = $true; extractedPackageRemoved = $true }
}
if (!(Assert-IdleControlReport -Report $good -ExpectedIdentity '$1|@1|%1|123' -SamplesPerPhase 2)) {
    throw 'A valid idle report was rejected.'
}

$cases = @(
    @{ name = 'wrong identity'; change = { param($r) $r.phases[1].identity = 'different' } },
    @{ name = 'missing sample'; change = { param($r) $r.phases[1].samples = @($r.phases[1].samples[0]) } },
    @{ name = 'retained client'; change = { param($r) $r.phases[2].nativeClientCount = 1 } },
    @{ name = 'client lost during idle'; change = { param($r) $r.phases[1].nativeClientCountAtEnd = 0 } },
    @{ name = 'retained process'; change = { param($r) $r.phases[2].aliveOwnedProcessCount = 3 } },
    @{ name = 'invalid allocation'; change = { param($r) $r.phases[1].samples[0].allocatedDeltaBytes = 9 } },
    @{ name = 'invalid CPU'; change = { param($r) $r.phases[1].samples[0].controlClient.cpuDeltaNanoseconds = 99 } },
    @{ name = 'failed cleanup'; change = { param($r) $r.cleanup.ownedFixtureRemoved = $false } }
)
foreach ($case in $cases) {
    $bad = $good | ConvertTo-Json -Depth 12 | ConvertFrom-Json -AsHashtable
    & $case.change $bad
    $rejected = $false
    try { $null = Assert-IdleControlReport -Report $bad -ExpectedIdentity '$1|@1|%1|123' -SamplesPerPhase 2 }
    catch { $rejected = $true }
    if (!$rejected) { throw "Idle report accepted $($case.name)." }
}

if ($PackageRoot) {
    $output = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-idle-control-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & "$PSScriptRoot/IdleControl.ps1" -PackageRoot $PackageRoot -ReviewRoot $ReviewRoot `
            -TmuxBinaryPath $TmuxBinaryPath `
            -OutputPath $output -SamplesPerPhase 2 -IntervalMilliseconds 100
        $report = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        if ($report.status -cne 'PASS' -or $report.parameters.samplesPerPhase -ne 2 -or
            $report.parameters.intervalMilliseconds -ne 100 -or
            $report.provenance.runnerSha256 -cne (Get-FileHash "$PSScriptRoot/IdleControl.ps1").Hash.ToLowerInvariant() -or
            $report.provenance.checksSha256 -cne (Get-FileHash "$PSScriptRoot/IdleControl.Checks.psm1").Hash.ToLowerInvariant() -or
            $report.provenance.packageIdentitySha256 -cne (Get-FileHash "$PSScriptRoot/PackageIdentity.psm1").Hash.ToLowerInvariant() -or
            $report.provenance.packageSha256 -cne (Get-FileHash (Join-Path $PackageRoot 'LibTmux.0.1.0-alpha1.nupkg')).Hash.ToLowerInvariant() -or
            !$report.provenance.corePackageVersion -or !$report.provenance.coreAssemblySha256 -or
            !$report.provenance.cmdletAssemblySha256 -or
            $report.provenance.sourceProvenance -cne $(if ($ReviewRoot) { 'verified' } else { 'unverified' }) -or
            ($ReviewRoot -and (!$report.provenance.reviewCoreRevision -or !$report.provenance.reviewPortRevision)) -or
            (!$ReviewRoot -and ($report.provenance.reviewCoreRevision -or $report.provenance.reviewPortRevision))) {
            throw 'Installed idle report omitted samples, parameters, or provenance.'
        }
        $null = Assert-IdleControlReport -Report $report -ExpectedIdentity $report.topologyIdentity -SamplesPerPhase 2
    } finally {
        if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output }
    }
}
if ($PackageRoot) { 'PASS idle control negative controls and installed smoke' }
else { 'PASS idle control negative controls' }
