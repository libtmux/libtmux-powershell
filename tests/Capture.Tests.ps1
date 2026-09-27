param([Parameter(Mandatory)] [string] $ModuleRoot)

# Integration: capture, raw dispatch and refresh use an owned live daemon.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

foreach ($name in @('Get-TmuxPaneContent', 'Invoke-TmuxCommand', 'Update-TmuxPane')) {
    Assert-True ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "Installed module does not export $name."
}

. "$PSScriptRoot/support/OwnedTmux.ps1"
Invoke-WithOwnedTmux {
    param($fixture)

    $trace = Join-Path $fixture.DirectoryPath 'calls'
    $wrapper = Join-Path $fixture.DirectoryPath 'tmux'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    $quotedTrace = "'" + $trace.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' tmux >> $quotedTrace
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)

    $absentSocket = Join-Path $fixture.DirectoryPath 'absent'
    $absent = LibTmux\New-TmuxServer -SocketPath $absentSocket -TmuxBinaryPath $wrapper -ConfigurationFile '/dev/null'
    try {
        $preview = @($absent | LibTmux\Invoke-TmuxCommand -Arguments @('new-session', '-d', '-s', 'never') -WhatIf)
        Assert-True ($preview.Count -eq 0 -and -not (Test-Path $absentSocket) -and -not (Test-Path $trace)) 'Raw WhatIf dispatched tmux or emitted a result.'
    } finally {
        if (Test-Path $absentSocket) {
            $cleanup = New-OwnedTmuxStartInfo ([pscustomobject]@{
                TmuxPath = $fixture.TmuxPath; DirectoryPath = $fixture.DirectoryPath; SocketPath = $absentSocket
            }) @('kill-server')
            $client = [Diagnostics.Process]::Start($cleanup)
            try {
                if (-not $client.WaitForExit(1000)) { $client.Kill($true); throw 'Unexpected owned daemon cleanup timed out.' }
            } finally { $client.Dispose() }
        }
    }

    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper -ConfigurationFile '/dev/null'
    $other = New-OwnedTmuxFixture
    try {
        $null = Invoke-OwnedTmux $fixture -Arguments @('set-environment', '-g', 'RAW_ENDPOINT', 'selected')
        $null = Invoke-OwnedTmux $other -Arguments @('set-environment', '-g', 'RAW_ENDPOINT', 'other')
        foreach ($arguments in @(
            ,@('-S', $other.SocketPath, 'set-environment', '-g', 'RAW_ENDPOINT', 'redirected')
            ,@("-S$($other.SocketPath)", 'set-environment', '-g', 'RAW_ENDPOINT', 'redirected')
            ,@('-L', 'unused', '-S', $other.SocketPath, 'set-environment', '-g', 'RAW_ENDPOINT', 'redirected')
            ,@('-f', '/dev/null', 'set-environment', '-g', 'RAW_ENDPOINT', 'redirected')
            ,@('-c', 'true')
            ,@('--', 'set-environment', '-g', 'RAW_ENDPOINT', 'redirected')
            ,@('-V')
            ,@('-')
        )) {
            $before = if (Test-Path -LiteralPath $trace) { [IO.File]::ReadAllLines($trace).Length } else { 0 }
            $invalid = $null
            $returned = [Collections.Generic.List[object]]::new()
            try {
                $server | LibTmux\Invoke-TmuxCommand -Arguments $arguments -Confirm:$false |
                    ForEach-Object { $returned.Add($_) }
            } catch { $invalid = $_ }
            $after = if (Test-Path -LiteralPath $trace) { [IO.File]::ReadAllLines($trace).Length } else { 0 }
            $selectedValue = (Invoke-OwnedTmux $fixture -Arguments @('show-environment', '-g', 'RAW_ENDPOINT')).StdOut.Trim()
            $otherValue = (Invoke-OwnedTmux $other -Arguments @('show-environment', '-g', 'RAW_ENDPOINT')).StdOut.Trim()
            Assert-True ($null -ne $invalid -and $invalid.FullyQualifiedErrorId -like 'Tmux.InvalidCommand,*' -and
                $returned.Count -eq 0 -and $before -eq $after -and
                $selectedValue -ceq 'RAW_ENDPOINT=selected' -and $otherValue -ceq 'RAW_ENDPOINT=other') `
                "Option-shaped command $($arguments[0]) escaped validation: selected=$selectedValue; other=$otherValue; native calls=$($after - $before)."
        }
        $invalid = $null
        try { $server | LibTmux\Invoke-TmuxCommand -Arguments @('-S', $other.SocketPath, 'list-sessions') -WhatIf | Out-Null }
        catch { $invalid = $_ }
        Assert-True ($null -ne $invalid -and $invalid.FullyQualifiedErrorId -like 'Tmux.InvalidCommand,*') 'WhatIf accepted a global option in place of a command name.'
    } finally {
        Remove-OwnedTmuxFixture $other
    }

    $literal = 'spaces; literal $value "quotes"'
    $result = $server | LibTmux\Invoke-TmuxCommand -Arguments @('set-environment', '-g', 'CAPTURE_LITERAL', $literal) -Confirm:$false
    Assert-True ($result -is [LibTmux.TmuxCommandResult] -and $result.ExitCode -eq 0 -and
        $result.Arguments.Count -eq 4 -and $result.Arguments[3] -ceq $literal) 'Raw command changed the literal argument or did not emit the native successful result.'
    $result = $server | LibTmux\Invoke-TmuxCommand -Arguments @('showenv', '-g', 'CAPTURE_LITERAL') -Confirm:$false
    $nativeDisplay = (Invoke-OwnedTmux $fixture -Arguments @('showenv', '-g', 'CAPTURE_LITERAL')).StdOut.TrimEnd("`r", "`n")
    Assert-True ($result.StandardOutputLines[0] -ceq $nativeDisplay) 'Raw command changed native showenv output.'
    $null = $server | LibTmux\Invoke-TmuxCommand -Arguments @('set-environment', '-g', 'CAPTURE_EMPTY', '') -Confirm:$false
    $result = $server | LibTmux\Invoke-TmuxCommand -Arguments @('show-environment', '-g', 'CAPTURE_EMPTY') -Confirm:$false
    Assert-True ($result.StandardOutputLines[0] -ceq 'CAPTURE_EMPTY=') 'Raw command rejected or lost an empty argument.'

    $failure = $null
    $success = [Collections.Generic.List[object]]::new()
    try {
        $server | LibTmux\Invoke-TmuxCommand -Arguments @('not-a-tmux-command') -Confirm:$false |
            ForEach-Object { $success.Add($_) }
    } catch { $failure = $_ }
    Assert-True ($success.Count -eq 0 -and $null -ne $failure) 'A nonzero raw command became successful output.'
    Assert-True ($failure.FullyQualifiedErrorId -like 'Tmux.CommandFailed,*') 'Raw failure lost its stable error ID.'
    Assert-True ($failure.Exception -is [LibTmux.TmuxCommandException] -and
        $failure.Exception.Result.ExitCode -ne 0 -and
        $failure.Exception.Result.StandardErrorLines.Count -gt 0 -and
        $failure.Exception.Result.Arguments -contains 'not-a-tmux-command' -and
        $failure.Exception.Dispatch -eq [LibTmux.TmuxDispatchState]::Dispatched) 'Raw failure lost its original result or dispatch metadata.'
    $errors = @()
    $continued = @(@($absent, $server) | LibTmux\Invoke-TmuxCommand -Arguments @('show-options', '-gv', 'status') -Confirm:$false -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-True ($continued.Count -eq 1 -and $errors.Count -eq 1 -and $errors[0].TargetObject -eq $absent) 'Raw per-target errors stopped later owners or lost their target.'

    $pane = $server | LibTmux\Get-TmuxPane | Select-Object -First 1
    $oldTitle = $pane.Title
    $null = Invoke-OwnedTmux $fixture -Arguments @('select-pane', '-t', $pane.Id.ToString(), '-T', 'refreshed-title')
    $updated = $pane | LibTmux\Update-TmuxPane
    Assert-True ($updated -is [LibTmux.Pane] -and -not [object]::ReferenceEquals($pane, $updated) -and
        $updated.Id -eq $pane.Id -and $updated.Title -ceq 'refreshed-title' -and $pane.Title -ceq $oldTitle) 'Refresh changed the old pane or failed to emit its captured replacement.'

    $script = Join-Path $fixture.DirectoryPath 'output.sh'
    $literalPath = Join-Path $fixture.DirectoryPath 'literal-environment'
    $quotedSocket = "'" + $fixture.SocketPath.Replace("'", "'\''") + "'"
    $quotedLiteralPath = "'" + $literalPath.Replace("'", "'\''") + "'"
    $wide = 'w' * 120
    @"
#!/bin/sh
i=0
while [ "`$i" -lt 40 ]; do printf 'history-%02d\n' "`$i"; i=`$((i + 1)); done
printf '\033[31mred-text\033[0m\nleft\n\nright  \n'
printf '%s\n' '$wide'
printf '%s' "`$CAPTURE_LITERAL" > $quotedLiteralPath
$quotedTmux -S $quotedSocket wait-for -S capture-ready
exec /bin/cat
"@ | Set-Content -LiteralPath $script
    $created = Invoke-OwnedTmux $fixture -Arguments @('new-window', '-d', '-P', '-F', '#{pane_id}', '-n', 'capture', "/bin/sh '$script'")
    Register-OwnedTmuxPane $fixture
    $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', 'capture-ready')
    Assert-True ([IO.File]::ReadAllText($literalPath) -ceq $literal) 'The pane received a changed literal environment value.'
    $capture = $server | LibTmux\Get-TmuxPane -Id $created.StdOut.Trim()
    $visible = @($capture | LibTmux\Get-TmuxPaneContent)
    $history = @($capture | LibTmux\Get-TmuxPaneContent -History)
    Assert-True ($history -ccontains 'history-00' -and $visible -cnotcontains 'history-00' -and $history.Count -gt $visible.Count) 'History capture did not include scrollback independently of the visible screen.'
    Assert-True (@($capture | LibTmux\Get-TmuxPaneContent -StartLine 0 -EndLine 0).Count -eq 1) 'Capture line bounds were not forwarded.'
    $raw = @($capture | LibTmux\Get-TmuxPaneContent -History -Raw)
    Assert-True ($raw.Count -eq 1 -and $raw[0] -is [string] -and $raw[0].Contains("left`n`nright")) 'Raw capture did not preserve internal blank lines in one string.'
    Assert-True ($raw[0] -ceq ($history -join "`n")) 'Raw capture changed the captured line projection.'
    Assert-True (-not $raw[0].Contains($wide)) 'The wrapping fixture did not produce a wrapped line.'
    $joined = $capture | LibTmux\Get-TmuxPaneContent -History -JoinWrappedLines -Raw
    Assert-True ($joined.Contains($wide)) 'Capture did not join wrapped lines.'
    $escaped = $capture | LibTmux\Get-TmuxPaneContent -History -EscapeSequences -Raw
    Assert-True ($escaped.Contains([string][char]27 + '[') -and $escaped.Contains('red-text')) 'Capture lost requested terminal escape sequences.'
    $octal = $capture | LibTmux\Get-TmuxPaneContent -History -EscapeSequences -EscapeNonPrintable -Raw
    Assert-True ($octal.Contains('\033')) 'Capture did not escape nonprintable output.'
    $spaces = @($capture | LibTmux\Get-TmuxPaneContent -History -PreserveTrailingSpaces)
    Assert-True (@($spaces | Where-Object { $_ -cmatch '^right  +$' }).Count -eq 1) 'Capture lost preserved trailing spaces.'
    Assert-True (@($capture | LibTmux\Get-TmuxPaneContent -AlternateScreen -Quiet).Count -eq 0) 'Quiet missing alternate-screen capture emitted lines.'
    $emptyRaw = @($capture | LibTmux\Get-TmuxPaneContent -AlternateScreen -Quiet -Raw)
    Assert-True ($emptyRaw.Count -eq 1 -and $emptyRaw[0] -ceq '') 'Raw empty capture did not emit one empty string.'

    $before = [IO.File]::ReadAllLines($trace).Length
    $invalid = $null
    try { $capture | LibTmux\Get-TmuxPaneContent -PreserveTrailingSpaces -TrimTrailingSpaces | Out-Null }
    catch { $invalid = $_ }
    Assert-True ($null -ne $invalid -and $invalid.FullyQualifiedErrorId -like 'Tmux.InvalidCapture,*' -and
        [IO.File]::ReadAllLines($trace).Length -eq $before) 'Contradictory capture flags did not terminate before dispatch.'
    $invalid = $null
    try { $server | LibTmux\Invoke-TmuxCommand -Arguments @(' ') -Confirm:$false | Out-Null }
    catch { $invalid = $_ }
    Assert-True ($null -ne $invalid -and $invalid.FullyQualifiedErrorId -like 'Tmux.InvalidCommand,*' -and
        [IO.File]::ReadAllLines($trace).Length -eq $before) 'An invalid raw command did not terminate before dispatch.'

    $null = Invoke-OwnedTmux $fixture -Arguments @('kill-window', '-t', 'fixture:capture')
    foreach ($case in @(
        @{ Command = 'Get-TmuxPaneContent'; ErrorId = 'Tmux.PaneCaptureFailed,*' },
        @{ Command = 'Update-TmuxPane'; ErrorId = 'Tmux.PaneRefreshFailed,*' }
    )) {
        $errors = @()
        $remaining = @(@($capture, $updated) | & "LibTmux\$($case.Command)" -ErrorAction Continue -ErrorVariable errors 2>$null)
        Assert-True ($remaining.Count -gt 0 -and $errors.Count -eq 1 -and
            $errors[0].FullyQualifiedErrorId -like $case.ErrorId -and $errors[0].TargetObject -eq $capture -and
            $errors[0].Exception -is [LibTmux.LibTmuxException]) 'A missing pane lost its error or stopped later owners.'
    }
}

'PASS: installed capture flags, history, raw argv/errors, WhatIf and replacement refresh'
