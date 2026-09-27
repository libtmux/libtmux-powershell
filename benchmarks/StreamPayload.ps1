[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $ReviewRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source,
    [ValidateRange(0, 20)] [int] $WarmupRounds = 3,
    [ValidateRange(1, 100)] [int] $SampleRounds = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-StreamPayloadSummary([long[]] $Values) {
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

function Stop-StreamPayloadPipeline {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'This internal cleanup stops only the benchmark runspace it owns.')]
    param($Pipeline, $Invocation, [string] $Name)
    if (!$Pipeline) { return }
    if ($Invocation -and !$Invocation.IsCompleted) {
        $stop = $Pipeline.BeginStop($null, $null)
        if (!$stop.AsyncWaitHandle.WaitOne(1000)) { throw "$Name did not stop within one second." }
        $Pipeline.EndStop($stop)
    }
    $Pipeline.Dispose()
}

$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) { throw 'PackageRoot must contain LibTmux.0.1.0.nupkg.' }
$binary = (Resolve-Path -LiteralPath $TmuxBinaryPath).Path
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $destination) { throw 'OutputPath already exists; choose a new report path.' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-stream-payload-' + [Guid]::NewGuid().ToString('N'))
$fixture = $null
$control = $null
$watchRunspace = $null
$watchPipeline = $null
$watchInvocation = $null
$watchReady = [Threading.ManualResetEventSlim]::new($false)
$watchMatched = [Threading.ManualResetEventSlim]::new($false)
$report = $null
$controlDisconnected = $false
$writer = $null
$null = New-Item -ItemType Directory -Path $temporary
try {
    $extractWatch = [Diagnostics.Stopwatch]::StartNew()
    $moduleRoot = Join-Path $temporary 'LibTmux/0.1.0'
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $moduleRoot)
    $extractWatch.Stop()
    Import-Module "$PSScriptRoot/StreamPayload.Checks.psm1" -Force
    Import-Module "$PSScriptRoot/PackageIdentity.psm1" -Force
    $identity = Get-BenchmarkPackageIdentity -PackageRoot $PackageRoot -ModuleRoot $moduleRoot -ReviewRoot $ReviewRoot
    $dependencies = Get-Content -LiteralPath (Join-Path $moduleRoot 'dependencies.json') -Raw | ConvertFrom-Json
    $modulePath = Join-Path $moduleRoot 'LibTmux.psd1'
    $importWatch = [Diagnostics.Stopwatch]::StartNew()
    Import-Module $modulePath -ErrorAction Stop
    $importWatch.Stop()
    . "$PSScriptRoot/../tests/support/OwnedTmux.ps1"

    $setupWatch = [Diagnostics.Stopwatch]::StartNew()
    $fixture = New-OwnedTmuxFixture -TmuxPath $binary
    $null = Invoke-OwnedTmux $fixture -Arguments @('set-window-option', '-t', 'fixture:0',
        'automatic-rename', 'off')
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $binary -ConfigurationFile '/dev/null'
    $pane = @($server | LibTmux\Get-TmuxPane -ErrorAction Stop)[0]
    if (!$pane) { throw 'The owned tmux fixture has no pane.' }
    $paneId = $pane.Id.ToString()
    $paneTty = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t',
        'fixture:0.0', '#{pane_tty}')).StdOut.Trim()
    if (!$paneTty -or !(Test-Path -LiteralPath $paneTty -PathType Leaf)) {
        throw 'The owned pane has no writable terminal.'
    }
    $writer = [IO.File]::Open($paneTty, [IO.FileMode]::Open, [IO.FileAccess]::Write,
        [IO.FileShare]::ReadWrite)
    $tmuxVersion = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()
    $setupWatch.Stop()

    $connectWatch = [Diagnostics.Stopwatch]::StartNew()
    $control = $server | LibTmux\Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
    $connectWatch.Stop()
    $initial = @($control | LibTmux\Watch-TmuxEvent -MaxEvents 1 -MaxOutputBytes 4096 -ErrorAction Stop)
    if ($initial.Count -ne 1 -or $initial[0] -isnot [LibTmux.TmuxNotificationEvent]) {
        throw 'The initial control notification was not consumed.'
    }

    $marker = 'watch-ready-' + [Guid]::NewGuid().ToString('N')
    $watchState = [hashtable]::Synchronized(@{
        EndMarker = ''; Accumulator = ''; Fragments = 0; ObservedTicks = 0L;
        EventPaneId = ''; Dropped = $false; WrongPane = $false; MarkerTicks = 0L
    })
    $watchInitial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $watchInitial.ImportPSModule(@($modulePath))
    $watchRunspace = [RunspaceFactory]::CreateRunspace($watchInitial)
    $watchRunspace.Open()
    $watchPipeline = [PowerShell]::Create()
    $watchPipeline.Runspace = $watchRunspace
    $watchScript = @'
param($control, $paneId, $marker, $state, $ready, $matched)
$control | LibTmux\Watch-TmuxEvent -MaxEvents 4096 -MaxEventBytes 8192 -MaxOutputBytes 4194304 -ErrorAction Stop |
    ForEach-Object {
        if ($_ -is [LibTmux.TmuxEventsDroppedEvent]) {
            $state.Dropped = $true
            $matched.Set()
        } elseif ($_ -is [LibTmux.TmuxNotificationEvent]) {
            if ($_.Name -ceq 'window-renamed' -and @($_.Arguments).Count -eq 2 -and
                $_.Arguments[1] -ceq $marker) {
                $state.MarkerTicks = [Diagnostics.Stopwatch]::GetTimestamp()
                $ready.Set()
            }
        } elseif ($_ -is [LibTmux.TmuxOutputEvent]) {
            if ($_.PaneId.ToString() -cne $paneId) {
                $state.WrongPane = $true
                $matched.Set()
            } else {
                $endMarker = [string] $state.EndMarker
                if ($endMarker -and $state.ObservedTicks -eq 0) {
                    $state.Accumulator += $_.Data
                    $state.Fragments++
                    if ([Text.Encoding]::UTF8.GetByteCount($state.Accumulator) -gt 65536) {
                        throw 'Event accumulation exceeded the per-round byte bound.'
                    }
                    if ($state.Accumulator.Contains($endMarker, [StringComparison]::Ordinal)) {
                        $state.EventPaneId = $_.PaneId.ToString()
                        $state.ObservedTicks = [Diagnostics.Stopwatch]::GetTimestamp()
                        $state.EndMarker = ''
                        $matched.Set()
                    }
                }
            }
        }
    }
'@
    $null = $watchPipeline.AddScript($watchScript).AddArgument($control).AddArgument($paneId).
        AddArgument($marker).AddArgument($watchState).AddArgument($watchReady).AddArgument($watchMatched)
    $watchInvocation = $watchPipeline.BeginInvoke()
    $markerWatch = [Diagnostics.Stopwatch]::StartNew()
    $null = Invoke-OwnedTmux $fixture -Arguments @('rename-window', '-t', 'fixture:0', $marker)
    if (!$watchReady.Wait(1000) -or $watchState.MarkerTicks -le 0) {
        throw 'The output watcher did not acknowledge the readiness notification.'
    }
    $markerWatch.Stop()

    $firstCalls = [Collections.Generic.List[object]]::new()
    $warmups = [Collections.Generic.List[object]]::new()
    $samples = [Collections.Generic.List[object]]::new()
    $previousEndMarker = ''
    foreach ($phase in @('firstCall', 'warmup', 'sample')) {
        $rounds = switch ($phase) {
            firstCall { 1 }
            warmup { $WarmupRounds }
            sample { $SampleRounds }
        }
        for ($round = 0; $round -lt $rounds; $round++) {
            $id = [Guid]::NewGuid().ToString('N')
            $beginMarker = 'LTSP_BEGIN_' + $id
            $endMarker = 'LTSP_END_' + $id
            $lines = @(0..11 | ForEach-Object { 'line-{0:D2}-{1}-abcdefghij' -f $_, $id })
            $payload = (@($beginMarker) + $lines + @($endMarker)) -join "`n"
            $bytes = [Text.Encoding]::ASCII.GetBytes($payload + "`n")
            $clear = [Text.Encoding]::ASCII.GetBytes("`e[2J`e[H")
            $writer.Write($clear, 0, $clear.Length)
            $writer.Flush()
            $null = Invoke-OwnedTmux $fixture -Arguments @('clear-history', '-t', $paneId)
            $watchState.Accumulator = ''
            $watchState.Fragments = 0
            $watchState.ObservedTicks = 0L
            $watchState.EventPaneId = ''
            $watchMatched.Reset()
            $watchState.EndMarker = $endMarker
            $pollState = [hashtable]::Synchronized(@{
                ReadyTicks = 0L; ObservedTicks = 0L; Attempts = 0;
                InitialAbsent = $false; CaptureText = ''; BaselineBytes = 0
            })
            $pollReady = [Threading.ManualResetEventSlim]::new($false)
            $pollMatched = [Threading.ManualResetEventSlim]::new($false)
            $pollRunspace = $null
            $pollPipeline = $null
            $pollInvocation = $null
            try {
                $pollInitial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
                $pollInitial.ImportPSModule(@($modulePath))
                $pollRunspace = [RunspaceFactory]::CreateRunspace($pollInitial)
                $pollRunspace.Open()
                $pollPipeline = [PowerShell]::Create()
                $pollPipeline.Runspace = $pollRunspace
                $pollScript = @'
param($pane, $beginMarker, $endMarker, $previousEndMarker, $state, $ready, $matched)
for ($attempt = 0; $attempt -lt 100; $attempt++) {
    $first = [string] ($pane | LibTmux\Get-TmuxPaneContent -History -Raw -ErrorAction Stop)
    $firstBytes = [Text.Encoding]::UTF8.GetByteCount($first)
    if ($firstBytes -gt 8192) { throw 'Baseline capture exceeded the byte bound.' }
    if (!$first.Contains($beginMarker, [StringComparison]::Ordinal) -and
        (!$previousEndMarker -or !$first.Contains($previousEndMarker, [StringComparison]::Ordinal))) {
        $state.InitialAbsent = $true
        $state.BaselineBytes = $firstBytes
        $state.ReadyTicks = [Diagnostics.Stopwatch]::GetTimestamp()
        $ready.Set()
        break
    }
    [Threading.Tasks.Task]::Delay(10).GetAwaiter().GetResult()
}
if (!$state.InitialAbsent) { throw 'Previous payload remained in rendered capture.' }
for ($attempt = 0; $attempt -lt 100; $attempt++) {
    $content = [string] ($pane | LibTmux\Get-TmuxPaneContent -History -Raw -ErrorAction Stop)
    $state.Attempts++
    if ([Text.Encoding]::UTF8.GetByteCount($content) -gt 65536) {
        throw 'Rendered capture exceeded the per-round byte bound.'
    }
    if ($content.Contains($endMarker, [StringComparison]::Ordinal)) {
        $state.CaptureText = $content
        $state.ObservedTicks = [Diagnostics.Stopwatch]::GetTimestamp()
        $matched.Set()
        break
    }
    [Threading.Tasks.Task]::Delay(10).GetAwaiter().GetResult()
}
'@
                $null = $pollPipeline.AddScript($pollScript).AddArgument($pane).AddArgument($beginMarker).
                    AddArgument($endMarker).AddArgument($previousEndMarker).AddArgument($pollState).
                    AddArgument($pollReady).AddArgument($pollMatched)
                $pollInvocation = $pollPipeline.BeginInvoke()
                if (!$pollReady.Wait(1000) -or !$pollState.InitialAbsent) {
                    throw "$phase/$round capture poller was not armed before production."
                }
                $startTicks = [Diagnostics.Stopwatch]::GetTimestamp()
                $deadlineTicks = $startTicks + [Diagnostics.Stopwatch]::Frequency
                $writer.Write($bytes, 0, $bytes.Length)
                $writer.Flush()
                $producerDoneTicks = [Diagnostics.Stopwatch]::GetTimestamp()
                $remaining = [int] [Math]::Max(0, [Math]::Ceiling(
                    ($deadlineTicks - [Diagnostics.Stopwatch]::GetTimestamp()) *
                    1000.0 / [Diagnostics.Stopwatch]::Frequency))
                if (![Threading.WaitHandle]::WaitAll([Threading.WaitHandle[]] @(
                            $watchMatched.WaitHandle, $pollMatched.WaitHandle), $remaining)) {
                    throw "$phase/$round did not reach both observers within one second."
                }
                if ($watchInvocation.IsCompleted -or $watchPipeline.Streams.Error.Count -ne 0 -or
                    $pollPipeline.Streams.Error.Count -ne 0) {
                    throw "$phase/$round observer ended or emitted an error."
                }
                if (!$pollInvocation.AsyncWaitHandle.WaitOne(1000)) {
                    throw "$phase/$round capture poller did not finish after the payload."
                }
                $null = $pollPipeline.EndInvoke($pollInvocation)
                $observation = @{
                    beginMarker = $beginMarker; endMarker = $endMarker; payload = $payload
                    expectedPaneId = $paneId; eventPaneId = $watchState.EventPaneId
                    eventRaw = [string] $watchState.Accumulator; captureText = [string] $pollState.CaptureText
                    markerTicks = [long] $watchState.MarkerTicks; pollerReadyTicks = [long] $pollState.ReadyTicks
                    startTicks = [long] $startTicks; producerDoneTicks = [long] $producerDoneTicks
                    eventTicks = [long] $watchState.ObservedTicks
                    captureTicks = [long] $pollState.ObservedTicks; deadlineTicks = [long] $deadlineTicks
                    eventFragments = [int] $watchState.Fragments
                    captureAttempts = [int] $pollState.Attempts; dropped = [bool] $watchState.Dropped
                    initialAbsent = [bool] $pollState.InitialAbsent
                }
                if ($watchState.WrongPane) { throw "$phase/$round observed output from another pane." }
                $checked = Assert-StreamPayloadRound -Observation $observation -Lane "$phase/$round"
                $frequency = [Diagnostics.Stopwatch]::Frequency
                $record = @{ round = $round; phase = $phase; beginMarker = $beginMarker;
                    endMarker = $endMarker; paneId = $paneId;
                    payloadBytes = $checked.payloadBytes; producedBytes = $bytes.Length;
                    baselineCaptureBytes = $pollState.BaselineBytes;
                    eventRawBytes = $checked.eventRawBytes; captureRawBytes = $checked.captureRawBytes;
                    payloadSha256 = $checked.payloadSha256;
                    eventPayloadSha256 = $checked.eventPayloadSha256;
                    capturePayloadSha256 = $checked.capturePayloadSha256;
                    eventFragments = $observation.eventFragments; captureAttempts = $observation.captureAttempts;
                    producerNanoseconds = [long] [Math]::Round(
                        ($producerDoneTicks - $startTicks) * 1000000000.0 / $frequency);
                    eventCompletionNanoseconds = [long] [Math]::Round(
                        ($observation.eventTicks - $startTicks) * 1000000000.0 / $frequency);
                    captureCompletionNanoseconds = [long] [Math]::Round(
                        ($observation.captureTicks - $startTicks) * 1000000000.0 / $frequency) }
                $previousEndMarker = $endMarker
                switch ($phase) {
                    firstCall { $firstCalls.Add($record) }
                    warmup { $warmups.Add($record) }
                    sample { $samples.Add($record) }
                }
            } finally {
                try { Stop-StreamPayloadPipeline $pollPipeline $pollInvocation 'Capture poller' }
                finally {
                    if ($pollRunspace) { $pollRunspace.Dispose() }
                    $pollReady.Dispose()
                    $pollMatched.Dispose()
                }
            }
        }
    }
    if ($watchInvocation.IsCompleted -or $watchState.Dropped -or $watchState.WrongPane) {
        throw 'The borrowed output watcher ended or lost output.'
    }
    $summary = foreach ($lane in @('event', 'capture')) {
        $property = if ($lane -eq 'event') { 'eventCompletionNanoseconds' } else { 'captureCompletionNanoseconds' }
        @{ lane = $lane; timing = (Get-StreamPayloadSummary ([long[]] @($samples |
                    ForEach-Object { $_[$property] }))) }
    }
    $sourceCommit = (git -C (Split-Path $PSScriptRoot) rev-parse HEAD).Trim()
    $sourceDirty = @((git -C (Split-Path $PSScriptRoot) status --porcelain --untracked-files=all)).Count -gt 0
    $report = [ordered]@{
        schema = 1
        status = 'PASS'
        recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        kind = 'complete multiline pane payload observation'
        workload = 'one display-safe ASCII block with twelve body lines written once to the owned pane terminal'
        shape = @{ sessions = 1; windows = 1; panes = 1; linkedWindows = 0 }
        parameters = @{ warmupRounds = $WarmupRounds; sampleRounds = $SampleRounds;
            capturePollIntervalMilliseconds = 10; observationTimeoutMilliseconds = 1000;
            maxCaptureAttempts = 100; maxEventCount = 4096; maxEventBytes = 8192;
            maxTotalOutputBytes = 4194304; maxRoundObservationBytes = 65536;
            sampling = 'serial rounds; one persistent watcher and a freshly armed capture poller per round' }
        semantics = @{ start = 'monotonic timestamp before one write of the payload plus LF to the owned pane PTY';
            event = 'first callback completing the end marker; the accumulated exact canonical block must match';
            capture = 'first complete-history rendered capture containing the end marker; the exact block must match';
            transform = 'event CRLF to LF only; no trimming or case folding within the compared block';
            scope = 'same multiline block and start clock, with observer scheduling and 10 ms capture polling included';
            noRawByteParityClaim = $true }
        provenance = @{ sourceCommit = $sourceCommit; sourceDirty = $sourceDirty;
            runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();
            checksSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/StreamPayload.Checks.psm1" -Algorithm SHA256).Hash.ToLowerInvariant();
            packageIdentitySha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/PackageIdentity.psm1" -Algorithm SHA256).Hash.ToLowerInvariant();
            packageSha256 = $identity.packageSha256;
            packageVersion = (Get-Module LibTmux).Version.ToString();
            corePackageVersion = $identity.corePackageVersion;
            embeddedAssemblyHashesVerified = $true; assemblies = @($dependencies.assemblies);
            coreAssemblySha256 = $identity.coreAssemblySha256;
            cmdletAssemblySha256 = $identity.cmdletAssemblySha256;
            sourceProvenance = $identity.sourceProvenance;
            reviewCoreRevision = $identity.reviewCoreRevision;
            reviewPortRevision = $identity.reviewPortRevision;
            coreAssemblyMvid = [LibTmux.Server].Assembly.ManifestModule.ModuleVersionId.ToString();
            cmdletAssemblyMvid = [LibTmux.PowerShell.WatchTmuxEventCommand].Assembly.ManifestModule.ModuleVersionId.ToString();
            powerShellVersion = $PSVersionTable.PSVersion.ToString(); dotnetVersion = [Environment]::Version.ToString();
            tmuxVersion = $tmuxVersion; tmuxBinarySha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant();
            os = [Runtime.InteropServices.RuntimeInformation]::OSDescription;
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }
        timing = @{ packageExtractionNanoseconds = [long] [Math]::Round(
                $extractWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            moduleImportNanoseconds = [long] [Math]::Round(
                $importWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            fixtureSetupNanoseconds = [long] [Math]::Round(
                $setupWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            controlConnectNanoseconds = [long] [Math]::Round(
                $connectWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            watcherReadinessNanoseconds = [long] [Math]::Round(
                $markerWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            warmSamplesExcludeSetupAndFirstCall = $true }
        firstCalls = $firstCalls.ToArray()
        warmups = $warmups.ToArray()
        samples = $samples.ToArray()
        summary = @($summary)
        cleanup = @{}
    }
} finally {
    try { Stop-StreamPayloadPipeline $watchPipeline $watchInvocation 'Output watcher' }
    finally {
        try {
            if ($watchRunspace) { $watchRunspace.Dispose() }
            if ($writer) { $writer.Dispose() }
            if ($control) {
                $control | LibTmux\Disconnect-TmuxControl -Confirm:$false -ErrorAction Stop
                $controlDisconnected = !$control.IsRunning -and
                    @($server | LibTmux\Get-TmuxClient -ErrorAction Stop).Count -eq 0
            }
        } finally {
            try {
                if ($fixture) { Remove-OwnedTmuxFixture $fixture }
            } finally {
                $watchReady.Dispose()
                $watchMatched.Dispose()
                Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction Stop
            }
        }
    }
}
if (!$report) { throw 'Stream payload benchmark did not produce a report.' }
$fixtureRemoved = $fixture.Closed -and !(Test-Path -LiteralPath $fixture.DirectoryPath)
if (!$controlDisconnected -or !$fixtureRemoved -or (Test-Path -LiteralPath $temporary)) {
    throw 'Stream payload benchmark left a control client, owned fixture or package extraction.'
}
$report.cleanup = @{ controlDisconnected = $controlDisconnected; fixtureRemoved = $fixtureRemoved;
    packageExtractionRemoved = $true }
$parent = Split-Path -Parent $destination
if (!(Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -NoNewline
"PASS stream payload: $SampleRounds exact multiline samples; report: $destination"
