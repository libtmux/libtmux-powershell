param([Parameter(Mandatory)] [string] $ModuleRoot)

# Integration: renames use an owned daemon and change only the named session or window.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-Rename([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Rename: $Message" }
}

foreach ($name in @('Rename-TmuxSession', 'Rename-TmuxWindow')) {
    Assert-Rename ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "installed module has no $name"
}

function Get-Names($Fixture, [string] $Kind) {
    $arguments = if ($Kind -ceq 'Session') { @('list-sessions', '-F', '#{session_id} #{session_name}') } else { @('list-windows', '-a', '-F', '#{window_id} #{window_name}') }
    $rows = (Invoke-OwnedTmux $Fixture -Arguments $arguments).StdOut.Split("`n", [StringSplitOptions]::RemoveEmptyEntries)
    $names = @{}
    foreach ($row in $rows) { $id, $name = $row.Split(' ', 2); $names[$id] = $name }
    $names
}

Invoke-WithOwnedTmux {
    param($fixture)
    $trace = Join-Path $fixture.DirectoryPath 'dispatch'
    $wrapper = Join-Path $fixture.DirectoryPath 'tmux'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    $quotedTrace = "'" + $trace.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
case "`$*" in
*"run-shell -C libtmux-version-"*|"-V") ;;
*) printf '%s\n' dispatch >> $quotedTrace ;;
esac
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper -ConfigurationFile '/dev/null'
    $anchor = $server | LibTmux\Get-TmuxSession -Name fixture
    $session = $server | LibTmux\New-TmuxSession -Name rename-before -Command 'exec /bin/sh' -Confirm:$false
    $bystander = $server | LibTmux\New-TmuxSession -Name rename-bystander -Command 'exec /bin/sh' -Confirm:$false
    Register-OwnedTmuxPane $fixture

    # A session: no output by default, the old handle keeps its captured name, and only the target changes.
    $output = @($session | LibTmux\Rename-TmuxSession -Name rename-after -Confirm:$false)
    $names = Get-Names $fixture Session
    Assert-Rename ($output.Count -eq 0 -and $names[$session.Id.ToString()] -ceq 'rename-after' -and
        $names[$bystander.Id.ToString()] -ceq 'rename-bystander' -and $names[$anchor.Id.ToString()] -ceq 'fixture') 'a session rename emitted output or changed another session'
    Assert-Rename ($session.Name -ceq 'rename-before') 'a rename changed the captured handle'

    # PassThru emits the replacement handle, and a typed read pipes in.
    $replacement = @($session | LibTmux\Rename-TmuxSession -Name rename-final -PassThru -Confirm:$false)
    Assert-Rename ($replacement.Count -eq 1 -and $replacement[0] -is [LibTmux.Session] -and $replacement[0].Id -eq $session.Id -and
        $replacement[0].Name -ceq 'rename-final') 'PassThru did not emit the renamed session'
    $piped = @($server | LibTmux\Get-TmuxSession -Name rename-final | LibTmux\Rename-TmuxSession -Name rename-piped -PassThru -Confirm:$false)
    Assert-Rename ($piped.Count -eq 1 -and $piped[0].Name -ceq 'rename-piped' -and
        (Get-Names $fixture Session)[$session.Id.ToString()] -ceq 'rename-piped') 'a session read with Get-TmuxSession did not pipe into Rename-TmuxSession'

    # A window.
    $window = $session | LibTmux\New-TmuxWindow -Name window-before -Command 'exec /bin/sh' -Confirm:$false
    $neighbour = $bystander | LibTmux\New-TmuxWindow -Name window-neighbour -Command 'exec /bin/sh' -Confirm:$false
    Register-OwnedTmuxPane $fixture
    $output = @($window | LibTmux\Rename-TmuxWindow -Name window-after -Confirm:$false)
    $names = Get-Names $fixture Window
    Assert-Rename ($output.Count -eq 0 -and $names[$window.Id.ToString()] -ceq 'window-after' -and
        $names[$neighbour.Id.ToString()] -ceq 'window-neighbour') 'a window rename emitted output or changed another window'
    Assert-Rename ($window.Name -ceq 'window-before') 'a rename changed the captured window handle'
    $replacement = @($window | LibTmux\Rename-TmuxWindow -Name window-final -PassThru -Confirm:$false)
    Assert-Rename ($replacement.Count -eq 1 -and $replacement[0] -is [LibTmux.Window] -and $replacement[0].Id -eq $window.Id -and
        $replacement[0].Name -ceq 'window-final') 'PassThru did not emit the renamed window'
    $piped = @($session | LibTmux\Get-TmuxWindow | Where-Object Id -EQ $window.Id | LibTmux\Rename-TmuxWindow -Name window-piped -PassThru -Confirm:$false)
    Assert-Rename ($piped.Count -eq 1 -and $piped[0].Name -ceq 'window-piped') 'a window read with Get-TmuxWindow did not pipe into Rename-TmuxWindow'

    # A preview dispatches nothing and changes nothing.
    $before = [IO.File]::ReadAllLines($trace).Length
    $preview = @($session | LibTmux\Rename-TmuxSession -Name preview -PassThru -WhatIf)
    $preview += @($window | LibTmux\Rename-TmuxWindow -Name preview -PassThru -WhatIf)
    Assert-Rename ($preview.Count -eq 0 -and [IO.File]::ReadAllLines($trace).Length -eq $before -and
        (Get-Names $fixture Session)[$session.Id.ToString()] -ceq 'rename-piped' -and
        (Get-Names $fixture Window)[$window.Id.ToString()] -ceq 'window-piped') 'WhatIf dispatched tmux, renamed something or returned output'

    # An empty name is refused before tmux is called.
    $before = [IO.File]::ReadAllLines($trace).Length
    foreach ($command in @('Rename-TmuxSession', 'Rename-TmuxWindow')) {
        $target = if ($command -ceq 'Rename-TmuxSession') { $session } else { $window }
        $refused = $null
        try { $target | & "LibTmux\$command" -Name '' -Confirm:$false -ErrorAction Stop } catch { $refused = $_ }
        Assert-Rename ($null -ne $refused -and $refused.Exception -is [System.Management.Automation.ParameterBindingException]) "$command accepted an empty name"
    }
    Assert-Rename ([IO.File]::ReadAllLines($trace).Length -eq $before) 'an empty name reached tmux'

    # A target that is gone is an error that names its owner, and later owners are still renamed.
    $gone = $server | LibTmux\New-TmuxSession -Name rename-gone -Command 'exec /bin/sh' -Confirm:$false
    Register-OwnedTmuxPane $fixture
    $gone | LibTmux\Remove-TmuxSession -Confirm:$false
    $errors = @()
    $output = @(@($gone, $session) | LibTmux\Rename-TmuxSession -Name rename-continued -PassThru -Confirm:$false -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-Rename ($output.Count -eq 1 -and $output[0].Name -ceq 'rename-continued' -and $errors.Count -eq 1 -and
        $errors[0].FullyQualifiedErrorId -like 'Tmux.SessionRenameFailed,*' -and
        [object]::ReferenceEquals($errors[0].TargetObject, $gone)) 'a failed session rename lost its error or stopped the pipeline'
    $goneWindow = $session | LibTmux\New-TmuxWindow -Name window-gone -Command 'exec /bin/sh' -Confirm:$false
    Register-OwnedTmuxPane $fixture
    $goneWindow | LibTmux\Remove-TmuxWindow -Confirm:$false
    $errors = @()
    $output = @(@($goneWindow, $window) | LibTmux\Rename-TmuxWindow -Name window-continued -PassThru -Confirm:$false -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-Rename ($output.Count -eq 1 -and $output[0].Name -ceq 'window-continued' -and $errors.Count -eq 1 -and
        $errors[0].FullyQualifiedErrorId -like 'Tmux.WindowRenameFailed,*' -and
        [object]::ReferenceEquals($errors[0].TargetObject, $goneWindow)) 'a failed window rename lost its error or stopped the pipeline'
}

'PASS rename: only the target changes, PassThru replacement, typed pipeline input, previews, empty names and target failures'
