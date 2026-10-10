[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $ReviewRoot,
    [string] $TmuxBinaryPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source,
    [ValidateRange(0, 20)] [int] $WarmupRounds = 3,
    [ValidateRange(1, 100)] [int] $SampleRounds = 20,
    [ValidateRange(1, 8)] [int] $MaxConcurrency = 4
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-DisplayReply($Result, [string] $Lane) {
    if ($Result -isnot [LibTmux.TmuxCommandResult] -or $Result.ExitCode -ne 0 -or
        $Result.StandardOutputLines.Count -ne 1) {
        throw "$Lane did not return one successful native output line."
    }
    [string] $Result.StandardOutputLines[0]
}

function Get-ControlReply($Lines, [string] $Lane) {
    $values = [Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) { $values.Add($line) }
    if ($values.Count -ne 1) {
        throw "$Lane did not return one native output line."
    }
    $values[0]
}

function Get-OwnedPaneState($Fixture) {
    (Invoke-OwnedTmux $Fixture -Arguments @('list-panes', '-a', '-F',
        '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}')).StdOut.TrimEnd("`r", "`n")
}

function Invoke-NativeSerial($Fixture, [object[]] $ArgumentSets) {
    $observed = for ($index = 0; $index -lt $ArgumentSets.Count; $index++) {
        $reply = (Invoke-OwnedTmux $Fixture -Arguments $ArgumentSets[$index]).StdOut.TrimEnd("`r", "`n")
        [pscustomobject]@{ index = [int] $index; reply = $reply }
    }
    [pscustomobject]@{ replies = @($observed); submissionOrder = @(0..($ArgumentSets.Count - 1));
        observedCompletionOrder = @(0..($ArgumentSets.Count - 1)) }
}

function Invoke-DirectSerial($Server, [object[]] $ArgumentSets) {
    $observed = for ($index = 0; $index -lt $ArgumentSets.Count; $index++) {
        $result = $Server | LibTmux\Invoke-TmuxCommand -Arguments $ArgumentSets[$index] -ErrorAction Stop
        [pscustomobject]@{ index = [int] $index; reply = Get-DisplayReply $result 'direct serial' }
    }
    [pscustomobject]@{ replies = @($observed); submissionOrder = @(0..($ArgumentSets.Count - 1));
        observedCompletionOrder = @(0..($ArgumentSets.Count - 1)) }
}

function Invoke-ControlSerial($Control, [object[]] $Commands) {
    $observed = for ($index = 0; $index -lt $Commands.Count; $index++) {
        $lines = @($Control | LibTmux\Invoke-TmuxControlCommand -Command $Commands[$index] -ErrorAction Stop)
        [pscustomobject]@{ index = [int] $index; reply = Get-ControlReply $lines 'control serial' }
    }
    [pscustomobject]@{ replies = @($observed); submissionOrder = @(0..($Commands.Count - 1));
        observedCompletionOrder = @(0..($Commands.Count - 1)) }
}

function Invoke-Chained($Server, [object[]] $Commands) {
    $result = $Server | LibTmux\Invoke-TmuxChain -Command $Commands -ErrorAction Stop
    if ($result -isnot [LibTmux.TmuxCommandResult] -or $result.ExitCode -ne 0 -or
        $result.StandardOutputLines.Count -ne $Commands.Count) {
        throw 'The chain did not return one successful native output line per command.'
    }
    $observed = for ($index = 0; $index -lt $Commands.Count; $index++) {
        [pscustomobject]@{ index = [int] $index; reply = [string] $result.StandardOutputLines[$index] }
    }
    [pscustomobject]@{ replies = @($observed); submissionOrder = @(0..($Commands.Count - 1));
        observedCompletionOrder = @(0..($Commands.Count - 1)) }
}

function Invoke-BoundedReplyBatch([int] $Count, [int] $Limit, [scriptblock] $Start, [scriptblock] $Read) {
    $observed = [Collections.Generic.List[object]]::new()
    $completion = [Collections.Generic.List[int]]::new()
    for ($offset = 0; $offset -lt $Count; $offset += $Limit) {
        $cancellation = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(1))
        $running = [Collections.Generic.List[object]]::new()
        try {
            for ($index = $offset; $index -lt [Math]::Min($Count, $offset + $Limit); $index++) {
                $running.Add([pscustomobject]@{ index = [int] $index;
                    task = (& $Start $index $cancellation.Token) })
            }
            while ($running.Count -gt 0) {
                $tasks = [System.Threading.Tasks.Task[]] @($running | ForEach-Object task)
                $finished = [System.Threading.Tasks.Task]::WhenAny($tasks).WaitAsync(
                    [TimeSpan]::FromSeconds(1)).GetAwaiter().GetResult()
                $matching = @($running | Where-Object { [object]::ReferenceEquals($_.task, $finished) })
                if ($matching.Count -ne 1) { throw 'Concurrent task could not be matched to its command.' }
                $item = $matching[0]
                $reply = & $Read $finished.GetAwaiter().GetResult()
                $observed.Add([pscustomobject]@{ index = [int] $item.index; reply = [string] $reply })
                $completion.Add([int] $item.index)
                $null = $running.Remove($item)
            }
        } finally {
            $cancellation.Cancel()
            $cancellation.Dispose()
        }
    }
    [pscustomobject]@{ replies = $observed.ToArray(); submissionOrder = @(0..($Count - 1));
        observedCompletionOrder = $completion.ToArray() }
}

$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) { throw 'PackageRoot must contain LibTmux.0.1.0.nupkg.' }
$binary = (Resolve-Path -LiteralPath $TmuxBinaryPath).Path
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $destination) { throw 'OutputPath already exists; choose a new report path.' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-display-dispatch-' + [Guid]::NewGuid().ToString('N'))
$fixture = $null
$control = $null
$report = $null
$null = New-Item -ItemType Directory -Path $temporary
try {
    $module = Join-Path $temporary 'LibTmux/0.1.0'
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $module)
    Import-Module "$PSScriptRoot/PackageIdentity.psm1" -Force
    $identity = Get-BenchmarkPackageIdentity -PackageRoot $PackageRoot -ModuleRoot $module -ReviewRoot $ReviewRoot
    $importWatch = [Diagnostics.Stopwatch]::StartNew()
    Import-Module (Join-Path $module 'LibTmux.psd1') -ErrorAction Stop
    $importWatch.Stop()
    Import-Module "$PSScriptRoot/DisplayDispatch.Checks.psm1" -Force
    . "$PSScriptRoot/../tests/support/OwnedTmux.ps1"

    $fixture = New-OwnedTmuxFixture -TmuxPath $binary
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $binary -ConfigurationFile '/dev/null'
    $tmuxVersion = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()
    $formats = [string[]] @(0..7 | ForEach-Object { "reply-$($_.ToString('D2'))|#{session_id}|#{window_id}|#{pane_id}" })
    $argumentSets = [Collections.Generic.List[object]]::new()
    $commands = [Collections.Generic.List[object]]::new()
    $expected = [Collections.Generic.List[string]]::new()
    foreach ($format in $formats) {
        $arguments = [string[]] @('display-message', '-p', '-t', 'fixture', $format)
        $argumentSets.Add($arguments)
        $commands.Add((LibTmux\New-TmuxCommand -Name 'display-message' -Arguments @('-p', '-t', 'fixture', $format)))
        $native = (Invoke-OwnedTmux $fixture -Arguments $arguments).StdOut.TrimEnd("`r", "`n")
        if ($native.Contains("`n") -or $native -cnotmatch '^reply-[0-7][0-9]\|\$[0-9]+\|@[0-9]+\|%[0-9]+$') {
            throw "The native reference returned an unexpected display reply: $native"
        }
        $expected.Add($native)
    }
    if (@($expected | Select-Object -Unique).Count -ne 8) { throw 'The native reference did not return eight distinct replies.' }
    $state = Get-OwnedPaneState $fixture
    $connectWatch = [Diagnostics.Stopwatch]::StartNew()
    $control = $server | LibTmux\Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
    $connectWatch.Stop()
    if (!$control.IsRunning) { throw 'The benchmark control client did not start.' }

    $lanes = @('direct-serial', 'direct-concurrent', 'control-serial', 'control-concurrent', 'chained',
        'native-serial')
    $operations = @{
        'native-serial' = { Invoke-NativeSerial $fixture $argumentSets.ToArray() }
        'direct-serial' = { Invoke-DirectSerial $server $argumentSets.ToArray() }
        'direct-concurrent' = { Invoke-BoundedReplyBatch $argumentSets.Count $MaxConcurrency {
                param($index, $token)
                $server.ExecuteCommandAsync([string[]] $argumentSets[$index], $token)
            } { param($result) Get-DisplayReply $result 'direct concurrent' } }
        'control-serial' = { Invoke-ControlSerial $control $commands.ToArray() }
        'control-concurrent' = { Invoke-BoundedReplyBatch $commands.Count $MaxConcurrency {
                param($index, $token)
                $control.SendAsync($commands[$index], $token)
            } { param($lines) Get-ControlReply $lines 'control concurrent' } }
        chained = { Invoke-Chained $server $commands.ToArray() }
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
                $before = Get-OwnedPaneState $fixture
                if ($before -cne $state) { throw "$phase/$round/$lane changed the owned topology before dispatch." }
                $watch = [Diagnostics.Stopwatch]::StartNew()
                $actual = & $operations[$lane]
                $watch.Stop()
                $after = Get-OwnedPaneState $fixture
                if ($after -cne $before) { throw "$phase/$round/$lane changed the owned topology." }
                $ordered = $lane -in @('native-serial', 'direct-serial', 'control-serial', 'chained')
                Assert-BenchmarkDisplayReplySet -Expected $expected.ToArray() -Observed $actual.replies `
                    -Lane "$phase/$round/$lane" -RequireOrder:$ordered
                $record = @{ round = $round; position = $position; lane = $lane;
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

    $disconnectWatch = [Diagnostics.Stopwatch]::StartNew()
    $control | LibTmux\Disconnect-TmuxControl -Confirm:$false -ErrorAction Stop
    $disconnectWatch.Stop()
    $controlDisconnected = !$control.IsRunning -and @($server | LibTmux\Get-TmuxClient -ErrorAction Stop).Count -eq 0
    $borrowedSessionAlive = @($server | LibTmux\Get-TmuxSession -Name 'fixture' -ErrorAction Stop).Count -eq 1 -and
        !$fixture.ServerProcess.HasExited -and (Get-OwnedPaneState $fixture) -ceq $state
    if (!$controlDisconnected -or !$borrowedSessionAlive) {
        throw 'Control cleanup changed the borrowed topology or left a client attached.'
    }

    $summary = foreach ($lane in $lanes) {
        $values = [long[]] @($samples | Where-Object lane -EQ $lane | ForEach-Object elapsedNanoseconds)
        [Array]::Sort($values)
        $middle = [int] [Math]::Floor($values.Length / 2)
        $median = if ($values.Length % 2) { $values[$middle] } else { ($values[$middle - 1] + $values[$middle]) / 2.0 }
        @{ lane = $lane; samples = $values.Length; medianMilliseconds = $median / 1000000.0;
            p95Milliseconds = $(if ($values.Length -ge 20) {
                    $values[[int] [Math]::Ceiling($values.Length * 0.95) - 1] / 1000000.0
                } else { $null }) }
    }
    $sourceCommit = (git -C (Split-Path $PSScriptRoot) rev-parse HEAD).Trim()
    $sourceDirty = @((git -C (Split-Path $PSScriptRoot) status --porcelain --untracked-files=all)).Count -gt 0
    $report = [ordered]@{
        schema = 1
        status = 'PASS'
        recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        workload = 'eight distinct display-message replies on one owned session/window/pane'
        lanes = $lanes
        operations = @(
            @{ lane = 'native-serial'; path = 'Invoke-OwnedTmux <argv>; one native tmux client process per command' }
            @{ lane = 'direct-serial'; path = 'Server | LibTmux\Invoke-TmuxCommand -Arguments <argv>; one process-backed command at a time' }
            @{ lane = 'direct-concurrent'; path = 'Server.ExecuteCommandAsync(<argv>); process-backed, bounded waves' }
            @{ lane = 'control-serial'; path = 'Control | LibTmux\Invoke-TmuxControlCommand -Command <command>; one reused client' }
            @{ lane = 'control-concurrent'; path = 'Control.SendAsync(<command>); one reused client, bounded waves' }
            @{ lane = 'chained'; path = 'Server | LibTmux\Invoke-TmuxChain -Command <eight commands>; one process-backed chain' }
        )
        argvTemplate = @('display-message', '-p', '-t', 'fixture', '<format>')
        shape = @{ sessions = 1; windows = 1; panes = 1; linkedWindows = 0 }
        parameters = @{ warmupRounds = $WarmupRounds; sampleRounds = $SampleRounds;
            maxConcurrency = $MaxConcurrency; commandsPerWorkload = 8;
            sampling = 'serial benchmark rounds, rotating lane order';
            timeoutSecondsPerConcurrentBatch = 1 }
        ordering = @{ serialAndChain = 'command order required'; concurrent = 'replies matched by submitted index';
            observedCompletionOrder = 'order reaped by Task.WhenAny; simultaneous completions may appear in submission order' }
        provenance = @{ sourceCommit = $sourceCommit; sourceDirty = $sourceDirty;
            runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();
            checksSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/DisplayDispatch.Checks.psm1" -Algorithm SHA256).Hash.ToLowerInvariant();
            packageVersion = (Get-Module LibTmux).Version.ToString();
            corePackageVersion = $identity.corePackageVersion;
            packageSha256 = $identity.packageSha256;
            coreAssemblySha256 = $identity.coreAssemblySha256;
            cmdletAssemblySha256 = $identity.cmdletAssemblySha256;
            sourceProvenance = $identity.sourceProvenance;
            reviewCoreRevision = $identity.reviewCoreRevision;
            reviewPortRevision = $identity.reviewPortRevision;
            packageIdentitySha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/PackageIdentity.psm1" -Algorithm SHA256).Hash.ToLowerInvariant();
            tmuxVersion = $tmuxVersion;
            tmuxSha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant();
            powerShellVersion = $PSVersionTable.PSVersion.ToString();
            dotnetRuntimeVersion = [Environment]::Version.ToString();
            os = [Runtime.InteropServices.RuntimeInformation]::OSDescription;
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();
            coreAssemblyMvid = [LibTmux.Server].Assembly.ManifestModule.ModuleVersionId.ToString();
            cmdletAssemblyMvid = [LibTmux.PowerShell.InvokeTmuxCommandCommand].Assembly.ManifestModule.ModuleVersionId.ToString() }
        timing = @{ moduleImportNanoseconds = [long] [Math]::Round(
                $importWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            controlConnectNanoseconds = [long] [Math]::Round(
                $connectWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            controlDisconnectNanoseconds = [long] [Math]::Round(
                $disconnectWatch.ElapsedTicks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency);
            firstCallsIncludeJit = $true; warmSamplesExcludeImportAndFixtureSetup = $true;
            controlConnectionReused = $true }
        cleanup = @{ controlDisconnected = $controlDisconnected; borrowedSessionAlive = $borrowedSessionAlive }
        formats = $formats
        expectedReplies = $expected.ToArray()
        expectedPaneState = $state
        firstCalls = $firstCalls.ToArray()
        warmups = $warmups.ToArray()
        samples = $samples.ToArray()
        summary = @($summary)
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
if (!$report.cleanup.ownedFixtureRemoved -or !$report.cleanup.extractedPackageRemoved) {
    throw 'Display dispatch cleanup did not remove the owned fixture and extracted package.'
}
$parent = Split-Path $destination
if (!(Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -NoNewline
"PASS display dispatch: $SampleRounds rounds per lane; report: $destination"
