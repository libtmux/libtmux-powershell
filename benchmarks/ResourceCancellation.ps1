[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source,
    [ValidateRange(0, 10)] [int] $WarmupRounds = 2,
    [ValidateRange(1, 100)] [int] $SampleRounds = 20,
    [ValidateRange(0.1, 0.8)] [double] $TimeoutSeconds = 0.5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertTo-NanosecondCount([long] $Ticks) {
    [long] [Math]::Round($Ticks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency)
}

function Get-WorkingSetByteCount([Diagnostics.Process] $Process) {
    if ($Process.HasExited) { return $null }
    $Process.Refresh()
    [long] $Process.WorkingSet64
}

function Get-AliveOwnedProcessCount($Fixture) {
    $processes = @($Fixture.ServerProcess) + $Fixture.PaneProcesses.ToArray() + $Fixture.ClientProcesses.ToArray()
    @($processes | Where-Object { !$_.HasExited }).Count
}

function Get-NativeClientCount($Fixture) {
    $result = Invoke-OwnedTmux $Fixture -Arguments @('list-clients', '-F', '#{client_pid}') -AllowFailure
    if ($result.ExitCode -ne 0 -and $result.StdErr -cnotmatch '^no clients') {
        throw "Native list-clients failed ($($result.ExitCode)): $($result.StdErr.Trim())"
    }
    @($result.StdOut.Split("`n", [StringSplitOptions]::RemoveEmptyEntries)).Count
}

function Get-TopologyIdentity($Fixture) {
    (Invoke-OwnedTmux $Fixture -Arguments @('display-message', '-p', '-t', 'fixture:0.0',
            '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}')).StdOut.Trim()
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

function Invoke-ResourceCancellationCell {
    param($Fixture, $WaitServer, $ProofServer, $Runspace, [string] $Lane,
        [string] $Phase, [int] $Round, [double] $TimeoutSeconds,
        [string] $ExpectedIdentity, [int] $ExpectedClientCount,
        [Diagnostics.Process] $PowerShellProcess)

    $channel = "cancel-bench-$phase-$round-$Lane"
    $pidFile = Join-Path $Fixture.DirectoryPath $channel
    $pipeline = [PowerShell]::Create()
    $client = $null
    $invocation = $null
    $complete = $false
    try {
        $clientCountBefore = Get-NativeClientCount $Fixture
        $processCountBefore = Get-AliveOwnedProcessCount $Fixture
        $rssPowerShellBefore = Get-WorkingSetByteCount $PowerShellProcess
        $rssServerBefore = Get-WorkingSetByteCount $Fixture.ServerProcess
        $budget = if ($Lane -ceq 'timeout') { $TimeoutSeconds } else { 10.0 }
        $pipeline.Runspace = $Runspace
        $null = $pipeline.AddCommand('LibTmux\Wait-TmuxChannel').AddParameter('Server', $WaitServer).
            AddParameter('Channel', $channel).AddParameter('Timeout', $budget).
            AddParameter('ErrorAction', 'Continue')

        $started = [Diagnostics.Stopwatch]::GetTimestamp()
        $invocation = $pipeline.BeginInvoke()
        $null = Invoke-OwnedTmux $Fixture -Arguments @('wait-for', "ready-$channel")
        $registered = [Diagnostics.Stopwatch]::GetTimestamp()
        if (!(Test-Path -LiteralPath $pidFile)) { throw "$Phase/$Round/$Lane did not record its native client." }
        $clientId = [int] [IO.File]::ReadAllText($pidFile)
        $client = [Diagnostics.Process]::GetProcessById($clientId)
        $Fixture.ClientProcesses.Add($client)
        $null = $Fixture.OwnedProcessIds.Add($clientId)
        $activeClientAlive = !$client.HasExited
        $activeClientRss = Get-WorkingSetByteCount $client
        $clientCountActive = Get-NativeClientCount $Fixture
        $processCountActive = Get-AliveOwnedProcessCount $Fixture
        $rssPowerShellActive = Get-WorkingSetByteCount $PowerShellProcess
        $rssServerActive = Get-WorkingSetByteCount $Fixture.ServerProcess

        $triggered = if ($Lane -ceq 'timeout') { $started } else { [Diagnostics.Stopwatch]::GetTimestamp() }
        if ($Lane -ceq 'pipeline-stop') {
            $stop = $pipeline.BeginStop($null, $null)
            if (!$stop.AsyncWaitHandle.WaitOne(1000)) { throw "$Phase/$Round/$Lane did not stop within one second." }
            $pipeline.EndStop($stop)
        }
        if (!$invocation.AsyncWaitHandle.WaitOne(1000)) {
            throw "$Phase/$Round/$Lane did not finish within one second after the trigger."
        }
        $stopExceptionType = $null
        $output = @()
        try { $output = @($pipeline.EndInvoke($invocation)) } catch {
            if ($Lane -cne 'pipeline-stop' -or
                $_.Exception.InnerException -isnot [Management.Automation.PipelineStoppedException]) { throw }
            $stopExceptionType = $_.Exception.InnerException.GetType().FullName
        }
        $completed = [Diagnostics.Stopwatch]::GetTimestamp()
        $errors = @($pipeline.Streams.Error)
        $clientExited = $client.WaitForExit(1000)
        $clientCountAfter = Get-NativeClientCount $Fixture
        $processCountAfter = Get-AliveOwnedProcessCount $Fixture
        $rssPowerShellAfter = Get-WorkingSetByteCount $PowerShellProcess
        $rssServerAfter = Get-WorkingSetByteCount $Fixture.ServerProcess

        $null = Invoke-OwnedTmux $Fixture -Arguments @('wait-for', '-S', $channel)
        $nextSignal = @($ProofServer | LibTmux\Wait-TmuxChannel -Channel $channel -Timeout 0.5 -ErrorAction Stop)
        $identityAfter = Get-TopologyIdentity $Fixture
        $record = [ordered]@{
            phase = $Phase; round = $Round; lane = $Lane; channel = $channel;
            clientStartAcknowledged = $true; nativeClientPid = $clientId;
            activeClientAlive = $activeClientAlive; clientExited = $clientExited;
            pipelineState = [string] $pipeline.InvocationStateInfo.State;
            outputCount = $output.Count; errorCount = $errors.Count;
            errorType = $(if ($errors.Count) { $errors[0].Exception.GetType().FullName } else { $null });
            errorCategory = $(if ($errors.Count) { [string] $errors[0].CategoryInfo.Category } else { $null });
            errorId = $(if ($errors.Count) { $errors[0].FullyQualifiedErrorId } else { $null });
            stopExceptionType = $stopExceptionType;
            nextSignalObserved = $nextSignal.Count -eq 1 -and $nextSignal[0] -is [bool] -and $nextSignal[0];
            identityAfter = $identityAfter;
            clientCount = @{ before = $clientCountBefore; active = $clientCountActive; after = $clientCountAfter };
            processCount = @{ before = $processCountBefore; active = $processCountActive; after = $processCountAfter };
            rssBytes = @{ beforePowerShell = $rssPowerShellBefore; activePowerShell = $rssPowerShellActive;
                afterPowerShell = $rssPowerShellAfter; beforeServer = $rssServerBefore;
                activeServer = $rssServerActive; afterServer = $rssServerAfter;
                activeClient = $activeClientRss };
            timingNanoseconds = @{ startToClientMarker = ConvertTo-NanosecondCount ($registered - $started);
                triggerToCompletion = ConvertTo-NanosecondCount ($completed - $triggered);
                startToCompletion = ConvertTo-NanosecondCount ($completed - $started) }
        }
        $null = Assert-ResourceCancellationRecord -Record $record -ExpectedIdentity $ExpectedIdentity `
            -BaselineClientCount $ExpectedClientCount -Lane "$Phase/$Round/$Lane"
        $complete = $true
        $record
    } finally {
        if (!$client -and (Test-Path -LiteralPath $pidFile)) {
            try { $client = [Diagnostics.Process]::GetProcessById([int] [IO.File]::ReadAllText($pidFile)) }
            catch [ArgumentException] { $client = $null }
        }
        if ($client -and !$client.HasExited) {
            $client.Kill($true)
            if (!$client.WaitForExit(1000)) { throw "$Phase/$Round/$Lane left its owned native client alive." }
        }
        if ($pipeline.InvocationStateInfo.State -in @('Running', 'Stopping')) {
            $stop = $pipeline.BeginStop($null, $null)
            if ($stop.AsyncWaitHandle.WaitOne(1000)) { $pipeline.EndStop($stop) }
        }
        $pipeline.Dispose()
        if (!$complete -and (Test-Path -LiteralPath $pidFile)) { Remove-Item -LiteralPath $pidFile }
    }
}

$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) { throw 'PackageRoot must contain LibTmux.0.1.0.nupkg.' }
$binary = (Resolve-Path -LiteralPath $TmuxBinaryPath).Path
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $destination) { throw 'OutputPath already exists; choose a new report path.' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-resource-cancel-' + [Guid]::NewGuid().ToString('N'))
$fixture = $null
$runspace = $null
$report = $null
$powerShellProcess = [Diagnostics.Process]::GetCurrentProcess()
$null = New-Item -ItemType Directory -Path $temporary
try {
    $module = Join-Path $temporary 'LibTmux/0.1.0'
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $module)
    $modulePath = Join-Path $module 'LibTmux.psd1'
    $coreVersion = (Get-Content -LiteralPath (Join-Path $module 'dependencies.json') -Raw |
        ConvertFrom-Json).corePackageVersion
    if ($coreVersion -cne '0.0.0-alpha.16.ps.2') {
        throw "Resource cancellation benchmark requires reviewed core 0.0.0-alpha.16.ps.2; found $coreVersion."
    }
    $importWatch = [Diagnostics.Stopwatch]::StartNew()
    Import-Module $modulePath -ErrorAction Stop
    $importWatch.Stop()
    Import-Module "$PSScriptRoot/ResourceCancellation.Checks.psm1" -Force
    . "$PSScriptRoot/../tests/support/OwnedTmux.ps1"

    $fixture = New-OwnedTmuxFixture -TmuxPath $binary
    $tmuxVersion = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()
    $identity = Get-TopologyIdentity $fixture
    $baselineClients = Get-NativeClientCount $fixture
    $wrapper = Join-Path $fixture.DirectoryPath 'cancellation-tmux'
    $quote = { param([string] $Value) "'" + $Value.Replace("'", "'\''") + "'" }
    $script = @'
#!/bin/sh
mode=
previous=
for argument in "$@"; do
    if [ "$previous" = wait-for ]; then mode="$argument"; fi
    previous="$argument"
done
case "$mode:$previous" in
    --:cancel-bench-*)
        printf '%s\n' "$$" > __PID_DIRECTORY__/"$previous"
        exec __TMUX__ -S __SOCKET__ -f /dev/null wait-for -S "ready-$previous" ';' wait-for -- "$previous"
        ;;
esac
exec __TMUX__ "$@"
'@
    $script = $script.Replace('__PID_DIRECTORY__', (& $quote $fixture.DirectoryPath)).
        Replace('__SOCKET__', (& $quote $fixture.SocketPath)).Replace('__TMUX__', (& $quote $binary))
    Set-Content -LiteralPath $wrapper -Value $script
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $waitServer = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper
    $proofServer = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $binary

    $initial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $initial.ImportPSModule(@($modulePath))
    $runspace = [RunspaceFactory]::CreateRunspace($initial)
    $openWatch = [Diagnostics.Stopwatch]::StartNew()
    $runspace.Open()
    $openWatch.Stop()
    $initialPowerShellRss = Get-WorkingSetByteCount $powerShellProcess
    $initialServerRss = Get-WorkingSetByteCount $fixture.ServerProcess

    $lanes = @('timeout', 'pipeline-stop')
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
                $record = Invoke-ResourceCancellationCell -Fixture $fixture -WaitServer $waitServer `
                    -ProofServer $proofServer -Runspace $runspace -Lane $lane -Phase $phase -Round $round `
                    -TimeoutSeconds $TimeoutSeconds -ExpectedIdentity $identity `
                    -ExpectedClientCount $baselineClients -PowerShellProcess $powerShellProcess
                switch ($phase) {
                    firstCall { $firstCalls.Add($record) }
                    warmup { $warmups.Add($record) }
                    sample { $samples.Add($record) }
                }
            }
        }
    }

    $endClients = Get-NativeClientCount $fixture
    $identityAtEnd = Get-TopologyIdentity $fixture
    $borrowedServerAlive = !$fixture.ServerProcess.HasExited -and $identityAtEnd -ceq $identity
    if ($endClients -ne $baselineClients -or !$borrowedServerAlive) {
        throw 'Resource benchmark left a client or changed the owned topology.'
    }
    $summary = foreach ($lane in $lanes) {
        $rows = @($samples | Where-Object lane -CEQ $lane)
        $latencies = [long[]] @($rows | ForEach-Object { $_.timingNanoseconds.triggerToCompletion })
        @{ lane = $lane; samples = $rows.Count; triggerToCompletion = Get-TimingSummary $latencies;
            clientRssBytes = @($rows | ForEach-Object { $_.rssBytes.activeClient });
            powerShellRssDeltaBytes = @($rows | ForEach-Object {
                    $_.rssBytes.afterPowerShell - $_.rssBytes.beforePowerShell }) }
    }
    $sourceCommit = (git -C (Split-Path $PSScriptRoot) rev-parse HEAD).Trim()
    $sourceDirty = @((git -C (Split-Path $PSScriptRoot) status --porcelain --untracked-files=all)).Count -gt 0
    $report = [ordered]@{
        schema = 1; status = 'PASS'; recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O');
        kind = 'bounded cancellation resource observation';
        lanes = $lanes; shape = @{ sessions = 1; windows = 1; panes = 1; linkedWindows = 0 };
        parameters = @{ warmupRounds = $WarmupRounds; sampleRounds = $SampleRounds;
            timeoutSeconds = $TimeoutSeconds; stopCompletionLimitMilliseconds = 1000;
            sampling = 'serial, rotating lane order; one owned tmux socket and one reused runspace' };
        semantics = @{ timeout = 'Wait-TmuxChannel expires without signal and emits one OperationTimeout error; timing starts at BeginInvoke';
            pipelineStop = 'BeginStop interrupts Wait-TmuxChannel and yields PipelineStoppedException; timing starts at BeginStop';
            commonOutcome = 'no success output; native wait client exits; the next signal is observed once; owned topology and client count remain unchanged';
            comparison = 'different cancellation triggers and error semantics; no speed ratio';
            queue = 'tmux wait-for queue depth is not exposed and is not estimated';
            clientCount = 'tmux list-clients omits unattached wait-for command clients on this host; native PID and owned process counts prove active and retired client processes';
            marker = 'the native client signals a start marker before entering wait-for; the marker does not prove the waiter has registered';
            rss = 'WorkingSet64 observations of this PowerShell process, the owned daemon, and the active wait client; PowerShell includes benchmark harness allocations and is not a leak verdict' };
        provenance = @{ sourceCommit = $sourceCommit; sourceDirty = $sourceDirty;
            runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant();
            checksSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/ResourceCancellation.Checks.psm1").Hash.ToLowerInvariant();
            packageVersion = (Get-Module LibTmux).Version.ToString(); corePackageVersion = $coreVersion;
            packageSha256 = (Get-FileHash -LiteralPath $package).Hash.ToLowerInvariant();
            tmuxVersion = $tmuxVersion; tmuxSha256 = (Get-FileHash -LiteralPath $binary).Hash.ToLowerInvariant();
            powerShellVersion = $PSVersionTable.PSVersion.ToString();
            dotnetRuntimeVersion = [Environment]::Version.ToString();
            os = [Runtime.InteropServices.RuntimeInformation]::OSDescription;
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();
            coreAssemblyMvid = [LibTmux.Server].Assembly.ManifestModule.ModuleVersionId.ToString();
            cmdletAssemblyMvid = [LibTmux.PowerShell.WaitTmuxChannelCommand].Assembly.ManifestModule.ModuleVersionId.ToString() };
        timing = @{ moduleImportNanoseconds = ConvertTo-NanosecondCount $importWatch.ElapsedTicks;
            runspaceOpenNanoseconds = ConvertTo-NanosecondCount $openWatch.ElapsedTicks;
            firstCallsIncludeJit = $true; warmSamplesExcludePackageImportAndFixtureSetup = $true };
        baseline = @{ topologyIdentity = $identity; nativeClientCount = $baselineClients;
            powerShellRssBytes = $initialPowerShellRss; serverRssBytes = $initialServerRss };
        cleanup = @{ nativeClientCountAtEnd = $endClients; ownedServerAlive = $borrowedServerAlive };
        firstCalls = $firstCalls.ToArray(); warmups = $warmups.ToArray();
        samples = $samples.ToArray(); summary = @($summary)
    }
} finally {
    try {
        if ($runspace) { $runspace.Dispose() }
    } finally {
        try {
            if ($fixture) { Remove-OwnedTmuxFixture $fixture }
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
        }
    }
}
$report.cleanup.ownedFixtureRemoved = $fixture.Closed -and !(Test-Path -LiteralPath $fixture.DirectoryPath)
$report.cleanup.extractedPackageRemoved = !(Test-Path -LiteralPath $temporary)
if (!$report.cleanup.ownedFixtureRemoved -or !$report.cleanup.extractedPackageRemoved) {
    throw 'Resource benchmark did not remove its owned fixture and extracted package.'
}
$parent = Split-Path $destination
if (!(Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -NoNewline
"PASS resource cancellation: $SampleRounds rounds per lane; report: $destination"
