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

function Get-OutputLatencySummary([long[]] $Values) {
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

function Stop-OutputLatencyPipeline {
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
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-output-latency-' + [Guid]::NewGuid().ToString('N'))
$fixture = $null
$control = $null
$watchRunspace = $null
$watchPipeline = $null
$watchInvocation = $null
$watchReady = [Threading.ManualResetEventSlim]::new($false)
$watchMatched = [Threading.ManualResetEventSlim]::new($false)
$report = $null
$controlDisconnected = $false
$null = New-Item -ItemType Directory -Path $temporary
try {
    $extractWatch = [Diagnostics.Stopwatch]::StartNew()
    $moduleRoot = Join-Path $temporary 'LibTmux/0.1.0'
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $moduleRoot)
    $extractWatch.Stop()
    Import-Module "$PSScriptRoot/OutputLatency.Checks.psm1" -Force
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
    $null = Invoke-OwnedTmux $fixture -Arguments @('send-keys', '-t', 'fixture:0.0',
        'stty -echo && exec /bin/cat', 'Enter')
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $binary -ConfigurationFile '/dev/null'
    $pane = @($server | LibTmux\Get-TmuxPane -ErrorAction Stop)[0]
    if (!$pane) { throw 'The owned tmux fixture has no pane.' }
    $paneId = $pane.Id.ToString()
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
        Token = ''; Accumulator = ''; Fragments = 0; ObservedTicks = 0L;
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
$control | LibTmux\Watch-TmuxEvent -MaxEvents 1024 -MaxOutputBytes 131072 -ErrorAction Stop |
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
                $token = [string] $state.Token
                if ($token -and $state.ObservedTicks -eq 0) {
                    $state.Accumulator += $_.Data
                    $state.Fragments++
                    if ($state.Accumulator.Contains($token, [StringComparison]::Ordinal)) {
                        $state.EventPaneId = $_.PaneId.ToString()
                        $state.ObservedTicks = [Diagnostics.Stopwatch]::GetTimestamp()
                        $state.Token = ''
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
    foreach ($phase in @('firstCall', 'warmup', 'sample')) {
        $rounds = switch ($phase) {
            firstCall { 1 }
            warmup { $WarmupRounds }
            sample { $SampleRounds }
        }
        for ($round = 0; $round -lt $rounds; $round++) {
            $token = 'LTB' + [Guid]::NewGuid().ToString('N')
            $watchState.Accumulator = ''
            $watchState.Fragments = 0
            $watchState.ObservedTicks = 0L
            $watchState.EventPaneId = ''
            $watchMatched.Reset()
            $watchState.Token = $token
            $pollState = [hashtable]::Synchronized(@{
                ReadyTicks = 0L; ObservedTicks = 0L; Attempts = 0;
                InitialAbsent = $false; CaptureText = ''
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
param($pane, $token, $state, $ready, $matched)
$first = [string] ($pane | LibTmux\Get-TmuxPaneContent -History -Raw -ErrorAction Stop)
if ($first.Contains($token, [StringComparison]::Ordinal)) { throw 'Token existed before timed send.' }
$state.InitialAbsent = $true
$state.ReadyTicks = [Diagnostics.Stopwatch]::GetTimestamp()
$ready.Set()
while ($true) {
    $content = [string] ($pane | LibTmux\Get-TmuxPaneContent -History -Raw -ErrorAction Stop)
    $state.Attempts++
    if ($content.Contains($token, [StringComparison]::Ordinal)) {
        $state.CaptureText = $content
        $state.ObservedTicks = [Diagnostics.Stopwatch]::GetTimestamp()
        $matched.Set()
        break
    }
    [Threading.Tasks.Task]::Delay(10).GetAwaiter().GetResult()
}
'@
                $null = $pollPipeline.AddScript($pollScript).AddArgument($pane).AddArgument($token).
                    AddArgument($pollState).AddArgument($pollReady).AddArgument($pollMatched)
                $pollInvocation = $pollPipeline.BeginInvoke()
                if (!$pollReady.Wait(1000) -or !$pollState.InitialAbsent) {
                    throw "$phase/$round capture poller was not armed before the send."
                }
                $budget = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(1))
                try {
                    $startTicks = [Diagnostics.Stopwatch]::GetTimestamp()
                    $deadlineTicks = $startTicks + [Diagnostics.Stopwatch]::Frequency
                    $null = Invoke-OwnedTmux $fixture -Arguments @('send-keys', '-t', $paneId, '-l', '--', $token) `
                        -CancellationToken $budget.Token
                    $null = Invoke-OwnedTmux $fixture -Arguments @('send-keys', '-t', $paneId, 'Enter') `
                        -CancellationToken $budget.Token
                    $remaining = [int] [Math]::Max(0, [Math]::Ceiling(
                        ($deadlineTicks - [Diagnostics.Stopwatch]::GetTimestamp()) *
                        1000.0 / [Diagnostics.Stopwatch]::Frequency))
                    if (![Threading.WaitHandle]::WaitAll([Threading.WaitHandle[]] @(
                                $watchMatched.WaitHandle, $pollMatched.WaitHandle), $remaining)) {
                        throw "$phase/$round did not reach both observers within one second."
                    }
                } finally { $budget.Dispose() }
                if ($watchInvocation.IsCompleted -or $watchPipeline.Streams.Error.Count -ne 0 -or
                    $pollPipeline.Streams.Error.Count -ne 0) {
                    throw "$phase/$round observer ended or emitted an error."
                }
                if (!$pollInvocation.AsyncWaitHandle.WaitOne(1000)) {
                    throw "$phase/$round capture poller did not finish after observing the token."
                }
                $null = $pollPipeline.EndInvoke($pollInvocation)
                $observation = @{
                    token = $token; expectedPaneId = $paneId; eventPaneId = $watchState.EventPaneId
                    eventText = [string] $watchState.Accumulator; captureText = [string] $pollState.CaptureText
                    markerTicks = [long] $watchState.MarkerTicks; pollerReadyTicks = [long] $pollState.ReadyTicks
                    startTicks = [long] $startTicks; eventTicks = [long] $watchState.ObservedTicks
                    captureTicks = [long] $pollState.ObservedTicks; deadlineTicks = [long] $deadlineTicks
                    eventFragments = [int] $watchState.Fragments
                    captureAttempts = [int] $pollState.Attempts; dropped = [bool] $watchState.Dropped
                    initialAbsent = [bool] $pollState.InitialAbsent
                }
                Assert-OutputLatencyRound -Observation $observation -Lane "$phase/$round"
                $frequency = [Diagnostics.Stopwatch]::Frequency
                $record = @{ round = $round; phase = $phase; token = $token; paneId = $paneId;
                    eventFragments = $observation.eventFragments; captureAttempts = $observation.captureAttempts;
                    eventText = $observation.eventText; captureMatchedLine = @($observation.captureText.Split("`n") |
                        Where-Object { $_.Contains($token, [StringComparison]::Ordinal) })[0];
                    eventVisibilityNanoseconds = [long] [Math]::Round(
                        ($observation.eventTicks - $startTicks) * 1000000000.0 / $frequency);
                    captureVisibilityNanoseconds = [long] [Math]::Round(
                        ($observation.captureTicks - $startTicks) * 1000000000.0 / $frequency) }
                switch ($phase) {
                    firstCall { $firstCalls.Add($record) }
                    warmup { $warmups.Add($record) }
                    sample { $samples.Add($record) }
                }
            } finally {
                try { Stop-OutputLatencyPipeline $pollPipeline $pollInvocation 'Capture poller' }
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
        $property = if ($lane -eq 'event') { 'eventVisibilityNanoseconds' } else { 'captureVisibilityNanoseconds' }
        @{ lane = $lane; timing = (Get-OutputLatencySummary ([long[]] @($samples |
                    ForEach-Object { $_[$property] }))) }
    }
    $sourceCommit = (git -C (Split-Path $PSScriptRoot) rev-parse HEAD).Trim()
    $sourceDirty = @((git -C (Split-Path $PSScriptRoot) status --porcelain --untracked-files=all)).Count -gt 0
    $report = [ordered]@{
        schema = 1
        status = 'PASS'
        recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        kind = 'same-payload output visibility'
        workload = 'one plain ASCII token echoed by a cat pane to event and rendered capture observers'
        shape = @{ sessions = 1; windows = 1; panes = 1; linkedWindows = 0 }
        parameters = @{ warmupRounds = $WarmupRounds; sampleRounds = $SampleRounds;
            capturePollIntervalMilliseconds = 10; observationTimeoutMilliseconds = 1000;
            sampling = 'serial rounds; one persistent watcher and a freshly armed capture poller per round' }
        semantics = @{ start = 'monotonic timestamp before two owned tmux send-keys calls';
            event = 'first callback whose accumulated output fragments contain the exact token';
            capture = 'first complete-history rendered capture containing that token';
            scope = 'same token and start clock, with observer scheduling and 10 ms capture polling included';
            noByteExactClaim = $true }
        provenance = @{ sourceCommit = $sourceCommit; sourceDirty = $sourceDirty;
            runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();
            checksSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/OutputLatency.Checks.psm1" -Algorithm SHA256).Hash.ToLowerInvariant();
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
    try { Stop-OutputLatencyPipeline $watchPipeline $watchInvocation 'Output watcher' }
    finally {
        try {
            if ($watchRunspace) { $watchRunspace.Dispose() }
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
if (!$report) { throw 'Output latency benchmark did not produce a report.' }
$fixtureRemoved = $fixture.Closed -and !(Test-Path -LiteralPath $fixture.DirectoryPath)
if (!$controlDisconnected -or !$fixtureRemoved -or (Test-Path -LiteralPath $temporary)) {
    throw 'Output latency benchmark left a control client, owned fixture or package extraction.'
}
$report.cleanup = @{ controlDisconnected = $controlDisconnected; fixtureRemoved = $fixtureRemoved;
    packageExtractionRemoved = $true }
$parent = Split-Path -Parent $destination
if (!(Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -NoNewline
"PASS output latency: $SampleRounds same-payload samples; report: $destination"
