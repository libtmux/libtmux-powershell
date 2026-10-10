param([Parameter(Mandatory)] [string] $ModuleRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1')

function Assert-Endpoint([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Endpoint defaults: $Message" }
}

$environment = @{
    LIBTMUX_SOCKET_PATH = '/tmp/libtmux-powershell-offline/socket'
    LIBTMUX_SOCKET_NAME = '../ignored'
    TMUX = 'ignored malformed context'
    LIBTMUX_EXAMPLE_VALUE = 'captured'
    LIBTMUX_EXAMPLE_REMOVED = $null
}
$before = [Environment]::GetEnvironmentVariable('LIBTMUX_EXAMPLE_VALUE')
$server = New-TmuxServer -ChildEnvironment $environment -TmuxBinaryPath '/unlaunched-tmux'
$environment.LIBTMUX_EXAMPLE_VALUE = 'changed'
Assert-Endpoint ($server -is [LibTmux.Server]) 'constructor did not return a server handle'
Assert-Endpoint ($server.ConnectionOptions.ChildEnvironment['LIBTMUX_EXAMPLE_VALUE'] -ceq 'captured') 'constructor retained the caller hashtable'
Assert-Endpoint ($null -eq $server.ConnectionOptions.ChildEnvironment['LIBTMUX_EXAMPLE_REMOVED']) 'null removal override was discarded'
Assert-Endpoint ($before -ceq [Environment]::GetEnvironmentVariable('LIBTMUX_EXAMPLE_VALUE')) 'constructor edited the host environment'
$pipelineValue = Join-Path '/tmp/libtmux-powershell-offline' 'pipeline'
$pipelineServer = New-TmuxServer -ChildEnvironment @{ LIBTMUX_SOCKET_PATH = $pipelineValue }
Assert-Endpoint (!$pipelineServer.IsMaterialized) 'PowerShell-wrapped string override was rejected'

$explicit = New-TmuxServer -SocketPath '/tmp/libtmux-powershell-offline/explicit' `
    -ChildEnvironment @{ LIBTMUX_SOCKET_PATH = 'invalid lower selector' }
Assert-Endpoint ($explicit.ConnectionOptions.SocketPath -ceq '/tmp/libtmux-powershell-offline/explicit') 'explicit path did not override the environment selector'

foreach ($invalid in @(@{ KEY = 3 }, @{ 4 = 'value' }, @{ 'bad=name' = 'value' })) {
    $failure = $null
    try { $null = New-TmuxServer -SocketName 'offline' -ChildEnvironment $invalid }
    catch { $failure = $_ }
    Assert-Endpoint ($null -ne $failure -and $failure.Exception -is [ArgumentException]) 'invalid child environment was not rejected as an argument error'
}

$empty = @{ LIBTMUX_SOCKET_PATH = ''; LIBTMUX_SOCKET_NAME = ''; TMUX = ''; TMUX_TMPDIR = ''; PSMUX_SESSION = $null }
$default = New-TmuxServer -ChildEnvironment $empty -TmuxBinaryPath '/unlaunched-tmux'
Assert-Endpoint (!$default.IsMaterialized) 'default construction contacted tmux'

foreach ($context in @('/tmp/libtmux-powershell-offline/a,b,12,0',
    '/tmp/libtmux-powershell-offline/a,b,12,$0', '/tmp/libtmux-powershell-offline/a,b,12,-1')) {
    $values = $empty.Clone()
    $values.TMUX = $context
    Assert-Endpoint (!(New-TmuxServer -ChildEnvironment $values).IsMaterialized) 'valid comma-containing context was rejected'
}
foreach ($context in @('/tmp/socket,0,1', '/tmp/socket,+1,0', '/tmp/socket,1,-2',
    '/tmp/socket,1,', '/tmp/socket,,0', '/tmp/socket, 1,0', '/tmp/socket,1, 0',
    '/tmp/socket,1,$-1', '/tmp/socket,1,$$0', '/tmp/socket,1,0tail', 'relative,1,0', '/tmp/socket,1')) {
    $values = $empty.Clone()
    $values.TMUX = $context
    $failure = $null
    try { $null = New-TmuxServer -ChildEnvironment $values } catch { $failure = $_ }
    Assert-Endpoint ($failure.Exception -is [ArgumentException]) "selected malformed TMUX was accepted: $context"
}
foreach ($values in @(
    @{ LIBTMUX_SOCKET_PATH = 'relative'; LIBTMUX_SOCKET_NAME = 'valid' },
    @{ LIBTMUX_SOCKET_PATH = ''; LIBTMUX_SOCKET_NAME = '..' },
    @{ LIBTMUX_SOCKET_PATH = ''; LIBTMUX_SOCKET_NAME = 'a/b' },
    @{ LIBTMUX_SOCKET_PATH = ''; LIBTMUX_SOCKET_NAME = 'valid'; TMUX_TMPDIR = 'relative' }
)) {
    $failure = $null
    try { $null = New-TmuxServer -ChildEnvironment $values } catch { $failure = $_ }
    Assert-Endpoint ($failure.Exception -is [ArgumentException]) 'invalid selected endpoint fell through'
}
$named = New-TmuxServer -SocketName 'offline' -ChildEnvironment @{
    LIBTMUX_SOCKET_PATH = 'ignored invalid path'; TMUX_TMPDIR = '/tmp'; TMUX = 'ignored'
}
Assert-Endpoint (!$named.IsMaterialized) 'explicit name did not ignore lower selectors'
$both = $null
try { $null = New-TmuxServer -SocketName 'offline' -SocketPath '/tmp/offline' } catch { $both = $_ }
Assert-Endpoint ($both.Exception -is [Management.Automation.ParameterBindingException]) 'explicit path and name were accepted together'

'PASS endpoint constructors: defaults, copied overrides, precedence, context grammar and validation'
