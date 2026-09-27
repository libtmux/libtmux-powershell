[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module LibTmux -ErrorAction Stop

$socketName = 'libtmux-quickstart-' + [Guid]::NewGuid().ToString('N')
$server = LibTmux\New-TmuxServer -SocketName $socketName -ConfigurationFile /dev/null
$session = $null
try {
    $session = $server | New-TmuxSession -Name demo -WindowName editor -Command 'exec /bin/cat'
    $pane = $session | Get-TmuxPane
    $null = $pane | Split-TmuxPane -Horizontal -Command 'exec /bin/cat'
    $null = $session | New-TmuxWindow -Name logs -Command 'exec /bin/cat'

    $captured = ($server | Get-TmuxSnapshot).Sessions |
        Select-TmuxSession -Criteria @{ Name = 'demo' } -ExactlyOne
    $splitWindow = $captured.Windows |
        Select-TmuxWindow -Criteria @{ 'Panes.Count' = @{ Ge = 2 } } -ExactlyOne

    [pscustomobject]@{
        SocketName = $socketName
        Session = $captured.Name
        Windows = $captured.Windows.Count
        Panes = $captured.Panes.Count
        SplitWindow = $splitWindow.Name
    }
} finally {
    if ($session) { $session | Remove-TmuxSession -Confirm:$false }
}
