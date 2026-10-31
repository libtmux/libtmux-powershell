param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: shows what the test sandbox hands a tmux client, and that each
# check on it can fail. The recording tmux keeps argument lists and variable names, never
# values. Run through eng/Test.ps1, which enters the sandbox this checks.
#
# The cases that need a process of their own are started together, before the checks that
# need none, and read back in order afterwards: they are independent, and their startup
# and waits would otherwise add up.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/support/Sandbox.ps1"
Assert-TestSandbox

function Assert-Canary([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw "Sandbox canary: $Message" }
}

$selectors = @('TMUX', 'TMUX_PANE', 'LIBTMUX_SOCKET', 'LIBTMUX_SOCKET_PATH', 'LIBTMUX_SOCKET_NAME')
$decoys = [ordered]@{
    TMUX = '/decoy/server,1,0'; TMUX_PANE = '%9'; LIBTMUX_SOCKET = 'decoy'
    LIBTMUX_SOCKET_PATH = '/decoy/socket'; LIBTMUX_SOCKET_NAME = 'decoy'
}
$directory = $env:TMUX_TMPDIR
$scratch = Join-Path $directory 'canary'
$null = New-Item -ItemType Directory -Path $scratch -Force
$recorder = Join-Path $PSScriptRoot 'support/RecordingTmux.sh'
$tmux = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$ownerOnly = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute
$started = [Collections.Generic.List[object]]::new()

function Read-RecordedCall([string] $Path) {
    $calls = [Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $Path)) { return }
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $kind, $value = $line.Split("`t", 2)
        switch ($kind) {
            'call' {
                $calls.Add([pscustomobject]@{ Arguments = [Collections.Generic.List[string]]::new()
                    Set = [Collections.Generic.List[string]]::new(); TmpDir = '' })
            }
            'arg' { $calls[$calls.Count - 1].Arguments.Add($value) }
            'set' { $calls[$calls.Count - 1].Set.Add($value) }
            'tmpdir' { $calls[$calls.Count - 1].TmpDir = $value }
        }
    }
    $calls.ToArray()
}

function Start-Capture([Diagnostics.ProcessStartInfo] $Start) {
    $Start.UseShellExecute = $false
    $Start.RedirectStandardOutput = $true
    $Start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($Start)
    $capture = [pscustomobject]@{ Process = $process; Output = $process.StandardOutput.ReadToEndAsync()
        Errors = $process.StandardError.ReadToEndAsync() }
    $started.Add($capture)
    $capture
}

function Wait-Capture($Capture) {
    $process = $Capture.Process
    try {
        if (-not $process.WaitForExit(30000)) { $process.Kill($true); throw 'The probe exceeded its deadline.' }
        [pscustomobject]@{ ExitCode = $process.ExitCode
            Text = $Capture.Output.GetAwaiter().GetResult() + $Capture.Errors.GetAwaiter().GetResult() }
    } finally { $process.Dispose() }
}

function Invoke-Capture([Diagnostics.ProcessStartInfo] $Start) { Wait-Capture (Start-Capture $Start) }

function ConvertFrom-ChildReport($Result) {
    $line = $Result.Text.Split("`n")[0].Trim()
    if (-not $line.StartsWith('{')) { throw "Sandbox canary: a probe process reported nothing: $($Result.Text.Trim())" }
    $line | ConvertFrom-Json
}

function Test-ProcessAlive([int] $Id) {
    try { [Diagnostics.Process]::GetProcessById($Id).Dispose(); $true } catch [ArgumentException] { $false }
}

function Wait-ProcessGone([int] $Id) {
    $wait = [Diagnostics.Stopwatch]::StartNew()
    while ((Test-ProcessAlive $Id) -and $wait.ElapsedMilliseconds -lt 3000) { Start-Sleep -Milliseconds 50 }
    -not (Test-ProcessAlive $Id)
}

function New-TmuxWrapper([string] $Name, [string] $Body) {
    $wrapper = Join-Path $scratch "wrap-$Name"
    $null = New-Item -ItemType Directory -Path $wrapper -Force
    [IO.File]::WriteAllText((Join-Path $wrapper 'tmux'), "#!/bin/sh`n$Body`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::SetUnixFileMode((Join-Path $wrapper 'tmux'), $ownerOnly)
    $wrapper
}

# What a failed check leaves behind is stopped here: the server by its path, then by its
# process if that process still has the command line of the server this case started, and
# the directory the runner kept. A runner that did its job leaves nothing to do.
function Clear-ServedSandbox([string] $Report) {
    if (-not (Test-Path -LiteralPath $Report)) { return }
    $served = @(Get-Content -LiteralPath $Report)
    if ($served.Count -ne 2) { return }
    $socket = Join-Path $served[1] 'custom.sock'
    if (Test-Path -LiteralPath $socket) { & $tmux -S $socket kill-server 2>$null }
    if (-not (Wait-ProcessGone ([int] $served[0]))) {
        $arguments = (& /bin/ps -o args= -p $served[0] 2>$null) -join ' '
        if ($arguments.Contains($socket)) { Stop-Process -Id ([int] $served[0]) -Force }
    }
    if ((Test-Path -LiteralPath $served[1]) -and (Split-Path -Leaf $served[1]) -clike 'lt-ps-*') {
        Remove-Item -LiteralPath $served[1] -Recurse -Force
    }
}

# --- Processes started now and read back below ------------------------------------------

# A recording tmux first on PATH is what a child's sandbox, runner and servers are seen by.
$bin = Join-Path $scratch 'bin'
$null = New-Item -ItemType Directory -Path $bin -Force
Copy-Item -LiteralPath $recorder -Destination (Join-Path $bin 'tmux')
[IO.File]::SetUnixFileMode((Join-Path $bin 'tmux'), $ownerOnly)

# A process that arrives dirty and without a sandbox gets one, removes it on exit and
# fails the run if tmux chose the default socket in it. One started inside a sandbox
# joins it and leaves it alone.
$childScript = Join-Path $scratch 'child.ps1'
[IO.File]::WriteAllText($childScript, @'
param(
    [Parameter(Mandatory)] [string] $Library,
    [Parameter(Mandatory)] [ValidateSet('Enter', 'Leak', 'Link')] [string] $Mode,
    [switch] $InFunction
)
$ErrorActionPreference = 'Stop'
$body = {
    $directory = Enter-TestSandbox
    if ($Mode -in @('Leak', 'Link')) { $null = New-Item -ItemType Directory -Path (Join-Path $directory 'tmux-1') }
    if ($Mode -eq 'Leak') { Set-Content -LiteralPath (Join-Path $directory 'tmux-1/default') -Value '' }
    if ($Mode -eq 'Link') {
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $directory 'tmux-1/default') -Target $env:LIBTMUX_CANARY_TARGET
    }
    $held = @('TMUX', 'TMUX_PANE', 'LIBTMUX_SOCKET', 'LIBTMUX_SOCKET_PATH', 'LIBTMUX_SOCKET_NAME') |
        Where-Object { $null -ne [Environment]::GetEnvironmentVariable($_) }
    @{ Directory = $directory; Held = @($held); Routed = $directory -ceq $env:TMUX_TMPDIR
        Mode = [int] [IO.File]::GetUnixFileMode($directory) } | ConvertTo-Json -Compress
}
# The functions loaded inside a function are gone when it returns, as they are for a script
# that another script runs; the exit hook must still find what it needs.
function Invoke-InScope { . $Library; & $body }
if ($InFunction) { Invoke-InScope } else { . $Library; & $body }
'@, [Text.UTF8Encoding]::new($false))
$linkTarget = Join-Path $scratch 'link-target'
Set-Content -LiteralPath $linkTarget -Value ''
function Start-SandboxChild([string] $Mode, [string] $Record, [switch] $Join, [switch] $InFunction,
    [string] $Sandbox, [string] $TemporaryDirectory) {
    $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
    foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $childScript, '-Library',
        (Join-Path $PSScriptRoot 'support/Sandbox.ps1'), '-Mode', $Mode)) { $start.ArgumentList.Add($argument) }
    if ($InFunction) { $start.ArgumentList.Add('-InFunction') }
    $start.Environment['PATH'] = $bin
    $start.Environment['LIBTMUX_TEST_RECORD'] = $Record
    $start.Environment['LIBTMUX_CANARY_TARGET'] = $linkTarget
    if ($TemporaryDirectory) { $start.Environment['TMPDIR'] = $TemporaryDirectory }
    if ($Sandbox) {
        $start.Environment['TMUX_TMPDIR'] = $Sandbox
        $start.Environment['LIBTMUX_TEST_SANDBOX'] = $Sandbox
    } elseif (-not $Join) {
        foreach ($name in @('TMUX_TMPDIR', 'LIBTMUX_TEST_SANDBOX', 'LIBTMUX_TEST_SANDBOX_OWNER')) {
            $null = $start.Environment.Remove($name)
        }
        foreach ($name in $decoys.Keys) { $start.Environment[$name] = $decoys[$name] }
    }
    Start-Capture $start
}

# The runner is what fails a run on a leak when its children only joined the sandbox, so
# a copy of eng/Test.ps1 runs a stub in place of tests/Fixture.Tests.ps1. The stub refuses
# to go on in a process that is not sandboxed. One copy picks up selectors after it
# enters, which only the runner's own clearing of each child's environment can catch.
$runnerText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../eng/Test.ps1'))
$entry = '$sandbox = Enter-TestSandbox'
Assert-Canary ($runnerText.Contains($entry)) 'eng/Test.ps1 no longer enters the sandbox where this check expects it.'
$lateText = $runnerText.Replace($entry, $entry + "`n" +
    "foreach (`$name in @('TMUX', 'TMUX_PANE', 'LIBTMUX_SOCKET', 'LIBTMUX_SOCKET_PATH', 'LIBTMUX_SOCKET_NAME')) {`n" +
    "    [Environment]::SetEnvironmentVariable(`$name, 'decoy')`n}")
$stub = @'
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/support/Sandbox.ps1"
Assert-TestSandbox
$custom = Join-Path $env:TMUX_TMPDIR 'custom.sock'
switch ($env:LIBTMUX_CANARY_PLANT) {
    'default' {
        $null = New-Item -ItemType Directory -Path (Join-Path $env:TMUX_TMPDIR 'tmux-1')
        Set-Content -LiteralPath (Join-Path $env:TMUX_TMPDIR 'tmux-1/default') -Value ''
    }
    'server' {
        & $env:LIBTMUX_CANARY_TMUX -S $custom -f /dev/null new-session -d 'exec /bin/sleep 120'
        if ($LASTEXITCODE) { throw 'The stub could not start its server.' }
        $serverPid = & $env:LIBTMUX_CANARY_TMUX -S $custom display-message -p '#{pid}'
        Set-Content -LiteralPath $env:LIBTMUX_CANARY_REPORT -Value $serverPid, $env:TMUX_TMPDIR
    }
    'stale' {
        $null = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::Unix, [Net.Sockets.SocketType]::Stream,
            [Net.Sockets.ProtocolType]::Unspecified).Bind([Net.Sockets.UnixDomainSocketEndPoint]::new($custom))
    }
}
'@
function Start-StandInRunner([string] $Name, [string] $Record, [string] $Plant, [string] $Bin = $bin,
    [string] $Report, [string] $Text = $runnerText) {
    $root = Join-Path $scratch "runner-$Name"
    $null = New-Item -ItemType Directory -Path (Join-Path $root 'eng'), (Join-Path $root 'tests/support') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'support/Sandbox.ps1') -Destination (Join-Path $root 'tests/support/Sandbox.ps1')
    [IO.File]::WriteAllText((Join-Path $root 'eng/Test.ps1'), $Text)
    [IO.File]::WriteAllText((Join-Path $root 'tests/Fixture.Tests.ps1'), $stub, [Text.UTF8Encoding]::new($false))
    $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
    foreach ($argument in @('-NoLogo', '-NoProfile', '-File', (Join-Path $root 'eng/Test.ps1'), '-Suite', 'Fixture')) {
        $start.ArgumentList.Add($argument)
    }
    foreach ($name in @('TMUX_TMPDIR', 'LIBTMUX_TEST_SANDBOX', 'LIBTMUX_TEST_SANDBOX_OWNER')) {
        $null = $start.Environment.Remove($name)
    }
    foreach ($name in $decoys.Keys) { $start.Environment[$name] = $decoys[$name] }
    $start.Environment['PATH'] = $Bin
    $start.Environment['LIBTMUX_TEST_RECORD'] = $Record
    $start.Environment['LIBTMUX_CANARY_TMUX'] = $tmux
    $start.Environment['LIBTMUX_CANARY_REPORT'] = $Report
    if ($Plant) { $start.Environment['LIBTMUX_CANARY_PLANT'] = $Plant }
    $capture = Start-Capture $start
    $capture | Add-Member -NotePropertyName Root -NotePropertyValue $root
    $capture
}

# A test can start a server on a socket of its own inside the sandbox. The runner stops it
# by that path and checks the stop, which can take a moment; it fails the run although the
# tests passed; and it keeps the directory when a server will not stop. A stale socket file
# is none of that. The wrappers stand in for the tmux on PATH: one lets kill-server through
# a moment late, one drops it.
$binSlow = New-TmuxWrapper 'slow' @'
for argument in "$@"; do
    if [ "$argument" = kill-server ]; then
        ( /bin/sleep 0.5; "$LIBTMUX_CANARY_TMUX" "$@" ) >/dev/null 2>&1 &
        exit 0
    fi
done
exec "$LIBTMUX_CANARY_TMUX" "$@"
'@
$binDrop = New-TmuxWrapper 'drop' @'
for argument in "$@"; do [ "$argument" = kill-server ] && exit 0; done
exec "$LIBTMUX_CANARY_TMUX" "$@"
'@
$reportSlow = Join-Path $scratch 'slow.report'
$reportDrop = Join-Path $scratch 'drop.report'

# A directory others can enter, to be refused as a sandbox to join; and a parent with the
# setgid bit as TMPDIR, whose children inherit that bit. TMPDIR has to be short enough for
# a socket path, which a directory under the sandbox is not.
$loose = Join-Path (Split-Path $directory) ('lt-ps-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$setgidParent = Join-Path '/tmp' ('lt-sg-' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
$staleTree = Join-Path $scratch 'sockets'
$null = New-Item -ItemType Directory -Path $loose, $setgidParent, (Join-Path $staleTree 'deep/er'), `
    (Join-Path $staleTree 'outside'), (Join-Path $staleTree 'viewed') -Force
[IO.File]::SetUnixFileMode($loose, [IO.UnixFileMode] 511)
[IO.File]::SetUnixFileMode($setgidParent, [IO.UnixFileMode] 1472)

try {
    $runs = @{}
    $runs.Enter = Start-SandboxChild 'Enter' (Join-Path $scratch 'enter.record')
    $runs.Leak = Start-SandboxChild 'Leak' (Join-Path $scratch 'leak.record')
    $runs.Join = Start-SandboxChild 'Enter' (Join-Path $scratch 'join.record') -Join
    $runs.Loose = Start-SandboxChild 'Enter' (Join-Path $scratch 'loose.record') -Sandbox $loose
    $runs.Setgid = Start-SandboxChild 'Enter' (Join-Path $scratch 'setgid.record') -TemporaryDirectory $setgidParent
    $runs.ScopedLeak = Start-SandboxChild 'Leak' (Join-Path $scratch 'scoped.record') -InFunction
    $runs.Link = Start-SandboxChild 'Link' (Join-Path $scratch 'linked.record')
    $runs.Entered = Start-StandInRunner 'entered' (Join-Path $scratch 'entered.record') -Plant 'stale'
    $runs.Late = Start-StandInRunner 'late' (Join-Path $scratch 'late.record') -Text $lateText
    $runs.Default = Start-StandInRunner 'default' (Join-Path $scratch 'runner.record') -Plant 'default'
    $runs.Slow = Start-StandInRunner 'slow' (Join-Path $scratch 'slow.record') -Plant 'server' -Bin $binSlow -Report $reportSlow
    $runs.Drop = Start-StandInRunner 'drop' (Join-Path $scratch 'drop.record') -Plant 'server' -Bin $binDrop -Report $reportDrop
    # A socket file that nothing listens on is what a server leaves when it is killed
    # outright: the file stays when the process that bound it exits without closing it.
    $staleStart = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
    foreach ($argument in @('-NoLogo', '-NoProfile', '-Command', '$null = [Net.Sockets.Socket]::new(' +
        '[Net.Sockets.AddressFamily]::Unix, [Net.Sockets.SocketType]::Stream, [Net.Sockets.ProtocolType]::Unspecified).Bind(' +
        '[Net.Sockets.UnixDomainSocketEndPoint]::new($env:LIBTMUX_CANARY_STALE))')) { $staleStart.ArgumentList.Add($argument) }
    $staleStart.Environment['LIBTMUX_CANARY_STALE'] = Join-Path $staleTree 'deep/stale.sock'
    $runs.Stale = Start-Capture $staleStart

    # --- Checks that need no process of their own ---------------------------------------

    # The findings function reports every route to a server outside the sandbox, by name.
    $dirty = @{ TMUX_PANE = '%9'; TMUX = '/decoy/server,1,0'; LIBTMUX_SOCKET = 'decoy'
        LIBTMUX_SOCKET_PATH = '/decoy/socket'; LIBTMUX_SOCKET_NAME = 'decoy' }
    $findings = @(Get-TestSandboxViolation $dirty)
    Assert-Canary (($findings -join '|') -ceq ('LIBTMUX_SOCKET is set|LIBTMUX_SOCKET_NAME is set|' +
        'LIBTMUX_SOCKET_PATH is set|TMUX is set|TMUX_PANE is set|TMUX_TMPDIR is unset')) 'a dirty environment was not reported by name.'
    Assert-Canary (-not ($findings -join '|').Contains('decoy')) 'a finding printed a value.'
    $known = [Environment]::GetEnvironmentVariables()
    foreach ($name in @('LIBTMUX_TMUX', 'LIBTMUX_CONTROL_TRANSPORT', 'LIBTMUX_REQUIRE_REJECTED', 'LIBTMUX_TEST_RECORD')) {
        $known[$name] = 'x'
    }
    Assert-Canary (@(Get-TestSandboxViolation $known).Count -eq 0) 'a variable that selects no server was reported.'
    foreach ($case in @(
        @{ Directory = 'relative/dir'; Expected = 'TMUX_TMPDIR is not an absolute path' }
        @{ Directory = '/' + ('x' * 40); Expected = 'TMUX_TMPDIR is longer than 40 bytes' }
        @{ Directory = $directory; Marker = $null; Expected = 'TMUX_TMPDIR is not the sandbox directory of this run' }
        @{ Directory = '/tmp/lt-ps-missing'; Marker = '/tmp/lt-ps-missing'; Expected = 'the sandbox directory is missing' })) {
        $variables = @{ TMUX_TMPDIR = $case.Directory }
        if ($case.ContainsKey('Marker') -and $case.Marker) { $variables['LIBTMUX_TEST_SANDBOX'] = $case.Marker }
        Assert-Canary ((@(Get-TestSandboxViolation $variables) -join '|') -ceq $case.Expected) "TMUX_TMPDIR was not refused: $($case.Expected)"
    }

    # A process that was never sandboxed is refused by name. This one is, so a selector is
    # set for the length of the call and put back.
    [Environment]::SetEnvironmentVariable('TMUX', $decoys.TMUX)
    try {
        $refusal = try { Assert-TestSandbox; '' } catch { $_.Exception.Message }
    } finally {
        [Environment]::SetEnvironmentVariable('TMUX', $null)
    }
    Assert-Canary ($refusal.Contains('TMUX is set') -and -not $refusal.Contains('decoy')) 'a dirty process was not refused by name.'

    # The sandbox directory is the user's own and owner-only, and the check can tell when
    # one is not: a directory others can enter, one another user owns, a link, or nothing.
    # The setgid bit alone is no reason to refuse, and group or other bits still are.
    Assert-Canary (([int] [IO.File]::GetUnixFileMode($directory) -band 511) -eq 448) 'the sandbox directory is not owner-only.'
    $access = Join-Path $scratch 'access'
    $private = Join-Path $access 'private'
    $open = Join-Path $access 'open'
    $setgid = Join-Path $access 'setgid'
    $null = New-Item -ItemType Directory -Path $private, $open, $setgid -Force
    [IO.File]::SetUnixFileMode($private, $ownerOnly)
    [IO.File]::SetUnixFileMode($open, [IO.UnixFileMode] 511)
    [IO.File]::SetUnixFileMode($setgid, [IO.UnixFileMode] 1472)
    $null = New-Item -ItemType SymbolicLink -Path (Join-Path $access 'link') -Target $private
    Assert-Canary (-not (Get-TestSandboxAccessProblem $private)) 'an owner-only directory of the current user was refused.'
    Assert-Canary (([int] [IO.File]::GetUnixFileMode($setgid) -band 1024) -ne 0) 'the setgid directory has no setgid bit, so the check proves nothing.'
    Assert-Canary (-not (Get-TestSandboxAccessProblem $setgid)) 'an owner-only directory with the setgid bit was refused.'
    foreach ($case in @(
        @{ Path = $open; Expected = 'the sandbox directory is not owner-only' }
        @{ Path = (Join-Path $access 'link'); Expected = 'the sandbox directory is not a plain directory' }
        @{ Path = (Join-Path $access 'missing'); Expected = 'the sandbox directory is not a plain directory' })) {
        Assert-Canary ((Get-TestSandboxAccessProblem $case.Path) -ceq $case.Expected) "a directory was not refused: $($case.Expected)."
    }
    foreach ($mode in @(488, 449, 1528)) {
        $group = Join-Path $access "mode-$mode"
        $null = New-Item -ItemType Directory -Path $group -Force
        [IO.File]::SetUnixFileMode($group, [IO.UnixFileMode] $mode)
        Assert-Canary ((Get-TestSandboxAccessProblem $group) -ceq 'the sandbox directory is not owner-only') `
            'a directory with a group or other permission bit was not refused.'
    }
    Assert-Canary ((Get-TestSandboxAccessProblem $private -User 'not-the-owner') -ceq 'the sandbox directory is not owned by the current user') `
        'a directory of another user was not refused.'

    # A start info loses the selectors and keeps what is not one.
    $start = [Diagnostics.ProcessStartInfo]::new('/bin/sh')
    foreach ($name in $decoys.Keys) { $start.Environment[$name] = $decoys[$name] }
    $start.Environment['LIBTMUX_CONTROL_TRANSPORT'] = '0'
    Clear-TestSandboxSelector $start
    Assert-Canary (@($selectors | Where-Object { $start.Environment.ContainsKey($_) }).Count -eq 0) 'a selector survived Clear-TestSandboxSelector.'
    Assert-Canary ($start.Environment['LIBTMUX_CONTROL_TRANSPORT'] -ceq '0' -and $start.Environment['TMUX_TMPDIR'] -ceq $directory) `
        'Clear-TestSandboxSelector removed a variable that selects no server.'

    # The leak check sees the default socket and nothing else.
    $leakRoot = Join-Path $scratch 'leaks'
    $null = New-Item -ItemType Directory -Path (Join-Path $leakRoot 'empty'), (Join-Path $leakRoot 'named/tmux-1'), (Join-Path $leakRoot 'bare/tmux-1') -Force
    Set-Content -LiteralPath (Join-Path $leakRoot 'named/tmux-1/libtmux-named') -Value ''
    Set-Content -LiteralPath (Join-Path $leakRoot 'bare/tmux-1/default') -Value ''
    Assert-Canary (@(Get-TestSandboxLeak (Join-Path $leakRoot 'empty')).Count -eq 0 -and
        @(Get-TestSandboxLeak (Join-Path $leakRoot 'named')).Count -eq 0) 'the leak check reported a socket that tmux was given a name for.'
    Assert-Canary ((@(Get-TestSandboxLeak (Join-Path $leakRoot 'bare')) -join '|') -ceq 'tmux-1/default') 'the leak check missed a default socket.'
    $null = New-Item -ItemType Directory -Path (Join-Path $leakRoot 'dangling/tmux-1'), (Join-Path $leakRoot 'parent') -Force
    $null = New-Item -ItemType SymbolicLink -Path (Join-Path $leakRoot 'dangling/tmux-1/default') -Target (Join-Path $leakRoot 'not-there')
    $null = New-Item -ItemType SymbolicLink -Path (Join-Path $leakRoot 'parent/tmux-2') -Target $private
    Assert-Canary ((@(Get-TestSandboxLeak (Join-Path $leakRoot 'dangling')) -join '|') -ceq 'tmux-1/default') `
        'the leak check missed a default socket that is a link to nothing.'
    Assert-Canary ((@(Get-TestSandboxLeak (Join-Path $leakRoot 'parent')) -join '|') -ceq 'tmux-2') `
        'the leak check missed a tmux-<uid> directory that is a link.'

    # The recording tmux sees a leak, and a start info cleared of selectors hands it none.
    $record = Join-Path $scratch 'decoy.record'
    $start = [Diagnostics.ProcessStartInfo]::new($recorder)
    $start.Environment['LIBTMUX_TEST_RECORD'] = $record
    foreach ($name in $decoys.Keys) { $start.Environment[$name] = $decoys[$name] }
    $null = Invoke-Capture $start
    $calls = @(Read-RecordedCall $record)
    Assert-Canary ($calls.Count -eq 1 -and (($calls[0].Set | Sort-Object) -join ',') -ceq (($selectors | Sort-Object) -join ',')) `
        'the recording tmux did not see the decoys it was handed.'
    $record = Join-Path $scratch 'cleared.record'
    $start = [Diagnostics.ProcessStartInfo]::new($recorder)
    $start.Environment['LIBTMUX_TEST_RECORD'] = $record
    foreach ($name in $decoys.Keys) { $start.Environment[$name] = $decoys[$name] }
    Clear-TestSandboxSelector $start
    $null = Invoke-Capture $start
    $calls = @(Read-RecordedCall $record)
    Assert-Canary ($calls.Count -eq 1 -and $calls[0].Set.Count -eq 0 -and $calls[0].TmpDir -ceq 'sandbox') `
        'a cleared start info was handed a selector or a TMUX_TMPDIR outside the sandbox.'

    # A bare handle reaches tmux through the sandbox only. Whether it passes -L, -S or
    # nothing depends on the pinned core, so the check allows any route that stays inside.
    $record = Join-Path $scratch 'library.record'
    Import-Module (Join-Path (Resolve-Path -LiteralPath $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1')
    $env:LIBTMUX_CONTROL_TRANSPORT = '0'
    $env:LIBTMUX_TEST_RECORD = $record
    try {
        $server = LibTmux\New-TmuxServer -TmuxBinaryPath $recorder
        try { $null = $server | LibTmux\Get-TmuxSession -ErrorAction Stop } catch { $null = $_ }
    } finally {
        $env:LIBTMUX_CONTROL_TRANSPORT = $null
        $env:LIBTMUX_TEST_RECORD = $null
    }
    $calls = @(Read-RecordedCall $record)
    Assert-Canary ($calls.Count -gt 0) 'the library never ran the recording tmux.'
    # A core that derives -S from LIBTMUX_SOCKET_PATH would put that value in the argument
    # list, so a failure names the flags a call passed and never their arguments.
    foreach ($call in $calls) {
        $flags = @('-S', '-L') | Where-Object { $call.Arguments.Contains($_) }
        $passed = if ($flags) { " (it passed $($flags -join ' and '))" } else { '' }
        Assert-Canary ($call.Set.Count -eq 0) "a library call was handed $($call.Set -join ', ')$passed."
        Assert-Canary ($call.TmpDir -ceq 'sandbox') "a library call ran with a TMUX_TMPDIR outside the sandbox$passed."
        $route = [array]::IndexOf($call.Arguments.ToArray(), '-S')
        Assert-Canary ($route -lt 0 -or $call.Arguments[$route + 1].StartsWith("$directory/", [StringComparison]::Ordinal)) `
            "a library call addressed a socket outside the sandbox$passed."
    }

    # A client that names no socket looks only in the sandbox, and moving TMUX_TMPDIR moves it.
    function Invoke-BareClient([string] $Directory) {
        $start = [Diagnostics.ProcessStartInfo]::new($tmux)
        Clear-TestSandboxSelector $start
        $start.Environment['TMUX_TMPDIR'] = $Directory
        foreach ($argument in @('-N', '-f', '/dev/null', 'list-sessions')) { $start.ArgumentList.Add($argument) }
        Invoke-Capture $start
    }
    $own = Invoke-BareClient $directory
    $default = [regex]::Match($own.Text, [regex]::Escape("$directory/tmux-") + '(?<uid>[0-9]+)/default')
    Assert-Canary ($own.ExitCode -ne 0 -and $default.Success) `
        'a client that names no socket did not look for the default socket in the sandbox.'
    $uid = $default.Groups['uid'].Value
    $moved = Join-Path $scratch 'elsewhere'
    $null = New-Item -ItemType Directory -Path $moved -Force
    $elsewhere = Invoke-BareClient $moved
    Assert-Canary ($elsewhere.Text.Contains("$moved/tmux-$uid/default") -and
        -not $elsewhere.Text.Contains("$directory/tmux-$uid/default")) 'the client check cannot tell one TMUX_TMPDIR from another.'

    # --- Read back what was started -----------------------------------------------------

    $results = @{}
    foreach ($name in $runs.Keys) { $results[$name] = Wait-Capture $runs[$name] }

    $entered = $results.Enter
    $report = ConvertFrom-ChildReport $entered
    Assert-Canary ($entered.ExitCode -eq 0 -and $report.Held.Count -eq 0 -and $report.Routed -and
        $report.Directory -cne $directory) 'a dirty process did not enter a sandbox of its own.'
    Assert-Canary (([int] $report.Mode -band 511) -eq 448) 'a dirty process entered a sandbox that is not owner-only.'
    Assert-Canary (-not (Test-Path -LiteralPath $report.Directory)) 'a process left its sandbox directory behind.'
    Assert-Canary (-not $entered.Text.Contains('decoy')) 'the sandbox printed a value.'

    $leaked = $results.Leak
    $report = ConvertFrom-ChildReport $leaked
    Assert-Canary ($leaked.ExitCode -ne 0 -and $leaked.Text.Contains('tmux-1/default') -and
        $leaked.Text.Contains('left a default socket or a server')) 'a default socket in the sandbox did not fail the run.'
    Assert-Canary (-not (Test-Path -LiteralPath $report.Directory)) 'a failed run left its sandbox directory behind.'
    $calls = @(Read-RecordedCall (Join-Path $scratch 'leak.record'))
    Assert-Canary ($calls.Count -eq 1 -and
        ($calls[0].Arguments -join ' ') -ceq "-S $($report.Directory)/tmux-1/default kill-server") `
        'the run did not stop the server on the default socket by its path.'

    $joined = $results.Join
    $report = ConvertFrom-ChildReport $joined
    Assert-Canary ($joined.ExitCode -eq 0 -and $report.Directory -ceq $directory -and
        (Test-Path -LiteralPath $scratch)) 'a process inside a sandbox did not join it.'

    # A process that would join a directory others can enter is refused, and the directory is
    # left as it was.
    $declined = $results.Loose
    Assert-Canary ($declined.ExitCode -ne 0 -and $declined.Text.Contains('owner-only')) `
        'a process joined a sandbox directory that others can enter.'
    Assert-Canary ([IO.File]::GetUnixFileMode($loose) -eq [IO.UnixFileMode] 511) 'a refused join changed the directory.'

    # Under a TMPDIR with the setgid bit the new directory has it too, and is still owner-only.
    $inherited = $results.Setgid
    $report = ConvertFrom-ChildReport $inherited
    Assert-Canary ($inherited.ExitCode -eq 0 -and $report.Directory.StartsWith("$setgidParent/", [StringComparison]::Ordinal)) `
        'a process refused, or left, a TMPDIR with the setgid bit.'
    Assert-Canary (([int] $report.Mode -band 1024) -ne 0 -or -not $IsLinux) `
        'the new directory did not inherit the setgid bit, so the check proves nothing.'

    # The exit hook cleans up after a script that entered inside a function, which leaves
    # nothing behind to call by name.
    $scopedLeak = $results.ScopedLeak
    $report = ConvertFrom-ChildReport $scopedLeak
    Assert-Canary ($scopedLeak.ExitCode -ne 0 -and $scopedLeak.Text.Contains('tmux-1/default') -and
        -not $scopedLeak.Text.Contains('could not clean')) 'a default socket in a sandbox entered inside a function did not fail the run.'
    Assert-Canary (-not (Test-Path -LiteralPath $report.Directory)) 'a failed run entered inside a function left its sandbox directory behind.'
    $calls = @(Read-RecordedCall (Join-Path $scratch 'scoped.record'))
    Assert-Canary ($calls.Count -eq 1 -and
        ($calls[0].Arguments -join ' ') -ceq "-S $($report.Directory)/tmux-1/default kill-server") `
        'a run entered inside a function did not stop the server on the default socket by its path.'

    # A default socket that is a link is reported, never followed: no kill goes through it
    # and its target is left alone.
    $linked = $results.Link
    $report = ConvertFrom-ChildReport $linked
    Assert-Canary ($linked.ExitCode -ne 0 -and $linked.Text.Contains('tmux-1/default')) 'a default socket that is a link did not fail the run.'
    Assert-Canary (@(Read-RecordedCall (Join-Path $scratch 'linked.record')).Count -eq 0) 'the run stopped a server through a link.'
    Assert-Canary ((Test-Path -LiteralPath $linkTarget) -and -not (Test-Path -LiteralPath $report.Directory)) `
        'the run followed a link out of its sandbox, or left the sandbox directory behind.'

    # A server that answers on any socket in the tree is a leak, and the scan goes as deep as
    # the tree does. A socket that nothing answers on is not, and a link is never followed to
    # one.
    $null = New-Item -ItemType SymbolicLink -Path (Join-Path $staleTree 'viewed/out') -Target (Join-Path $staleTree 'outside')
    Assert-Canary (Test-Path -LiteralPath (Join-Path $staleTree 'deep/stale.sock')) 'the stale socket was not left behind, so the check proves nothing.'
    $listeners = foreach ($path in @('deep/er/custom.sock', 'outside/beyond.sock')) {
        $listener = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::Unix, [Net.Sockets.SocketType]::Stream,
            [Net.Sockets.ProtocolType]::Unspecified)
        $listener.Bind([Net.Sockets.UnixDomainSocketEndPoint]::new((Join-Path $staleTree $path)))
        $listener.Listen(5)
        $listener
    }
    try {
        Assert-Canary (((@(Get-TestSandboxLeak $staleTree) | Sort-Object) -join '|') -ceq 'deep/er/custom.sock|outside/beyond.sock') `
            'the scan did not report exactly the sockets with a server on them.'
        Assert-Canary (@(Get-TestSandboxLeak (Join-Path $staleTree 'viewed')).Count -eq 0) 'the scan followed a link to a socket outside its tree.'
    } finally {
        foreach ($listener in $listeners) { $listener.Dispose() }
    }
    Assert-Canary (@(Get-TestSandboxLeak $staleTree).Count -eq 0) 'the scan reported a socket after its server was gone.'

    # The runner. A socket that nothing answers on does not fail it, and it hands its child a
    # sandbox, even when the process picks up selectors after it enters.
    $stale = $results.Entered
    Assert-Canary ($stale.ExitCode -eq 0) "the runner did not hand its child a sandbox, or failed a socket that nothing answers on: $($stale.Text.Trim())"
    $late = $results.Late
    Assert-Canary ($late.ExitCode -eq 0) "the runner handed its child a selector it picked up after entering: $($late.Text.Trim())"

    $leaked = $results.Default
    Assert-Canary ($leaked.ExitCode -ne 0 -and $leaked.Text.Contains('tmux-1/default')) `
        'a default socket in a sandbox its children only joined did not fail the run.'
    Assert-Canary ((Get-Content -LiteralPath (Join-Path $runs.Default.Root 'build/test-Fixture.json') -Raw | ConvertFrom-Json).status -ceq 'FAIL') `
        'the runner recorded a pass for a run with a default socket in its sandbox.'
    $calls = @(Read-RecordedCall (Join-Path $scratch 'runner.record'))
    $stopped = if ($calls.Count -eq 1) { $calls[0].Arguments.ToArray() } else { @() }
    Assert-Canary ($stopped.Count -eq 3 -and $stopped[0] -ceq '-S' -and $stopped[2] -ceq 'kill-server' -and
        $stopped[1] -cmatch '/lt-ps-[0-9a-f]{8}/tmux-1/default$') 'the runner did not stop the server on the default socket by its path.'
    Assert-Canary (-not (Test-Path -LiteralPath (Split-Path (Split-Path $stopped[1])))) 'the runner left its sandbox directory behind.'

    $slow = $results.Slow
    $served = @(Get-Content -LiteralPath $reportSlow)
    Assert-Canary ($slow.ExitCode -ne 0 -and $slow.Text.Contains('custom.sock')) `
        'a server on a socket of its own in the sandbox did not fail the run.'
    Assert-Canary (Wait-ProcessGone ([int] $served[0])) 'the runner left a server running on a socket of its own.'
    Assert-Canary (-not (Test-Path -LiteralPath $served[1])) 'the runner left its sandbox directory behind after stopping its server.'

    $drop = $results.Drop
    $served = @(Get-Content -LiteralPath $reportDrop)
    Assert-Canary ($drop.ExitCode -ne 0 -and $drop.Text.Contains('kept') -and $drop.Text.Contains('custom.sock')) `
        'a server that would not stop did not fail the run with its directory kept.'
    Assert-Canary ([regex]::Matches($drop.Text, 'kept').Count -eq 1) 'the runner tried to stop a server it could not stop twice.'
    Assert-Canary ((Test-Path -LiteralPath $served[1]) -and (Test-ProcessAlive ([int] $served[0]))) `
        'the runner removed a sandbox directory while a server still answered in it.'
    Assert-Canary ((Get-Content -LiteralPath (Join-Path $runs.Drop.Root 'build/test-Fixture.json') -Raw | ConvertFrom-Json).status -ceq 'FAIL') `
        'the runner recorded a pass for a run that left a server running.'
} finally {
    # A run that stops early leaves the others going. They are short, and a runner killed
    # part way through would leave its server with no report to find it by, so each is given
    # time to finish on its own.
    foreach ($capture in $started) {
        try {
            if (-not $capture.Process.WaitForExit(20000)) { $capture.Process.Kill($true) }
        } catch { $null = $_ }
    }
    Clear-ServedSandbox $reportSlow
    Clear-ServedSandbox $reportDrop
    foreach ($leftover in @($loose, $setgidParent)) {
        if (Test-Path -LiteralPath $leftover) { Remove-Item -LiteralPath $leftover -Recurse -Force }
    }
}

'PASS sandbox canary: environment, directory access, recorded calls, default socket, servers, runner, exit cleanup'
