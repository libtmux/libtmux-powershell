param([Parameter(Mandatory)] [string] $ModuleRoot)

# Integration: cmdlets check the connected daemon before they dispatch.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw "VersionCheck: $Message" }
}

function New-Wrapper([string] $Directory, [string] $Name, [string] $Real, [string] $Body) {
    $path = Join-Path $Directory $Name
    $quoted = "'" + $Real.Replace("'", "'\''") + "'"
    "#!/bin/sh`n$Body`nexec $quoted `"`$@`"`n" | Set-Content -LiteralPath $path -NoNewline
    [IO.File]::SetUnixFileMode($path, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $path
}

function Get-Refusals($Errors) {
    @($Errors | Where-Object { $_.Exception -is [LibTmux.TmuxVersionTooLowException] })
}

function Test-NativeSession($Fixture, [string] $Name) {
    (Invoke-OwnedTmux $Fixture -Arguments @('has-session', '-t', "=$Name") -AllowFailure).ExitCode -eq 0
}

function Get-NativeSessions($Fixture) {
    (Invoke-OwnedTmux $Fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Trim()
}

Import-Module (Join-Path $ModuleRoot 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1')

# Version check fails closed: every cmdlet either resolves a daemon to check or is explicitly exempt.
$base = [LibTmux.PowerShell.TmuxCmdlet]
$cmdlets = @(
    $base.Assembly.GetTypes() + [LibTmux.Workspace.PowerShell.InvokeTmuxWorkspaceCommand].Assembly.GetTypes() |
        Where-Object { $_.IsSubclassOf($base) -and -not $_.IsAbstract })
$exempt = @($cmdlets | Where-Object { $_.IsDefined([LibTmux.PowerShell.TmuxVersionCheckExemptAttribute], $false) } |
    ForEach-Object Name | Sort-Object)
$expectedExempt = @('ConvertToTmuxWorkspaceCommand', 'DisconnectTmuxControlCommand', 'GetTmuxWorkspaceCommand',
    'ImportTmuxWorkspaceCommand', 'InvokeTmuxControlCommandCommand', 'ResolveTmuxWorkspaceCommand',
    'SelectTmuxPaneCommand', 'SelectTmuxSessionCommand', 'SelectTmuxWindowCommand', 'WatchTmuxEventCommand')
Assert-True (-not (Compare-Object $exempt $expectedExempt)) "the exempt cmdlets changed: $($exempt -join ', ')"
$checkable = @('Server', 'Session', 'Window', 'Pane', 'Client', 'WorkspacePlan')
foreach ($type in $cmdlets | Where-Object { $_.Name -cnotin $exempt }) {
    $resolves = $type.GetMethod('ResolveServer', [Reflection.BindingFlags]'Instance,NonPublic,DeclaredOnly') -or
        @($type.GetProperties() | Where-Object {
            $_.IsDefined([Management.Automation.ParameterAttribute], $false) -and $_.PropertyType.Name -cin $checkable }).Count -gt 0
    Assert-True $resolves "$($type.Name) neither exposes a checkable object nor is marked exempt"
}

# A cmdlet that forgets both a server and the exemption is refused rather than run without a version check.
Add-Type -ReferencedAssemblies @($base.Assembly.Location, [Management.Automation.PSCmdlet].Assembly.Location) -TypeDefinition @'
using System.Management.Automation;
namespace LibTmux.Testing
{
    [Cmdlet("Invoke", "ForgottenVersionCheck")]
    public sealed class InvokeForgottenVersionCheckCommand : LibTmux.PowerShell.TmuxCmdlet
    {
        protected override void ProcessRecord() =>
            ReadResult(_ => System.Threading.Tasks.Task.FromResult("ran"), "Test.Forgotten", "not-a-server");
    }
}
'@
Import-Module -Assembly ([LibTmux.Testing.InvokeForgottenVersionCheckCommand].Assembly)
$errors = @()
$ran = @(Invoke-ForgottenVersionCheck -ErrorAction SilentlyContinue -ErrorVariable errors)
Assert-True ($ran.Count -eq 0 -and $errors.Count -eq 1 -and $errors[0].Exception.Message -clike '*not marked TmuxVersionCheckExempt*') 'a cmdlet without a server or exemption ran without a version check'

$floor = [LibTmux.TmuxVersion]::Parse('3.3a')
$tmux = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$reported = (& $tmux -V)
$null = $reported -match '^\S+ (\S+)$'
$binaryVersion = [LibTmux.TmuxVersion]::Parse($Matches[1])
$supported = $binaryVersion -ge $floor
Write-Host "VersionCheck: tmux $($binaryVersion.Raw) is $(if ($supported) { 'supported' } else { 'below the floor' })"
# A rejection lane names the release it must run; a missing or mismatched build fails instead of skipping.
$requiredRejection = $env:LIBTMUX_REQUIRE_REJECTED
if ($requiredRejection) {
    Assert-True ((-not $supported) -and $binaryVersion.Raw -ceq $requiredRejection) "the rejection lane expected tmux $requiredRejection but found $($binaryVersion.Raw)"
}

Invoke-WithOwnedTmux {
    param($fixture)
    $bin = Join-Path $fixture.DirectoryPath 'bin'
    $null = New-Item -ItemType Directory $bin

    if (-not $supported) {
        # A client that claims to be newer must not qualify an older daemon.
        $lying = New-Wrapper $bin 'tmux' $fixture.TmuxPath 'if [ "$1" = "-V" ]; then echo "tmux 9.9"; exit 0; fi'
        $absent = Join-Path $fixture.DirectoryPath 'absent'
        $null = Invoke-OwnedTmux $fixture -Arguments @('set-option', '-g', '@sentinel', 'kept')
        $null = Invoke-OwnedTmux $fixture -Arguments @('set-buffer', '-b', 'sentinel', 'kept')
        # An absent endpoint checks the executable that would start it, so only a live daemon can be lied about.
        foreach ($case in @(
            @{ Name = 'live daemon'; Path = $fixture.SocketPath; Binaries = @($fixture.TmuxPath, $lying) },
            @{ Name = 'absent endpoint'; Path = $absent; Binaries = @($fixture.TmuxPath) }
        )) {
            foreach ($binary in $case.Binaries) {
                $label = "$($case.Name) via $(if ($binary -ceq $lying) { 'newer-reporting' } else { 'native' }) client"
                $server = New-TmuxServer -SocketPath $case.Path -TmuxBinaryPath $binary
                $errors = @()
                $read = @($server | Get-TmuxSession -ErrorAction SilentlyContinue -ErrorVariable errors)
                Assert-True ($read.Count -eq 0 -and @(Get-Refusals $errors).Count -eq 1) "read was not refused for $label"
                $errors = @()
                $null = $server | New-TmuxSession -Name sentinel -Command 'exec /bin/sh' -ErrorAction SilentlyContinue -ErrorVariable errors
                Assert-True (@(Get-Refusals $errors).Count -eq 1) "session creation was not refused for $label"
                $errors = @()
                $null = $server | Invoke-TmuxCommand -Arguments @('new-session', '-d', '-s', 'sentinel', 'exec /bin/sh') `
                    -ErrorAction SilentlyContinue -ErrorVariable errors
                Assert-True (@(Get-Refusals $errors).Count -eq 1) "raw command was not refused for $label"
                $errors = @()
                $chain = New-TmuxCommand -Name 'new-session' -Arguments @('-d', '-s', 'sentinel', 'exec /bin/sh')
                $null = $server | Invoke-TmuxChain -Command $chain -ErrorAction SilentlyContinue -ErrorVariable errors
                Assert-True (@(Get-Refusals $errors).Count -eq 1) "chain was not refused for $label"
            }
        }
        Assert-True ((Get-NativeSessions $fixture) -ceq 'fixture') 'a refused operation changed the live daemon'
        Assert-True ((Invoke-OwnedTmux $fixture -Arguments @('show-options', '-gv', '@sentinel')).StdOut.Trim() -ceq 'kept' -and
            (Invoke-OwnedTmux $fixture -Arguments @('list-buffers', '-F', '#{buffer_name}')).StdOut.Trim() -ceq 'sentinel' -and
            (Invoke-OwnedTmux $fixture -Arguments @('show-buffer', '-b', 'sentinel')).StdOut -ceq 'kept') 'a refused operation changed an option or buffer'
        Assert-True (-not (Test-Path -LiteralPath $absent)) 'a refused operation started a daemon on the absent endpoint'
        Write-Host 'VersionCheck: older daemons refused with no effects'
        return
    }

    $server = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath

    # Supported daemons are checked for reads and writes.
    $sessions = @($server | Get-TmuxSession)
    Assert-True ($sessions.Count -eq 1 -and $sessions[0].Name -ceq 'fixture') 'a supported daemon was not read'
    $created = $server | New-TmuxSession -Name checked -Command 'exec /bin/sh'
    Assert-True ($created.Name -ceq 'checked' -and (Test-NativeSession $fixture 'checked')) 'a supported daemon was not written'

    # The probe fires neither an after-hook nor command-error.
    $log = Join-Path $fixture.DirectoryPath 'hooks.log'
    $null = Invoke-OwnedTmux $fixture -Arguments @('set-hook', '-g', 'after-display-message', "run-shell 'echo display >> $log'")
    $errorHook = (Invoke-OwnedTmux $fixture -AllowFailure -Arguments @('set-hook', '-g', 'command-error', "run-shell 'echo error >> $log'")).ExitCode -eq 0
    if (-not $errorHook) { Write-Host 'VersionCheck: SKIPPED command-error hook (unsupported before tmux 3.5)' }
    $null = $server | Invoke-TmuxCommand -Arguments @('list-sessions')
    # Typed reads fire display-message hooks themselves; raw dispatch isolates version check.
    $null = $server | Invoke-TmuxChain -Command (New-TmuxCommand -Name 'list-sessions')
    $null = Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', 'control')
    if ($errorHook) { $null = Invoke-OwnedTmux $fixture -Arguments @('select-pane', '-t', '%999999') -AllowFailure }
    $expected = if ($errorHook) { 2 } else { 1 }
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline -and
        (-not (Test-Path -LiteralPath $log) -or @(Get-Content -LiteralPath $log).Count -lt $expected)) {
        Start-Sleep -Milliseconds 50
    }
    Start-Sleep -Milliseconds 300
    $fired = @(Get-Content -LiteralPath $log)
    Assert-True ($fired.Count -eq $expected) "version check fired hooks: $($fired -join ',')"
    $null = Invoke-OwnedTmux $fixture -Arguments @('set-hook', '-gu', 'after-display-message')
    if ($errorHook) { $null = Invoke-OwnedTmux $fixture -Arguments @('set-hook', '-gu', 'command-error') }

    # A daemon replaced after the version check fails the fence before any command runs.
    $replaced = New-Wrapper $bin 'tmux-replaced' $fixture.TmuxPath @'
case "$*" in
*"run-shell -C libtmux-version-"*)
    for last; do :; done
    printf 'unknown command: %s\n' "$(printf %s "$last" | sed 's/#{version}/9.9/')" >&2
    exit 1;;
esac
'@
    $lagging = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $replaced
    $errors = @()
    $null = $lagging | Invoke-TmuxCommand -Arguments @('new-session', '-d', '-s', 'fenced', 'exec /bin/sh') `
        -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True (@(Get-Refusals $errors).Count -eq 1 -and $errors[0].Exception.Message -clike '*changed*') 'a replaced daemon passed the command fence'
    Assert-True (-not (Test-NativeSession $fixture 'fenced')) 'the fenced command took effect'
    $errors = @()
    $chain = New-TmuxCommand -Name 'new-session' -Arguments @('-d', '-s', 'fenced', 'exec /bin/sh')
    $null = $lagging | Invoke-TmuxChain -Command $chain -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True (@(Get-Refusals $errors).Count -eq 1 -and $errors[0].Exception.Message -clike '*changed*') 'a replaced daemon passed the chain fence'
    Assert-True (-not (Test-NativeSession $fixture 'fenced')) 'the fenced chain took effect'
    $pass = New-Wrapper $bin 'tmux-pass' $fixture.TmuxPath ''
    $null = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $pass |
        Invoke-TmuxCommand -Arguments @('new-session', '-d', '-s', 'fenced', 'exec /bin/sh')
    Assert-True (Test-NativeSession $fixture 'fenced') 'the fence refused an unchanged daemon'

    # Version grammar: every form tmux has reported, in the canonical vectors.
    $check = @('3.3a', '3.4', '3.7d', '3.8', '3.10', '4.0', '3.4-rc', '3.8-rc', '3.8-rc2', 'next-3.4', 'next-3.9')
    $refuse = @('3.3', '3.2a', '3.3-rc', '3.2-rc5', 'next-3.3', 'master', 'openbsd-7.6', '', '3', 'garbage',
        '3.3a garbage', '3.3a-master', '3.3a-dev', 'next-3.3a', 'next-3.9-master')
    $cases = [ordered]@{}
    foreach ($report in $check) { $cases[$report] = $true }
    foreach ($report in $refuse) { $cases[$report] = $false }
    $ranked = @('next-3.7', '3.7-rc', '3.7-rc3', '3.7', '3.7a', '3.9', '3.10')
    for ($i = 1; $i -lt $ranked.Count; $i++) {
        Assert-True ([LibTmux.TmuxVersion]::Parse($ranked[$i - 1]) -lt [LibTmux.TmuxVersion]::Parse($ranked[$i])) "$($ranked[$i - 1]) does not rank below $($ranked[$i])"
    }
    Assert-True ([LibTmux.TmuxVersion]::Parse('next-3.4') -lt [LibTmux.TmuxVersion]::Parse('3.4-rc') -and
        [LibTmux.TmuxVersion]::Parse('3.4-rc') -lt [LibTmux.TmuxVersion]::Parse('3.4')) 'next-3.4 < 3.4-rc < 3.4 fails'
    $seven = [LibTmux.TmuxVersion]::Parse('3.7')
    Assert-True ([LibTmux.TmuxVersion]::Parse('3.8-rc2') -ge $seven -and [LibTmux.TmuxVersion]::Parse('next-3.8') -ge $seven -and
        [LibTmux.TmuxVersion]::Parse('next-3.7') -lt $seven -and [LibTmux.TmuxVersion]::Parse('3.7-rc2') -lt $seven) 'control-gate ordering around 3.7 fails'
    foreach ($entry in $cases.GetEnumerator()) {
        $env:LIBTMUX_VERSION_REPORT = $entry.Key
        try {
            $reporting = New-Wrapper $bin ('tmux-reporting-' + [Guid]::NewGuid().ToString('N')) $fixture.TmuxPath @'
case "$*" in
*"run-shell -C libtmux-version-"*)
    for last; do :; done
    printf 'unknown command: %s\n' "$(printf %s "$last" | sed "s/#{version}/$LIBTMUX_VERSION_REPORT/")" >&2
    exit 1;;
esac
'@
            $probe = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $reporting
            $errors = @()
            $read = @($probe | Get-TmuxSession -ErrorAction SilentlyContinue -ErrorVariable errors)
            Assert-True (($read.Count -gt 0) -eq $entry.Value -and ($errors.Count -eq 0) -eq $entry.Value) "daemon report '$($entry.Key)' should be checked: $($entry.Value)"
        } finally {
            Remove-Item Env:LIBTMUX_VERSION_REPORT -ErrorAction Ignore
        }
    }

    # One probe checks an endpoint; later operations reuse it until a fence or failure says otherwise.
    $probeLog = Join-Path $fixture.DirectoryPath 'probes.log'
    $counted = New-Wrapper $bin 'tmux-counted' $fixture.TmuxPath @"
case "`$*" in
*"run-shell -C libtmux-version-"*) echo probe >> '$probeLog';;
esac
"@
    $cachedServer = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $counted
    foreach ($index in 1..3) { $null = $cachedServer | Get-TmuxSession }
    $null = $cachedServer | Invoke-TmuxCommand -Arguments @('list-sessions')
    Assert-True (@(Get-Content -LiteralPath $probeLog).Count -eq 1) "operations on one endpoint probed more than once: $(@(Get-Content -LiteralPath $probeLog).Count)"

    # A daemon that is not the one checked fails the fence, and the next operation probes again.
    $state = Join-Path $fixture.DirectoryPath 'swapped'
    $swapLog = Join-Path $fixture.DirectoryPath 'swap-probes.log'
    $swapped = New-Wrapper $bin 'tmux-swapped' $fixture.TmuxPath @"
case "`$*" in
*"run-shell -C libtmux-version-"*)
    echo probe >> '$swapLog'
    if [ ! -e '$state' ]; then
        : > '$state'
        for last; do :; done
        printf 'unknown command: %s\n' "`$(printf %s "`$last" | sed 's/#{version}/9.9/')" >&2
        exit 1
    fi;;
esac
"@
    $swappedServer = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $swapped
    $errors = @()
    $null = $swappedServer | Invoke-TmuxCommand -Arguments @('list-sessions') -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True (@(Get-Refusals $errors).Count -eq 1) 'the swapped daemon passed the fence'
    $again = $swappedServer | Invoke-TmuxCommand -Arguments @('list-sessions')
    Assert-True ($again.ExitCode -eq 0 -and @(Get-Content -LiteralPath $swapLog).Count -eq 2) 'the fence did not invalidate the cached version check'

    # A failed batch reports what the caller sent, not the fence.
    $errors = @()
    $null = $server | Invoke-TmuxChain -Command (New-TmuxCommand -Name 'select-pane' -Arguments @('-t', '%999999999')) `
        -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True ($errors.Count -eq 1 -and $errors[0].Exception -is [LibTmux.TmuxCommandException] -and
        ($errors[0].Exception.Result.Arguments -join ' ') -cnotmatch 'libtmux-version|if-shell') 'a failed chain leaked the version check fence'

    # Stopping a server nobody is running is a no-op.
    $gone = New-TmuxServer -SocketPath (Join-Path $fixture.DirectoryPath 'never.sock') -TmuxBinaryPath $fixture.TmuxPath
    $errors = @()
    $stopped = $gone | Invoke-TmuxCommand -Arguments @('kill-server') -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True ($errors.Count -eq 0 -and $stopped.ExitCode -eq 0) 'kill-server on an absent endpoint was not a no-op'

    # A connection opened outside the module is checked from its own daemon before it carries a command.
    # Control clients crash older servers, so this positive control runs only where they are routine.
    if ($binaryVersion -ge [LibTmux.TmuxVersion]::Parse('3.7')) {
        $outside = $server.EnterControlModeAsync('fixture').GetAwaiter().GetResult()
        try {
            $errors = @()
            $null = $outside | Invoke-TmuxControlCommand -Command (New-TmuxCommand -Name 'list-sessions') -ErrorAction SilentlyContinue -ErrorVariable errors
            Assert-True ($errors.Count -eq 1 -and $errors[0].Exception.Message -clike '*Pass -Server*') 'an unknown control connection was used without naming its endpoint'
            $reply = @($outside | Invoke-TmuxControlCommand -Server $server -Command (New-TmuxCommand -Name 'display-message' -Arguments @('-p', 'outside')))
            Assert-True ($reply.Count -eq 1 -and $reply[0] -ceq 'outside') 'a supplied control connection was not checked and used'
            # A connection known to belong to a sub-floor daemon carries nothing.
            $remember = [LibTmux.PowerShell.TmuxCmdlet].Assembly.GetType('LibTmux.PowerShell.TmuxVersionCheck').GetMethod(
                'Remember', [Reflection.BindingFlags]'Static,NonPublic')
            $null = $remember.Invoke($null, @($outside, [LibTmux.TmuxVersion]::Parse('3.2a')))
            $errors = @()
            $null = $outside | Invoke-TmuxControlCommand -ErrorAction SilentlyContinue -ErrorVariable errors `
                -Command (New-TmuxCommand -Name 'set-option' -Arguments @('-g', '@outside', 'sent'))
            Assert-True (@(Get-Refusals $errors).Count -eq 1 -and
                (Invoke-OwnedTmux $fixture -Arguments @('show-options', '-gv', '@outside') -AllowFailure).StdOut.Trim().Length -eq 0) 'a control connection to a sub-floor daemon carried a command'
        } finally { $null = $outside.DisposeAsync().AsTask().GetAwaiter().GetResult() }

        # Control version check is hook-free too: neither list-commands nor display-message hooks fire.
        $controlLog = Join-Path $fixture.DirectoryPath 'control-hooks.log'
        $hooks = @{ 'after-list-commands' = 'list'; 'after-display-message' = 'display'; 'command-error' = 'error' }
        $armed = @()
        foreach ($hook in $hooks.GetEnumerator()) {
            $set = Invoke-OwnedTmux $fixture -AllowFailure -Arguments @('set-hook', '-g', $hook.Key, "run-shell 'echo $($hook.Value) >> $controlLog'")
            if ($set.ExitCode -eq 0) { $armed += $hook.Key } else { Write-Host "VersionCheck: SKIPPED $($hook.Key) hook (not available on this tmux)" }
        }
        function Wait-ControlLog([int] $Minimum) {
            $deadline = [DateTime]::UtcNow.AddSeconds(3)
            while ([DateTime]::UtcNow -lt $deadline -and
                (-not (Test-Path -LiteralPath $controlLog) -or @(Get-Content -LiteralPath $controlLog).Count -lt $Minimum)) { Start-Sleep -Milliseconds 50 }
            Start-Sleep -Milliseconds 400
            if (Test-Path -LiteralPath $controlLog) { @(Get-Content -LiteralPath $controlLog).Count } else { 0 }
        }
        # The package's own attach and command fire some of these hooks; the baseline measures exactly that.
        $bare = $server.EnterControlModeAsync('fixture').GetAwaiter().GetResult()
        try { $null = $bare.SendAsync((New-TmuxCommand -Name 'list-sessions')).GetAwaiter().GetResult() }
        finally { $null = $bare.DisposeAsync().AsTask().GetAwaiter().GetResult() }
        $baseline = Wait-ControlLog 0
        Remove-Item -LiteralPath $controlLog -ErrorAction Ignore
        $viaCmdlets = $server | Connect-TmuxControl -Target fixture
        try {
            $null = $viaCmdlets | Invoke-TmuxControlCommand -Command (New-TmuxCommand -Name 'list-sessions')
        } finally { $null = $viaCmdlets.DisposeAsync().AsTask().GetAwaiter().GetResult() }
        $cmdletPath = Wait-ControlLog 0
        Remove-Item -LiteralPath $controlLog -ErrorAction Ignore
        $foreign = $server.EnterControlModeAsync('fixture').GetAwaiter().GetResult()
        try {
            $null = $foreign | Invoke-TmuxControlCommand -Server $server -Command (New-TmuxCommand -Name 'list-sessions')
        } finally { $null = $foreign.DisposeAsync().AsTask().GetAwaiter().GetResult() }
        $foreignPath = Wait-ControlLog 0
        Assert-True ($cmdletPath -le $baseline -and $foreignPath -le $baseline) "control version check fired hooks: package attach $baseline, cmdlet path $cmdletPath, foreign connection $foreignPath"
        Remove-Item -LiteralPath $controlLog -ErrorAction Ignore
        # Version check of a foreign connection sends nothing over it: only the caller's command arrives.
        Add-Type -ReferencedAssemblies (@([LibTmux.Server].Assembly.Location) + @(Get-ChildItem "$PSHOME/ref/*.dll" | Select-Object -ExpandProperty FullName)) -CompilerOptions '/nowarn:1701' -TypeDefinition @'
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
namespace LibTmux.Testing
{
    public sealed class CountingConnection : LibTmux.IControlModeSession
    {
        public List<string> Sent { get; } = new();
        public bool IsRunning => true;
        public IAsyncEnumerable<LibTmux.TmuxEvent> Events => throw new System.NotSupportedException();
        public Task<IReadOnlyList<string>> SendAsync(LibTmux.TmuxCommand command, CancellationToken cancellationToken = default)
        {
            Sent.Add(command.Name);
            return Task.FromResult<IReadOnlyList<string>>(new List<string>());
        }
        public System.Threading.Tasks.ValueTask DisposeAsync() => default;
    }
}
'@
        $counting = [LibTmux.Testing.CountingConnection]::new()
        $null = $counting | Invoke-TmuxControlCommand -Server $server -Command (New-TmuxCommand -Name 'list-sessions')
        Assert-True ($counting.Sent.Count -eq 1 -and $counting.Sent[0] -ceq 'list-sessions') "control version check sent commands over the connection: $($counting.Sent -join ',')"
        # The armed hooks do fire for ordinary commands.
        $null = Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', 'control')
        $null = Invoke-OwnedTmux $fixture -Arguments @('list-commands') -AllowFailure
        if ($armed -contains 'command-error') { $null = Invoke-OwnedTmux $fixture -Arguments @('select-pane', '-t', '%999999') -AllowFailure }
        $want = 1 + $(if ($armed -contains 'command-error') { 1 } else { 0 })
        $fired = Wait-ControlLog $want
        $seen = @(Get-Content -LiteralPath $controlLog)
        Assert-True ($seen -ccontains 'display' -and (($armed -cnotcontains 'command-error') -or $seen -ccontains 'error')) "the armed control hooks do not fire for ordinary commands (saw $($seen -join ','))"
        foreach ($hook in $hooks.GetEnumerator()) { if ($armed -contains $hook.Key) { $null = Invoke-OwnedTmux $fixture -Arguments @('set-hook', '-gu', $hook.Key) -AllowFailure } }
    } else {
        Write-Host 'VersionCheck: SKIPPED supplied control connection (control clients need tmux 3.7)'
    }

    # A daemon that vanishes after the version check is not restarted by the client that dispatches.
    $second = Join-Path $fixture.DirectoryPath 'vanish.sock'
    $null = & $fixture.TmuxPath -S $second -f /dev/null new-session -d -s keep 'exec /bin/sh'
    $vanish = New-Wrapper $bin 'tmux-vanish' $fixture.TmuxPath @"
case "`$*" in
*"if-shell -F"*)
    '$($fixture.TmuxPath)' -S '$second' kill-server
    sleep 0.3;;
esac
"@
    $vanished = New-TmuxServer -SocketPath $second -TmuxBinaryPath $vanish
    $errors = @()
    $null = $vanished | Invoke-TmuxCommand -Arguments @('new-session', '-d', '-s', 'revived', 'exec /bin/sh') `
        -ErrorAction SilentlyContinue -ErrorVariable errors
    Start-Sleep -Milliseconds 300
    $null = & $fixture.TmuxPath -S $second -f /dev/null has-session 2>$null
    Assert-True ($errors.Count -eq 1 -and $LASTEXITCODE -ne 0) 'a vanished daemon was restarted by the dispatching client'
    $null = & $fixture.TmuxPath -S $second kill-server 2>$null

    # An absent endpoint is checked from the executable's own banner. The shared .NET package
    # reads only `tmux <version>`, so a renamed 3.3a, which prints its file name, stays untested.
    $renamed = Join-Path $bin 'tmux-renamed'
    $null = [IO.File]::CreateSymbolicLink($renamed, $fixture.TmuxPath)
    if ((& $renamed -V) -clike 'tmux *') {
        $absent = Join-Path $fixture.DirectoryPath 'renamed.sock'
        $cold = New-TmuxServer -SocketPath $absent -TmuxBinaryPath $renamed
        $null = $cold | Invoke-TmuxCommand -Arguments @('new-session', '-d', '-s', 'cold', 'exec /bin/sh')
        $null = & $fixture.TmuxPath -S $absent -f /dev/null has-session -t '=cold'
        Assert-True ($LASTEXITCODE -eq 0) 'an absent endpoint was not checked through a renamed executable'
        $null = & $fixture.TmuxPath -S $absent -f /dev/null kill-server
    } else {
        Write-Host 'VersionCheck: SKIPPED renamed executable (its banner is not "tmux <version>")'
    }
    Write-Host 'VersionCheck: supported daemon checked, hook-free, fenced'
}
