# Starts the installed MCP tool with the settings the README pages show.
# Dot-source after ReadmeLinks.ps1; the caller supplies an owned tmux fixture.
Set-StrictMode -Version Latest

$script:McpSettingNames = @(
    'LIBTMUX_TMUX', 'LIBTMUX_SOCKET', 'LIBTMUX_SOCKET_PATH', 'LIBTMUX_TOOLSETS',
    'LIBTMUX_EXCLUDE_TOOLS', 'LIBTMUX_TOOLS', 'LIBTMUX_MCP_ALLOW_POLLING_FALLBACK')

# The registrations in a page: `claude mcp add` commands and mcpServers JSON.
function Get-McpReadmeConfiguration($Document) {
    foreach ($fence in $Document.Fences) {
        if ($fence.Info -ceq 'console' -and $fence.Code -match '(?m)^\$ claude mcp add ') {
            $line = ($fence.Code -replace '\\\n', ' ') -replace '^\$ ', ''
            $tokens = @($line -split '\s+' | Where-Object { $_ })
            if (($tokens[0..2] -join ' ') -cne 'claude mcp add') { throw "$($Document.Path):$($fence.Line): not a claude mcp add command" }
            $separator = [array]::IndexOf($tokens, '--')
            if ($separator -lt 4 -or $separator -ge $tokens.Count - 1) { throw "$($Document.Path):$($fence.Line): no command after --" }
            if ($tokens.Count -ne $separator + 2) { throw "$($Document.Path):$($fence.Line): the command takes arguments" }
            $settings = [ordered]@{}
            for ($index = 4; $index -lt $separator; $index += 2) {
                if ($tokens[$index] -cne '-e' -or $tokens[$index + 1] -cnotmatch '^(?<k>[A-Z_]+)=(?<v>.+)$') {
                    throw "$($Document.Path):$($fence.Line): unexpected token $($tokens[$index])"
                }
                $settings[$Matches.k] = $Matches.v
            }
            [pscustomobject]@{ Path = $Document.Path; Line = $fence.Line; Kind = 'claude'
                Command = $tokens[$separator + 1]; Settings = $settings }
        } elseif ($fence.Info -ceq 'json' -and $fence.Code -match '"mcpServers"') {
            $servers = ($fence.Code | ConvertFrom-Json).mcpServers
            foreach ($server in $servers.PSObject.Properties) {
                if ($server.Value.PSObject.Properties['args']) { throw "$($Document.Path):$($fence.Line): the server takes arguments" }
                $settings = [ordered]@{}
                if ($server.Value.PSObject.Properties['env']) {
                    foreach ($setting in $server.Value.env.PSObject.Properties) { $settings[$setting.Name] = [string] $setting.Value }
                }
                [pscustomobject]@{ Path = $Document.Path; Line = $fence.Line; Kind = 'json'
                    Command = $server.Value.command; Settings = $settings }
            }
        }
    }
}

function Read-McpResponse($Process, [int] $Id, [TimeSpan] $Timeout) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $remaining = $Timeout - $watch.Elapsed
        if ($remaining -le [TimeSpan]::Zero) { throw "MCP server sent no response $Id in time." }
        $line = $Process.StandardOutput.ReadLineAsync().WaitAsync($remaining).GetAwaiter().GetResult()
        if ($null -eq $line) {
            $null = $Process.WaitForExit(2000)
            throw "MCP server ended before response ${Id}: $($Process.StandardError.ReadToEnd().Trim())"
        }
        $message = $line | ConvertFrom-Json
        if ($message.PSObject.Properties['id'] -and $message.id -eq $Id) { return $message }
    }
}

# Each session owns a process; start several first so their startup overlaps.
function Start-McpServer($Fixture, [string] $Command, [hashtable] $Settings) {
    $start = [Diagnostics.ProcessStartInfo]::new($Command)
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($name in @($start.Environment.Keys | Where-Object { $_ -clike 'LIBTMUX_*' })) { $null = $start.Environment.Remove($name) }
    foreach ($name in @('TMUX', 'TMUX_PANE')) { $null = $start.Environment.Remove($name) }
    $start.Environment['TMUX_TMPDIR'] = $Fixture.DirectoryPath
    foreach ($name in $Settings.Keys) { $start.Environment[$name] = $Settings[$name] }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $null = $process.Start()
    $Fixture.ClientProcesses.Add($process)
    $null = $Fixture.OwnedProcessIds.Add($process.Id)
    $process
}

# Handshake, tools/list and tmux://capabilities, then a normal stdio shutdown.
function Complete-McpServerSession($Process) {
    $process = $Process
    $timeout = [TimeSpan]::FromSeconds(10)
    try {
        $send = {
            param($Message)
            $process.StandardInput.WriteLine(($Message | ConvertTo-Json -Compress -Depth 6))
            $process.StandardInput.Flush()
        }
        & $send @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{
            protocolVersion = '2025-06-18'; capabilities = @{}; clientInfo = @{ name = 'readme'; version = '1' } } }
        $initialize = Read-McpResponse $process 1 $timeout
        & $send @{ jsonrpc = '2.0'; method = 'notifications/initialized' }
        & $send @{ jsonrpc = '2.0'; id = 2; method = 'tools/list' }
        $tools = Read-McpResponse $process 2 $timeout
        & $send @{ jsonrpc = '2.0'; id = 3; method = 'resources/read'; params = @{ uri = 'tmux://capabilities' } }
        $resource = Read-McpResponse $process 3 $timeout
        [pscustomobject]@{
            Server = $initialize.result.serverInfo
            Tools = @($tools.result.tools | ForEach-Object { $_.name })
            Capabilities = $resource.result.contents[0].text | ConvertFrom-Json
        }
    } finally {
        try { $process.StandardInput.Close() } catch { Write-Verbose "stdin already closed: $_" }
        if (!$process.WaitForExit(5000)) {
            $process.Kill($true)
            if (!$process.WaitForExit(2000)) { throw 'MCP server did not exit.' }
        }
    }
}

# A refused configuration exits on its own and says why on standard error.
function Get-McpServerRefusal($Process) {
    if (!$Process.WaitForExit(10000)) {
        $Process.Kill($true)
        throw 'The server neither started nor refused its configuration.'
    }
    if ($Process.ExitCode -eq 0) { throw 'The server exited successfully on a refused configuration.' }
    $Process.StandardError.ReadToEnd()
}

function Invoke-McpServerSession($Fixture, [string] $Command, [hashtable] $Settings) {
    Complete-McpServerSession (Start-McpServer $Fixture $Command $Settings)
}

# A shown setting must change what the server reports, so a misspelt name fails.
function Assert-McpSettingEffect([hashtable] $Settings, $Session) {
    $capabilities = $Session.Capabilities
    foreach ($name in $Settings.Keys) {
        if ($name -cnotin $script:McpSettingNames) { throw "MCP setting $name is not one the checks observe." }
    }
    function Assert-Same($Actual, $Expected, [string] $What) {
        $actualText = (@($Actual) | Sort-Object) -join ','
        $expectedText = (@($Expected) | Sort-Object) -join ','
        if ($actualText -cne $expectedText) { throw "MCP $What is '$actualText', not '$expectedText'." }
    }
    if ($Settings.Contains('LIBTMUX_TOOLSETS')) { Assert-Same $capabilities.toolsets $Settings['LIBTMUX_TOOLSETS'].Split(',') 'toolsets' }
    if ($Settings.Contains('LIBTMUX_EXCLUDE_TOOLS')) { Assert-Same $capabilities.excludedTools $Settings['LIBTMUX_EXCLUDE_TOOLS'].Split(',') 'excluded tools' }
    if ($Settings.Contains('LIBTMUX_TOOLS')) { Assert-Same $capabilities.includedTools $Settings['LIBTMUX_TOOLS'].Split(',') 'included tools' }
    if ($Settings.Contains('LIBTMUX_SOCKET')) { Assert-Same $capabilities.socket.selector ('name:' + $Settings['LIBTMUX_SOCKET']) 'socket selector' }
    if ($Settings.Contains('LIBTMUX_SOCKET_PATH')) { Assert-Same $capabilities.socket.selector ('path:' + $Settings['LIBTMUX_SOCKET_PATH']) 'socket selector' }
    if ($Settings.Contains('LIBTMUX_TMUX') -and !$capabilities.connection.attachCommand.StartsWith("'$($Settings['LIBTMUX_TMUX'])' ", [StringComparison]::Ordinal)) {
        throw 'MCP attach command does not use LIBTMUX_TMUX.'
    }
    $polling = $Settings.Contains('LIBTMUX_MCP_ALLOW_POLLING_FALLBACK') -and $Settings['LIBTMUX_MCP_ALLOW_POLLING_FALLBACK'] -ceq 'true'
    if ($capabilities.paneObservation.pollingFallbackAllowed -ne $polling) { throw 'MCP polling fallback policy differs from the setting.' }
    if ($capabilities.paneObservation.controlRequired -eq $polling) { throw 'MCP control observation policy differs from the setting.' }
    Assert-Same $Session.Tools $capabilities.effectiveTools 'tools/list'
}

# Every distinct configuration on the pages starts the tool and shows its effect,
# and every tool name on the pages is linked to a tool the server has.
function Test-McpReadme($Fixture, [string] $Command, $Documents) {
    $owned = 'libtmux-powershell-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $configurations = @($Documents | ForEach-Object { Get-McpReadmeConfiguration $_ })
    if (!$configurations) { throw 'No MCP configuration found on the README pages.' }
    $plan = [Collections.Generic.List[hashtable]]::new()
    $seen = @{}
    foreach ($configuration in $configurations) {
        if ($configuration.Command -cnotmatch '(^|/)libtmux-mcp$') { throw "$($configuration.Path):$($configuration.Line): the command is not libtmux-mcp." }
        $settings = @{}
        foreach ($name in $configuration.Settings.Keys) {
            $settings[$name] = switch ($name) {
                'LIBTMUX_TMUX' { $Fixture.TmuxPath }
                'LIBTMUX_SOCKET_PATH' { $Fixture.SocketPath }
                'LIBTMUX_SOCKET' { $owned }
                default { $configuration.Settings[$name] }
            }
        }
        if (!$settings.ContainsKey('LIBTMUX_SOCKET') -and !$settings.ContainsKey('LIBTMUX_SOCKET_PATH')) {
            throw "$($configuration.Path):$($configuration.Line): the configuration names no socket."
        }
        $key = (($settings.Keys | Sort-Object | ForEach-Object { "$_=$($settings[$_])" }) -join ';')
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $plan.Add(@{ Role = 'page'; Settings = $settings })
    }
    $plan.Add(@{ Role = 'both'; Settings = @{ LIBTMUX_TMUX = $Fixture.TmuxPath; LIBTMUX_SOCKET = $owned; LIBTMUX_SOCKET_PATH = $Fixture.SocketPath } })
    $plan.Add(@{ Role = 'neither'; Settings = @{ LIBTMUX_TMUX = $Fixture.TmuxPath } })
    $plan.Add(@{ Role = 'retired'; Settings = @{ LIBTMUX_SOCKET_NAME = $owned } })
    $plan.Add(@{ Role = 'tools'; Settings = @{ LIBTMUX_TMUX = $Fixture.TmuxPath; LIBTMUX_SOCKET_PATH = $Fixture.SocketPath; LIBTMUX_TOOLSETS = 'inspect,manage,execute,teardown' } })
    foreach ($item in $plan) { $item.Process = Start-McpServer $Fixture $Command $item.Settings }
    $tools = $null
    foreach ($item in $plan) {
        # The path wins when both are set; with neither the server drives the one tmux picks
        # and says so; the retired name alone selects nothing and stops startup. The messages
        # name the rule and never a socket.
        if ($item.Role -ceq 'both') {
            $session = Complete-McpServerSession $item.Process
            if ($session.Capabilities.socket.selector -cne ('path:' + $Fixture.SocketPath)) {
                throw 'The server did not let LIBTMUX_SOCKET_PATH win over LIBTMUX_SOCKET.'
            }
            continue
        }
        if ($item.Role -ceq 'neither') {
            $session = Complete-McpServerSession $item.Process
            if ($session.Capabilities.socket.selector -cne 'default') { throw 'The server chose a socket of its own when none was set.' }
            if ($session.Capabilities.toolsets -contains 'teardown') { throw 'The server offered teardown on a server it did not start.' }
            continue
        }
        if ($item.Role -ceq 'retired') {
            $refusal = Get-McpServerRefusal $item.Process
            if (!$refusal.Contains('LIBTMUX_SOCKET_NAME') -or $refusal -cnotmatch '\bLIBTMUX_SOCKET\b') {
                throw 'The server did not refuse LIBTMUX_SOCKET_NAME alone and name LIBTMUX_SOCKET.'
            }
            continue
        }
        $session = Complete-McpServerSession $item.Process
        if ($item.Role -ceq 'page') { Assert-McpSettingEffect $item.Settings $session }
        else { $tools = $session }
    }
    # Controls: a misspelt setting and a wrong expectation both fail.
    foreach ($case in @(
        @{ Name = 'misspelt setting'; Settings = @{ LIBTMUX_TOOLSET = 'inspect' } }
        @{ Name = 'wrong toolsets'; Settings = @{ LIBTMUX_TOOLSETS = 'inspect' } }
        @{ Name = 'wrong socket'; Settings = @{ LIBTMUX_SOCKET = $owned } })) {
        $rejected = $false
        try { Assert-McpSettingEffect $case.Settings $tools } catch { $rejected = $true }
        if (!$rejected) { throw "MCP setting control accepted a $($case.Name)." }
    }
    $problems = @($Documents | ForEach-Object { Test-ReadmeToolLink $_ $tools.Tools })
    if ($problems) { throw ("MCP tool links:`n" + ($problems -join "`n")) }
    # Control: an unlinked name and an unknown tool are both reported.
    $planted = Get-MarkdownDocument 'planted.md' ("Use ``$($tools.Tools[0])`` and [``no_such_tool``](" + (Get-ToolPageUrl 'no_such_tool') + ").`n")
    $found = @(Test-ReadmeToolLink $planted $tools.Tools)
    if (!($found | Where-Object { $_.Contains('is not linked') }) -or !($found | Where-Object { $_.Contains('not a tool of the installed server') })) {
        throw 'The MCP tool link control did not report both planted faults.'
    }
    [pscustomobject]@{ Configurations = $seen.Count; Tools = $tools.Tools.Count }
}
