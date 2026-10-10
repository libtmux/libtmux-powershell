[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if (!(Get-Module LibTmux)) { Import-Module LibTmux -ErrorAction Stop }

$socket = 'libtmux-quickstart-' + [Guid]::NewGuid().ToString('N')
$options = @{ SocketName = $socket; ConfigurationFile = '/dev/null' }
$server = LibTmux\New-TmuxServer @options
$session = $null
try {
    $session = $server |
        New-TmuxSession -Name demo -WindowName editor -Command 'exec /bin/cat'
    $pane = $session | Get-TmuxPane
    $null = $pane | Split-TmuxPane -Horizontal -Command 'exec /bin/cat'
    $null = $session | New-TmuxWindow -Name logs -Command 'exec /bin/cat'

    $captured = ($server | Get-TmuxSnapshot).Sessions |
        Select-TmuxSession -Criteria @{ Name = 'demo' } -ExactlyOne
    $captured
} finally {
    if ($session) { $session | Remove-TmuxSession -Confirm:$false }
}
