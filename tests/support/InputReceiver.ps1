function New-InputReceiver {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates only test resources inside the supplied owned tmux fixture.')]
    param($Fixture, $Session, [int] $ByteCount)
    $name = [Guid]::NewGuid().ToString('N')
    $script = Join-Path $Fixture.DirectoryPath "$name.sh"
    $output = Join-Path $Fixture.DirectoryPath "$name.bin"
    $tmux = "'" + $Fixture.TmuxPath.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
stty raw -echo
$tmux -S '$($Fixture.SocketPath)' wait-for -S '$name-ready'
dd bs=1 count=$($ByteCount + 1) 2>/dev/null > '$output'
$tmux -S '$($Fixture.SocketPath)' wait-for -S '$name-done'
exec /bin/cat
"@ | Set-Content -LiteralPath $script
    $window = $Session | LibTmux\New-TmuxWindow -Command "/bin/sh '$script'" -Confirm:$false
    Register-OwnedTmuxPane $Fixture
    $null = Invoke-OwnedTmux $Fixture -Arguments @('wait-for', "$name-ready")
    [pscustomobject]@{
        Pane = ($window | LibTmux\Get-TmuxPane | Select-Object -First 1)
        Window = $window
        OutputPath = $output
        Done = "$name-done"
    }
}

function Assert-Received($Fixture, $Receiver, [byte[]] $Expected) {
    # The independent sentinel makes excess trailing input fail the byte comparison.
    $null = Invoke-OwnedTmux $Fixture -Arguments @('send-keys', '-t', $Receiver.Pane.Id.ToString(), '-l', '--', '~')
    $Expected = $Expected + [byte] 126
    $null = Invoke-OwnedTmux $Fixture -Arguments @('wait-for', $Receiver.Done)
    $actual = [IO.File]::ReadAllBytes($Receiver.OutputPath)
    if ([Convert]::ToHexString($actual) -cne [Convert]::ToHexString($Expected)) {
        throw 'Input changed the received bytes or their order.'
    }
}
