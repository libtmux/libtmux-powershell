Import-Module LibTmux

$name = 'example-' + [Guid]::NewGuid().ToString('N')
New-TmuxServer | New-TmuxSession -Name $name -Owned |
    Invoke-TmuxScope {
        param($session)
        $session | Get-TmuxWindow
    }
