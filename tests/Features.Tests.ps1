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

function New-Wrapper([string] $Directory, [string] $Name, [string] $Real, [string] $Body) {
    $path = Join-Path $Directory $Name
    $quoted = "'" + $Real.Replace("'", "'\''") + "'"
    "#!/bin/sh`n$Body`nexec $quoted `"`$@`"`n" | Set-Content -LiteralPath $path -NoNewline
    [IO.File]::SetUnixFileMode($path, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $path
}

# A wrapper that reports a chosen daemon version to the version probe and passes everything else through.
function New-ReportingWrapper([string] $Directory, [string] $Real, [string] $Report) {
    New-Wrapper $Directory ('tmux-' + [Guid]::NewGuid().ToString('N')) $Real @"
case "`$*" in
*"run-shell -C libtmux-version-"*)
    for last; do :; done
    printf 'unknown command: %s\n' "`$(printf %s "`$last" | sed 's/#{version}/$Report/')" >&2
    exit 1;;
esac
"@
}

function Get-Refusal($Errors, [string] $Required) {
    @($Errors | Where-Object {
        $_.Exception -is [LibTmux.TmuxVersionTooLowException] -and
        $_.Exception.RequiredVersion.Raw -ceq $Required })
}

$tmux = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$null = (& $tmux -V) -match '^\S+ (\S+)$'
$version = [LibTmux.TmuxVersion]::Parse($Matches[1])
$control = $version -ge [LibTmux.TmuxVersion]::Parse('3.7')
$buffers = $version -ge [LibTmux.TmuxVersion]::Parse('3.4')
Write-Host "Features: tmux $($version.Raw): control=$control, named buffers=$buffers"

Invoke-WithOwnedTmux {
    param($fixture)
    $bin = Join-Path $fixture.DirectoryPath 'bin'
    $null = New-Item -ItemType Directory $bin
    $server = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $session = $server | Get-TmuxSession -Name fixture
    $pane = $session | Get-TmuxPane | Select-Object -First 1

    function Get-ClientCount { @((Invoke-OwnedTmux $fixture -Arguments @('list-clients', '-F', '#{client_name}')).StdOut.Split("`n", [StringSplitOptions]::RemoveEmptyEntries)).Count }

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
    # Waiting polls capture-pane below 3.7 and attaches no control client.
    $errors = @()
    $wait = @($pane | Wait-TmuxPaneText -Pattern 'never-printed' -Timeout 0.3 -ErrorAction SilentlyContinue -ErrorVariable errors)
    Assert-True ($errors.Count -eq 0 -and $wait.Count -eq 1 -and $wait[0].Outcome.ToString() -ceq 'TimedOut') "Wait-TmuxPaneText did not time out cleanly (errors: $($errors.Count))"
    $marker = 'polled-' + [Guid]::NewGuid().ToString('N')
    $null = Invoke-OwnedTmux $fixture -Arguments @('send-keys', '-t', $pane.Id.ToString(), '-l', "echo $marker")
    $null = Invoke-OwnedTmux $fixture -Arguments @('send-keys', '-t', $pane.Id.ToString(), 'Enter')
    $found = $pane | Wait-TmuxPaneText -Pattern "^$marker$" -Timeout 5
    Assert-True ($found.Outcome.ToString() -cin @('Matched', 'PresentAtEntry') -and $found.Found) 'Wait-TmuxPaneText did not find printed text'
    $stopped = $pane | Wait-TmuxPaneText -Pattern 'never-printed' -StopPattern $marker -Timeout 5
    Assert-True ($stopped.Outcome.ToString() -ceq 'Stopped') 'a stop pattern did not end the polling wait'
    Assert-True ((Get-ClientCount) -eq 0) 'a control client remains attached'
    Assert-True ((Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid}')).StdOut.Trim() -ceq [string] $fixture.ServerPid) 'the daemon changed during control refusals'

    # Commands sent over a connection carry the same literal guards, decided from that connection's daemon.
    if ($control) {
        $outside = $server.EnterControlModeAsync('fixture').GetAwaiter().GetResult()
        try {
            $remember = [LibTmux.PowerShell.TmuxCmdlet].Assembly.GetType('LibTmux.PowerShell.TmuxVersionCheck').GetMethod(
                'Remember', [Reflection.BindingFlags]'Static,NonPublic')
            $null = $remember.Invoke($null, @($outside, [LibTmux.TmuxVersion]::Parse('3.7')))
            foreach ($arguments in @(@('break-pane', '-d'), @('new-window', '-n', 'a.b'))) {
                $errors = @()
                $null = $outside | Invoke-TmuxControlCommand -Command (New-TmuxCommand -Name $arguments[0] -Arguments $arguments[1..($arguments.Count - 1)]) `
                    -ErrorAction SilentlyContinue -ErrorVariable errors
                Assert-True (@(Get-Refusal $errors '3.7a').Count -eq 1) "$($arguments -join ' ') crossed a control connection on 3.7"
            }
            Assert-True ((Invoke-OwnedTmux $fixture -Arguments @('list-windows', '-a', '-F', '#{window_id}')).StdOut.Trim().Split("`n").Count -eq 1) 'a refused control command changed the topology'
        } finally { $null = $outside.DisposeAsync().AsTask().GetAwaiter().GetResult() }
    } else {
        Write-Host 'Features: SKIPPED control command guards (control clients need tmux 3.7)'
    }

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

    # Releases that cannot be run here are reported through the version probe: refusal needs no dispatch.
    $cases = @(
        @{ Report = '3.7'; Arguments = @('break-pane', '-d', '-s', '%0'); Required = '3.7a' },
        @{ Report = '3.7'; Arguments = @('breakp', '-d'); Required = '3.7a' },
        @{ Report = '3.7'; Arguments = @('new-window', '-n', 'a.b'); Required = '3.7a' },
        @{ Report = '3.7'; Arguments = @('neww', '-n', 'a:b'); Required = '3.7a' },
        @{ Report = '3.7'; Arguments = @('new-session', '-d', '-s', 'ok', '-n', 'x.y'); Required = '3.7a' },
        @{ Report = '3.7'; Arguments = @('rename-window', '-t', '@0', 'c.d'); Required = '3.7a' },
        @{ Report = '3.7'; Arguments = @('rename-session', 'e:f'); Required = '3.7a' },
        @{ Report = '3.4'; Arguments = @('split-window', '-p', '30'); Required = '3.5' },
        @{ Report = '3.4'; Arguments = @('splitw', '-dp30'); Required = '3.5' }
    )
    foreach ($case in $cases) {
        $reporting = New-ReportingWrapper $bin $fixture.TmuxPath $case.Report
        $reported = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $reporting
        $errors = @()
        $null = $reported | Invoke-TmuxCommand -Arguments $case.Arguments -ErrorAction SilentlyContinue -ErrorVariable errors
        Assert-True (@(Get-Refusal $errors $case.Required).Count -eq 1 -and $errors[0].Exception.Message -clike '*was not sent*') "$($case.Arguments -join ' ') was not refused on a reported $($case.Report)"
    }
    Assert-True (@(Invoke-OwnedTmux $fixture -Arguments @('list-windows', '-a', '-F', '#{window_id}')).Count -eq 1 -and
        (Invoke-OwnedTmux $fixture -Arguments @('list-panes', '-a', '-F', '#{pane_id}')).StdOut.Trim().Split("`n").Count -eq 1) 'a refused command changed the topology'

    # The same commands pass the guard when they avoid the unsafe form. When the reported release is
    # the real one they run; otherwise the fence stops them. Either way no feature guard refuses them.
    foreach ($case in @(
        @{ Report = '3.7'; Arguments = @('break-pane', '-d', '-n', 'named', '-s', '%0') },
        @{ Report = '3.7'; Arguments = @('new-window', '-d', '-n', 'plain') },
        @{ Report = '3.7a'; Arguments = @('break-pane', '-d') },
        @{ Report = '3.4'; Arguments = @('split-window', '-d', '-l', '30%') },
        @{ Report = '3.5'; Arguments = @('split-window', '-d', '-p', '30') }
    )) {
        $reporting = New-ReportingWrapper $bin $fixture.TmuxPath $case.Report
        $reported = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $reporting
        $errors = @()
        $null = $reported | Invoke-TmuxCommand -Arguments $case.Arguments -ErrorAction SilentlyContinue -ErrorVariable errors
        Assert-True (@($errors | Where-Object { $_.Exception.Message -clike '*was not sent*' }).Count -eq 0) "$($case.Arguments -join ' ') was refused by a feature guard on a reported $($case.Report)"
    }

    # A typed creation and a workspace plan check names on exactly 3.7 before they send anything.
    $reporting = New-ReportingWrapper $bin $fixture.TmuxPath '3.7'
    $reported = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $reporting
    $errors = @()
    $created = $reported | Get-TmuxSession -Name fixture | New-TmuxWindow -Name 'bad.name' -Command 'exec /bin/sh' -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True ($null -eq $created -and @(Get-Refusal $errors '3.7a').Count -eq 1) 'New-TmuxWindow sent a name that 3.7 rejects'
    $errors = @()
    $made = $reported | New-TmuxSession -Name 'okname' -WindowName 'win.dot' -Command 'exec /bin/sh' -ErrorAction SilentlyContinue -ErrorVariable errors
    Assert-True ($null -eq $made -and @(Get-Refusal $errors '3.7a').Count -eq 1) 'New-TmuxSession sent a window name that 3.7 rejects'
    # The package itself refuses ':' and '.' in session names, so a plan cannot reach the daemon with one.
    $caught = $null
    try { $null = $reported | New-TmuxSession -Name 'bad.session' -Command 'exec /bin/sh' } catch { $caught = $_.Exception }
    Assert-True ($caught -is [ArgumentException] -or $caught -is [Management.Automation.ParentContainsErrorRecordException]) 'a dotted session name was not refused before dispatch'
    $declaration = LibTmux.Workspace\Import-TmuxWorkspace -Yaml @'
session_name: named-workspace
windows:
  - window_name: dotted.window
    panes:
      - shell_command: exec /bin/sh
'@
    $plan = $declaration.Resolve($fixture.DirectoryPath, $null) |
        LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $reported -ErrorAction SilentlyContinue
    if ($null -ne $plan) {
        $errors = @()
        $applied = $plan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable errors
        Assert-True ($null -eq $applied -and @(Get-Refusal $errors '3.7a').Count -eq 1) 'a workspace plan sent a window name that 3.7 rejects'
    } else {
        Write-Host 'Features: SKIPPED workspace name check (the plan could not be prepared on the reported daemon)'
    }
    Assert-True ((Invoke-OwnedTmux $fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Trim() -ceq 'fixture') 'a refused plan or creation changed the sessions'
    Write-Host 'Features: refusals precede effects; supported paths operative'
}
