param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: exercise the installed cmdlets and both client transports.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-EndpointLive([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Live endpoint: $Message" }
}

$fixture = New-OwnedTmuxFixture -NamedSocket
$other = $null
$defaultFixture = $null
$keys = @('PATH', 'LIBTMUX_SOCKET_PATH', 'LIBTMUX_SOCKET_NAME', 'TMUX', 'TMUX_PANE', 'TMUX_TMPDIR',
    'LIBTMUX_LIFECYCLE_VALUE', 'LIBTMUX_LIFECYCLE_REMOVED', 'LIBTMUX_LIFECYCLE_INHERITED', 'LIBTMUX_LIFECYCLE_LATER')
$prior = @{}
foreach ($key in $keys) { $prior[$key] = [Environment]::GetEnvironmentVariable($key) }
$bodyError = $null
try {
    $other = New-OwnedTmuxFixture
    $defaultFixture = New-OwnedTmuxFixture -NamedSocket -SocketName default
    $bin = New-Item -ItemType Directory (Join-Path $fixture.DirectoryPath 'bin')
    $python = (Get-Command python3 -CommandType Application | Select-Object -First 1).Source
    $wrapper = Join-Path $bin.FullName 'tmux'
    ("#!$python`n" + [IO.File]::ReadAllText("$PSScriptRoot/support/lifecycle_tmux.py")) |
        Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode] 448)
    $trace = Join-Path $fixture.DirectoryPath 'calls.jsonl'
    $overrides = @{
        PATH = $bin.FullName + [IO.Path]::PathSeparator + $env:PATH
        LIBTMUX_SOCKET_PATH = $fixture.SocketPath
        LIBTMUX_SOCKET_NAME = '../ignored'
        TMUX_TMPDIR = $fixture.DirectoryPath
        TMUX = 'ignored invalid context'
        TMUX_PANE = '%987654'
        LIBTMUX_LIFECYCLE_SOCKET = $fixture.SocketPath
        LIBTMUX_LIFECYCLE_BINARY = $fixture.TmuxPath
        LIBTMUX_LIFECYCLE_MODE = 'Environment'
        LIBTMUX_LIFECYCLE_TRACE = $trace
        LIBTMUX_LIFECYCLE_VALUE = 'captured override'
        LIBTMUX_LIFECYCLE_REMOVED = $null
        PSMUX_SESSION = $null
    }
    $env:LIBTMUX_LIFECYCLE_VALUE = 'host original'
    $env:LIBTMUX_LIFECYCLE_REMOVED = 'inherited removal candidate'
    $env:LIBTMUX_LIFECYCLE_INHERITED = 'inherited at construction'
    [Environment]::SetEnvironmentVariable('LIBTMUX_LIFECYCLE_LATER', $null)
    $server = New-TmuxServer -ChildEnvironment $overrides
    Assert-EndpointLive ($env:LIBTMUX_LIFECYCLE_VALUE -ceq 'host original') 'constructor mutated the host'
    $overrides.LIBTMUX_LIFECYCLE_VALUE = 'mutated caller map'
    $overrides.LIBTMUX_SOCKET_PATH = $other.SocketPath
    $env:PATH = '/unavailable-after-construction'
    $env:LIBTMUX_SOCKET_PATH = $other.SocketPath
    $env:LIBTMUX_SOCKET_NAME = 'other'
    $env:TMUX_TMPDIR = $other.DirectoryPath
    $env:TMUX = "$($other.SocketPath),1,0"
    $env:TMUX_PANE = '%123456'
    $env:LIBTMUX_LIFECYCLE_VALUE = 'host changed'
    $env:LIBTMUX_LIFECYCLE_INHERITED = 'host changed after construction'
    $env:LIBTMUX_LIFECYCLE_LATER = 'added after construction'
    $snapshot = $server | Get-TmuxSnapshot
    Assert-EndpointLive ($snapshot.Sessions.Count -eq 1 -and
        $snapshot.Sessions[0].Generation.ProcessId -eq $fixture.ServerPid) 'subprocess followed the changed host or caller map'
    $control = $server | Connect-TmuxControl -Target fixture
    try {
        $command = New-TmuxCommand -Name display-message -Arguments @('-p', '#{pid}')
        $reply = $control | Invoke-TmuxControlCommand -Command $command
        Assert-EndpointLive ([int] $reply -eq $fixture.ServerPid) 'control client followed changed host values'
    } finally { $control | Disconnect-TmuxControl -Confirm:$false }
    Assert-EndpointLive ($env:LIBTMUX_LIFECYCLE_VALUE -ceq 'host changed' -and
        $env:TMUX_PANE -ceq '%123456' -and $env:LIBTMUX_SOCKET_PATH -ceq $other.SocketPath) 'launch changed the host environment'
    $calls = @(Get-Content -LiteralPath $trace | ConvertFrom-Json)
    Assert-EndpointLive ($calls.Count -gt 2 -and
        @($calls | Where-Object { $_.value -cne 'captured override' -or $null -ne $_.removed }).Count -eq 0) 'client did not retain overrides or null removal'
    Assert-EndpointLive (@($calls | Where-Object {
        $_.inherited -cne 'inherited at construction' -or $null -ne $_.later
    }).Count -eq 0) 'client did not snapshot the complete inherited environment'
    Assert-EndpointLive (@($calls | Where-Object { $_.arguments -contains '-C' }).Count -eq 1) 'control environment was not exercised'

    $overrides.LIBTMUX_LIFECYCLE_VALUE = 'captured override'
    foreach ($selector in @('ExplicitPath', 'ExplicitName', 'Path', 'Name', 'Context', 'Default')) {
        $values = $overrides.Clone()
        $values.LIBTMUX_SOCKET_PATH = ''
        $values.LIBTMUX_SOCKET_NAME = ''
        $values.TMUX = ''
        $expected = $fixture
        $options = @{ ChildEnvironment = $values }
        switch ($selector) {
            ExplicitPath {
                $options.SocketPath = $fixture.SocketPath
                $values.LIBTMUX_SOCKET_PATH = 'ignored invalid lower path'
            }
            ExplicitName {
                $options.SocketName = 'socket'
                $values.LIBTMUX_SOCKET_PATH = 'ignored invalid lower path'
            }
            Path {
                $values.LIBTMUX_SOCKET_PATH = $fixture.SocketPath
                $values.LIBTMUX_SOCKET_NAME = '../ignored'
                $values.TMUX = 'ignored invalid context'
            }
            Name {
                $values.LIBTMUX_SOCKET_NAME = 'socket'
                $values.TMUX = 'ignored invalid context'
            }
            Context {
                $alias = Join-Path $fixture.DirectoryPath 'comma, path'
                $null = New-Item -ItemType SymbolicLink -Path $alias -Target (Split-Path $fixture.SocketPath)
                $values.TMUX = "$(Join-Path $alias 'socket'),12,`$0"
                $values.LIBTMUX_LIFECYCLE_SOCKET = Join-Path $alias 'socket'
            }
            Default {
                $expected = $defaultFixture
                $values.TMUX_TMPDIR = $defaultFixture.DirectoryPath
                $values.LIBTMUX_LIFECYCLE_SOCKET = $defaultFixture.SocketPath
            }
        }
        $resolved = New-TmuxServer @options
        $actual = $resolved | Get-TmuxServer
        Assert-EndpointLive ($actual.Generation.ProcessId -eq $expected.ServerPid) "wrong daemon for $selector"
    }
    $env:PATH = $prior.PATH
    $fresh = Join-Path $fixture.DirectoryPath 'fresh-root'
    $null = New-Item -ItemType Directory $fresh
    $freshOptions = @{
        LIBTMUX_SOCKET_PATH = ''; LIBTMUX_SOCKET_NAME = 'fresh'; TMUX = ''
        TMUX_TMPDIR = $fresh; PSMUX_SESSION = $null
    }
    $freshHandle = New-TmuxServer -ChildEnvironment $freshOptions -TmuxBinaryPath $fixture.TmuxPath
    $absent = @($freshHandle | Get-TmuxServer)
    Assert-EndpointLive ($absent.Count -eq 0) 'fresh private root unexpectedly had a daemon'
    $perUser = @(Get-ChildItem -LiteralPath $fresh -Directory)
    Assert-EndpointLive ($perUser.Count -eq 1 -and
        [int] [IO.File]::GetUnixFileMode($perUser[0].FullName) -eq 448) 'fresh named directory was not created with mode 0700'
    Remove-Item -LiteralPath $fresh -Recurse
    $failure = $null
    try { $null = $freshHandle | Get-TmuxServer } catch { $failure = $_ }
    Assert-EndpointLive ($null -ne $failure) 'removed named root silently fell back'
    $otherSessions = Invoke-OwnedTmux $other -Arguments @('list-sessions', '-F', '#{session_name}')
    Assert-EndpointLive ($otherSessions.StdOut.Trim() -ceq 'fixture') 'snapshot testing changed the alternate daemon'
    'PASS live endpoint precedence, comma context, defaults, root checks and frozen subprocess/control environments'
} catch {
    $bodyError = $_
    throw
} finally {
    foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key, $prior[$key]) }
    $cleanupErrors = [Collections.Generic.List[Exception]]::new()
    foreach ($owned in @($fixture, $other, $defaultFixture)) {
        if ($owned) {
            try {
                Remove-OwnedTmuxFixture $owned
                Assert-EndpointLive $owned.ExitConfirmedBeforeDirectoryRemoval 'directory removal preceded daemon-exit proof'
            } catch { $cleanupErrors.Add($_.Exception) }
        }
    }
    if ($cleanupErrors.Count) {
        if ($bodyError) { $cleanupErrors.Insert(0, $bodyError.Exception) }
        throw [AggregateException]::new('Live endpoint test cleanup failed.', $cleanupErrors)
    }
}
