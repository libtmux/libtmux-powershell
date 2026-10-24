param([Parameter(Mandatory)] [string] $ModuleRoot)

# Integration: optional features are refused per operation, before any effect.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')
Import-Module (Join-Path $ModuleRoot 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw "Features: $Message" }
}

# A wrapper that claims a daemon version to the package's version probe and passes everything else
# through. The probe and the guard on later batches each carry the version in one argument; the
# guard is pointed back at the real version so the batch is not mistaken for a replaced daemon.
function New-ClaimingWrapper([string] $Directory, [string] $Real, [string] $Claim, [string] $RealVersion) {
    $path = Join-Path $Directory ('tmux-' + [Guid]::NewGuid().ToString('N'))
    $quoted = "'" + $Real.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
for arg; do
    shift
    case "`$arg" in
    libtmux-version-*'#{version},#{pid}'*) arg=`$(printf %s "`$arg" | sed 's/#{version}/$Claim/');;
    '#{==:#{version},$Claim}') arg='#{==:#{version},$RealVersion}';;
    esac
    set -- "`$@" "`$arg"
done
exec $quoted "`$@"
"@ | Set-Content -LiteralPath $path -NoNewline
    [IO.File]::SetUnixFileMode($path, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $path
}

function Get-Refusal($Errors, [string] $Required) {
    @($Errors | Where-Object {
        $_.Exception -is [LibTmux.TmuxVersionTooLowException] -and
        $_.Exception.RequiredVersion.Raw -ceq $Required })
}

# The package refuses a release defect with TmuxVersionTooLowException and a name that exactly 3.7
# rejects with ArgumentException; both leave before anything is sent.
function Test-Refused($Errors, [string] $Required, [bool] $Name) {
    if ($Name) {
        return @($Errors | Where-Object { $_.Exception -is [ArgumentException] -and $_.Exception.Message -clike "*rejects ':' and '.'*" }).Count -eq 1
    }
    return @(Get-Refusal $Errors $Required).Count -eq 1
}

$tmux = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$null = (& $tmux -V) -match '^\S+ (\S+)$'
$version = [LibTmux.TmuxVersion]::Parse($Matches[1])
$realRaw = $version.Raw
$control = $version -ge [LibTmux.TmuxVersion]::Parse('3.7')
$buffers = $version -ge [LibTmux.TmuxVersion]::Parse('3.4')
Write-Host "Features: tmux ${realRaw}: control=$control, named buffers=$buffers"

Invoke-WithOwnedTmux {
    param($fixture)
    $bin = Join-Path $fixture.DirectoryPath 'bin'
    $null = New-Item -ItemType Directory $bin
    $server = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $session = $server | Get-TmuxSession -Name fixture
    $pane = $session | Get-TmuxPane | Select-Object -First 1

    function Get-ClientCount { @((Invoke-OwnedTmux $fixture -Arguments @('list-clients', '-F', '#{client_name}')).StdOut.Split("`n", [StringSplitOptions]::RemoveEmptyEntries)).Count }
    function Get-Topology { (Invoke-OwnedTmux $fixture -Arguments @('list-panes', '-a', '-F', '#{session_id}|#{window_id}|#{window_name}|#{pane_id}')).StdOut }

    # Control acquisition: refused below 3.7 before any client attaches, operative from 3.7.
    $errors = @()
    $connection = $server | Connect-TmuxControl -Target fixture -ErrorAction SilentlyContinue -ErrorVariable errors
    if ($control) {
        Assert-True ($null -ne $connection -and $errors.Count -eq 0) 'Connect-TmuxControl was refused on a 3.7 daemon'
        $connection | Disconnect-TmuxControl
    } else {
        Assert-True ($null -eq $connection -and @(Get-Refusal $errors '3.7').Count -eq 1) 'Connect-TmuxControl was not refused below 3.7'
    }
    $errors = @()
    $events = @($server | Watch-TmuxEvent -Target fixture -MaxEvents 1 -ErrorAction SilentlyContinue -ErrorVariable errors)
    if ($control) {
        Assert-True ($errors.Count -eq 0) 'Watch-TmuxEvent was refused on a 3.7 daemon'
    } else {
        Assert-True ($events.Count -eq 0 -and @(Get-Refusal $errors '3.7').Count -eq 1) 'Watch-TmuxEvent was not refused below 3.7'
    }
    Assert-True ((Get-ClientCount) -eq 0) 'a control client remains attached'
    Assert-True ((Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid}')).StdOut.Trim() -ceq [string] $fixture.ServerPid) 'the daemon changed during control refusals'

    # A pane text wait is never refused: below 3.7 it polls and attaches no control client.
    $errors = @()
    $wait = @($pane | Wait-TmuxPaneText -Pattern 'never-printed' -Timeout 0.2 -ErrorAction SilentlyContinue -ErrorVariable errors)
    Assert-True ($errors.Count -eq 0 -and $wait.Count -eq 1 -and
        $wait[0].Outcome -eq [LibTmux.PaneWaitOutcome]::TimedOut -and $wait[0].PollingFallback -eq (-not $control)) 'Wait-TmuxPaneText did not time out cleanly'
    Assert-True ((Get-ClientCount) -eq 0) 'a pane text wait left a client attached'

    # Subprocess operations keep working at the floor.
    $reply = $server | Invoke-TmuxCommand -Arguments @('display-message', '-p', 'subprocess')
    Assert-True ($reply.StandardOutputLines -ccontains 'subprocess') 'a subprocess command failed at the floor'

    # Named buffers: a pane run stages one, and explicit delete or rename is unsafe below 3.4.
    $null = Invoke-OwnedTmux $fixture -Arguments @('set-buffer', '-b', 'keep', 'sentinel')
    $errors = @()
    $run = $pane | Invoke-TmuxPaneCommand -Command 'true' -Timeout 5 -ErrorAction SilentlyContinue -ErrorVariable errors
    if ($buffers) {
        Assert-True ($null -ne $run -and $errors.Count -eq 0) 'Invoke-TmuxPaneCommand was refused on a 3.4 or newer daemon'
    } else {
        Assert-True ($null -eq $run -and @(Get-Refusal $errors '3.4').Count -eq 1) 'Invoke-TmuxPaneCommand was not refused below 3.4'
    }
    foreach ($arguments in @(
        @('delete-buffer', '-b', 'missing'),
        @('deleteb', '-bmissing'),
        @('set-buffer', '-b', 'missing', '-n', 'renamed')
    )) {
        $errors = @()
        $null = $server | Invoke-TmuxCommand -Arguments $arguments -ErrorAction SilentlyContinue -ErrorVariable errors
        if ($buffers) {
            Assert-True (@(Get-Refusal $errors '3.4').Count -eq 0 -and $errors.Count -eq 1 -and
                $errors[0].Exception -is [LibTmux.TmuxCommandException]) "$($arguments -join ' ') was refused on a 3.4 or newer daemon"
        } else {
            Assert-True (@(Get-Refusal $errors '3.4').Count -eq 1) "$($arguments -join ' ') was not refused below 3.4"
        }
    }
    Assert-True ((Invoke-OwnedTmux $fixture -Arguments @('list-buffers', '-F', '#{buffer_name}')).StdOut.Trim() -ceq 'keep') 'a buffer was created or removed'
    $errors = @()
    $null = $server | Invoke-TmuxCommand -Arguments @('delete-buffer') -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True (@(Get-Refusal $errors '3.4').Count -eq 0) 'delete-buffer without a name was refused'
    $null = Invoke-OwnedTmux $fixture -Arguments @('set-buffer', '-b', 'keep', 'sentinel') -AllowFailure

    # The release defects, on the daemon itself where it is the release that has them.
    $topology = Get-Topology
    $splitBroken = $version -eq [LibTmux.TmuxVersion]::Parse('3.4')
    $errors = @()
    $null = $server | Invoke-TmuxCommand -Arguments @('split-window', '-d', '-p', '30') -ErrorAction SilentlyContinue -ErrorVariable errors
    if ($splitBroken) {
        Assert-True (@(Get-Refusal $errors '3.5').Count -eq 1 -and (Get-Topology) -ceq $topology) 'split-window -p was not refused on tmux 3.4'
    } else {
        Assert-True (@(Get-Refusal $errors '3.5').Count -eq 0) 'split-window -p was refused away from tmux 3.4'
        $null = Invoke-OwnedTmux $fixture -Arguments @('kill-pane', '-a', '-t', 'fixture:0.0') -AllowFailure
    }
    $exact37 = $version -eq [LibTmux.TmuxVersion]::Parse('3.7')
    if ($exact37) {
        $null = Invoke-OwnedTmux $fixture -Arguments @('split-window', '-d', '-t', 'fixture:0')
        $topology = Get-Topology
        $errors = @()
        $null = $server | Invoke-TmuxCommand -Arguments @('break-pane', '-d', '-s', 'fixture:0.1') -ErrorAction SilentlyContinue -ErrorVariable errors
        Assert-True (@(Get-Refusal $errors '3.7a').Count -eq 1 -and (Get-Topology) -ceq $topology -and
            (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid}')).StdOut.Trim() -ceq [string] $fixture.ServerPid) `
            'a nameless break-pane reached the real tmux 3.7 daemon'
    }

    # Releases that cannot be run here are claimed to the version probe: the refusal needs no dispatch.
    $cases = @(
        @{ Claim = '3.7'; Arguments = @('break-pane', '-d', '-s', '%0'); Required = '3.7a' },
        @{ Claim = '3.7'; Arguments = @('breakp', '-d'); Required = '3.7a' },
        @{ Claim = '3.7'; Arguments = @('new-window', '-n', 'a.b'); Name = $true; Required = '3.7a' },
        @{ Claim = '3.7'; Arguments = @('neww', '-n', 'a:b'); Name = $true; Required = '3.7a' },
        @{ Claim = '3.7'; Arguments = @('new-session', '-d', '-s', 'ok', '-n', 'x.y'); Name = $true; Required = '3.7a' },
        @{ Claim = '3.7'; Arguments = @('rename-window', '-t', '@0', 'c.d'); Name = $true; Required = '3.7a' },
        @{ Claim = '3.7'; Arguments = @('rename-session', 'e:f'); Name = $true; Required = '3.7a' },
        @{ Claim = '3.3a'; Arguments = @('refresh-client', '-l'); Required = '3.6a' },
        @{ Claim = '3.4'; Arguments = @('refresh', '-lt', 'nosuch'); Required = '3.6a' },
        @{ Claim = '3.4'; Arguments = @('split-window', '-p', '30'); Required = '3.5' },
        @{ Claim = '3.4'; Arguments = @('splitw', '-dp30'); Required = '3.5' }
    )
    $topology = Get-Topology
    foreach ($case in $cases) {
        $claiming = New-ClaimingWrapper $bin $fixture.TmuxPath $case.Claim $realRaw
        $claimed = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $claiming
        foreach ($route in @('command', 'chain')) {
            $errors = @()
            if ($route -eq 'command') {
                $null = $claimed | Invoke-TmuxCommand -Arguments $case.Arguments -ErrorAction SilentlyContinue -ErrorVariable errors
            } else {
                $null = $claimed | Invoke-TmuxChain -Command (New-TmuxCommand -Name $case.Arguments[0] -Arguments $case.Arguments[1..($case.Arguments.Count - 1)]) `
                    -ErrorAction SilentlyContinue -ErrorVariable errors
            }
            Assert-True (Test-Refused $errors $case.Required ($case.ContainsKey("Name"))) `
                "$($case.Arguments -join ' ') was not refused by $route on a claimed $($case.Claim)"
        }
    }
    Assert-True ((Get-Topology) -ceq $topology) 'a refused command changed the topology'

    # The safe forms of the same commands are not stopped by a feature guard.
    foreach ($case in @(
        @{ Claim = '3.7'; Arguments = @('break-pane', '-d', '-n', 'named', '-s', 'fixture:9.9') },
        @{ Claim = '3.7'; Arguments = @('new-window', '-d', '-n', 'plain', '-t', 'nosuch:') },
        @{ Claim = '3.6a'; Arguments = @('refresh-client', '-l', '-t', 'nosuch') },
        @{ Claim = '3.4'; Arguments = @('refresh-client', '-t', 'nosuch') },
        @{ Claim = '3.4'; Arguments = @('split-window', '-d', '-l', '30%', '-t', 'nosuch:') },
        @{ Claim = '3.5'; Arguments = @('split-window', '-d', '-p', '30', '-t', 'nosuch:') }
    )) {
        $claiming = New-ClaimingWrapper $bin $fixture.TmuxPath $case.Claim $realRaw
        $claimed = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $claiming
        $errors = @()
        $null = $claimed | Invoke-TmuxCommand -Arguments $case.Arguments -ErrorAction SilentlyContinue -ErrorVariable errors
        Assert-True ($errors.Count -eq 0 -or @($errors | Where-Object { $_.Exception -is [LibTmux.TmuxVersionTooLowException] -or $_.Exception -is [ArgumentException] }).Count -eq 0) `
            "$($case.Arguments -join ' ') was refused by a feature guard on a claimed $($case.Claim)"
    }
    Assert-True ((Get-Topology) -ceq $topology) 'a command aimed at a missing target changed the topology'

    # A layout string that is not checksummed crashes releases below 3.4; the package refuses it before sending.
    if ($version -lt [LibTmux.TmuxVersion]::Parse('3.4')) {
        $window = $session | Get-TmuxWindow | Select-Object -First 1
        $before = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $window.Id, '#{window_layout}')).StdOut
        $errors = @()
        $null = $window | Set-TmuxLayout -Layout 'bogus-layout' -ErrorAction SilentlyContinue -ErrorVariable errors
        Assert-True ($errors.Count -eq 1 -and $errors[0].Exception -is [LibTmux.TmuxWindowException] -and
            (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid}')).StdOut.Trim() -ceq [string] $fixture.ServerPid -and
            (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $window.Id, '#{window_layout}')).StdOut -ceq $before) `
            'Set-TmuxLayout sent a layout that releases below 3.4 crash on'
    }

    # The same layout sent as a literal command: below 3.4 the package refuses it with ArgumentException,
    # not TmuxVersionTooLowException, and from 3.4 tmux answers the unknown layout itself.
    $window = $session | Get-TmuxWindow | Select-Object -First 1
    $before = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $window.Id, '#{window_layout}')).StdOut
    foreach ($arguments in @(@('select-layout', '-t', $window.Id, 'bogus'), @('selectl', 'bogus'))) {
        foreach ($route in @('command', 'chain')) {
            $errors = @()
            if ($route -eq 'command') {
                $null = $server | Invoke-TmuxCommand -Arguments $arguments -ErrorAction SilentlyContinue -ErrorVariable errors
            } else {
                $null = $server | Invoke-TmuxChain -Command (New-TmuxCommand -Name $arguments[0] -Arguments $arguments[1..($arguments.Count - 1)]) `
                    -ErrorAction SilentlyContinue -ErrorVariable errors
            }
            if ($version -lt [LibTmux.TmuxVersion]::Parse('3.4')) {
                Assert-True ($errors.Count -eq 1 -and $errors[0].Exception -is [ArgumentException] -and
                    $errors[0].Exception.Message -clike '*crashes on the layout*') "$($arguments -join ' ') was not refused with ArgumentException by $route"
            } else {
                Assert-True ($errors.Count -eq 1 -and $errors[0].Exception -is [LibTmux.TmuxCommandException]) `
                    "$($arguments -join ' ') was not answered by tmux itself through $route"
            }
            Assert-True ((Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid}')).StdOut.Trim() -ceq [string] $fixture.ServerPid -and
                (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $window.Id, '#{window_layout}')).StdOut -ceq $before) `
                "$($arguments -join ' ') through $route changed the daemon or the window"
        }
    }

    # A command list is read one command at a time: a refused command stops the whole list, so the
    # commands before it do not run either, and the same list without one runs both. A chain is a list,
    # and so is a ';' word in the arguments of Invoke-TmuxCommand.
    foreach ($case in @(
        @{ Claim = '3.7'; Refused = @('break-pane', '-d'); Required = '3.7a' },
        @{ Claim = '3.4'; Refused = @('refresh', '-l'); Required = '3.6a' },
        @{ Claim = '3.3a'; Refused = @('deleteb', '-b', 'missing'); Required = '3.4' }
    )) {
        $claiming = New-ClaimingWrapper $bin $fixture.TmuxPath $case.Claim $realRaw
        $claimed = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $claiming
        $first = @('set-option', '-g', '@listrun', 'ran')
        foreach ($route in @('chain', 'command')) {
            $null = Invoke-OwnedTmux $fixture -Arguments @('set-option', '-gu', '@listrun') -AllowFailure
            $errors = @()
            if ($route -eq 'chain') {
                $null = $claimed | Invoke-TmuxChain -ErrorAction SilentlyContinue -ErrorVariable errors -Command @(
                    (New-TmuxCommand -Name $first[0] -Arguments $first[1..($first.Count - 1)]),
                    (New-TmuxCommand -Name $case.Refused[0] -Arguments $case.Refused[1..($case.Refused.Count - 1)]))
            } else {
                $null = $claimed | Invoke-TmuxCommand -Arguments ($first + @(';') + $case.Refused) -ErrorAction SilentlyContinue -ErrorVariable errors
            }
            $ran = (Invoke-OwnedTmux $fixture -Arguments @('show-options', '-gqv', '@listrun')).StdOut.Trim()
            Assert-True (@(Get-Refusal $errors $case.Required).Count -eq 1 -and $ran -ceq '') `
                "a $route list holding $($case.Refused -join ' ') ran its first command on a claimed $($case.Claim)"
        }
        $null = Invoke-OwnedTmux $fixture -Arguments @('set-option', '-gu', '@listrun') -AllowFailure
        $errors = @()
        $null = $claimed | Invoke-TmuxChain -ErrorAction SilentlyContinue -ErrorVariable errors -Command @(
            (New-TmuxCommand -Name $first[0] -Arguments $first[1..($first.Count - 1)]),
            (New-TmuxCommand -Name display-message -Arguments @('-p', 'tail')))
        $ran = (Invoke-OwnedTmux $fixture -Arguments @('show-options', '-gqv', '@listrun')).StdOut.Trim()
        Assert-True ($errors.Count -eq 0 -and $ran -ceq 'ran') "a chain of safe commands did not run on a claimed $($case.Claim)"
    }
    $null = Invoke-OwnedTmux $fixture -Arguments @('set-option', '-gu', '@listrun') -AllowFailure

    # A typed creation and a workspace plan check names on exactly 3.7 before they send anything.
    $claiming = New-ClaimingWrapper $bin $fixture.TmuxPath '3.7' $realRaw
    $claimed = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $claiming
    $errors = @()
    $created = $claimed | Get-TmuxSession -Name fixture | New-TmuxWindow -Name 'bad.name' -Command 'exec /bin/sh' -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True ($null -eq $created -and @($errors | Where-Object { $_.Exception -is [ArgumentException] -and $_.Exception.Message -clike "*rejects ':' and '.'*" }).Count -eq 1) `
        'New-TmuxWindow did not refuse a name that 3.7 rejects with ArgumentException'
    $errors = @()
    $made = $claimed | New-TmuxSession -Name 'okname' -WindowName 'win.dot' -Command 'exec /bin/sh' -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True ($null -eq $made -and @($errors | Where-Object { $_.Exception -is [ArgumentException] -and $_.Exception.Message -clike "*rejects ':' and '.'*" }).Count -eq 1) `
        'New-TmuxSession did not refuse a window name that 3.7 rejects with ArgumentException'
    # The package itself refuses ':' and '.' in session names, so a plan cannot reach the daemon with one.
    $caught = $null
    try { $null = $claimed | New-TmuxSession -Name 'bad.session' -Command 'exec /bin/sh' } catch { $caught = $_.Exception }
    Assert-True ($caught -is [ArgumentException] -and $caught.ParamName -ceq 'name') `
        'New-TmuxSession did not refuse a session name that 3.7 rejects with ArgumentException'
    $declaration = LibTmux.Workspace\Import-TmuxWorkspace -Yaml @'
session_name: named-workspace
windows:
  - window_name: dotted.window
    panes:
      - shell_command: exec /bin/sh
'@
    $plan = $declaration.Resolve($fixture.DirectoryPath, $null) |
        LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $claimed
    Assert-True ($null -ne $plan) 'the workspace plan could not be prepared on the claimed daemon'
    $errors = @()
    $applied = $plan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True ($null -eq $applied -and @($errors | Where-Object { $_.Exception -is [ArgumentException] -and $_.Exception.Message -clike "*rejects ':' and '.'*" }).Count -eq 1) `
        'Invoke-TmuxWorkspace did not refuse a window name that 3.7 rejects with ArgumentException'
    Assert-True ((Invoke-OwnedTmux $fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Trim() -ceq 'fixture') 'a refused plan or creation changed the sessions'

    # Commands sent over a connection from Connect-TmuxControl carry the same guards; the package
    # checks them.
    if ($control) {
        $connection = $claimed | Connect-TmuxControl -Target fixture
        try {
            foreach ($arguments in @(@('break-pane', '-d'), @('new-window', '-n', 'a.b'))) {
                $errors = @()
                $null = $connection | Invoke-TmuxControlCommand -Command (New-TmuxCommand -Name $arguments[0] -Arguments $arguments[1..($arguments.Count - 1)]) `
                    -ErrorAction SilentlyContinue -ErrorVariable errors
                Assert-True (Test-Refused $errors '3.7a' ($arguments[0] -ceq 'new-window')) "$($arguments -join ' ') crossed a control connection on a claimed 3.7"
            }
            Assert-True ((Get-Topology) -ceq $topology) 'a refused control command changed the topology'
            $named = @($connection | Invoke-TmuxControlCommand -Command (New-TmuxCommand -Name display-message -Arguments @('-p', 'sent')))
            Assert-True ($named -ccontains 'sent') 'an unguarded command did not cross the control connection'
        } finally { $connection | Disconnect-TmuxControl }
    } else {
        Write-Host 'Features: SKIPPED control command guards (control clients need tmux 3.7)'
    }
    Write-Host 'Features: refusals precede effects; supported paths operative'
}
