# A tmux command that names no socket goes to the server an inherited TMUX names,
# and otherwise to the default socket under TMUX_TMPDIR. Enter-TestSandbox removes
# what selects a server, gives the process a TMUX_TMPDIR of its own, and refuses to
# go on if either did not hold. A process started by one that has entered joins its
# sandbox, which must be a plain directory of the same user and owner-only. Findings
# name variables and never their values: a TMUX value names a server.

function Test-TestSandboxSelector([string] $Name) {
    $Name -ceq 'TMUX' -or $Name -ceq 'TMUX_PANE' -or $Name.StartsWith('LIBTMUX_SOCKET', [StringComparison]::Ordinal)
}

# What makes TMUX_TMPDIR something other than the sandbox directory of this run. The
# directory leaves room for /tmux-<uid>/<name> inside the 104 bytes a unix socket
# address holds on macOS.
function Get-TestSandboxRouteProblem {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)] [Collections.IDictionary] $Variables)

    $directory = [string] $Variables['TMUX_TMPDIR']
    if (-not $directory) { 'TMUX_TMPDIR is unset' }
    elseif (-not $directory.StartsWith('/', [StringComparison]::Ordinal)) { 'TMUX_TMPDIR is not an absolute path' }
    elseif ([Text.Encoding]::UTF8.GetByteCount($directory) -gt 40) { 'TMUX_TMPDIR is longer than 40 bytes' }
    elseif ([string] $Variables['LIBTMUX_TEST_SANDBOX'] -cne $directory -or
        -not [IO.Path]::GetFileName($directory).StartsWith('lt-ps-', [StringComparison]::Ordinal)) {
        'TMUX_TMPDIR is not the sandbox directory of this run'
    } elseif (-not [IO.Directory]::Exists($directory)) { 'the sandbox directory is missing' }
}

# A directory that another user owns, that others can enter, or that is a link could
# put a socket where this run does not look.
function Get-TestSandboxAccessProblem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $Directory,
        [string] $User = [Environment]::UserName
    )

    $item = Get-Item -LiteralPath $Directory -Force -ErrorAction Ignore
    if (-not $item -or $item.LinkType -or -not $item.PSIsContainer) { 'the sandbox directory is not a plain directory' }
    elseif ($item.User -cne $User) { 'the sandbox directory is not owned by the current user' }
    # Only the permission bits count: a parent with the setgid bit gives a new directory
    # that bit too, and it opens nothing to anyone else. 448 is 0700.
    elseif (([int] $item.UnixFileMode -band 511) -ne 448) { 'the sandbox directory is not owner-only' }
}

# One line for each variable or property of TMUX_TMPDIR that could send tmux outside
# the sandbox.
function Get-TestSandboxViolation {
    [CmdletBinding()]
    param([Collections.IDictionary] $Variables = [Environment]::GetEnvironmentVariables())

    $names = [string[]] @($Variables.Keys)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    foreach ($name in $names) {
        if ((Test-TestSandboxSelector $name) -and $null -ne $Variables[$name]) { "$name is set" }
    }
    $route = Get-TestSandboxRouteProblem $Variables
    if ($route) { $route } else { Get-TestSandboxAccessProblem ([string] $Variables['TMUX_TMPDIR']) }
}

function Assert-TestSandbox {
    [CmdletBinding()]
    param()

    $found = @(Get-TestSandboxViolation)
    if ($found.Count) {
        throw "This test process could reach a tmux server it does not own: $($found -join '; '). " +
            'Run it through eng/Test.ps1 or call Enter-TestSandbox first.'
    }
}

# Takes the selectors out of one child's environment, for a launch that must not
# depend on its parent having entered the sandbox.
function Clear-TestSandboxSelector {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)] [Diagnostics.ProcessStartInfo] $StartInfo)

    foreach ($name in @($StartInfo.Environment.Keys)) {
        if (Test-TestSandboxSelector $name) { $null = $StartInfo.Environment.Remove($name) }
    }
}

# Whether anything accepts a connection on a socket path. A server too busy to accept
# still holds the socket, so a connect that does not finish, or that would block because
# its queue is full, counts as answering. Only a refusal, a missing socket or a path that
# is no socket says that nothing does.
function Test-TestSandboxServer {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)] [string] $Path)

    $socket = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::Unix, [Net.Sockets.SocketType]::Stream,
        [Net.Sockets.ProtocolType]::Unspecified)
    try {
        $connect = [Net.Sockets.SocketTaskExtensions]::ConnectAsync($socket, [Net.Sockets.UnixDomainSocketEndPoint]::new($Path))
        $null = $connect.Wait(1000)
        $true
    } catch {
        $failure = $_.Exception
        while ($failure.InnerException) { $failure = $failure.InnerException }
        $failure -is [Net.Sockets.SocketException] -and
            $failure.SocketErrorCode -notin @('ConnectionRefused', 'AddressNotAvailable', 'NotSocket')
    } finally { $socket.Dispose() }
}

# What a run leaves in the sandbox that it must not: anything at tmux-<uid>/default,
# where a command that named no socket went, and a server that still answers on any
# socket in the tree, such as a -S path a test chose inside it. Every test here
# addresses its server with -S or a name of its own and stops it. A link is reported
# where tmux would follow it out of the sandbox, and is never followed here.
function Get-TestSandboxLeak {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)] [string] $Directory)

    $found = [Collections.Generic.List[string]]::new()
    foreach ($entry in @(Get-ChildItem -LiteralPath $Directory -Force -Filter 'tmux-*' -ErrorAction Ignore)) {
        if ($entry.LinkType) { $found.Add($entry.Name); continue }
        if ($entry.PSIsContainer -and
            (Get-Item -LiteralPath (Join-Path $entry.FullName 'default') -Force -ErrorAction Ignore)) {
            $found.Add("$($entry.Name)/default")
        }
    }
    foreach ($entry in @(Get-ChildItem -LiteralPath $Directory -Recurse -Force -ErrorAction Ignore)) {
        if ($entry.LinkType -or $entry.UnixMode -cnotlike 's*') { continue }
        $name = $entry.FullName.Substring($Directory.Length).TrimStart('/')
        if ($name -cnotin $found -and (Test-TestSandboxServer $entry.FullName)) { $found.Add($name) }
    }
    $found
}

function Initialize-TestSandboxDirectory {
    [CmdletBinding()]
    param([string[]] $Parent = @([IO.Path]::GetTempPath().TrimEnd('/'), '/tmp'))

    $failure = $null
    foreach ($root in $Parent) {
        if (-not $root -or [Text.Encoding]::UTF8.GetByteCount($root) + 15 -gt 40 -or
            -not [IO.Directory]::Exists($root)) { continue }
        for ($attempt = 0; $attempt -lt 8; $attempt++) {
            $path = Join-Path $root ('lt-ps-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
            if (Get-Item -LiteralPath $path -Force -ErrorAction Ignore) { continue }
            # The mode is part of the mkdir, so there is no moment at the default one. A
            # umask can only remove bits, and the check catches a directory that lost one.
            try {
                $null = [IO.Directory]::CreateDirectory($path, [IO.UnixFileMode]::UserRead -bor
                    [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
            } catch { $failure = $_.Exception.GetType().Name; continue }
            $problem = Get-TestSandboxAccessProblem $path
            if ($problem) {
                [IO.Directory]::Delete($path)
                throw "The test sandbox could not be made: $problem."
            }
            return $path
        }
    }
    # Name the failure that stopped the last try, not a length that was fine.
    if ($failure) {
        throw "The test sandbox could not be made: creating its directory failed ($failure). Set TMPDIR to a directory you own."
    }
    throw 'No temporary directory is short enough for a tmux socket path. Set TMPDIR to a shorter one.'
}

# Stops every server a test left in the sandbox by `tmux -S <path> kill-server`, checks
# that each stopped, and removes the directory when this process made it and no server
# still answers. Returns the relative paths it found.
function Exit-TestSandbox {
    [CmdletBinding()]
    param()

    $directory = [Environment]::GetEnvironmentVariable('LIBTMUX_TEST_SANDBOX')
    if (-not $directory -or
        [Environment]::GetEnvironmentVariable('LIBTMUX_TEST_SANDBOX_OWNER') -cne [string] $PID -or
        [Environment]::GetEnvironmentVariable('TMUX_TMPDIR') -cne $directory -or
        -not [IO.Path]::GetFileName($directory).StartsWith('lt-ps-', [StringComparison]::Ordinal) -or
        -not [IO.Directory]::Exists($directory)) { return }
    $leaks = @(Get-TestSandboxLeak $directory)
    $tmux = Get-Command tmux -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    $answering = [Collections.Generic.List[string]]::new()
    foreach ($leak in $leaks) {
        $socket = Join-Path $directory $leak
        $item = Get-Item -LiteralPath $socket -Force -ErrorAction Ignore
        # A link would take the kill to a server this run does not own.
        if ($item -and $item.LinkType) { continue }
        if ($tmux) {
            $start = [Diagnostics.ProcessStartInfo]::new($tmux.Source)
            $start.UseShellExecute = $false
            $start.RedirectStandardOutput = $true
            $start.RedirectStandardError = $true
            foreach ($argument in @('-S', $socket, 'kill-server')) { $start.ArgumentList.Add($argument) }
            $process = [Diagnostics.Process]::Start($start)
            try { if (-not $process.WaitForExit(2000)) { $process.Kill($true) } } finally { $process.Dispose() }
        }
        $wait = [Diagnostics.Stopwatch]::StartNew()
        do {
            $up = Test-TestSandboxServer $socket
            if ($up -and $tmux) { Start-Sleep -Milliseconds 50 }
        } while ($up -and $tmux -and $wait.ElapsedMilliseconds -lt 3000)
        if ($up) { $answering.Add($leak) }
    }
    if ($answering.Count) {
        [Console]::Error.WriteLine("libtmux-powershell tests kept $([IO.Path]::GetFileName($directory)) because a server " +
            "still answers on $($answering -join ', ')")
    } else {
        Remove-Item -LiteralPath $directory -Recurse -Force
    }
    # The exit hook runs this again; it has nothing left to do, and must not wait out another stop.
    [Environment]::SetEnvironmentVariable('LIBTMUX_TEST_SANDBOX_OWNER', [NullString]::Value)
    $leaks
}

# PowerShell runs this when the host exits, after the script that entered has returned
# and possibly after its files are gone, so the hook carries the functions it calls.
function Register-TestSandboxExit {
    [CmdletBinding()]
    param()

    $global:LibTmuxTestSandboxExit = @('Test-TestSandboxServer', 'Get-TestSandboxLeak', 'Exit-TestSandbox' | ForEach-Object {
        "function $_ {$((Get-Command $_ -CommandType Function).Definition)}"
    }) -join "`n"
    $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        try {
            . ([scriptblock]::Create($global:LibTmuxTestSandboxExit))
            $leaks = @(Exit-TestSandbox)
        } catch {
            [Console]::Error.WriteLine("libtmux-powershell tests could not clean their sandbox: $($_.Exception.Message)")
            [Environment]::Exit(1)
        }
        if ($leaks.Count) {
            [Console]::Error.WriteLine('libtmux-powershell tests left a default socket or a server in the ' +
                "sandbox: $($leaks -join ', ')")
            [Environment]::Exit(1)
        }
    }
}

# Removes the selectors from this process, points TMUX_TMPDIR at a directory of
# this run's own unless an enclosing run made one, and returns that directory.
function Enter-TestSandbox {
    [CmdletBinding()]
    param()

    # PowerShell 7.6 hands $null to a string parameter as an empty string, and on .NET 10
    # that sets the variable instead of removing it. [NullString]::Value removes it on both.
    foreach ($name in @([Environment]::GetEnvironmentVariables().Keys)) {
        if (Test-TestSandboxSelector $name) { [Environment]::SetEnvironmentVariable($name, [NullString]::Value) }
    }
    $created = $null
    if (Get-TestSandboxRouteProblem ([Environment]::GetEnvironmentVariables())) {
        $created = Initialize-TestSandboxDirectory
        [Environment]::SetEnvironmentVariable('TMUX_TMPDIR', $created)
        [Environment]::SetEnvironmentVariable('LIBTMUX_TEST_SANDBOX', $created)
        [Environment]::SetEnvironmentVariable('LIBTMUX_TEST_SANDBOX_OWNER', [string] $PID)
    }
    $found = @(Get-TestSandboxViolation)
    if ($found.Count) {
        if ($created) { Remove-Item -LiteralPath $created -Recurse -Force }
        throw "The test sandbox could not be entered: $($found -join '; ')."
    }
    if ($created) { Register-TestSandboxExit }
    [Environment]::GetEnvironmentVariable('TMUX_TMPDIR')
}
