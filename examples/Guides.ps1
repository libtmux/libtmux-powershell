# Authoritative guide operations. Callers supply the declared native owners.
# The guide runner supplies owned fixtures; these operations do not own daemon lifetime.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'currentPane', Justification = 'The exact guide assignment is observed by the caller after dot-sourcing this operation.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'session', Justification = 'The exact guide assignment is observed by the caller after dot-sourcing this operation.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'window', Justification = 'The exact guide assignment is observed by the caller after dot-sourcing this operation.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'newPane', Justification = 'The exact guide assignment is observed by the caller after dot-sourcing this operation.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'captured', Justification = 'The exact guide assignment is observed by the caller after dot-sourcing this operation.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'server', Justification = 'The exact guide assignment is observed by the caller after dot-sourcing this operation.')]
param()

@{
    'read.endpoint' = @{ Requires = @(); Code = { $server = LibTmux\New-TmuxServer -SocketName development } }
    'readme.create' = @{ Requires = @('server'); Code = {
$captured = & {
    $session = $server | New-TmuxSession -Name 'demo' -WindowName 'editor' -Command 'exec /bin/cat' -Width 100 -Height 30 -ErrorAction Stop
    try {
        $pane = $session | Get-TmuxPane -ErrorAction Stop
        $null = $pane | Split-TmuxPane -Horizontal -Size 40 -Command 'exec /bin/cat' -ErrorAction Stop
        $snapshot = $server | Get-TmuxSnapshot -ErrorAction Stop
        $snapshot.Sessions | Where-Object Name -CEQ 'demo'
    } finally {
        $session | Remove-TmuxSession -Confirm:$false -ErrorAction Stop
    }
}
    } }
    'readme.filter' = @{ Requires = @('captured'); Code = {
$captured.Panes | Where-Object Width -GE 50 | Select-Object Id, Width, Height
    } }
    'readme.input' = @{ Requires = @('server'); Code = {
& {
    $ErrorActionPreference = 'Stop'
    $ready = 'libtmux-demo-' + [Guid]::NewGuid().ToString('N')
    $tmux = (Get-Command $server.ConnectionOptions.TmuxBinaryPath -CommandType Application).Source
    $signal = "'{0}' wait-for -S '{1}'" -f $tmux.Replace("'", "'\''"), $ready
    $session = $server | New-TmuxSession -Name 'input-demo' -Command 'exec /bin/sh'
    try {
        $pane = $session | Get-TmuxPane
        $pane | Send-TmuxText -Text ('printf "\nhello from PowerShell\n"; ' + $signal) -Enter
        $null = $server | Wait-TmuxChannel -Channel $ready -Timeout 10
        $pane | Get-TmuxPaneContent
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
    } }
    'workspace.parse' = @{ Requires = @(); Code = { LibTmux.Workspace\Import-TmuxWorkspace -Yaml 'session_name: development' } }
    'capture.lines' = @{ Requires = @('pane'); Code = { $pane | Get-TmuxPaneContent } }
    'capture.history' = @{ Requires = @('pane'); Code = { $pane | Get-TmuxPaneContent -History -JoinWrappedLines -Raw } }
    'capture.range' = @{ Requires = @('pane'); Code = { $pane | Get-TmuxPaneContent -StartLine -10 -EndLine 4 } }
    'capture.refresh' = @{ Requires = @('pane'); Code = { $currentPane = $pane | Update-TmuxPane } }
    'capture.raw-list' = @{ Requires = @('server'); Code = { $server | Invoke-TmuxCommand -Arguments @('list-sessions', '-F', '#{session_name}') } }
    'capture.raw-preview' = @{ Requires = @('server'); Code = { $server | Invoke-TmuxCommand -Arguments @('kill-session', '-t', '$3') -WhatIf } }
    'create.session' = @{ Requires = @('server'); Code = { $session = $server | New-TmuxSession -Name 'work' -WindowName 'editor' -Width 100 -Height 30 } }
    'create.window' = @{ Requires = @('session'); Code = { $window = $session | New-TmuxWindow -Name 'tools' -Index 5 -Activate } }
    'create.split' = @{ Requires = @('pane'); Code = { $newPane = $pane | Split-TmuxPane -Horizontal -Before -Size 20 } }
    'create.command' = @{ Requires = @('session'); Code = { $window = $session | New-TmuxWindow -Name 'shell' -Command 'exec /bin/sh' } }
    'create.environment' = @{ Requires = @('session'); Code = { $window = $session | New-TmuxWindow -Environment @{ APP_MODE = 'development'; OPTIONAL = '' } } }
    'remove.preview' = @{ Requires = @('session'); Code = { $session | Remove-TmuxSession -WhatIf } }
    'remove.session' = @{ Requires = @('session'); Code = { $session | Remove-TmuxSession -Confirm:$false } }
    'remove.window' = @{ Requires = @('window'); Code = { $window | Remove-TmuxWindow -Confirm:$false } }
    'remove.pane' = @{ Requires = @('pane'); Code = { $pane | Remove-TmuxPane -Confirm:$false } }
}
