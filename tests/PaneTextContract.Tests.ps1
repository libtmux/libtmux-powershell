param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: the edges of the pane text wait on an owned tmux server. Text that wraps
# across rows is matched as one line on the polling and the control path, and a pane or a server
# that goes away ends the wait as PaneExited with the output so far, the same on every release.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-Contract([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Pane text contract: $Message" }
}

function Get-Rows($Fixture, [string] $Target) {
    @((Invoke-OwnedTmux $Fixture -Arguments @('capture-pane', '-p', '-t', $Target)).StdOut.Split("`n"))
}

Invoke-WithOwnedTmux {
    param($fixture)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath

    # Wrapped lines: 150 characters on an 80-column pane occupy two rows, and no row holds the line.
    $wrapped = ('abcdefghij' * 15)
    foreach ($case in @(
            @{ Name = 'wrapped-entry'; Program = "printf '%s\n' $wrapped; exec /bin/cat" },
            @{ Name = 'wrapped-later'; Program = "sleep 1; printf '%s\n' $wrapped; exec /bin/cat" })) {
        $null = Invoke-OwnedTmux $fixture -Arguments @('new-session', '-d', '-s', $case.Name,
            '-x', '80', '-y', '24', $case.Program)
        $pane = $server | LibTmux\Get-TmuxSession -Name $case.Name | LibTmux\Get-TmuxPane
        if ($case.Name -eq 'wrapped-entry') {
            $deadline = [DateTime]::UtcNow.AddSeconds(10)
            while (@(Get-Rows $fixture "$($case.Name):0.0" | Where-Object { $_ -ceq $wrapped }).Count -eq 0 -and
                @(Get-Rows $fixture "$($case.Name):0.0" | Where-Object { $_.StartsWith('abcdefghij') }).Count -lt 2 -and
                [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 25 }
            $rows = @(Get-Rows $fixture "$($case.Name):0.0")
            Assert-Contract (@($rows | Where-Object { $_ -ceq $wrapped }).Count -eq 0) 'the pane did not wrap the line'
        }
        $result = $pane | LibTmux\Wait-TmuxPaneText -Pattern "^$wrapped`$" -Timeout 8 -Confirm:$false -ErrorAction Stop
        Assert-Contract ($result.Outcome.ToString() -cin @('PresentAtEntry', 'Matched') -and $result.Pattern -ceq "^$wrapped`$") `
            "a wrapped line was not matched as one line ($($case.Name): $($result.Outcome))"
        $stopped = $pane | LibTmux\Wait-TmuxPaneText -Pattern 'NEVER-READY' -StopPattern "^$wrapped`$" -Timeout 8 -Confirm:$false -ErrorAction Stop
        Assert-Contract ($stopped.Outcome -eq [LibTmux.PaneWaitOutcome]::Stopped) 'a wrapped stop line was not matched as one line'
    }

    # A pane that exits while the wait runs ends it with the output so far.
    $null = Invoke-OwnedTmux $fixture -Arguments @('new-session', '-d', '-s', 'dying', '-x', '80', '-y', '24',
        "printf 'before-death\n'; sleep 1; exit 0")
    $dying = $server | LibTmux\Get-TmuxSession -Name dying | LibTmux\Get-TmuxPane
    $result = $dying | LibTmux\Wait-TmuxPaneText -Pattern 'NEVER-READY' -Timeout 8 -Confirm:$false -ErrorAction Stop
    Assert-Contract ($result.Outcome -eq [LibTmux.PaneWaitOutcome]::PaneExited -and
        $result.Elapsed -lt [TimeSpan]::FromSeconds(5) -and ($result.Tail -join "`n") -cmatch 'before-death') `
        "a pane that exited mid-wait did not end it with its output ($($result.Outcome))"

    # A server killed while the wait runs ends it as well, without an error.
    $doomedSocket = Join-Path $fixture.DirectoryPath 'doomed.sock'
    $null = & $fixture.TmuxPath -S $doomedSocket -f /dev/null new-session -d -s doomed -x 80 -y 24 "printf 'before-kill\n'; exec /bin/cat"
    $doomed = LibTmux\New-TmuxServer -SocketPath $doomedSocket -TmuxBinaryPath $fixture.TmuxPath
    $doomedPane = $doomed | LibTmux\Get-TmuxSession -Name doomed | LibTmux\Get-TmuxPane
    $start = [Diagnostics.ProcessStartInfo]::new('/bin/sh')
    $start.ArgumentList.Add('-c')
    $start.ArgumentList.Add("sleep 1; '$($fixture.TmuxPath)' -S '$doomedSocket' kill-server")
    $killer = [Diagnostics.Process]::Start($start)
    try {
        $errors = @()
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $result = $doomedPane | LibTmux\Wait-TmuxPaneText -Pattern 'NEVER-READY' -Timeout 20 -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable errors
        Assert-Contract ($errors.Count -eq 0 -and $result.Outcome -eq [LibTmux.PaneWaitOutcome]::PaneExited -and
            $watch.Elapsed -lt [TimeSpan]::FromSeconds(10) -and ($result.Tail -join "`n") -cmatch 'before-kill') `
            "a server killed mid-wait did not end it as PaneExited with its output (errors: $($errors.Count))"
    } finally {
        if (-not $killer.WaitForExit(5000)) { $killer.Kill() }
        $killer.Dispose()
        $null = & $fixture.TmuxPath -S $doomedSocket kill-server 2>$null
    }
    # A second control client that is stopped keeps the killed server up, and the wait still ends.
    $stoppedSocket = Join-Path $fixture.DirectoryPath 'stopped.sock'
    $null = & $fixture.TmuxPath -S $stoppedSocket -f /dev/null new-session -d -s held -x 80 -y 24 "printf 'before-stop\n'; exec /bin/cat"
    $heldServer = LibTmux\New-TmuxServer -SocketPath $stoppedSocket -TmuxBinaryPath $fixture.TmuxPath
    $heldPane = $heldServer | LibTmux\Get-TmuxSession -Name held | LibTmux\Get-TmuxPane
    $attach = [Diagnostics.ProcessStartInfo]::new($fixture.TmuxPath)
    foreach ($argument in @('-S', $stoppedSocket, '-C', 'attach', '-t', 'held')) { $attach.ArgumentList.Add($argument) }
    $attach.RedirectStandardInput = $true
    $attach.RedirectStandardOutput = $true
    $client = [Diagnostics.Process]::Start($attach)
    $stopper = $null
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (@(& $fixture.TmuxPath -S $stoppedSocket list-clients -F '#{client_name}').Count -eq 0 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
        $null = & kill -STOP $client.Id
        $start = [Diagnostics.ProcessStartInfo]::new('/bin/sh')
        $start.ArgumentList.Add('-c')
        $start.ArgumentList.Add("sleep 1; '$($fixture.TmuxPath)' -S '$stoppedSocket' kill-server")
        $stopper = [Diagnostics.Process]::Start($start)
        $errors = @()
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $result = $heldPane | LibTmux\Wait-TmuxPaneText -Pattern 'NEVER-READY' -Timeout 20 -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable errors
        Assert-Contract ($errors.Count -eq 0 -and $result.Outcome -eq [LibTmux.PaneWaitOutcome]::PaneExited -and
            $watch.Elapsed -lt [TimeSpan]::FromSeconds(10) -and ($result.Tail -join "`n") -cmatch 'before-stop') `
            "a server held up by a stopped client did not end the wait as PaneExited with its output (errors: $($errors.Count))"
    } finally {
        $null = & kill -CONT $client.Id 2>$null
        if (-not $client.HasExited) { $client.Kill() }
        $client.Dispose()
        if ($null -ne $stopper) {
            if (-not $stopper.WaitForExit(5000)) { $stopper.Kill() }
            $stopper.Dispose()
        }
        $null = & $fixture.TmuxPath -S $stoppedSocket kill-server 2>$null
    }
    Assert-Contract (@($server | LibTmux\Get-TmuxSession -Name fixture).Count -eq 1) 'the contract probes disturbed the fixture server'
}

'PASS pane text contract: wrapped lines joined, pane exit and server kill end the wait'
