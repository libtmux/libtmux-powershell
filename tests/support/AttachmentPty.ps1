. "$PSScriptRoot/OwnedTmux.ps1"

# Foreground attachment needs a terminal. A second tmux server, the owner, hosts each
# attaching process in one of its panes, so the process has a real PTY: the harness types
# into that pane, reads what it shows, and learns the process's exit status, all through
# tmux commands and events. The borrowed daemon is the owned fixture the cmdlet attaches
# to; PowerShell owns it and its panes.

# Waits until the owner's pane shows a piece of text, as the library's own wait sees it.
function Wait-AttachmentText($Pane, [string] $Text, [double] $Seconds) {
    $wait = $Pane | LibTmux\Wait-TmuxPaneText -Pattern $Text -SimpleMatch -CaseSensitive -Timeout $Seconds -Confirm:$false
    $outcome = $wait.Outcome.ToString()
    if ($outcome -cnotin @('Matched', 'PresentAtEntry')) {
        throw "Missing terminal event '$Text': $outcome, with '$(($wait.Tail -join ' ').Trim())' on screen."
    }
}

function Get-AttachmentClient($Inner) {
    $rows = (Invoke-OwnedTmux $Inner -WaitTimeout ([TimeSpan]::FromSeconds(5)) -Arguments @('list-clients', '-F',
        '#{client_pid}|#{client_tty}|#{session_id}|#{client_readonly}')).StdOut
    @($rows.Split("`n", [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { , $_.Split('|') })
}

function Invoke-AttachmentTmux($Fixture, [string[]] $Arguments) {
    (Invoke-OwnedTmux $Fixture -Arguments $Arguments -WaitTimeout ([TimeSpan]::FromSeconds(5))).StdOut
}

function Assert-Attachment([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw $Message }
}

function Start-AttachmentSentinel($Inner, [string] $SentinelSession) {
    $start = New-OwnedTmuxStartInfo $Inner @('-C', 'attach-session', '-t', $SentinelSession)
    $start.RedirectStandardInput = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $null = $process.Start()
    $Inner.ClientProcesses.Add($process)
    $null = $Inner.OwnedProcessIds.Add($process.Id)
    $errors = $process.StandardError.ReadToEndAsync()
    # The attach command answers with %begin and %end once the control client is a client.
    $deadline = [Diagnostics.Stopwatch]::StartNew()
    do {
        $line = $process.StandardOutput.ReadLineAsync().WaitAsync([TimeSpan]::FromSeconds(5)).GetAwaiter().GetResult()
        if ($null -eq $line) { throw "The sentinel control client ended before it attached: $($errors.GetAwaiter().GetResult())" }
    } until ($line.StartsWith('%end ') -or $deadline.Elapsed.TotalSeconds -gt 5)
    $null = $process.StandardOutput.ReadToEndAsync()
    $process
}

function Stop-AttachmentSentinel($Process) {
    if (!$Process -or $Process.HasExited) { return }
    $Process.StandardInput.Close()
    if (!$Process.WaitForExit(2000)) {
        $Process.Kill($true)
        if (!$Process.WaitForExit(1000)) { throw 'The sentinel control client did not exit.' }
    }
}

function Invoke-AttachmentCase {
    param($Inner, $Outer, $OuterPane, [string] $ModuleRoot, [string] $Mode, [hashtable] $Borrowed, $Sentinel)

    $caseTimer = [Diagnostics.Stopwatch]::StartNew()
    $suffix = [Guid]::NewGuid().ToString('N')
    $cancel = "libtmux-powershell-attach-$suffix"
    $ready = "attach-ready-$suffix"
    $resultPath = Join-Path $Outer.DirectoryPath "$Mode.json"
    $preparation = $null
    $attachment = $null
    $workspaceWindow = $null
    $workspacePane = $null
    $marker = $null
    $selected = $null
    $diagnostic = {
        $screen = try { Invoke-AttachmentTmux $Outer @('capture-pane', '-p', '-t', 'fixture:0.0') } catch { '<unreadable>' }
        $file = if (Test-Path -LiteralPath $resultPath) { Get-Content -LiteralPath $resultPath -Raw } else { '<absent>' }
        "$Mode case: owner screen: $($screen.Trim()); result file: $($file.Trim())"
    }
    try {
        $child = @([Environment]::ProcessPath, '-NoLogo', '-NoProfile', '-File', (Join-Path $PSScriptRoot 'AttachmentChild.ps1'),
            '-ModuleRoot', $ModuleRoot, '-Binary', $Inner.TmuxPath, '-Socket', $Inner.SocketPath,
            '-SessionId', $Borrowed.Session, '-Mode', $Mode, '-CancelChannel', $cancel, '-ResultPath', $resultPath,
            '-ReadyBinary', $Outer.TmuxPath, '-ReadySocket', $Outer.SocketPath, '-ReadyChannel', $ready)
        $null = Invoke-AttachmentTmux $Outer (@('respawn-pane', '-k', '-t', 'fixture:0.0') + $child)
        if ($Mode -cin @('Detach', 'ReadOnly', 'Cancel')) {
            # Startup, import and help belong to the outer budget. Attachment gets its own five seconds.
            $null = Invoke-OwnedTmux $Outer -Arguments @('wait-for', $ready) -WaitTimeout ([TimeSpan]::FromSeconds(15))
            $preparation = $caseTimer.Elapsed.TotalSeconds
            $attachmentTimer = [Diagnostics.Stopwatch]::StartNew()
            Wait-AttachmentText $OuterPane 'LIBTMUX_ATTACHMENT_READY' 5
            $attachment = $attachmentTimer.Elapsed.TotalSeconds
            $selected = @(Get-AttachmentClient $Inner | Where-Object { $_[2] -ceq $Borrowed.Session })
            Assert-Attachment ($selected.Count -eq 1) "Expected one client of the borrowed session, found $($selected.Count)."
            $readOnly = if ($Mode -ceq 'ReadOnly') { '1' } else { '0' }
            Assert-Attachment ($selected[0][3] -ceq $readOnly) "The attached client read-only flag was $($selected[0][3])."
            if ($Mode -ceq 'Detach') {
                $active = (Invoke-AttachmentTmux $Inner @('display-message', '-p', '-t', "$($Borrowed.Session):",
                    '#{window_name}|#{window_id}|#{pane_id}')).Trim().Split('|')
                Assert-Attachment ($active.Count -eq 3 -and $active[0] -ceq 'workspace-attachment') `
                    "The workspace window was not active: $($active -join '|')."
                $workspaceWindow, $workspacePane = $active[1], $active[2]
            }
            $marker = 'PS_ATTACH_INPUT_' + [Guid]::NewGuid().ToString('N')
            $null = Invoke-AttachmentTmux $Outer @('send-keys', '-t', 'fixture:0.0', '-l', $marker)
            $null = Invoke-AttachmentTmux $Outer @('send-keys', '-t', 'fixture:0.0', 'Enter')
            if ($Mode -ceq 'ReadOnly') {
                $null = Invoke-AttachmentTmux $Inner @('detach-client', '-t', $selected[0][1])
            } else {
                Wait-AttachmentText $OuterPane $marker 5
                $target = if ($workspacePane) { $workspacePane } else { "$($Borrowed.Session):" }
                Assert-Attachment ((Invoke-AttachmentTmux $Inner @('capture-pane', '-p', '-t', $target)).Contains($marker)) `
                    'Foreground input did not reach the attached pane.'
                if ($Mode -ceq 'Cancel') { $null = Invoke-AttachmentTmux $Inner @('wait-for', '-S', $cancel) }
                else { $null = Invoke-AttachmentTmux $Inner @('detach-client', '-t', $selected[0][1]) }
            }
        }
        # The owner's hook signals when the process in its pane has exited.
        $null = Invoke-OwnedTmux $Outer -Arguments @('wait-for', 'pane-died') -WaitTimeout ([TimeSpan]::FromSeconds(10))
        $status = (Invoke-AttachmentTmux $Outer @('display-message', '-p', '-t', 'fixture:0.0', '#{pane_dead_status}')).Trim()
        if ($Mode -ceq 'ReadOnly') {
            Assert-Attachment (!(Invoke-AttachmentTmux $Inner @('capture-pane', '-p', '-t', "$($Borrowed.Session):")).Contains($marker)) `
                'A read-only attachment accepted input.'
        }
        Assert-Attachment (Test-Path -LiteralPath $resultPath) 'The attaching process left no result.'
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        $expected = @{ Cancel = 'Stopped'; Nested = 'NestedRejected'; WhatIf = 'Previewed' }[$Mode]
        if (!$expected) { $expected = 'Returned' }
        Assert-Attachment ($status -ceq '0' -and $result.outcome -ceq $expected) `
            "The attaching process exited $status with outcome $($result.outcome); expected $expected."
        if ($Mode -ceq 'Detach') {
            Assert-Attachment ($result.workspaceApplied -eq $true -and $result.appliedSessionId -ceq $result.returnedId -and
                $result.returnedId -ceq $Borrowed.Session) 'The applied workspace session is not the returned borrowed session.'
            Assert-Attachment ($result.workspaceWindowId -ceq $workspaceWindow -and $result.workspacePaneId -ceq $workspacePane) `
                'The applied workspace window or pane differs from the attached one.'
            $automaticRename = Invoke-AttachmentTmux $Inner @('show-window-options', '-v', '-t', $workspaceWindow, 'automatic-rename')
            Assert-Attachment ($automaticRename.Trim() -ceq 'off') 'automatic-rename was not off.'
            $retained = Invoke-AttachmentTmux $Inner @('show-window-options', '-v', '-t', $workspaceWindow, '@workspace-attachment')
            Assert-Attachment ($retained.Trim() -ceq 'installed') 'Applied workspace window option was not retained.'
            $listed = Invoke-AttachmentTmux $Inner @('list-windows', '-t', $Borrowed.Session, '-F', '#{window_id}')
            $surviving = @($listed.Split("`n", [StringSplitOptions]::RemoveEmptyEntries) | Sort-Object)
            $want = @($Borrowed.Windows + $workspaceWindow | Sort-Object)
            Assert-Attachment (!@(Compare-Object $surviving $want -CaseSensitive).Count) `
                "The session kept windows $($surviving -join ',') instead of $($want -join ',')."
        }
        # The attaching client is gone and the sentinel is the only client left.
        $clients = @(Get-AttachmentClient $Inner)
        Assert-Attachment ($clients.Count -eq 1 -and $clients[0][0] -ceq [string] $Sentinel.Id) `
            "Clients left after the attachment: $(@($clients | ForEach-Object { $_ -join '|' }) -join '; ')."
        $generation = Invoke-AttachmentTmux $Inner @('display-message', '-p', '#{pid}:#{start_time}')
        Assert-Attachment ($generation.Trim() -ceq $Borrowed.Generation) 'The borrowed daemon was replaced.'
        $null = Invoke-AttachmentTmux $Inner @('has-session', '-t', $Borrowed.Session)
        $null = Invoke-AttachmentTmux $Inner @('has-session', '-t', $Borrowed.SentinelSession)
        $restored = $result.terminalBefore -ceq $result.terminalAfter
        Assert-Attachment ($restored -and $result.terminalBefore) 'Terminal attributes were not restored.'
        [pscustomobject]@{ mode = $Mode; status = 'PASS'; seconds = $caseTimer.Elapsed.TotalSeconds
            preparationSeconds = $preparation; attachmentSeconds = $attachment; result = $result
            terminalRestored = $restored; borrowedDaemonSessionsClientPreserved = $true }
    } catch {
        throw "$($_.Exception.Message) $(& $diagnostic)"
    }
}

function Invoke-AttachmentCases {
    param($Inner, $Outer, [string] $ModuleRoot, [string[]] $Modes, $Report)

    $null = Invoke-OwnedTmux $Inner -Arguments @('respawn-pane', '-k', '-t', 'fixture:0.0',
        'printf "%s\n" LIBTMUX_ATTACHMENT_READY; exec /bin/cat')
    $session = (Invoke-AttachmentTmux $Inner @('display-message', '-p', '-t', 'fixture:', '#{session_id}')).Trim()
    $sentinelSession = (Invoke-AttachmentTmux $Inner @('new-session', '-d', '-s', 'sentinel',
        '-P', '-F', '#{session_id}', 'exec /bin/cat')).Trim()
    Register-OwnedTmuxPane $Inner
    $Report.tmuxVersion = (Invoke-AttachmentTmux $Inner @('display-message', '-p', '#{version}')).Trim()
    $Report.tmuxSha256 = (Get-FileHash -LiteralPath $Inner.TmuxPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $windows = Invoke-AttachmentTmux $Inner @('list-windows', '-t', $session, '-F', '#{window_id}')
    $borrowed = @{
        Session = $session; SentinelSession = $sentinelSession
        Generation = (Invoke-AttachmentTmux $Inner @('display-message', '-p', '#{pid}:#{start_time}')).Trim()
        Windows = @($windows.Split("`n", [StringSplitOptions]::RemoveEmptyEntries))
    }

    # The owner keeps a process's pane after it exits, and says so through a hook.
    $null = Invoke-AttachmentTmux $Outer @('set-option', '-g', 'default-terminal', 'xterm-256color')
    $null = Invoke-AttachmentTmux $Outer @('set-window-option', '-t', 'fixture:0', 'remain-on-exit', 'on')
    $null = Invoke-AttachmentTmux $Outer @('set-hook', '-g', 'pane-died', 'wait-for -S pane-died')
    Register-OwnedTmuxPane $Outer
    $outerServer = LibTmux\New-TmuxServer -SocketPath $Outer.SocketPath -TmuxBinaryPath $Outer.TmuxPath -ConfigurationFile '/dev/null'
    $outerPane = $outerServer | LibTmux\Get-TmuxPane | Select-Object -First 1

    $sentinel = $null
    try {
        $sentinel = Start-AttachmentSentinel $Inner $sentinelSession
        foreach ($mode in $Modes) {
            $Report.cases.Add((Invoke-AttachmentCase -Inner $Inner -Outer $Outer -OuterPane $outerPane -ModuleRoot $ModuleRoot `
                -Mode $mode -Borrowed $borrowed -Sentinel $sentinel))
        }
    } finally {
        try { Stop-AttachmentSentinel $sentinel } catch { $Report.cleanupErrors.Add("sentinel: $($_.Exception.Message)") }
        $Report.sentinelExited = !$sentinel -or $sentinel.HasExited
    }
}

function Invoke-AttachmentPty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ModuleRoot,
        [Parameter(Mandatory)]
        [ValidateSet('Detach', 'ReadOnly', 'Cancel', 'Nested', 'WhatIf')]
        [string[]] $Modes
    )

    Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $report = @{ status = 'RUNNING'; cases = [Collections.Generic.List[object]]::new()
        cleanupErrors = [Collections.Generic.List[string]]::new(); sentinelExited = $false }
    $fixtures = [Collections.Generic.List[object]]::new()
    $failure = $null
    try {
        Invoke-WithOwnedTmux {
            param($inner)
            $fixtures.Add($inner)
            Invoke-WithOwnedTmux {
                param($outer)
                $fixtures.Add($outer)
                Invoke-AttachmentCases $inner $outer $ModuleRoot $Modes $report
            }
        }
    } catch {
        $failure = $_.Exception
    }
    foreach ($fixture in $fixtures) {
        if (!$fixture.Closed -or (Test-Path -LiteralPath $fixture.DirectoryPath) -or (Test-Path -LiteralPath $fixture.SocketPath)) {
            $report.cleanupErrors.Add('Owned fixture directory or socket remains.')
        }
        foreach ($processId in $fixture.OwnedProcessIds) {
            $remaining = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($remaining) {
                $remaining.Dispose()
                $report.cleanupErrors.Add("Owned daemon, pane or test client remains: $processId")
            }
        }
    }
    if ($failure -or $report.cleanupErrors.Count) {
        $detail = @($report.cleanupErrors.ToArray())
        if ($failure) { $detail = @($failure.Message) + $detail }
        throw "Attachment test failed: $($detail -join '; ')"
    }
    [pscustomobject]@{
        status = 'PASS'; cases = @($report.cases.ToArray()); cleanupErrors = @()
        tmuxVersion = $report.tmuxVersion; tmuxSha256 = $report.tmuxSha256
        ownedClientsExited = $report.sentinelExited; seconds = $timer.Elapsed.TotalSeconds; fixtureRemoved = $true
    }
}
