# Authoritative guide operations. Callers supply the declared native owners.
# The guide runner supplies owned fixtures; operations do not own the daemon.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    '',
    Justification = 'The caller observes each guide assignment.')]
param()

@{
    'query.01-capture' = @{ Requires = @('server'); Code = {
$captured = $server |
    Get-TmuxServer -ErrorAction Stop |
    Get-TmuxSnapshot -ErrorAction Stop
    } }
    'query.02-native' = @{ Requires = @('captured'); Code = {
$captured.Panes | Where-Object { $_.Width -ge 50 -and $_.Height -gt 0 }
    } }
    'query.03-criteria' = @{ Requires = @(); Code = {
$query = New-TmuxQuery -Target Pane -Criteria @{
    Width = @{ Ge = 50 }
    Height = @{ Gt = 0 }
}
    } }
    'query.04-select' = @{ Requires = @('query', 'captured'); Code = {
$captured.Panes | Select-TmuxPane -Query $query
    } }
    'query.05-fields' = @{ Requires = @(); Code = {
Get-TmuxQueryField -Target Pane | Where-Object WireName -CEQ 'pane_width'
    } }
    'query.06-related' = @{ Requires = @('captured'); Code = {
$captured.Windows | Select-TmuxWindow -Criteria @{
    Panes = @{ Some = @{ Width = @{ Ge = 50 }; Height = @{ Gt = 0 } } }
}
    } }
    'query.07-boolean' = @{ Requires = @('captured'); Code = {
$captured.Windows | Select-TmuxWindow -Criteria @{
    Or = @(@{ Name = @{ StartsWith = 'api-' } }, @{ Name = 'logs' })
    Not = @{ Name = @{ Contains = 'scratch' } }
}
    } }
    'query.08-regex' = @{ Requires = @('captured'); Code = {
$captured.Windows | Select-TmuxWindow -Criteria @{
    Name = @{ Regex = @{ Pattern = '^API-'; Options = @('IgnoreCase') } }
}
    } }
    'query.09-json' = @{ Requires = @('query'); Code = {
New-TmuxQuery -Json ($query | ConvertTo-TmuxQueryJson)
    } }
    'query.10-plan' = @{ Requires = @('query', 'captured'); Code = {
$queryPlan = $query | Get-TmuxQueryPlan -DaemonVersion $captured.DaemonVersion
    } }
    'query.11-execute' = @{ Requires = @('server', 'queryPlan'); Code = {
$server | Invoke-TmuxQuery -Plan $queryPlan -AsResult -ErrorAction Stop
    } }
    'query.12-one' = @{ Requires = @('captured'); Code = {
$captured.Sessions |
    Select-TmuxSession -Criteria @{ Name = 'development' } -ExactlyOne
    } }
    'read.endpoint' = @{ Requires = @(); Code = {
$server = LibTmux\New-TmuxServer `
    -SocketName ('libtmux-readme-' + [Guid]::NewGuid().ToString('N')) `
    -ConfigurationFile /dev/null
    } }
    'readme.install.import' = @{ Requires = @(); Code = {
$modules = $env:LIBTMUX_REVIEW_MODULE_ROOT
Import-Module -Name @(
    "$modules/LibTmux/0.1.0/LibTmux.psd1",
    "$modules/LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1"
) -ErrorAction Stop
    } }
    'readme.quickstart' = @{ Requires = @(); Code = {
(./examples/QuickStart.ps1).Windows | Select-Object Name, @{
    Name = 'PaneIds'
    Expression = { $_.Panes.Id -join ', ' }
}
    } }
    'readme.create' = @{ Requires = @('server'); Code = {
$captured = & {
    $ErrorActionPreference = 'Stop'
    $session = $server |
        New-TmuxSession -Name demo -WindowName editor -Command 'exec /bin/cat'
    try {
        $pane = $session | Get-TmuxPane
        $null = $pane | Split-TmuxPane -Horizontal -Command 'exec /bin/cat'
        $null = $session | New-TmuxWindow -Name logs -Command 'exec /bin/cat'
        ($server | Get-TmuxSnapshot).Sessions | Where-Object Name -CEQ demo
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
    } }
    'readme.filter' = @{ Requires = @('captured'); Code = {
$captured.Windows |
    Where-Object { $_.Panes.Count -gt 1 } |
    Select-Object Name, @{ Name = 'PaneCount'; Expression = { $_.Panes.Count } }
    } }
    'readme.related' = @{ Requires = @('captured'); Code = {
$captured.Windows |
    Select-TmuxWindow -Criteria @{ 'Panes.Count' = @{ Ge = 2 } } -ExactlyOne
    } }
    'readme.input' = @{ Requires = @('server'); Code = {
& {
    $ErrorActionPreference = 'Stop'
    $ready = 'libtmux-demo-' + [Guid]::NewGuid().ToString('N')
    $binary = $server.ConnectionOptions.TmuxBinaryPath
    $tmux = (Get-Command $binary -CommandType Application |
        Select-Object -First 1).Source
    $selector = if ($server.ConnectionOptions.SocketPath) {
        "-S '{0}'" -f $server.ConnectionOptions.SocketPath.Replace("'", "'\''")
    } elseif ($server.ConnectionOptions.SocketName) {
        "-L '{0}'" -f $server.ConnectionOptions.SocketName.Replace("'", "'\''")
    } else { '' }
    $quoted = $tmux.Replace("'", "'\''")
    $signal = "'{0}' {1} wait-for -S '{2}'" -f $quoted, $selector, $ready
    $session = $server |
        New-TmuxSession -Name 'input-demo' -Command 'exec /bin/sh'
    try {
        $pane = $session | Get-TmuxPane
        $text = 'printf "\nhello from PowerShell\n"; ' + $signal
        $pane | Send-TmuxText -Text $text -Enter
        $null = $server | Wait-TmuxChannel -Channel $ready -Timeout 10
        $pane | Get-TmuxPaneContent
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
    } }
    'input.http-ready' = @{ Requires = @('server'); Code = {
& {
    $ErrorActionPreference = 'Stop'
    $session = $server | New-TmuxSession `
        -Name ('http-' + [Guid]::NewGuid().ToString('N')) `
        -Command 'exec python3 -u -m http.server 0 --bind 127.0.0.1'
    try {
        $pane = $session | Get-TmuxPane
        $ready = $pane | Wait-TmuxPaneText `
            -Pattern '^Serving HTTP on 127\.0\.0\.1 port [0-9]+' `
            -CaseSensitive -Timeout 10 -TailLines 4 -Confirm:$false
        if ($ready.Outcome -notin 'PresentAtEntry', 'Matched') {
            throw "HTTP readiness ended with $($ready.Outcome)."
        }
        $tail = $ready.Tail -join "`n"
        $port = [regex]::Match($tail, 'port ([0-9]+)').Groups[1].Value
        $uri = "http://127.0.0.1:$port/"
        $response = Invoke-WebRequest -Uri $uri -TimeoutSec 5 -NoProxy
        $ready
        $response.StatusCode
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
    } }
    'input.run' = @{ Requires = @('server'); Code = {
& {
    $ErrorActionPreference = 'Stop'
    $name = 'pane-run-' + [Guid]::NewGuid().ToString('N')
    $session = $server | New-TmuxSession -Name $name -Command 'exec /bin/sh'
    try {
        $pane = $session | Get-TmuxPane
        $pane |
            Invoke-TmuxPaneCommand -Command 'exit 7' -Timeout 5 -Confirm:$false
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
    } }
    'readme.control' = @{ Requires = @('server'); Code = {
& {
    $ErrorActionPreference = 'Stop'
    $session = $server |
        New-TmuxSession -Name control-demo -Command 'exec /bin/cat'
    try {
        $client = $server |
            Connect-TmuxControl -Target 'control-demo' -ErrorAction Stop
        try {
            $command = New-TmuxCommand -Name display-message -Arguments @(
                '-p', '#{session_name}'
            )
            $client |
                Invoke-TmuxControlCommand -Command $command -ErrorAction Stop
        } finally {
            $client | Disconnect-TmuxControl -Confirm:$false
        }
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
    } }
    'watch.job-create' = @{ Requires = @('server'); Code = {
$job = & {
    $path = $server.ConnectionOptions.SocketPath
    $binary = $server.ConnectionOptions.TmuxBinaryPath
    Start-ThreadJob -ScriptBlock {
        Import-Module LibTmux
        New-TmuxServer -SocketPath $using:path -TmuxBinaryPath $using:binary |
            Watch-TmuxEvent -Target 'fixture' -MaxEvents 1 -MaxOutputBytes 1MB
    }
}
    } }
    'watch.job-receive' = @{ Requires = @('job'); Code = {
& {
    try {
        $job | Receive-Job -Wait -ErrorAction Stop
    } finally {
        $job | Stop-Job
        $job | Remove-Job
    }
}
    } }
    'watch.owned-rename' = @{ Requires = @(); Code = {
& {
    $ErrorActionPreference = 'Stop'
    Import-Module LibTmux
    $name = 'libtmux-watch-' + $PID + '-' + [Guid]::NewGuid().ToString('N')
    $socketDirectory = Join-Path ([IO.Path]::GetTempPath()) $name
    $null = New-Item $socketDirectory -ItemType Directory -ErrorAction Stop
    $ownerOnly = [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor
        [IO.UnixFileMode]::UserExecute
    [IO.File]::SetUnixFileMode($socketDirectory, $ownerOnly)
    $socketPath = Join-Path $socketDirectory 'socket'
    $options = @{ SocketPath = $socketPath; ConfigurationFile = '/dev/null' }
    $server = New-TmuxServer @options
    $session = $control = $job = $null
    try {
        $session = $server | New-TmuxSession `
            -Name watch-demo -WindowName before -Command 'exec /bin/cat'
        $control = $server |
            Connect-TmuxControl -Target $session.Name -ErrorAction Stop
        $job = Start-ThreadJob -ScriptBlock {
            Import-Module LibTmux
            $using:control |
                Watch-TmuxEvent -MaxEvents 16 -MaxOutputBytes 1MB |
                Where-Object {
                    $_ -is [LibTmux.TmuxNotificationEvent] -and
                    $_.Name -ceq 'window-renamed' -and
                    $_.Arguments -ccontains 'after'
                } |
                Select-Object -First 1
        }
        $null = $server | Invoke-TmuxCommand -Arguments @(
            'rename-window', '-t', 'watch-demo:0', 'after'
        )
        if (-not ($job | Wait-Job -Timeout 5)) {
            throw 'The rename notification did not arrive within five seconds.'
        }
        $notification = $job | Receive-Job -ErrorAction Stop
        if ($null -eq $notification) {
            throw 'The watcher ended without the rename notification.'
        }
        $notification
    } finally {
        try {
            if ($job) {
                $job | Stop-Job
                $job | Remove-Job
            }
        } finally {
            try {
                if ($control) {
                    $control | Disconnect-TmuxControl -Confirm:$false
                }
            } finally {
                if ($session) { $session | Remove-TmuxSession -Confirm:$false }
                if ($session -or -not (Test-Path -LiteralPath $socketPath)) {
                    Remove-Item -LiteralPath $socketDirectory -Recurse -Force
                }
            }
        }
    }
}
    } }
    'watch.parallel' = @{ Requires = @('server'); Code = {
& {
    $path = $server.ConnectionOptions.SocketPath
    $binary = $server.ConnectionOptions.TmuxBinaryPath
    'first', 'second' | ForEach-Object -ThrottleLimit 2 -Parallel {
        Import-Module LibTmux
        $options = @{ SocketPath = $using:path; TmuxBinaryPath = $using:binary }
        $endpoint = New-TmuxServer @options
        $control = $endpoint |
            Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
        try {
            $command = New-TmuxCommand -Name 'display-message' -Arguments @(
                '-p', $_
            )
            $control |
                Invoke-TmuxControlCommand -Command $command -ErrorAction Stop
        } finally {
            $control | Disconnect-TmuxControl -Confirm:$false
        }
    }
}
    } }
    'commands.chain' = @{ Requires = @('server'); Code = {
$first = New-TmuxCommand -Name 'display-message' -Arguments @('-p', 'first')
$second = New-TmuxCommand -Name 'display-message' -Arguments @('-p', 'second')
$server | Invoke-TmuxChain -Command @($first, $second)
    } }
    'commands.control' = @{ Requires = @('server'); Code = {
& {
    $control = $server |
        Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
    try {
        $command = New-TmuxCommand -Name 'display-message' -Arguments @(
            '-p', '#{session_name}'
        )
        $control |
            Invoke-TmuxControlCommand -Command $command -ErrorAction Stop
    } finally {
        $control | Disconnect-TmuxControl -Confirm:$false
    }
}
    } }
    'commands.concurrent' = @{ Requires = @('server'); Code = {
$commands = @(foreach ($name in @('api', 'worker', 'scheduler')) {
    New-TmuxCommand -Name 'display-message' -Arguments @('-p', $name)
})
./examples/ConcurrentCommands.ps1 -Server $server -Command $commands `
    -MaxPending 2 -MaxResultBytes 4096 -Timeout 1
    } }
    'commands.concurrent-control' = @{ Requires = @('server'); Code = {
& {
    $control = $server |
        Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
    try {
        $commands = @(foreach ($format in @(
                '#{session_name}', '#{window_name}', '#{pane_id}')) {
            New-TmuxCommand -Name 'display-message' -Arguments @(
                '-p', '-t', 'fixture:0.0', $format
            )
        })
        ./examples/ConcurrentCommands.ps1 -Connection $control `
            -Command $commands -MaxPending 2 -MaxResultBytes 4096 `
            -Timeout 1 -CompletionOrder
    } finally {
        $control | Disconnect-TmuxControl -Confirm:$false
    }
}
    } }
    'layout.pane-size' = @{ Requires = @('pane'); Code = {
$pane | Set-TmuxPaneSize -Width '40' -PassThru
    } }
    'layout.select' = @{ Requires = @('window'); Code = {
$window | Set-TmuxLayout -Layout 'even-horizontal' -PassThru
    } }
    'layout.window-size' = @{ Requires = @('window'); Code = {
$window | Set-TmuxWindowSize -Width 120 -Height 40 -PassThru
    } }
    'layout.zoom' = @{ Requires = @('pane'); Code = {
$pane | Set-TmuxPaneSize -Zoom
    } }
    'placement.01-link' = @{ Requires = @('window', 'session'); Code = {
$window |
    New-TmuxWindowLink -Session $session -Index 5 -NoSelect -Confirm:$false
    } }
    'placement.02-select' = @{ Requires = @('window', 'session'); Code = {
$window = $session | Get-TmuxWindow |
    Where-Object { $_.Id -eq $window.Id -and $_.Index -eq 5 }
    } }
    'placement.03-move' = @{ Requires = @('window'); Code = {
$window = $window | Move-TmuxWindow -Index 6 -PassThru -Confirm:$false
    } }
    'placement.04-remove' = @{ Requires = @('window'); Code = {
$window | Remove-TmuxWindowLink -Confirm:$false
    } }
    'clients.read' = @{ Requires = @('server'); Code = {
$server | Get-TmuxClient
    } }
    'clients.refresh' = @{ Requires = @('client'); Code = {
$client | Update-TmuxClient
    } }
    'clients.attachment' = @{ Requires = @('client'); Code = {
$client | Get-TmuxClientAttachment
    } }
    'options.read' = @{ Requires = @('session'); Code = {
$session | Get-TmuxOption -Name 'status-keys' -IncludeInherited
    } }
    'options.set' = @{ Requires = @('session'); Code = {
$session | Set-TmuxOption -Name '@project' -Value 'api' -PassThru
    } }
    'options.remove' = @{ Requires = @('session'); Code = {
$session | Remove-TmuxOption -Name '@scratch'
    } }
    'hooks.read' = @{ Requires = @('session'); Code = {
$session | Get-TmuxHook -Name 'alert-bell'
    } }
    'hooks.set' = @{ Requires = @('session'); Code = {
$command = 'display-message "build finished"'
$session | Set-TmuxHook -Name 'alert-bell[7]' -Command $command -PassThru
    } }
    'hooks.invoke' = @{ Requires = @('session'); Code = {
$session | Invoke-TmuxHook -Name 'alert-bell'
    } }
    'hooks.remove' = @{ Requires = @('session'); Code = {
$session | Remove-TmuxHook -Name 'alert-bell[7]'
    } }
    'environment.read' = @{ Requires = @('session'); Code = {
$session | Get-TmuxEnvironment -Name 'APP_MODE'
    } }
    'environment.set' = @{ Requires = @('session'); Code = {
$session | Set-TmuxEnvironment -Name 'APP_MODE' -Value 'development' -PassThru
    } }
    'environment.unset' = @{ Requires = @('session'); Code = {
$session | Remove-TmuxEnvironment -Name 'APP_MODE'
    } }
    'environment.mark-removed' = @{ Requires = @('session'); Code = {
$session | Remove-TmuxEnvironment -Name 'APP_MODE' -MarkRemoved
    } }
    'workspace.01-load' = @{
        Requires = @('workspacePath', 'projectRoot'); Code = {
$resolve = @{
    BaseDirectory = Split-Path -LiteralPath $workspacePath
    Variables = @{ PROJECT_ROOT = $projectRoot }
}
$workspace = Get-TmuxWorkspace -LiteralPath $workspacePath -ErrorAction Stop |
    Import-TmuxWorkspace -ErrorAction Stop |
    Resolve-TmuxWorkspace @resolve -ErrorAction Stop
    } }
    'workspace.02-validate' = @{ Requires = @('workspace'); Code = {
$workspace | Test-TmuxWorkspace -ErrorAction Stop
    } }
    'workspace.03-plan' = @{ Requires = @('workspace', 'server'); Code = {
$planOptions = @{
    Server = $server
    ExistingSession = 'Error'
    ServerStartup = 'CreateOrJoin'
    ErrorAction = 'Stop'
}
$workspacePlan = $workspace | Get-TmuxWorkspacePlan @planOptions
    } }
    'workspace.04-review' = @{ Requires = @('workspacePlan'); Code = {
$workspacePlan.Actions
    } }
    'workspace.05-preview' = @{ Requires = @('workspacePlan'); Code = {
$workspacePlan | Invoke-TmuxWorkspace -WhatIf
    } }
    'workspace.06-apply' = @{ Requires = @('workspacePlan'); Code = {
$workspaceResult = $workspacePlan |
    Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
    } }
    'workspace.07-export' = @{ Requires = @('server', 'exportPath'); Code = {
($server | Get-TmuxSnapshot -Depth Panes -ErrorAction Stop).Sessions |
    Select-TmuxSession -ExactlyOne -ErrorAction Stop -Criteria @{
        Name = 'development'
    } |
    ConvertTo-TmuxWorkspace -ErrorAction Stop |
    ConvertTo-TmuxWorkspaceYaml -ErrorAction Stop |
    Set-Content -LiteralPath $exportPath -Encoding utf8NoBOM -ErrorAction Stop
    } }
    'workspace.08-edit' = @{
        Requires = @('workspaceFile', 'editor', 'editorArguments'); Code = {
& {
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandArgumentPassing = 'Standard'
    $PSNativeCommandUseErrorActionPreference = $false
    & $editor @editorArguments $workspaceFile.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "Editor exited with code $LASTEXITCODE."
    }
}
    } }
    'workspace.09-recover' = @{
        Requires = @('server', 'workspaceResult'); Code = {
$workspaceRecovery = & {
    $broken = Import-TmuxWorkspace -Yaml @'
session_name: development
windows:
  - window_name: recovery-demo
    panes:
      - options:
          libtmux-invalid-option: fail
'@ -ErrorAction Stop
    $plan = $broken | Get-TmuxWorkspacePlan -Server $server `
        -ExistingSession Append -ServerStartup RequireExisting `
        -CompensateOnFailure -ErrorAction Stop
    try {
        $null = $plan | Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
        throw 'The deliberately invalid option was accepted.'
    } catch {
        $type = [LibTmux.Workspace.WorkspaceBuildException]
        if ($_.Exception -isnot $type) { throw }
        $failure = $_.Exception
    }
    [pscustomobject]@{
        Plan = $plan
        Failure = $failure
        Current = ($server | Get-TmuxSnapshot -Depth Panes -ErrorAction Stop)
    }
}
    } }
    'workspace.10-pending' = @{ Requires = @('server'); Code = {
& {
    $ErrorActionPreference = 'Stop'
    $declaration = Import-TmuxWorkspace -Yaml @'
session_name: review-command
options:
  default-command: exec /bin/sh
windows:
  - window_name: review
    panes:
      - shell_command:
          - cmd: "printf '\\nreview %s\\n' complete"
            enter: false
'@
    $plan = $declaration | Get-TmuxWorkspacePlan -Server $server
    $result = $null
    try {
        $result = $plan | Invoke-TmuxWorkspace -Confirm:$false
        $pane = $result.Windows[0].Panes[0]
        $typed = "printf '\nreview %s\n' complete"
        $wait = @{ Timeout = 10; Confirm = $false }
        $pending = $pane |
            Wait-TmuxPaneText -Pattern $typed -SimpleMatch @wait
        if ($pending.Outcome -notin 'PresentAtEntry', 'Matched') {
            throw "Pending input wait ended with $($pending.Outcome)."
        }
        $pane | Send-TmuxKey -Key Enter -Confirm:$false
        $completion = $pane |
            Wait-TmuxPaneText -Pattern '^review complete$' @wait
        if ($completion.Outcome -notin 'PresentAtEntry', 'Matched') {
            throw "Pending command wait ended with $($completion.Outcome)."
        }
        [pscustomobject]@{
            Pending = $pending.Tail -join "`n"
            Completion = $completion
            Plan = $plan
        }
    } finally {
        if ($result) { $result.Session | Remove-TmuxSession -Confirm:$false }
    }
}
    } }
    'workspace.11-options' = @{ Requires = @('server'); Code = {
& {
    $declaration = Import-TmuxWorkspace -Yaml @'
session_name: option-staging
global_options:
  default-shell: /bin/sh
windows:
  - window_name: workers
    layout: main-horizontal
    options:
      main-pane-height: '5'
    options_after:
      synchronize-panes: 'on'
    panes:
      - shell_command: printf first
      - shell_command: printf second
'@
    $declaration | Get-TmuxWorkspacePlan -Server $server
}
    } }
    'readme.workspace.01-import' = @{ Requires = @(); Code = {
$workspace = LibTmux.Workspace\Import-TmuxWorkspace -Yaml @'
session_name: readme-workspace-preview
windows:
  - window_name: editor
    panes:
      - shell_command: exec /bin/sh
      - shell_command: exec /bin/sh
'@
    } }
    'readme.workspace.02-plan' = @{
        Requires = @('workspace', 'server'); Code = {
$workspacePlan = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan `
    -Server $server -ServerStartup CreateOrJoin -ExistingSession Error
    } }
    'readme.workspace.03-review' = @{ Requires = @('workspacePlan'); Code = {
$workspacePlan.Actions
    } }
    'readme.workspace.04-preview' = @{ Requires = @('workspacePlan'); Code = {
$workspacePlan | LibTmux.Workspace\Invoke-TmuxWorkspace -WhatIf
    } }
    'readme.workspace.05-apply' = @{ Requires = @('workspacePlan'); Code = {
$workspaceResult = & {
    $result = $workspacePlan |
        LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
    try { $result } finally {
        $result.Session | Remove-TmuxSession -Confirm:$false
    }
}
    } }
    'readme.workspace.06-graph' = @{ Requires = @('workspaceResult'); Code = {
$workspaceResult.Windows |
    Select-Object Name, @{ Name = 'PaneCount'; Expression = { $_.Panes.Count } }
    } }
    'capture.lines' = @{ Requires = @('pane'); Code = {
$pane | Get-TmuxPaneContent
    } }
    'capture.history' = @{ Requires = @('pane'); Code = {
$pane | Get-TmuxPaneContent -History -JoinWrappedLines -Raw
    } }
    'capture.range' = @{ Requires = @('pane'); Code = {
$pane | Get-TmuxPaneContent -StartLine -10 -EndLine 4
    } }
    'capture.refresh' = @{ Requires = @('pane'); Code = {
$currentPane = $pane | Update-TmuxPane
    } }
    'capture.raw-list' = @{ Requires = @('server'); Code = {
$server | Invoke-TmuxCommand -Arguments @(
    'list-sessions', '-F', '#{session_name}'
)
    } }
    'capture.buffer' = @{ Requires = @('server'); Code = {
& {
    $name = 'libtmux-' + [guid]::NewGuid().ToString('N')
    $quiet = @{ Confirm = $false; ErrorAction = 'Stop' }
    $created = $false
    try {
        $set = @('set-buffer', '-b', $name, 'hello from PowerShell')
        $null = $server | Invoke-TmuxCommand -Arguments $set @quiet
        $created = $true
        $show = @('show-buffer', '-b', $name)
        $shown = $server | Invoke-TmuxCommand -Arguments $show @quiet
        $shown.StandardOutputLines
    } finally {
        if ($created) {
            $delete = @('delete-buffer', '-b', $name)
            $server | Invoke-TmuxCommand -Arguments $delete @quiet | Out-Null
        }
    }
}
    } }
    'capture.raw-preview' = @{ Requires = @('server'); Code = {
$server | Invoke-TmuxCommand -Arguments @('kill-session', '-t', '$3') -WhatIf
    } }
    'create.session' = @{ Requires = @('server'); Code = {
$session = $server |
    New-TmuxSession -Name 'work' -WindowName 'editor' -Width 100 -Height 30
    } }
    'create.window' = @{ Requires = @('session'); Code = {
$window = $session | New-TmuxWindow -Name 'tools' -Index 5 -Activate
    } }
    'create.split' = @{ Requires = @('pane'); Code = {
$newPane = $pane | Split-TmuxPane -Horizontal -Before -Size 20
    } }
    'create.command' = @{ Requires = @('session'); Code = {
$window = $session | New-TmuxWindow -Name 'shell' -Command 'exec /bin/sh'
    } }
    'create.environment' = @{ Requires = @('session'); Code = {
$window = $session | New-TmuxWindow -Environment @{
    APP_MODE = 'development'
    OPTIONAL = ''
}
    } }
    'remove.preview' = @{ Requires = @('session'); Code = {
$session | Remove-TmuxSession -WhatIf
    } }
    'remove.session' = @{ Requires = @('session'); Code = {
$session | Remove-TmuxSession -Confirm:$false
    } }
    'remove.window' = @{ Requires = @('window'); Code = {
$window | Remove-TmuxWindow -Confirm:$false
    } }
    'remove.pane' = @{ Requires = @('pane'); Code = {
$pane | Remove-TmuxPane -Confirm:$false
    } }
}
