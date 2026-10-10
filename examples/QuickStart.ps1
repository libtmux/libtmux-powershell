Import-Module LibTmux

$server = Start-TmuxServer -ErrorAction Stop
$session = ($server | Resolve-TmuxSession -Name libtmux-demo `
    -Request @{ WindowName = 'editor' } -ErrorAction Stop).Value
$null = $session | Resolve-TmuxWindow -Name logs -ErrorAction Stop

($server | Get-TmuxSnapshot -ErrorAction Stop).Sessions |
    Select-TmuxSession -Criteria @{ Name = 'libtmux-demo' } -ExactlyOne
