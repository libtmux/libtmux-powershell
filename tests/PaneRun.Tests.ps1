param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: a native pane command reports shell completion on an owned server.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-PaneRun([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Pane command: $Message" }
}

$command = Get-Command 'LibTmux\Invoke-TmuxPaneCommand' -ErrorAction SilentlyContinue
Assert-PaneRun ($null -ne $command) 'installed module has no native Invoke-TmuxPaneCommand'
Assert-PaneRun ($command.OutputType.Type -contains [LibTmux.PaneRunResult]) 'cmdlet does not declare the native result type'
Assert-PaneRun ($command.Parameters['Timeout'].ParameterType -eq [double]) 'timeout must use seconds'

Invoke-WithOwnedTmux {
    param($fixture)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $anchor = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:0.0',
            '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}')).StdOut.Trim()
    $null = Invoke-OwnedTmux $fixture -Arguments @('new-session', '-d', '-s', 'pane-run',
        'exec /bin/sh')
    try {
        $session = $server | LibTmux\Get-TmuxSession -Name 'pane-run'
        $pane = $session | LibTmux\Get-TmuxPane
        Assert-PaneRun ($pane -is [LibTmux.Pane]) 'did not select a native pane'

        $preview = Join-Path $fixture.DirectoryPath 'should-not-exist'
        $escaped = $preview.Replace("'", "'\''")
        $before = @($pane | LibTmux\Invoke-TmuxPaneCommand -Command "touch '$escaped'" -WhatIf)
        Assert-PaneRun ($before.Count -eq 0 -and !(Test-Path -LiteralPath $preview)) 'WhatIf ran a shell command or emitted a result'

        $success = $pane | LibTmux\Invoke-TmuxPaneCommand -Command 'printf "pane run ok\n"' -Timeout $HangGuardSeconds -Confirm:$false
        Assert-PaneRun ($success -is [LibTmux.PaneRunResult] -and
            $success.PaneId -eq $pane.Id -and $success.ExitStatus -eq 0 -and !$success.TimedOut -and
            $success.EffectiveTimeout -eq $HangGuard) 'success lost native completion facts'

        $nonzero = $pane | LibTmux\Invoke-TmuxPaneCommand -Command 'exit 7' -Timeout $HangGuardSeconds -Confirm:$false
        Assert-PaneRun ($nonzero -is [LibTmux.PaneRunResult] -and
            $nonzero.ExitStatus -eq 7 -and !$nonzero.TimedOut) 'nonzero shell exit became a cmdlet error'

        $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
        $quotedSocket = "'" + $fixture.SocketPath.Replace("'", "'\''") + "'"
        $channel = 'libtmux-pane-run-' + [Guid]::NewGuid().ToString('N')
        $blocked = "$quotedTmux -S $quotedSocket wait-for $channel"
        $timedOut = $pane | LibTmux\Invoke-TmuxPaneCommand -Command $blocked -Timeout 0.02 -Confirm:$false
        Assert-PaneRun ($timedOut -is [LibTmux.PaneRunResult] -and
            $timedOut.TimedOut -and $null -eq $timedOut.ExitStatus -and
            $timedOut.PaneId -eq $pane.Id) 'timeout claimed command completion'
        $errors = @()
        $overlap = @($pane | LibTmux\Invoke-TmuxPaneCommand -Command 'true' -Timeout $HangGuardSeconds `
                -Confirm:$false -ErrorAction Continue -ErrorVariable errors 2>$null)
        Assert-PaneRun ($overlap.Count -eq 0 -and $errors.Count -eq 1 -and
            $errors[0].FullyQualifiedErrorId -like 'Tmux.PaneCommandFailed,*' -and
            [object]::ReferenceEquals($errors[0].TargetObject, $pane)) 'retained command accepted a second same-pane run'
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', '-S', $channel)

        foreach ($timeout in @(0, -1, 86401, [double]::NaN, [double]::PositiveInfinity)) {
            $rejected = $false
            try {
                $pane | LibTmux\Invoke-TmuxPaneCommand -Command 'true' -Timeout $timeout -WhatIf | Out-Null
            } catch {
                if ($_.FullyQualifiedErrorId -notlike 'Tmux.InvalidTimeout,*') { throw }
                $rejected = $true
            }
            Assert-PaneRun $rejected 'invalid timeout passed WhatIf validation'
        }
        foreach ($candidate in @(' ', "before`0after")) {
            $rejected = $false
            try {
                $pane | LibTmux\Invoke-TmuxPaneCommand -Command $candidate -WhatIf | Out-Null
            } catch {
                if ($_.FullyQualifiedErrorId -notlike 'Tmux.InvalidPaneCommand,*') { throw }
                $rejected = $true
            }
            Assert-PaneRun $rejected 'invalid command passed WhatIf validation'
        }
    } finally {
        $null = Invoke-OwnedTmux $fixture -Arguments @('kill-session', '-t', 'pane-run')
    }
    $after = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:0.0',
            '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}')).StdOut.Trim()
    Assert-PaneRun ($after -ceq $anchor) 'pane run changed the borrowed session or pane'
}

'PASS native pane-command completion, nonzero exit, timeout reservation, WhatIf and borrowed ownership'
