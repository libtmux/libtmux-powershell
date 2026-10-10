[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $ReviewRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source,
    [ValidateRange(0, 10)] [int] $WarmupRounds = 2,
    [ValidateRange(1, 100)] [int] $SampleRounds = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$format = '#{pid}|#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}|#{session_name}'
$arguments = [string[]] @('display-message', '-p', '-t', 'fixture:0.0', $format)

function Get-NativeEndpointReply($Fixture) {
    $result = Invoke-OwnedTmux $Fixture -Arguments $arguments
    if ($result.StdErr -or @($result.StdOut.Split("`n", [StringSplitOptions]::RemoveEmptyEntries)).Count -ne 1) {
        throw 'Native display-message did not return exactly one clean reply.'
    }
    $result.StdOut.TrimEnd("`r", "`n")
}

function Get-NativeClientCount($Fixture) {
    $result = Invoke-OwnedTmux $Fixture -Arguments @('list-clients', '-F', '#{client_pid}') -AllowFailure
    if ($result.ExitCode -ne 0 -and $result.StdErr -cnotmatch '^no clients') {
        throw "Native list-clients failed ($($result.ExitCode)): $($result.StdErr.Trim())"
    }
    @($result.StdOut.Split("`n", [StringSplitOptions]::RemoveEmptyEntries)).Count
}

function New-EndpointInvocation {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates only a local invocation object; it does not start the command.')]
    param($Runspace, $Server)
    $pipeline = [PowerShell]::Create()
    $pipeline.Runspace = $Runspace
    $null = $pipeline.AddCommand('LibTmux\Invoke-TmuxCommand').AddParameter('Server', $Server).
        AddParameter('Arguments', $arguments).AddParameter('ErrorAction', 'Stop')
    $pipeline
}

function Get-CmdletEndpointReply($Pipeline, $Invocation, [string] $Lane) {
    $result = @(if ($Invocation) { $Pipeline.EndInvoke($Invocation) } else { $Pipeline.Invoke() })
    if ($Pipeline.Streams.Error.Count -ne 0 -or $result.Count -ne 1 -or
        $result[0] -isnot [LibTmux.TmuxCommandResult] -or $result[0].ExitCode -ne 0 -or
        $result[0].StandardOutputLines.Count -ne 1 -or $result[0].StandardErrorLines.Count -ne 0) {
        throw "$Lane did not return one clean TmuxCommandResult."
    }
    [string] $result[0].StandardOutputLines[0]
}

function Invoke-NativePair([object[]] $Fixtures) {
    $replies = for ($index = 0; $index -lt 2; $index++) {
        [pscustomobject]@{ index = [int] $index; reply = Get-NativeEndpointReply $Fixtures[$index] }
    }
    [pscustomobject]@{ replies = @($replies); submissionOrder = @(0, 1);
        observedCompletionOrder = @(0, 1) }
}

function Invoke-CmdletSerialPair([object[]] $Runspaces, [object[]] $Servers) {
    $replies = for ($index = 0; $index -lt 2; $index++) {
        $pipeline = New-EndpointInvocation $Runspaces[$index] $Servers[$index]
        try {
            $reply = Get-CmdletEndpointReply $pipeline $null 'cmdlet serial'
            [pscustomobject]@{ index = [int] $index; reply = $reply }
        } finally { $pipeline.Dispose() }
    }
    [pscustomobject]@{ replies = @($replies); submissionOrder = @(0, 1);
        observedCompletionOrder = @(0, 1) }
}

function Invoke-CmdletConcurrentPair([object[]] $Runspaces, [object[]] $Servers) {
    $pipelines = [PowerShell[]]::new(2)
    $invocations = [IAsyncResult[]]::new(2)
    try {
        for ($index = 0; $index -lt 2; $index++) {
            $pipelines[$index] = New-EndpointInvocation $Runspaces[$index] $Servers[$index]
        }
        for ($index = 0; $index -lt 2; $index++) {
            $invocations[$index] = $pipelines[$index].BeginInvoke()
        }
        $handles = [Threading.WaitHandle[]] @($invocations[0].AsyncWaitHandle, $invocations[1].AsyncWaitHandle)
        $first = [Threading.WaitHandle]::WaitAny($handles, 1000)
        if ($first -eq [Threading.WaitHandle]::WaitTimeout) {
            throw 'Two-endpoint concurrent dispatch did not complete within one second.'
        }
        $second = 1 - $first
        $firstReply = Get-CmdletEndpointReply $pipelines[$first] $invocations[$first] 'cmdlet concurrent'
        if (!$invocations[$second].AsyncWaitHandle.WaitOne(1000)) {
            throw 'The second endpoint did not complete within one second.'
        }
        $secondReply = Get-CmdletEndpointReply $pipelines[$second] $invocations[$second] 'cmdlet concurrent'
        [pscustomobject]@{
            replies = @(
                [pscustomobject]@{ index = [int] $first; reply = $firstReply }
                [pscustomobject]@{ index = [int] $second; reply = $secondReply }
            )
            submissionOrder = @(0, 1)
            observedCompletionOrder = @([int] $first, [int] $second)
        }
    } finally {
        foreach ($pipeline in $pipelines) {
            if (!$pipeline) { continue }
            if ($pipeline.InvocationStateInfo.State -in @('Running', 'Stopping')) {
                $stop = $pipeline.BeginStop($null, $null)
                if ($stop.AsyncWaitHandle.WaitOne(1000)) { $pipeline.EndStop($stop) }
            }
            $pipeline.Dispose()
        }
    }
}

function Get-TimingSummary([long[]] $Values) {
    $sorted = [long[]] $Values.Clone()
    [Array]::Sort($sorted)
    $middle = [int] [Math]::Floor($sorted.Length / 2)
    $median = if ($sorted.Length % 2) { $sorted[$middle] } else {
        ($sorted[$middle - 1] + $sorted[$middle]) / 2.0
    }
    @{ samples = $sorted.Length; medianMilliseconds = $median / 1000000.0;
        p95Milliseconds = $(if ($sorted.Length -ge 20) {
                $sorted[[int] [Math]::Ceiling($sorted.Length * 0.95) - 1] / 1000000.0
            } else { $null }) }
}

$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0-alpha1.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) { throw 'PackageRoot must contain LibTmux.0.1.0-alpha1.nupkg.' }
$binary = (Resolve-Path -LiteralPath $TmuxBinaryPath).Path
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $destination) { throw 'OutputPath already exists; choose a new report path.' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-endpoint-pair-' + [Guid]::NewGuid().ToString('N'))
$fixtures = [Collections.Generic.List[object]]::new()
$runspaces = [Collections.Generic.List[object]]::new()
$report = $null
$null = New-Item -ItemType Directory -Path $temporary
try {
    $module = Join-Path $temporary 'LibTmux/0.1.0'
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $module)
    $modulePath = Join-Path $module 'LibTmux.psd1'
    Import-Module "$PSScriptRoot/PackageIdentity.psm1" -Force
    $identity = Get-BenchmarkPackageIdentity -PackageRoot $PackageRoot -ModuleRoot $module -ReviewRoot $ReviewRoot
    $importWatch = [Diagnostics.Stopwatch]::StartNew()
    Import-Module $modulePath -ErrorAction Stop
    $importWatch.Stop()
    Import-Module "$PSScriptRoot/EndpointPair.Checks.psm1" -Force
    . "$PSScriptRoot/../tests/support/OwnedTmux.ps1"

    $fixtureWatch = [Diagnostics.Stopwatch]::StartNew()
    $fixtures.Add((New-OwnedTmuxFixture -TmuxPath $binary))
    $fixtures.Add((New-OwnedTmuxFixture -TmuxPath $binary))
    $fixtureWatch.Stop()
    if ($fixtures[0].SocketPath -ceq $fixtures[1].SocketPath -or
        $fixtures[0].ServerPid -eq $fixtures[1].ServerPid) {
        throw 'The endpoint pair did not own two distinct tmux daemons and sockets.'
    }
    $expected = [string[]] @($fixtures | ForEach-Object { Get-NativeEndpointReply $_ })
    for ($index = 0; $index -lt 2; $index++) {
        $fields = $expected[$index].Split('|')
        if ($fields.Count -ne 6 -or $fields[0] -cne [string] $fixtures[$index].ServerPid -or
            $fields[1] -cnotmatch '^\$[0-9]+$' -or $fields[2] -cnotmatch '^@[0-9]+$' -or
            $fields[3] -cnotmatch '^%[0-9]+$' -or $fields[4] -cnotmatch '^[0-9]+$' -or
            $fields[5] -cne 'fixture') {
            throw "The native reference did not identify endpoint $index."
        }
    }
    if ($expected[0] -ceq $expected[1]) { throw 'The two endpoint identities are not distinct.' }
    $tmuxVersion = (Invoke-OwnedTmux $fixtures[0] -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()
    $servers = @($fixtures | ForEach-Object {
            LibTmux\New-TmuxServer -SocketPath $_.SocketPath -TmuxBinaryPath $binary -ConfigurationFile '/dev/null'
        })
    $runspaceWatch = [Diagnostics.Stopwatch]::StartNew()
    for ($index = 0; $index -lt 2; $index++) {
        $initial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
        $initial.ImportPSModule(@($modulePath))
        $runspace = [RunspaceFactory]::CreateRunspace($initial)
        $runspace.Open()
        $runspaces.Add($runspace)
    }
    $runspaceWatch.Stop()

    $lanes = @('native-serial', 'cmdlet-serial', 'cmdlet-concurrent')
    $operations = @{
        'native-serial' = { Invoke-NativePair $fixtures.ToArray() }
        'cmdlet-serial' = { Invoke-CmdletSerialPair $runspaces.ToArray() $servers }
        'cmdlet-concurrent' = { Invoke-CmdletConcurrentPair $runspaces.ToArray() $servers }
    }
    $firstCalls = [Collections.Generic.List[object]]::new()
    $warmups = [Collections.Generic.List[object]]::new()
    $samples = [Collections.Generic.List[object]]::new()
    foreach ($phase in @('firstCall', 'warmup', 'sample')) {
        $rounds = switch ($phase) {
            firstCall { 1 }
            warmup { $WarmupRounds }
            sample { $SampleRounds }
        }
        for ($round = 0; $round -lt $rounds; $round++) {
            for ($position = 0; $position -lt $lanes.Count; $position++) {
                $lane = if ($phase -eq 'firstCall') { $lanes[$position] } else {
                    $lanes[($round + $position) % $lanes.Count]
                }
                $before = [string[]] @($fixtures | ForEach-Object { Get-NativeEndpointReply $_ })
                if ($before[0] -cne $expected[0] -or $before[1] -cne $expected[1]) {
                    throw "$phase/$round/$lane started with a changed endpoint."
                }
                $watch = [Diagnostics.Stopwatch]::StartNew()
                $actual = & $operations[$lane]
                $watch.Stop()
                $after = [string[]] @($fixtures | ForEach-Object { Get-NativeEndpointReply $_ })
                Assert-EndpointPairReplySet -Expected $expected -Observed @($actual.replies) `
                    -StateAfter $after -Lane "$phase/$round/$lane" -RequireOrder:($lane -cne 'cmdlet-concurrent')
                $record = @{ phase = $phase; round = $round; position = $position; lane = $lane;
                    elapsedNanoseconds = [long] [Math]::Round(
                        $watch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
                    replies = @($actual.replies); submissionOrder = @($actual.submissionOrder);
                    observedCompletionOrder = @($actual.observedCompletionOrder);
                    stateBefore = $before; stateAfter = $after }
                switch ($phase) {
                    firstCall { $firstCalls.Add($record) }
                    warmup { $warmups.Add($record) }
                    sample { $samples.Add($record) }
                }
            }
        }
    }

    $clientsAfter = @($fixtures | ForEach-Object { Get-NativeClientCount $_ })
    $identityAtEnd = [string[]] @($fixtures | ForEach-Object { Get-NativeEndpointReply $_ })
    $bothAlive = !$fixtures[0].ServerProcess.HasExited -and !$fixtures[1].ServerProcess.HasExited
    if ($clientsAfter[0] -ne 0 -or $clientsAfter[1] -ne 0 -or !$bothAlive -or
        $identityAtEnd[0] -cne $expected[0] -or $identityAtEnd[1] -cne $expected[1]) {
        throw 'The endpoint pair left a native client or changed an owned daemon.'
    }
    $summary = foreach ($lane in $lanes) {
        $values = [long[]] @($samples | Where-Object lane -CEQ $lane | ForEach-Object elapsedNanoseconds)
        @{ lane = $lane; timing = Get-TimingSummary $values }
    }
    $sourceCommit = (git -C (Split-Path $PSScriptRoot) rev-parse HEAD).Trim()
    $sourceDirty = @((git -C (Split-Path $PSScriptRoot) status --porcelain --untracked-files=all)).Count -gt 0
    $report = [ordered]@{
        schema = 1; status = 'PASS'; recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O');
        workload = 'one display-message identity read from each of two owned tmux sockets';
        lanes = $lanes;
        operations = @(
            @{ lane = 'native-serial'; path = 'Invoke-OwnedTmux display-message once per socket, serially' },
            @{ lane = 'cmdlet-serial'; path = 'LibTmux\Invoke-TmuxCommand once per socket in dedicated runspaces, serially' },
            @{ lane = 'cmdlet-concurrent'; path = 'LibTmux\Invoke-TmuxCommand once per socket in dedicated runspaces, both in flight; concurrency cap 2' }
        );
        argv = $arguments;
        shape = @{ endpoints = 2; sessionsPerEndpoint = 1; windowsPerEndpoint = 1;
            panesPerEndpoint = 1; linkedWindows = 0 };
        parameters = @{ warmupRounds = $WarmupRounds; sampleRounds = $SampleRounds;
            maximumConcurrentCmdlets = 2; sampling = 'serial rounds, rotating lane order';
            concurrentCompletionLimitMilliseconds = 1000 };
        ordering = @{ serial = 'submission and result order 0,1';
            concurrent = 'order reaped by WaitAny; replies matched to endpoint index; simultaneous completions may appear in index order';
            equality = 'each lane returns the same exact identity for each socket; state before and after agree' };
        provenance = @{ sourceCommit = $sourceCommit; sourceDirty = $sourceDirty;
            runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant();
            checksSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/EndpointPair.Checks.psm1").Hash.ToLowerInvariant();
            packageVersion = (Get-Module LibTmux).Version.ToString();
            corePackageVersion = $identity.corePackageVersion;
            packageSha256 = $identity.packageSha256;
            coreAssemblySha256 = $identity.coreAssemblySha256;
            cmdletAssemblySha256 = $identity.cmdletAssemblySha256;
            sourceProvenance = $identity.sourceProvenance;
            reviewCoreRevision = $identity.reviewCoreRevision;
            reviewPortRevision = $identity.reviewPortRevision;
            packageIdentitySha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/PackageIdentity.psm1").Hash.ToLowerInvariant();
            tmuxVersion = $tmuxVersion; tmuxSha256 = (Get-FileHash -LiteralPath $binary).Hash.ToLowerInvariant();
            powerShellVersion = $PSVersionTable.PSVersion.ToString();
            dotnetRuntimeVersion = [Environment]::Version.ToString();
            os = [Runtime.InteropServices.RuntimeInformation]::OSDescription;
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();
            coreAssemblyMvid = [LibTmux.Server].Assembly.ManifestModule.ModuleVersionId.ToString();
            cmdletAssemblyMvid = [LibTmux.PowerShell.InvokeTmuxCommandCommand].Assembly.ManifestModule.ModuleVersionId.ToString() };
        timing = @{ moduleImportNanoseconds = [long] [Math]::Round(
                $importWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            ownedFixtureSetupNanoseconds = [long] [Math]::Round(
                $fixtureWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            runspaceOpenNanoseconds = [long] [Math]::Round(
                $runspaceWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            firstCallsIncludeJit = $true; warmSamplesExcludeImportAndFixtureSetup = $true };
        expectedReplies = $expected;
        cleanup = @{ bothOwnedServersAlive = $bothAlive; nativeClientCountByEndpoint = $clientsAfter };
        firstCalls = $firstCalls.ToArray(); warmups = $warmups.ToArray();
        samples = $samples.ToArray(); summary = @($summary)
    }
} finally {
    try {
        try {
            if ($runspaces.Count -gt 1) { $runspaces[1].Dispose() }
        } finally {
            if ($runspaces.Count -gt 0) { $runspaces[0].Dispose() }
        }
    } finally {
        try {
            try {
                if ($fixtures.Count -gt 1) { Remove-OwnedTmuxFixture $fixtures[1] }
            } finally {
                if ($fixtures.Count -gt 0) { Remove-OwnedTmuxFixture $fixtures[0] }
            }
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
        }
    }
}
$report.cleanup.firstFixtureRemoved = $fixtures[0].Closed -and !(Test-Path -LiteralPath $fixtures[0].DirectoryPath)
$report.cleanup.secondFixtureRemoved = $fixtures[1].Closed -and !(Test-Path -LiteralPath $fixtures[1].DirectoryPath)
$report.cleanup.extractedPackageRemoved = !(Test-Path -LiteralPath $temporary)
if (!$report.cleanup.firstFixtureRemoved -or !$report.cleanup.secondFixtureRemoved -or
    !$report.cleanup.extractedPackageRemoved) {
    throw 'Endpoint pair cleanup did not remove both owned fixtures and the extracted package.'
}
$parent = Split-Path $destination
if (!(Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -NoNewline
"PASS endpoint pair: $SampleRounds rounds per lane; report: $destination"
