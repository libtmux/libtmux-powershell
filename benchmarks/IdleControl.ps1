[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source,
    [ValidateRange(0, 5)] [int] $WarmupIntervals = 2,
    [ValidateRange(1, 100)] [int] $SamplesPerPhase = 20,
    [ValidateRange(50, 1000)] [int] $IntervalMilliseconds = 250
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertTo-NanosecondCount([long] $Ticks) {
    [long] [Math]::Round($Ticks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency)
}

function Get-ProcessCounter([Diagnostics.Process] $Process) {
    if ($Process.HasExited) { throw "Owned process $($Process.Id) exited during idle sampling." }
    $Process.Refresh()
    @{ cpuTicks = [long] $Process.TotalProcessorTime.Ticks;
        rssBytes = [long] $Process.WorkingSet64 }
}

function Get-IdleSnapshot([Diagnostics.Process] $PowerShellProcess,
    [Diagnostics.Process] $TmuxServerProcess, [Diagnostics.Process] $ControlClientProcess) {
    $timestamp = [Diagnostics.Stopwatch]::GetTimestamp()
    $powerShell = Get-ProcessCounter $PowerShellProcess
    $tmuxServer = Get-ProcessCounter $TmuxServerProcess
    $controlClient = if ($ControlClientProcess) { Get-ProcessCounter $ControlClientProcess } else { $null }
    @{ timestamp = $timestamp; allocatedBytes = [long] [GC]::GetTotalAllocatedBytes($true);
        powerShell = $powerShell; tmuxServer = $tmuxServer; controlClient = $controlClient }
}

function ConvertTo-ProcessInterval($Start, $End) {
    if (!$Start -or !$End) { return $null }
    @{ cpuStartTicks = $Start.cpuTicks; cpuEndTicks = $End.cpuTicks;
        cpuDeltaNanoseconds = [long] (100L * ($End.cpuTicks - $Start.cpuTicks));
        rssStartBytes = $Start.rssBytes; rssEndBytes = $End.rssBytes }
}

function ConvertTo-IdleInterval($Start, $End, [int] $Index) {
    @{ index = $Index;
        intervalNanoseconds = ConvertTo-NanosecondCount ($End.timestamp - $Start.timestamp);
        allocatedStartBytes = $Start.allocatedBytes; allocatedEndBytes = $End.allocatedBytes;
        allocatedDeltaBytes = $End.allocatedBytes - $Start.allocatedBytes;
        powerShell = ConvertTo-ProcessInterval $Start.powerShell $End.powerShell;
        tmuxServer = ConvertTo-ProcessInterval $Start.tmuxServer $End.tmuxServer;
        controlClient = ConvertTo-ProcessInterval $Start.controlClient $End.controlClient }
}

function Get-NativeClientPidList($Fixture) {
    $result = Invoke-OwnedTmux $Fixture -Arguments @('list-clients', '-F', '#{client_pid}') -AllowFailure
    if ($result.ExitCode -ne 0 -and $result.StdErr -cnotmatch '^no clients') {
        throw "Native list-clients failed ($($result.ExitCode)): $($result.StdErr.Trim())"
    }
    foreach ($line in $result.StdOut.Split("`n", [StringSplitOptions]::RemoveEmptyEntries)) {
        [int] $line.Trim()
    }
}

function Get-AliveOwnedProcessCount($Fixture) {
    $processes = @($Fixture.ServerProcess) + $Fixture.PaneProcesses.ToArray() + $Fixture.ClientProcesses.ToArray()
    @($processes | Where-Object { !$_.HasExited }).Count
}

function Get-TopologyIdentity($Fixture) {
    (Invoke-OwnedTmux $Fixture -Arguments @('display-message', '-p', '-t', 'fixture:0.0',
            '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}')).StdOut.Trim()
}

function Get-PhaseState($Fixture, $Control) {
    $pids = @(Get-NativeClientPidList $Fixture)
    @{ identity = Get-TopologyIdentity $Fixture; nativeClientCount = $pids.Count;
        controlClientPid = $(if ($pids.Count -eq 1) { $pids[0] } else { $null });
        aliveOwnedProcessCount = Get-AliveOwnedProcessCount $Fixture;
        connectionRunning = [bool] ($Control -and $Control.IsRunning) }
}

function Measure-IdlePhase($Fixture, $Control, [Diagnostics.Process] $PowerShellProcess,
    [Diagnostics.Process] $ControlClientProcess, [string] $Name,
    [int] $WarmupIntervals, [int] $SamplesPerPhase, [int] $IntervalMilliseconds) {
    $startState = Get-PhaseState $Fixture $Control
    $warmups = [Collections.Generic.List[object]]::new()
    $samples = [Collections.Generic.List[object]]::new()
    $timer = [Threading.PeriodicTimer]::new([TimeSpan]::FromMilliseconds($IntervalMilliseconds))
    try {
        $previous = Get-IdleSnapshot $PowerShellProcess $Fixture.ServerProcess $ControlClientProcess
        for ($index = 0; $index -lt $WarmupIntervals + $SamplesPerPhase; $index++) {
            if (!$timer.WaitForNextTickAsync().AsTask().GetAwaiter().GetResult()) {
                throw "$Name periodic timer stopped before the requested interval completed."
            }
            $next = Get-IdleSnapshot $PowerShellProcess $Fixture.ServerProcess $ControlClientProcess
            if ($index -lt $WarmupIntervals) {
                $warmups.Add((ConvertTo-IdleInterval $previous $next $index))
            } else {
                $samples.Add((ConvertTo-IdleInterval $previous $next ($index - $WarmupIntervals)))
            }
            $previous = $next
        }
    } finally {
        $timer.Dispose()
    }
    $endState = Get-PhaseState $Fixture $Control
    @{ name = $Name; identity = $startState.identity; identityAtEnd = $endState.identity;
        nativeClientCount = $startState.nativeClientCount;
        nativeClientCountAtEnd = $endState.nativeClientCount;
        controlClientPid = $startState.controlClientPid;
        controlClientPidAtEnd = $endState.controlClientPid;
        aliveOwnedProcessCount = $startState.aliveOwnedProcessCount;
        aliveOwnedProcessCountAtEnd = $endState.aliveOwnedProcessCount;
        connectionRunning = $startState.connectionRunning;
        connectionRunningAtEnd = $endState.connectionRunning;
        warmups = $warmups.ToArray(); samples = $samples.ToArray() }
}

function Get-Distribution([long[]] $Values) {
    $sorted = [long[]] $Values.Clone()
    [Array]::Sort($sorted)
    $middle = [int] [Math]::Floor($sorted.Length / 2)
    $median = if ($sorted.Length % 2) { $sorted[$middle] } else {
        ($sorted[$middle - 1] + $sorted[$middle]) / 2.0
    }
    @{ samples = $sorted.Length; median = $median;
        p95 = $(if ($sorted.Length -ge 20) {
                $sorted[[int] [Math]::Ceiling($sorted.Length * 0.95) - 1]
            } else { $null }) }
}

$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) { throw 'PackageRoot must contain LibTmux.0.1.0.nupkg.' }
$binary = (Resolve-Path -LiteralPath $TmuxBinaryPath).Path
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $destination) { throw 'OutputPath already exists; choose a new report path.' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-idle-control-' + [Guid]::NewGuid().ToString('N'))
$fixture = $null
$control = $null
$controlClientProcess = $null
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
        throw "Idle control benchmark requires reviewed core 0.0.0-alpha.16.ps.2; found $coreVersion."
    }
    $importWatch = [Diagnostics.Stopwatch]::StartNew()
    Import-Module $modulePath -ErrorAction Stop
    $importWatch.Stop()
    Import-Module "$PSScriptRoot/IdleControl.Checks.psm1" -Force
    . "$PSScriptRoot/../tests/support/OwnedTmux.ps1"

    $fixtureWatch = [Diagnostics.Stopwatch]::StartNew()
    $fixture = New-OwnedTmuxFixture -TmuxPath $binary
    $fixtureWatch.Stop()
    $tmuxVersion = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()
    $identity = Get-TopologyIdentity $fixture
    if ($identity -cnotmatch '^\$[0-9]+\|@[0-9]+\|%[0-9]+\|[0-9]+$') {
        throw 'The owned fixture did not return one native session/window/pane/process identity.'
    }
    $options = [LibTmux.ServerConnectionOptions] @{
        SocketPath = $fixture.SocketPath
        TmuxBinaryPath = $binary
        ControlModeEventBufferCapacity = 16
    }
    $server = [LibTmux.Server]::Open($options)

    $phases = [Collections.Generic.List[object]]::new()
    $phases.Add((Measure-IdlePhase $fixture $null $powerShellProcess $null 'before' `
                $WarmupIntervals $SamplesPerPhase $IntervalMilliseconds))
    $connectWatch = [Diagnostics.Stopwatch]::StartNew()
    $control = $server | LibTmux\Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
    $connectWatch.Stop()
    if (!$control.IsRunning) { throw 'The installed control client did not start.' }
    $clientPids = @(Get-NativeClientPidList $fixture)
    if ($clientPids.Count -ne 1) { throw 'The owned tmux server did not expose exactly one control client.' }
    $controlClientProcess = [Diagnostics.Process]::GetProcessById($clientPids[0])
    $fixture.ClientProcesses.Add($controlClientProcess)
    $null = $fixture.OwnedProcessIds.Add($clientPids[0])
    $phases.Add((Measure-IdlePhase $fixture $control $powerShellProcess $controlClientProcess 'during' `
                $WarmupIntervals $SamplesPerPhase $IntervalMilliseconds))
    $disconnectWatch = [Diagnostics.Stopwatch]::StartNew()
    $control | LibTmux\Disconnect-TmuxControl -Confirm:$false -ErrorAction Stop
    $disconnectWatch.Stop()
    $controlClientExited = $controlClientProcess.WaitForExit(1000)
    $controlDisconnected = !$control.IsRunning
    $phases.Add((Measure-IdlePhase $fixture $control $powerShellProcess $null 'after' `
                $WarmupIntervals $SamplesPerPhase $IntervalMilliseconds))
    $identityAtEnd = Get-TopologyIdentity $fixture
    $nativeClientsAtEnd = @(Get-NativeClientPidList $fixture).Count
    $borrowedSessionAlive = !$fixture.ServerProcess.HasExited -and $identityAtEnd -ceq $identity

    $summary = foreach ($phase in $phases) {
        $rows = @($phase.samples)
        @{ name = $phase.name;
            actualIntervalNanoseconds = Get-Distribution ([long[]] @($rows | ForEach-Object intervalNanoseconds));
            powerShellCpuNanoseconds = Get-Distribution ([long[]] @($rows | ForEach-Object { $_.powerShell.cpuDeltaNanoseconds }));
            tmuxServerCpuNanoseconds = Get-Distribution ([long[]] @($rows | ForEach-Object { $_.tmuxServer.cpuDeltaNanoseconds }));
            dotnetAllocatedBytes = Get-Distribution ([long[]] @($rows | ForEach-Object allocatedDeltaBytes));
            powerShellRssEndBytes = Get-Distribution ([long[]] @($rows | ForEach-Object { $_.powerShell.rssEndBytes }));
            tmuxServerRssEndBytes = Get-Distribution ([long[]] @($rows | ForEach-Object { $_.tmuxServer.rssEndBytes }));
            controlClientCpuNanoseconds = $(if ($phase.name -eq 'during') {
                    Get-Distribution ([long[]] @($rows | ForEach-Object { $_.controlClient.cpuDeltaNanoseconds }))
                } else { $null });
            controlClientRssEndBytes = $(if ($phase.name -eq 'during') {
                    Get-Distribution ([long[]] @($rows | ForEach-Object { $_.controlClient.rssEndBytes }))
                } else { $null }) }
    }
    $sourceCommit = (git -C (Split-Path $PSScriptRoot) rev-parse HEAD).Trim()
    $sourceDirty = @((git -C (Split-Path $PSScriptRoot) status --porcelain --untracked-files=all)).Count -gt 0
    $report = [ordered]@{
        schema = 1; status = 'PASS'; recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O');
        kind = 'single idle control connection resource observation';
        shape = @{ sockets = 1; sessions = 1; windows = 1; panes = 1; linkedWindows = 0 };
        parameters = @{ warmupIntervals = $WarmupIntervals; samplesPerPhase = $SamplesPerPhase;
            intervalMilliseconds = $IntervalMilliseconds; eventBufferCapacity = 16;
            phaseOrder = @('before', 'during', 'after') };
        semantics = @{ workload = 'one owned detached tmux session, an installed control connection, and no scheduled tmux commands during each sampling phase';
            comparison = 'equal-duration serial observations before connection, while connected, and after disconnect; no speed ratio or causal idle-cost claim';
            timer = 'one PeriodicTimer per phase; actual interval length is recorded per sample; native probes occur outside timed intervals';
            cpu = 'TotalProcessorTime deltas of this PowerShell process, the owned foreground tmux daemon, and the native control client while connected';
            allocation = 'GC.GetTotalAllocatedBytes(true) is process-wide .NET allocation, including the sampler, module, and background threads; no per-connection allocation attribution';
            rss = 'WorkingSet64 snapshots are process RSS observations, not retained-memory or leak measurements';
            queue = 'control event buffer configured to capacity 16; occupancy, high-water mark, and drop count are not exposed by this passive sampler';
            idle = 'initial control notifications may remain buffered; no event producer or watcher is active during timed intervals';
            order = 'fixed before/during/after order can include temporal drift and connection warmup effects' };
        provenance = @{ sourceCommit = $sourceCommit; sourceDirty = $sourceDirty;
            runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant();
            checksSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/IdleControl.Checks.psm1").Hash.ToLowerInvariant();
            packageVersion = (Get-Module LibTmux).Version.ToString(); corePackageVersion = $coreVersion;
            packageSha256 = (Get-FileHash -LiteralPath $package).Hash.ToLowerInvariant();
            tmuxVersion = $tmuxVersion; tmuxSha256 = (Get-FileHash -LiteralPath $binary).Hash.ToLowerInvariant();
            powerShellVersion = $PSVersionTable.PSVersion.ToString();
            dotnetRuntimeVersion = [Environment]::Version.ToString();
            os = [Runtime.InteropServices.RuntimeInformation]::OSDescription;
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();
            coreAssemblyMvid = [LibTmux.Server].Assembly.ManifestModule.ModuleVersionId.ToString();
            cmdletAssemblyMvid = [LibTmux.PowerShell.ConnectTmuxControlCommand].Assembly.ManifestModule.ModuleVersionId.ToString() };
        timing = @{ moduleImportNanoseconds = ConvertTo-NanosecondCount $importWatch.ElapsedTicks;
            fixtureSetupNanoseconds = ConvertTo-NanosecondCount $fixtureWatch.ElapsedTicks;
            controlConnectNanoseconds = ConvertTo-NanosecondCount $connectWatch.ElapsedTicks;
            controlDisconnectNanoseconds = ConvertTo-NanosecondCount $disconnectWatch.ElapsedTicks;
            setupAndConnectExcludedFromIdleIntervals = $true };
        topologyIdentity = $identity;
        eventQueue = @{ configuredCapacity = 16; depthObserved = $null;
            highWaterObserved = $null; dropCountObserved = $null };
        phases = $phases.ToArray(); summary = @($summary);
        cleanup = @{ controlClientExited = $controlClientExited; controlDisconnected = $controlDisconnected;
            nativeClientCount = $nativeClientsAtEnd; borrowedSessionAlive = $borrowedSessionAlive }
    }
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
$report.cleanup.ownedFixtureRemoved = $fixture.Closed -and !(Test-Path -LiteralPath $fixture.DirectoryPath)
$report.cleanup.extractedPackageRemoved = !(Test-Path -LiteralPath $temporary)
if (!$report.cleanup.borrowedSessionAlive -or
    !(Assert-IdleControlReport -Report $report -ExpectedIdentity $identity -SamplesPerPhase $SamplesPerPhase)) {
    throw 'Idle control report failed its resource and topology checks.'
}
$parent = Split-Path $destination
if (!(Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -NoNewline
"PASS idle control resources: $SamplesPerPhase intervals per phase; report: $destination"
