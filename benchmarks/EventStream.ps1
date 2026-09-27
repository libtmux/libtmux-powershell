[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source,
    [ValidateRange(0, 20)] [int] $WarmupRounds = 3,
    [ValidateRange(1, 100)] [int] $SampleRounds = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-BoundedEventWatch($Runspace, $Control, [int] $MaxEvents) {
    $pipeline = [PowerShell]::Create()
    try {
        $pipeline.Runspace = $Runspace
        $null = $pipeline.AddCommand('LibTmux\Watch-TmuxEvent').AddParameter('Connection', $Control).
            AddParameter('MaxEvents', $MaxEvents).AddParameter('MaxOutputBytes', 1048576)
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $invocation = $pipeline.BeginInvoke()
        if (!$invocation.AsyncWaitHandle.WaitOne(1000)) {
            $stop = $pipeline.BeginStop($null, $null)
            if (!$stop.AsyncWaitHandle.WaitOne(1000)) { throw 'Event watch did not stop within one second.' }
            $pipeline.EndStop($stop)
            throw 'Event watch did not complete within one second.'
        }
        $events = @($pipeline.EndInvoke($invocation))
        $watch.Stop()
        if ($pipeline.Streams.Error.Count -ne 0) {
            throw "Event watch emitted an error: $($pipeline.Streams.Error[0])"
        }
        [pscustomobject]@{ events = $events; elapsedNanoseconds = [long] [Math]::Round(
                $watch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency) }
    } finally {
        $pipeline.Dispose()
    }
}

function Get-WindowName($Control) {
    $command = LibTmux\New-TmuxCommand -Name 'display-message' -Arguments @('-p', '-t', 'fixture:0', '#{window_name}')
    $output = @($Control | LibTmux\Invoke-TmuxControlCommand -Command $command -ErrorAction Stop)
    if ($output.Count -ne 1 -or $output[0] -isnot [string]) {
        throw 'The native window name read did not return one line.'
    }
    $output[0]
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

$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) { throw 'PackageRoot must contain LibTmux.0.1.0.nupkg.' }
$binary = (Resolve-Path -LiteralPath $TmuxBinaryPath).Path
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $destination) { throw 'OutputPath already exists; choose a new report path.' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-event-stream-' + [Guid]::NewGuid().ToString('N'))
$fixture = $null
$control = $null
$runspace = $null
$report = $null
$null = New-Item -ItemType Directory -Path $temporary
try {
    $module = Join-Path $temporary 'LibTmux/0.1.0'
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $module)
    $modulePath = Join-Path $module 'LibTmux.psd1'
    $coreVersion = (Get-Content -LiteralPath (Join-Path $module 'dependencies.json') -Raw |
        ConvertFrom-Json).corePackageVersion
    if ($coreVersion -cne '0.0.0-alpha.16.ps.2') {
        throw "Event stream benchmark requires the reviewed 0.0.0-alpha.16.ps.2 core; found $coreVersion."
    }
    $importWatch = [Diagnostics.Stopwatch]::StartNew()
    Import-Module $modulePath -ErrorAction Stop
    $importWatch.Stop()
    Import-Module "$PSScriptRoot/EventStream.Checks.psm1" -Force
    . "$PSScriptRoot/../tests/support/OwnedTmux.ps1"

    $fixture = New-OwnedTmuxFixture -TmuxPath $binary
    $options = [LibTmux.ServerConnectionOptions] @{
        SocketPath = $fixture.SocketPath
        TmuxBinaryPath = $binary
        ControlModeEventBufferCapacity = 1
    }
    $server = [LibTmux.Server]::Open($options)
    $tmuxVersion = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()
    $windowId = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:0',
        '#{window_id}')).StdOut.Trim()
    if ($windowId -cnotmatch '^@[0-9]+$') { throw 'The owned fixture did not return one native window ID.' }
    $connectWatch = [Diagnostics.Stopwatch]::StartNew()
    $control = $server | LibTmux\Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
    $connectWatch.Stop()
    if (!$control.IsRunning) { throw 'The pressure-test control client did not start.' }

    $initial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $initial.ImportPSModule(@($modulePath))
    $runspace = [RunspaceFactory]::CreateRunspace($initial)
    $runspace.Open()
    $initialDrain = Invoke-BoundedEventWatch $runspace $control 1
    $initialEvents = [Collections.Generic.List[object]]::new()
    foreach ($item in $initialDrain.events) { $initialEvents.Add($item) }
    $previousTotalDropped = 0L
    if ($initialEvents[0] -is [LibTmux.TmuxEventsDroppedEvent]) {
        $previousTotalDropped = $initialEvents[0].TotalDropped
        $remaining = Invoke-BoundedEventWatch $runspace $control 1
        foreach ($item in $remaining.events) { $initialEvents.Add($item) }
    }
    if ($initialEvents[-1] -isnot [LibTmux.TmuxNotificationEvent]) {
        throw 'The initial control notification was not drained before sampling.'
    }
    $initialTotalDropped = $previousTotalDropped

    $cells = @('burst-8', 'burst-16')
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
            for ($position = 0; $position -lt $cells.Count; $position++) {
                $cell = if ($phase -eq 'firstCall') { $cells[$position] } else {
                    $cells[($round + $position) % $cells.Count]
                }
                $burst = if ($cell -eq 'burst-8') { 8 } else { 16 }
                $lastName = $null
                $produceWatch = [Diagnostics.Stopwatch]::StartNew()
                for ($index = 0; $index -lt $burst; $index++) {
                    $lastName = "stream-$phase-$round-$burst-$($index.ToString('D2'))"
                    $command = LibTmux\New-TmuxCommand -Name 'rename-window' -Arguments @('-t', 'fixture:0', $lastName)
                    $output = @($control | LibTmux\Invoke-TmuxControlCommand -Command $command -ErrorAction Stop)
                    if ($output.Count -ne 0) { throw "$phase/$round/$cell returned output for a rename command." }
                }
                $produceWatch.Stop()
                $drain = Invoke-BoundedEventWatch $runspace $control 2
                $events = @($drain.events)
                $observed = foreach ($item in $events) {
                    if ($item -is [LibTmux.TmuxEventsDroppedEvent]) {
                        [pscustomobject]@{ kind = 'dropped'; count = [long] $item.Count;
                            totalDropped = [long] $item.TotalDropped }
                    } elseif ($item -is [LibTmux.TmuxNotificationEvent]) {
                        [pscustomobject]@{ kind = 'notification'; name = $item.Name;
                            arguments = @($item.Arguments) }
                    } else {
                        [pscustomobject]@{ kind = $item.GetType().Name }
                    }
                }
                $nativeFinalName = Get-WindowName $control
                $accounting = Assert-BenchmarkEventBurst -ExpectedBurst $burst -ExpectedWindowId $windowId `
                    -ExpectedFinalName $lastName -Events @($observed) -ObservedFinalName $nativeFinalName `
                    -PreviousTotalDropped $previousTotalDropped -Lane "$phase/$round/$cell"
                $previousTotalDropped = $accounting.totalDropped
                $record = @{ round = $round; position = $position; cell = $cell;
                    produced = $accounting.produced; delivered = $accounting.delivered;
                    dropped = $accounting.dropped; totalDropped = $accounting.totalDropped;
                    finalName = $lastName; nativeFinalName = $nativeFinalName;
                    events = @($observed);
                    produceNanoseconds = [long] [Math]::Round(
                        $produceWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
                    drainNanoseconds = $drain.elapsedNanoseconds }
                switch ($phase) {
                    firstCall { $firstCalls.Add($record) }
                    warmup { $warmups.Add($record) }
                    sample { $samples.Add($record) }
                }
            }
        }
    }

    $runspace.Dispose()
    $runspace = $null
    $disconnectWatch = [Diagnostics.Stopwatch]::StartNew()
    $control | LibTmux\Disconnect-TmuxControl -Confirm:$false -ErrorAction Stop
    $disconnectWatch.Stop()
    $controlDisconnected = !$control.IsRunning -and @($server | LibTmux\Get-TmuxClient -ErrorAction Stop).Count -eq 0
    $borrowedSessionAlive = @($server | LibTmux\Get-TmuxSession -Name 'fixture' -ErrorAction Stop).Count -eq 1 -and
        !$fixture.ServerProcess.HasExited
    if (!$controlDisconnected -or !$borrowedSessionAlive) {
        throw 'Event stream cleanup changed the borrowed session or left a client attached.'
    }

    $summary = foreach ($cell in $cells) {
        $rows = @($samples | Where-Object cell -EQ $cell)
        @{ cell = $cell; samples = $rows.Count;
            produced = ($rows | Measure-Object produced -Sum).Sum;
            delivered = ($rows | Measure-Object delivered -Sum).Sum;
            dropped = ($rows | Measure-Object dropped -Sum).Sum;
            production = (Get-TimingSummary ([long[]] @($rows | ForEach-Object produceNanoseconds)));
            drain = (Get-TimingSummary ([long[]] @($rows | ForEach-Object drainNanoseconds))) }
    }
    $sourceCommit = (git -C (Split-Path $PSScriptRoot) rev-parse HEAD).Trim()
    $sourceDirty = @((git -C (Split-Path $PSScriptRoot) status --porcelain --untracked-files=all)).Count -gt 0
    $report = [ordered]@{
        schema = 1
        status = 'PASS'
        recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        kind = 'queue-pressure'
        workload = 'sequential window renames followed by a bounded event drain'
        cells = $cells
        shape = @{ sessions = 1; windows = 1; panes = 1; linkedWindows = 0 }
        parameters = @{ eventBufferCapacity = 1; warmupRounds = $WarmupRounds;
            sampleRounds = $SampleRounds; bursts = @(8, 16);
            sampling = 'serial pressure cells, rotating burst order';
            watchMaxEvents = 2; watchMaxOutputBytes = 1048576;
            watchCompletionTimeoutMilliseconds = 1000 }
        semantics = @{ comparison = 'pressure outcomes only; no polling or capture lane';
            producer = 'one reused control client sends rename-window -t fixture:0 <name> serially';
            consumer = 'Watch-TmuxEvent on the borrowed client emits one loss record and the retained final notification';
            equality = 'produced = delivered + dropped; latest event and native final window name agree' }
        provenance = @{ sourceCommit = $sourceCommit; sourceDirty = $sourceDirty;
            runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();
            checksSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/EventStream.Checks.psm1" -Algorithm SHA256).Hash.ToLowerInvariant();
            packageVersion = (Get-Module LibTmux).Version.ToString();
            corePackageVersion = $coreVersion;
            packageSha256 = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant();
            tmuxVersion = $tmuxVersion;
            tmuxSha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant();
            powerShellVersion = $PSVersionTable.PSVersion.ToString();
            dotnetRuntimeVersion = [Environment]::Version.ToString();
            os = [Runtime.InteropServices.RuntimeInformation]::OSDescription;
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();
            coreAssemblyMvid = [LibTmux.Server].Assembly.ManifestModule.ModuleVersionId.ToString();
            cmdletAssemblyMvid = [LibTmux.PowerShell.WatchTmuxEventCommand].Assembly.ManifestModule.ModuleVersionId.ToString() }
        timing = @{ moduleImportNanoseconds = [long] [Math]::Round(
                $importWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            controlConnectNanoseconds = [long] [Math]::Round(
                $connectWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            controlDisconnectNanoseconds = [long] [Math]::Round(
                $disconnectWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            firstCallsIncludeJit = $true; warmSamplesExcludeConnectionAndFixtureSetup = $true;
            producerAndDrainTimedSeparately = $true }
        initialEvents = @($initialEvents | ForEach-Object { $_.GetType().Name })
        initialTotalDropped = $initialTotalDropped
        windowId = $windowId
        cleanup = @{ controlDisconnected = $controlDisconnected; borrowedSessionAlive = $borrowedSessionAlive }
        firstCalls = $firstCalls.ToArray()
        warmups = $warmups.ToArray()
        samples = $samples.ToArray()
        summary = @($summary)
    }
} finally {
    try {
        if ($runspace) { $runspace.Dispose() }
    } finally {
        try {
            if ($control) { $null = $control.DisposeAsync().AsTask().GetAwaiter().GetResult() }
        } finally {
            try {
                if ($fixture) { Remove-OwnedTmuxFixture $fixture }
            } finally {
                if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
            }
        }
    }
}
$report.cleanup.ownedFixtureRemoved = $fixture.Closed -and !(Test-Path -LiteralPath $fixture.DirectoryPath)
$report.cleanup.extractedPackageRemoved = !(Test-Path -LiteralPath $temporary)
if (!$report.cleanup.ownedFixtureRemoved -or !$report.cleanup.extractedPackageRemoved) {
    throw 'Event stream cleanup did not remove the owned fixture and extracted package.'
}
$parent = Split-Path $destination
if (!(Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -NoNewline
"PASS event stream pressure: $SampleRounds rounds per burst; report: $destination"
