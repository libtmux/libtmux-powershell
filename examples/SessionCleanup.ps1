[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if (!(Get-Module LibTmux)) { Import-Module LibTmux -ErrorAction Stop }

$server = LibTmux\New-TmuxServer
$command = 'exec /bin/cat'
$session = $null
$bodyError = $null
try {
    $session = $server |
        New-TmuxSession -Name demo -WindowName editor -Command $command
    $pane = $session | Get-TmuxPane
    $null = $pane | Split-TmuxPane -Horizontal -Command $command
    $null = $session | New-TmuxWindow -Name logs -Command $command

    $captured = ($server | Get-TmuxSnapshot).Sessions |
        Select-TmuxSession -Criteria @{ Name = 'demo' } -ExactlyOne
    $captured
} catch {
    $bodyError = $_
    throw
} finally {
    if ($session) {
        try { $session | Remove-TmuxSession -Confirm:$false }
        catch {
            if ($bodyError) {
                throw [AggregateException]::new(
                    'Session body and cleanup failed.',
                    [Exception[]] @($bodyError.Exception, $_.Exception))
            }
            throw
        }
    }
}
