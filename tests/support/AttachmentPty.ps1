. "$PSScriptRoot/OwnedTmux.ps1"

function Invoke-AttachmentPty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ModuleRoot,
        [Parameter(Mandatory)]
        [ValidateSet('Detach', 'ReadOnly', 'Cancel', 'Nested', 'WhatIf')]
        [string[]] $Modes
    )

    $python = (Get-Command python3 -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $context = @{ Fixture = $null; Report = $null; Failure = $null; ModuleRoot = $ModuleRoot; Modes = $Modes }
    $cleanupErrors = [Collections.Generic.List[string]]::new()
    try {
        Invoke-WithOwnedTmux {
            param($fixture)
            $context.Fixture = $fixture
            try {
                $null = Invoke-OwnedTmux $fixture -Arguments @('respawn-pane', '-k', '-t', 'fixture:0.0',
                    'printf "%s\n" LIBTMUX_ATTACHMENT_READY; exec /bin/cat')
                $session = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:', '#{session_id}')).StdOut.Trim()
                $sentinel = (Invoke-OwnedTmux $fixture -Arguments @('new-session', '-d', '-s', 'sentinel',
                    '-P', '-F', '#{session_id}', 'exec /bin/cat')).StdOut.Trim()
                Register-OwnedTmuxPane $fixture
                $resultPath = Join-Path $fixture.DirectoryPath 'attachment.json'
                $start = [Diagnostics.ProcessStartInfo]::new($python)
                $start.UseShellExecute = $false
                $start.RedirectStandardOutput = $true
                $start.RedirectStandardError = $true
                $null = $start.Environment.Remove('TMUX')
                $null = $start.Environment.Remove('TMUX_PANE')
                foreach ($argument in @((Join-Path $PSScriptRoot 'attachment_pty.py'), '--module-root', $context.ModuleRoot,
                    '--pwsh', [Environment]::ProcessPath, '--binary', $fixture.TmuxPath, '--socket', $fixture.SocketPath,
                    '--session', $session, '--sentinel-session', $sentinel, '--output', $resultPath,
                    '--modes') + $context.Modes) {
                    $start.ArgumentList.Add($argument)
                }
                $process = [Diagnostics.Process]::new()
                $process.StartInfo = $start
                $started = $false
                try {
                    $started = $process.Start()
                    $fixture.ClientProcesses.Add($process)
                    $null = $fixture.OwnedProcessIds.Add($process.Id)
                    $output = $process.StandardOutput.ReadToEndAsync()
                    $errorOutput = $process.StandardError.ReadToEndAsync()
                    if (!$process.WaitForExit(15000)) { throw 'Attachment PTY owner exceeded its outer deadline.' }
                    $stdout = $output.GetAwaiter().GetResult()
                    $stderr = $errorOutput.GetAwaiter().GetResult()
                    if (Test-Path -LiteralPath $resultPath) {
                        $context.Report = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
                    }
                    if ($process.ExitCode -ne 0 -or !$context.Report -or $context.Report.status -cne 'PASS') {
                        throw "Attachment PTY owner failed ($($process.ExitCode)): $stderr $stdout"
                    }
                } catch {
                    $context.Failure = $_.Exception
                    throw
                } finally {
                    try {
                        if ($started -and !$process.HasExited) {
                            $process.Kill($true)
                            if (!$process.WaitForExit(1000)) { throw 'Attachment PTY owner did not exit.' }
                        }
                    } catch {
                        $cleanupErrors.Add($_.Exception.Message)
                    }
                    if (!$started) { $process.Dispose() }
                }
            } catch {
                if (!$context.Failure) { $context.Failure = $_.Exception }
                throw
            }
        }
    } catch {
        if ($context.Failure -and ![object]::ReferenceEquals($context.Failure, $_.Exception)) {
            $cleanupErrors.Add($_.Exception.Message)
        } else {
            $context.Failure = $_.Exception
        }
    } finally {
        $fixture = $context.Fixture
        if ($fixture) {
            if (!$fixture.Closed -or (Test-Path -LiteralPath $fixture.DirectoryPath) -or
                (Test-Path -LiteralPath $fixture.SocketPath)) { $cleanupErrors.Add('Owned fixture directory or socket remains.') }
            foreach ($processId in $fixture.OwnedProcessIds) {
                $remaining = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($remaining) {
                    $remaining.Dispose()
                    $cleanupErrors.Add("Owned daemon, pane or test client remains: $processId")
                }
            }
        }
    }
    if ($context.Failure -or $cleanupErrors.Count) {
        $detail = @($cleanupErrors.ToArray())
        if ($context.Failure) { $detail = @($context.Failure.Message) + $detail }
        throw "Attachment test failed: $($detail -join '; ')"
    }
    $context.Report | Add-Member -NotePropertyName fixtureRemoved -NotePropertyValue $true
    $context.Report
}
