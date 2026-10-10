param(
    [Parameter(Mandatory)] [string] $McpCommand,
    [Parameter(Mandatory)] [string] $McpVersion,
    [string] $McpProbe = "$PSScriptRoot/support/McpDiscovery/bin/Release/net8.0/McpDiscovery.dll",
    [string] $McpGuide = "$PSScriptRoot/../docs/mcp.md"
)

# Outer integration: an independently installed tool speaks MCP over owned stdio.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$McpCommand = (Get-Item -LiteralPath $McpCommand -ErrorAction Stop).FullName
$McpProbe = (Get-Item -LiteralPath $McpProbe -ErrorAction Stop).FullName
$McpGuide = (Get-Item -LiteralPath $McpGuide -ErrorAction Stop).FullName
$dotnet = (Get-Command dotnet -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
. "$PSScriptRoot/support/OwnedTmux.ps1"
$state = @{ Fixture = $null; Version = $McpVersion }
try {
    Invoke-WithOwnedTmux {
        param($fixture)
        $state.Fixture = $fixture
        $readyChannel = 'mcp-workflow-' + [Guid]::NewGuid().ToString('N')
        $program = Join-Path $fixture.DirectoryPath 'mcp-workflow.sh'
        $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
        $quotedSocket = "'" + $fixture.SocketPath.Replace("'", "'\''") + "'"
        $quotedProgram = "'" + $program.Replace("'", "'\''") + "'"
        [IO.File]::WriteAllText($program, "printf 'Service ready\n'`n$quotedTmux -S $quotedSocket wait-for -S '$readyChannel'`nexec /bin/cat`n")
        $null = Invoke-OwnedTmux $fixture -Arguments @('respawn-pane', '-k', '-t', 'fixture:0.0', "/bin/sh $quotedProgram")
        Register-OwnedTmuxPane $fixture
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', $readyChannel)
        $before = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:', '#{pid}|#{start_time}|#{session_id}|#{pane_id}|#{pane_pid}')).StdOut
        $pidFile = Join-Path $fixture.DirectoryPath 'mcp.pid'
        $launcher = Join-Path $fixture.DirectoryPath 'mcp-launcher'
        $quotedPid = "'" + $pidFile.Replace("'", "'\''") + "'"
        $quotedTool = "'" + $McpCommand.Replace("'", "'\''") + "'"
        [IO.File]::WriteAllText($launcher, "#!/bin/sh`nprintf '%s' `"`$`$`" > $quotedPid`nexec $quotedTool`n")
        [IO.File]::SetUnixFileMode($launcher, [IO.UnixFileMode]::UserRead -bor
            [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
        $receipt = Join-Path $fixture.DirectoryPath 'discovery.json'
        $start = [Diagnostics.ProcessStartInfo]::new($dotnet)
        $start.UseShellExecute = $false
        foreach ($argument in @($McpProbe, $launcher, $fixture.TmuxPath, $fixture.SocketPath, $state.Version, $receipt, $pidFile, $McpGuide)) {
            $start.ArgumentList.Add($argument)
        }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $start
        $started = $false
        try {
            $started = $process.Start()
            $fixture.ClientProcesses.Add($process)
            $null = $fixture.OwnedProcessIds.Add($process.Id)
            if (!$process.WaitForExit(15000)) { throw 'MCP discovery probe exceeded its outer deadline.' }
            if ($process.ExitCode -ne 0) { throw "MCP discovery probe failed with exit $($process.ExitCode)." }
            $result = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
            if ($result.server.version -cne $state.Version) { throw 'MCP receipt version differs.' }
            if (!$result.PSObject.Properties['listedSession'] -or
                $result.listedSession.name -cne 'fixture' -or
                $result.listedSession.sessionId -cne $before.Split('|')[2]) {
                throw 'MCP discovery probe did not return the owned session from list_sessions.'
            }
            if (!$result.PSObject.Properties['paneWorkflow'] -or
                $result.paneWorkflow.paneId -cne $before.Split('|')[3] -or
                $result.paneWorkflow.captureContainsReady -ne $true -or
                $result.paneWorkflow.tailContainsReady -ne $true -or
                $result.paneWorkflow.outcome -cne 'PresentAtEntry' -or
                $result.paneWorkflow.pollingFallback -ne $false -or
                $result.paneWorkflow.eventsDropped -ne 0) {
                throw 'MCP client did not complete the advertised pane-list, capture and ready-text workflow.'
            }
            $after = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:', '#{pid}|#{start_time}|#{session_id}|#{pane_id}|#{pane_pid}')).StdOut
            if ($before -cne $after -or
                (Invoke-OwnedTmux $fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Trim() -cne 'fixture' -or
                (Invoke-OwnedTmux $fixture -Arguments @('list-clients', '-F', '#{client_pid}')).StdOut.Trim().Length -ne 0) {
                throw 'MCP discovery or shutdown changed the borrowed daemon, session, pane or clients.'
            }
            [pscustomobject]@{
                protocol = $result.protocol
                version = $result.server.version
                sdk = $result.sdk
                tmux = (Invoke-OwnedTmux $fixture -Arguments @('-V')).StdOut.Trim()
                tools = $result.effectiveTools
                paneWorkflow = $result.paneWorkflow
                guideSha256 = $result.guideSha256
                toolSha256 = (Get-FileHash -LiteralPath $McpCommand -Algorithm SHA256).Hash
                borrowedStatePreserved = $true
            } | ConvertTo-Json -Depth 5
        } finally {
            if ($started -and !$process.HasExited) {
                $process.Kill($true)
                if (!$process.WaitForExit(1000)) { throw 'MCP discovery probe did not exit.' }
            }
            if (!$started) { $process.Dispose() }
            if (Test-Path -LiteralPath "$pidFile.identity") {
                $identity = Get-Content -LiteralPath "$pidFile.identity" -Raw | ConvertFrom-Json
                if (!$identity.exited) { throw 'MCP process shutdown was not confirmed by its retained handle.' }
            }
        }
    }
} finally {
    if ($state.Fixture -and (!$state.Fixture.Closed -or (Test-Path -LiteralPath $state.Fixture.DirectoryPath))) {
        throw 'MCP owned fixture cleanup was incomplete.'
    }
}
'PASS MCP discovery preserves borrowed tmux state and removes owned test resources'
