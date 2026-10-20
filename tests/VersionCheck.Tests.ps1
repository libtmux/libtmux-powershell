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

# Reads sessions in a second runspace so a refusal that waits on an output pipe fails the bound instead of hanging the suite.
function Invoke-BoundedRead($Server, [string] $Label, [int] $Seconds = 10) {
    $shell = [powershell]::Create()
    try {
        $null = $shell.AddScript({
            param($Manifest, $Server)
            Import-Module $Manifest
            $errors = @()
            $rows = @($Server | Get-TmuxSession -ErrorAction SilentlyContinue -ErrorVariable errors)
            [pscustomobject]@{ Rows = $rows.Count; Errors = @($errors) }
        }).AddArgument((Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')).AddArgument($Server)
        $pending = $shell.BeginInvoke()
        if (-not $pending.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($Seconds))) {
            $shell.Stop()
            throw "VersionCheck: the refusal for $Label waited on the output pipe past $Seconds s"
        }
        @($shell.EndInvoke($pending))[0]
    } finally {
        $shell.Dispose()
    }
}

function Test-NativeSession($Fixture, [string] $Name) {
    (Invoke-OwnedTmux $Fixture -Arguments @('has-session', '-t', "=$Name") -AllowFailure).ExitCode -eq 0
}

function Get-NativeSessions($Fixture) {
    (Invoke-OwnedTmux $Fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Trim()
}

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

# The remedy rewrite replaces the package's wording and, if that wording changes, appends the release.
$nameRelease = [LibTmux.PowerShell.TmuxCmdlet].GetMethod('NameModuleRelease', [Reflection.BindingFlags]'Static,NonPublic')
$packageText = 'tmux 3.3a or newer is required. Upgrade tmux and restart the tmux server, or use LibTmux 0.0.0-alpha.21, the last release that supports older tmux.'
$rewritten = $nameRelease.Invoke($null, @($packageText))
Assert-True ($rewritten -clike '*or install LibTmux 0.1.0-alpha2 from the PowerShell Gallery*' -and $rewritten -cnotlike '*alpha.21*') 'the package remedy was not replaced'
$appended = $nameRelease.Invoke($null, @('tmux 3.3a or newer is required; reworded by the package.'))
Assert-True ($appended -ceq 'tmux 3.3a or newer is required; reworded by the package. For libtmux for PowerShell, install LibTmux 0.1.0-alpha2 from the PowerShell Gallery, the last release that supports older tmux.') 'a reworded package remedy did not get the installable release appended'

Invoke-WithOwnedTmux {
    param($fixture)
    $bin = Join-Path $fixture.DirectoryPath 'bin'
    $null = New-Item -ItemType Directory $bin

    # The probe answers with the version, the daemon's pid and its start time in one word.
    # A double answers it like tmux does, naming the release it claims.
    function Get-ProbeAnswer([string] $Version) {
        @"
    for last; do :; done
    printf 'unknown command: %s\n' "`$(printf %s "`$last" | sed -e "s/#{version}/$Version/" -e 's/#{pid}/4242/' -e 's/#{start_time}/1700000000/')" >&2
    exit 1
"@
    }

    # Releases before 3.2 cannot report a version through the hook-free probe. Each double answers the
    # probe the way a real build does; the refusal must name that release, say what to do and
    # come back while the daemon's client still holds stdout open, as 3.0a and 3.1c do.
    $olderAnswers = @(
        @{ Name = 'a 3.1c daemon'; Expected = '3.1c'; Hold = $true; Probe = 'echo "usage: run-shell [-b] [-t target-pane] shell-command" >&2; exit 1' },
        @{ Name = 'a 3.0a daemon'; Expected = '3.0a'; Hold = $true; Probe = 'echo "server version is too old for client" >&2; exit 1' },
        @{ Name = 'a client older than 3.2'; Expected = '3.1c'; Hold = $false; Probe = 'echo "tmux: unknown option -- N" >&2; echo "usage: tmux [-2CDluvV] [-c shell-command]" >&2; exit 1' }
    )
    foreach ($answer in $olderAnswers) {
        $hold = if ($answer.Hold) { 'sleep 20 2>/dev/null &' } else { '' }
        $double = New-Wrapper $bin ('tmux-older-' + [Guid]::NewGuid().ToString('N')) $fixture.TmuxPath @"
case "`$*" in
"-V") echo "tmux 3.1c"; exit 0;;
*"run-shell -C libtmux-version-"*)
    $hold
    $($answer.Probe);;
esac
"@
        $older = New-TmuxServer -SocketPath (Join-Path $fixture.DirectoryPath 'older') -TmuxBinaryPath $double
        $outcome = Invoke-BoundedRead $older $answer.Name
        $refused = @(Get-Refusals $outcome.Errors)
        Assert-True ($outcome.Rows -eq 0 -and $refused.Count -eq 1) "$($answer.Name) was not refused as a version failure"
        Assert-True ($refused[0].Exception.ActualVersion.Raw -ceq $answer.Expected) "$($answer.Name) was refused as $($refused[0].Exception.ActualVersion.Raw)"
        Assert-True ($refused[0].Exception.Message -clike '*Upgrade tmux and restart the tmux server*') "$($answer.Name) was refused without saying what to do"
        Assert-True ($refused[0].CategoryInfo.Category -ceq 'NotImplemented') "$($answer.Name) was not reported as unimplemented"
        Assert-True ($refused[0].ToString() -clike '*install LibTmux 0.1.0-alpha2*' -and $refused[0].ToString() -cnotlike '*alpha.21*') "$($answer.Name) was refused without naming an installable release"
    }
    Write-Host 'VersionCheck: pre-3.2 answers refused promptly'

    # A real 3.0a or 3.1c daemon behind this newer client: the lane names the release it must run.
    if ($env:LIBTMUX_OLD_DAEMON) {
        Assert-True ($supported) 'the old-daemon lane needs a client at or above the floor'
        $oldVersion = (& $env:LIBTMUX_OLD_DAEMON -V)
        Assert-True ($oldVersion -ceq "tmux $env:LIBTMUX_REQUIRE_OLD_DAEMON") "the old-daemon lane expected tmux $env:LIBTMUX_REQUIRE_OLD_DAEMON but found $oldVersion"
        $oldSocket = Join-Path $fixture.DirectoryPath 'old-daemon'
        $oldStart = [Diagnostics.ProcessStartInfo]::new($env:LIBTMUX_OLD_DAEMON)
        $oldStart.UseShellExecute = $false
        $oldStart.RedirectStandardOutput = $true
        $oldStart.RedirectStandardError = $true
        $null = $oldStart.Environment.Remove('TMUX')
        $oldStart.Environment['SHELL'] = '/bin/sh'
        foreach ($argument in @('-S', $oldSocket, '-f', '/dev/null', 'new-session', '-d', '-s', 'old', 'exec /bin/sleep 600')) { $oldStart.ArgumentList.Add($argument) }
        $oldProcess = [Diagnostics.Process]::Start($oldStart)
        try {
            $null = $oldProcess.WaitForExit(5000)
            $deadline = [DateTime]::UtcNow.AddSeconds(5)
            while (-not (Test-Path -LiteralPath $oldSocket) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
            Assert-True (Test-Path -LiteralPath $oldSocket) "the tmux $env:LIBTMUX_REQUIRE_OLD_DAEMON daemon did not start"
            $oldServer = New-TmuxServer -SocketPath $oldSocket -TmuxBinaryPath $fixture.TmuxPath
            $outcome = Invoke-BoundedRead $oldServer "tmux $env:LIBTMUX_REQUIRE_OLD_DAEMON"
            $refused = @(Get-Refusals $outcome.Errors)
            Assert-True ($outcome.Rows -eq 0 -and $refused.Count -eq 1) "the tmux $env:LIBTMUX_REQUIRE_OLD_DAEMON daemon was not refused as a version failure"
            Assert-True ($refused[0].Exception.ActualVersion -le [LibTmux.TmuxVersion]::Parse($env:LIBTMUX_REQUIRE_OLD_DAEMON)) 'the refusal named a release newer than the daemon'
            Write-Host "VersionCheck: tmux $env:LIBTMUX_REQUIRE_OLD_DAEMON daemon refused promptly by a newer client"
        } finally {
            if (-not $oldProcess.HasExited) { $oldProcess.Kill($true) }
            $oldProcess.Dispose()
            $null = & $env:LIBTMUX_OLD_DAEMON -S $oldSocket kill-server 2>$null
        }
        return
    }

    if (-not $supported) {
        # A client that claims to be newer must not qualify an older daemon.
        $lying = New-Wrapper $bin 'tmux' $fixture.TmuxPath 'if [ "$1" = "-V" ]; then echo "tmux 9.9"; exit 0; fi'
        $absent = Join-Path $fixture.DirectoryPath 'absent'
        $null = Invoke-OwnedTmux $fixture -Arguments @('set-option', '-g', '@sentinel', 'kept')
        $null = Invoke-OwnedTmux $fixture -Arguments @('set-buffer', '-b', 'sentinel', 'kept')
        # Every operation below holds a server, so each must reach the package's check. Discovery
        # operations never start a daemon: on an absent endpoint they report the missing daemon.
        $chain = New-TmuxCommand -Name 'new-session' -Arguments @('-d', '-s', 'sentinel', 'exec /bin/sh')
        $operations = @(
            @{ Name = 'Get-TmuxSession'; Discovery = $true; Run = { param($s) $null = $s | Get-TmuxSession -ErrorAction SilentlyContinue -ErrorVariable e; $e } }
            @{ Name = 'Get-TmuxClient'; Discovery = $true; Run = { param($s) $null = $s | Get-TmuxClient -ErrorAction SilentlyContinue -ErrorVariable e; $e } }
            @{ Name = 'Get-TmuxHook'; Discovery = $false; Run = { param($s) $null = $s | Get-TmuxHook -ErrorAction SilentlyContinue -ErrorVariable e; $e } }
            @{ Name = 'Get-TmuxSnapshot'; Discovery = $true; Run = { param($s) $null = $s | Get-TmuxSnapshot -ErrorAction SilentlyContinue -ErrorVariable e; $e } }
            @{ Name = 'Connect-TmuxControl'; Discovery = $true; Run = { param($s)
                $control = $s | Connect-TmuxControl -Target fixture -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable e
                if ($control) { $null = $control.DisposeAsync().AsTask().GetAwaiter().GetResult() }
                $e } }
            @{ Name = 'New-TmuxSession'; Discovery = $false; Run = { param($s) $null = $s | New-TmuxSession -Name sentinel -Command 'exec /bin/sh' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable e; $e } }
            @{ Name = 'Set-TmuxOption'; Discovery = $false; Run = { param($s) $null = $s | Set-TmuxOption -Name '@sentinel' -Value changed -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable e; $e } }
            @{ Name = 'Set-TmuxEnvironment'; Discovery = $false; Run = { param($s) $null = $s | Set-TmuxEnvironment -Name LIBTMUX_SENTINEL -Value set -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable e; $e } }
            @{ Name = 'Wait-TmuxChannel'; Discovery = $false; Run = { param($s) $null = $s | Wait-TmuxChannel -Channel sentinel-channel -Timeout 1 -ErrorAction SilentlyContinue -ErrorVariable e; $e } }
            @{ Name = 'Invoke-TmuxCommand'; Discovery = $false; Run = { param($s) $null = $s | Invoke-TmuxCommand -Arguments @('new-session', '-d', '-s', 'sentinel', 'exec /bin/sh') -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable e; $e } }
            @{ Name = 'Invoke-TmuxChain'; Discovery = $false; Run = { param($s) $null = $s | Invoke-TmuxChain -Command $chain -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable e; $e } }
        )
        $missed = [Collections.Generic.List[string]]::new()
        foreach ($case in @(
            @{ Name = 'live daemon'; Path = $fixture.SocketPath; Binaries = @($fixture.TmuxPath, $lying) },
            @{ Name = 'absent endpoint'; Path = $absent; Binaries = @($fixture.TmuxPath) }
        )) {
            foreach ($binary in $case.Binaries) {
                $label = "$($case.Name) via $(if ($binary -ceq $lying) { 'newer-reporting' } else { 'native' }) client"
                $server = New-TmuxServer -SocketPath $case.Path -TmuxBinaryPath $binary
                foreach ($operation in $operations) {
                    $errors = @(& $operation.Run $server)
                    $refusals = @(Get-Refusals $errors)
                    if ($case.Name -ceq 'absent endpoint' -and $operation.Discovery) {
                        $ok = $errors.Count -eq 1 -and $errors[0].Exception -is [LibTmux.TmuxCommandException] -and
                            $errors[0].Exception.Message -clike '*server generation discovery failed*' -and
                            $errors[0].Exception.Message.Contains($case.Path)
                    } else {
                        $ok = $errors.Count -eq 1 -and $refusals.Count -eq 1 -and
                            $refusals[0].CategoryInfo.Category -ceq 'NotImplemented' -and
                            $refusals[0].ToString() -clike '*install LibTmux 0.1.0-alpha2*' -and $refusals[0].ToString() -cnotlike '*alpha.21*'
                    }
                    if (-not $ok) { $missed.Add("$($operation.Name) for $label") }
                }
            }
        }
        Assert-True ($missed.Count -eq 0) "operations were not refused as expected: $($missed -join '; ')"

        # Objects captured while a daemon looked supported must refuse once it is replaced by a daemon
        # below the floor: the double claims 3.4, which keeps the library off control mode, and passes the guard until the flip, then tells the truth.
        Import-Module (Join-Path $ModuleRoot 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1')
        $flipped = Join-Path $fixture.DirectoryPath 'flipped-below'
        $hostMarker = Join-Path $fixture.DirectoryPath 'host-script-ran'
        $below = New-Wrapper $bin 'tmux-below' $fixture.TmuxPath @"
if [ ! -e '$flipped' ]; then
    for arg; do
        shift
        case "`$arg" in
        libtmux-version-*'#{version},#{pid}'*) arg=`$(printf %s "`$arg" | sed 's/#{version}/3.4/');;
        *'#{==:#{version},3.4}'*) arg=`$(printf %s "`$arg" | sed 's/3\.4/$($binaryVersion.Raw)/');;
        esac
        set -- "`$@" "`$arg"
    done
fi
"@
        $believing = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $below
        $pane = @(($believing | Get-TmuxSnapshot -Depth Panes).Panes)[0]
        $source = Join-Path $fixture.DirectoryPath 'replaced.yaml'
        "session_name: replaced-below`nbefore_script: printf ran > '$hostMarker'`nwindows:`n  - panes:`n      - echo ready`n" | Set-Content -LiteralPath $source
        $workspace = (Import-TmuxWorkspace -LiteralPath $source).Resolve($fixture.DirectoryPath, $null)
        $plan = $workspace | Get-TmuxWorkspacePlan -Server $believing -AllowHostScripts
        Assert-True ($null -ne $pane -and $plan -is [LibTmux.Workspace.WorkspacePlan]) 'the double did not let a pane and a plan be captured'
        $null = New-Item -ItemType File $flipped
        $replacedOperations = @(
            @{ Name = 'Wait-TmuxPaneText'; Run = { $null = $pane | Wait-TmuxPaneText -Pattern 'never' -Timeout 1 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable e; $e } }
            @{ Name = 'Invoke-TmuxWorkspace'; Run = { $null = $plan | Invoke-TmuxWorkspace -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable e; $e } }
        )
        foreach ($operation in $replacedOperations) {
            $errors = @(& $operation.Run)
            $refusals = @($errors | Where-Object { $_.Exception -is [LibTmux.TmuxVersionTooLowException] -or $_.Exception.InnerException -is [LibTmux.TmuxVersionTooLowException] })
            Assert-True ($errors.Count -eq 1 -and $refusals.Count -eq 1 -and $refusals[0].CategoryInfo.Category -ceq 'NotImplemented' -and
                $refusals[0].ToString() -clike '*install LibTmux 0.1.0-alpha2*') "$($operation.Name) was not refused after the daemon was replaced by one below the floor"
        }
        Assert-True (-not (Test-Path -LiteralPath $hostMarker)) 'a refused workspace ran its host script'
        Assert-True ((Get-NativeSessions $fixture) -ceq 'fixture') 'a refused operation changed the live daemon'
        Assert-True ((Invoke-OwnedTmux $fixture -AllowFailure -Arguments @('show-environment', '-g', 'LIBTMUX_SENTINEL')).ExitCode -ne 0) 'a refused operation set an environment variable'
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
    # A new handle has not been checked yet, so its first command runs the probe with the hooks armed.
    # Typed reads fire display-message hooks themselves; raw dispatch isolates version check.
    $unchecked = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $null = $unchecked | Invoke-TmuxCommand -Arguments @('list-sessions')
    $null = $unchecked | Invoke-TmuxChain -Command (New-TmuxCommand -Name 'list-sessions')
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

    # A daemon replaced after the version check fails the fence before any command runs. The double
    # reports a release the real daemon is not, so every recheck disagrees with the fence as well.
    $replaced = New-Wrapper $bin 'tmux-replaced' $fixture.TmuxPath @"
case "`$*" in
*"run-shell -C libtmux-version-"*)
$(Get-ProbeAnswer '9.9');;
esac
"@
    $lagging = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $replaced
    $errors = @()
    $null = $lagging | Invoke-TmuxCommand -Arguments @('new-session', '-d', '-s', 'fenced', 'exec /bin/sh') `
        -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True ($errors.Count -eq 1 -and $errors[0].Exception -is [LibTmux.TmuxTransportException] -and
        $errors[0].Exception.Message -clike '*changed*' -and $errors[0].Exception.Dispatch -eq 'NotDispatched') 'a replaced daemon passed the command fence'
    Assert-True (-not (Test-NativeSession $fixture 'fenced')) 'the fenced command took effect'
    $errors = @()
    $chain = New-TmuxCommand -Name 'new-session' -Arguments @('-d', '-s', 'fenced', 'exec /bin/sh')
    $null = $lagging | Invoke-TmuxChain -Command $chain -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True ($errors.Count -eq 1 -and $errors[0].Exception.Message -clike '*changed*') 'a replaced daemon passed the chain fence'
    Assert-True (-not (Test-NativeSession $fixture 'fenced')) 'the fenced chain took effect'
    $pass = New-Wrapper $bin 'tmux-pass' $fixture.TmuxPath ''
    $null = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $pass |
        Invoke-TmuxCommand -Arguments @('new-session', '-d', '-s', 'fenced', 'exec /bin/sh')
    Assert-True (Test-NativeSession $fixture 'fenced') 'the fence refused an unchanged daemon'

    # A replacement below the floor is refused: the recheck after a failed fence reads an older daemon.
    $flipState = Join-Path $fixture.DirectoryPath 'flipped'
    $flip = New-Wrapper $bin 'tmux-flip' $fixture.TmuxPath @"
case "`$*" in
*"run-shell -C libtmux-version-"*)
    version=9.9
    if [ -e '$flipState' ]; then version=3.2a; fi
    : > '$flipState'
$(Get-ProbeAnswer '$version');;
esac
"@
    $errors = @()
    $null = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $flip |
        Invoke-TmuxCommand -Arguments @('new-session', '-d', '-s', 'flipped', 'exec /bin/sh') `
            -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True (@(Get-Refusals $errors).Count -eq 1 -and $errors[0].Exception.ActualVersion.Raw -ceq '3.2a' -and $errors[0].Exception.Dispatch -eq 'NotDispatched') 'a replacement below the floor was not refused'
    Assert-True (-not (Test-NativeSession $fixture 'flipped')) 'a command ran behind a refused replacement'

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
            $reporting = New-Wrapper $bin ('tmux-reporting-' + [Guid]::NewGuid().ToString('N')) $fixture.TmuxPath @"
case "`$*" in
*"run-shell -C libtmux-version-"*)
$(Get-ProbeAnswer '$LIBTMUX_VERSION_REPORT');;
esac
"@
            $probe = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $reporting
            $errors = @()
            $read = @($probe | Invoke-TmuxCommand -Arguments @('list-sessions') -ErrorAction SilentlyContinue -ErrorVariable errors)
            # A release the real daemon is not reaches the fence and fails there; only a refusal means the report was rejected.
            $refused = @(Get-Refusals $errors).Count -eq 1
            Assert-True ($refused -eq (-not $entry.Value) -and ($entry.Value -or $read.Count -eq 0)) "daemon report '$($entry.Key)' should be checked: $($entry.Value)"
        } finally {
            Remove-Item Env:LIBTMUX_VERSION_REPORT -ErrorAction Ignore
        }
    }

    # One probe checks a server handle; later operations on it reuse the answer.
    $probeLog = Join-Path $fixture.DirectoryPath 'probes.log'
    $counted = New-Wrapper $bin 'tmux-counted' $fixture.TmuxPath @"
case "`$*" in
*"run-shell -C libtmux-version-"*) echo probe >> '$probeLog';;
esac
"@
    $cachedServer = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $counted
    foreach ($index in 1..3) { $null = $cachedServer | Invoke-TmuxCommand -Arguments @('list-sessions') }
    $null = $cachedServer | Invoke-TmuxChain -Command (New-TmuxCommand -Name 'list-sessions')
    Assert-True (@(Get-Content -LiteralPath $probeLog).Count -eq 1) "operations on one server handle probed more than once: $(@(Get-Content -LiteralPath $probeLog).Count)"

    # A replaced daemon that is supported is checked again and the command still runs, once.
    $state = Join-Path $fixture.DirectoryPath 'swapped'
    $swapLog = Join-Path $fixture.DirectoryPath 'swap-probes.log'
    $actual = $binaryVersion.Raw
    $swapped = New-Wrapper $bin 'tmux-swapped' $fixture.TmuxPath @"
case "`$*" in
*"run-shell -C libtmux-version-"*)
    echo probe >> '$swapLog'
    if [ ! -e '$state' ]; then
        : > '$state'
$(Get-ProbeAnswer '9.9')
    fi;;
esac
"@
    $swappedServer = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $swapped
    $again = $swappedServer | Invoke-TmuxCommand -Arguments @('list-sessions')
    Assert-True ($again.ExitCode -eq 0 -and @(Get-Content -LiteralPath $swapLog).Count -eq 2) 'a supported replacement was not checked again before the command ran'

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
    # A read on a supported executable reports the same missing-daemon error the rejection lanes see.
    $errors = @()
    $null = $gone | Get-TmuxSession -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True ($errors.Count -eq 1 -and $errors[0].Exception -is [LibTmux.TmuxCommandException] -and
        $errors[0].Exception.Message -clike '*server generation discovery failed*' -and
        $errors[0].Exception.Message.Contains($gone.ConnectionOptions.SocketPath)) 'a read on an absent endpoint did not report the missing daemon'

    # The package checks the daemon before it attaches a control client, so a connection carries a
    # checked daemon. Control clients crash older servers, so this runs only where they are routine.
    if ($binaryVersion -ge [LibTmux.TmuxVersion]::Parse('3.7')) {
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
        Assert-True ($cmdletPath -le $baseline) "control version check fired hooks: package attach $baseline, cmdlet path $cmdletPath"
        Remove-Item -LiteralPath $controlLog -ErrorAction Ignore
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
        Write-Host 'VersionCheck: SKIPPED control connection (control clients need tmux 3.7)'
    }

    # A daemon that vanishes after the version check is not restarted under that answer: the fenced
    # client starts none, and the command is sent again only after the endpoint is checked afresh.
    $second = Join-Path $fixture.DirectoryPath 'vanish.sock'
    $null = & $fixture.TmuxPath -S $second -f /dev/null new-session -d -s keep 'exec /bin/sh'
    $vanishState = Join-Path $fixture.DirectoryPath 'vanished'
    $vanishLog = Join-Path $fixture.DirectoryPath 'vanish-probes.log'
    $vanish = New-Wrapper $bin 'tmux-vanish' $fixture.TmuxPath @"
case "`$*" in
*"run-shell -C libtmux-version-"*) echo probe >> '$vanishLog';;
*"if-shell -F"*)
    if [ ! -e '$vanishState' ]; then
        : > '$vanishState'
        '$($fixture.TmuxPath)' -S '$second' kill-server
        sleep 0.3
    fi;;
esac
"@
    $vanished = New-TmuxServer -SocketPath $second -TmuxBinaryPath $vanish
    $null = $vanished | Invoke-TmuxCommand -Arguments @('new-session', '-d', '-s', 'revived', 'exec /bin/sh')
    Assert-True (@(Get-Content -LiteralPath $vanishLog).Count -eq 2) 'a vanished daemon was not checked again before the command was sent again'
    $null = & $fixture.TmuxPath -S $second -f /dev/null has-session -t '=revived' 2>$null
    Assert-True ($LASTEXITCODE -eq 0) 'the command was not sent again after the endpoint was checked afresh'
    $null = & $fixture.TmuxPath -S $second kill-server 2>$null

    # An absent endpoint is checked from the executable's own banner, which 3.3a prefixes with the
    # file name it was run as; a renamed executable still starts a daemon.
    $renamed = Join-Path $bin 'tmux-renamed'
    $null = [IO.File]::CreateSymbolicLink($renamed, $fixture.TmuxPath)
    $absent = Join-Path $fixture.DirectoryPath 'renamed.sock'
    $cold = New-TmuxServer -SocketPath $absent -TmuxBinaryPath $renamed
    $null = $cold | Invoke-TmuxCommand -Arguments @('new-session', '-d', '-s', 'cold', 'exec /bin/sh')
    $null = & $fixture.TmuxPath -S $absent -f /dev/null has-session -t '=cold'
    Assert-True ($LASTEXITCODE -eq 0) 'an absent endpoint was not checked through a renamed executable'
    $null = & $fixture.TmuxPath -S $absent -f /dev/null kill-server
    Write-Host 'VersionCheck: supported daemon checked, hook-free, fenced'
}
