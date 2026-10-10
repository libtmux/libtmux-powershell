param([Parameter(Mandatory)] [string] $ModuleRoot)

# Integration: input reaches only owned panes, with explicit receiver readiness.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

foreach ($name in @('Send-TmuxText', 'Send-TmuxKey')) {
    Assert-True ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "Installed module does not export $name."
}

. "$PSScriptRoot/support/OwnedTmux.ps1"

. "$PSScriptRoot/support/InputReceiver.ps1"

Invoke-WithOwnedTmux {
    param($fixture)

    $trace = Join-Path $fixture.DirectoryPath 'calls'
    $wrapper = Join-Path $fixture.DirectoryPath 'tmux'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' tmux >> '$trace'
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper
    $session = $server | LibTmux\Get-TmuxSession | Select-Object -First 1

    $text = "-literal; #{pane_id} 'quotes' `u{03bb}`nnext;"
    $expected = [Text.Encoding]::UTF8.GetBytes($text) + [byte] 13
    $receiver = New-InputReceiver $fixture $session $expected.Length
    $result = @($receiver.Pane | LibTmux\Send-TmuxText -Text $text -Enter -Confirm:$false)
    Assert-True ($result.Count -eq 0) 'Text input emitted a success object.'
    Assert-Received $fixture $receiver $expected

    $receiver = New-InputReceiver $fixture $session 3
    [string[]] $keys = @('C-a', 'Enter')
    $result = @(& { $keys[0] = 'Z'; $receiver.Pane } | LibTmux\Send-TmuxKey -Key $keys -Confirm:$false)
    $result += @($receiver.Pane | LibTmux\Send-TmuxText -Text '!' -Confirm:$false)
    Assert-True ($result.Count -eq 0 -and $keys[0] -ceq 'Z') 'Key sending emitted output or failed to exercise caller-array mutation.'
    Assert-Received $fixture $receiver ([byte[]] @(1, 13, 33))

    $receiver = New-InputReceiver $fixture $session 6
    $receiver.Pane | LibTmux\Send-TmuxText -Text 'Enter' -Confirm:$false
    $receiver.Pane | LibTmux\Send-TmuxKey -Key Enter -Confirm:$false
    Assert-Received $fixture $receiver ([Text.Encoding]::UTF8.GetBytes('Enter') + [byte] 13)

    $receiver = New-InputReceiver $fixture $session 1
    $receiver.Pane | LibTmux\Send-TmuxText -Text '' -Enter -Confirm:$false
    Assert-Received $fixture $receiver ([byte[]] @(13))

    $before = [IO.File]::ReadAllLines($trace).Length
    $result = @(@() | LibTmux\Send-TmuxText -Text 'never' -Confirm:$false)
    $result += @(@() | LibTmux\Send-TmuxKey -Key Enter -Confirm:$false)
    $result += @($receiver.Pane | LibTmux\Send-TmuxText -Text 'never' -Enter -WhatIf)
    $result += @($receiver.Pane | LibTmux\Send-TmuxKey -Key Enter -WhatIf)
    Assert-True ($result.Count -eq 0 -and [IO.File]::ReadAllLines($trace).Length -eq $before) 'Empty input or WhatIf dispatched tmux or emitted output.'

    foreach ($command in @('Send-TmuxText', 'Send-TmuxKey')) {
        foreach ($preview in @($false, $true)) {
            $arguments = if ($command -eq 'Send-TmuxText') { @{ Text = "before`0after" } } else { @{ Key = @('Enter', "before`0after") } }
            $failure = $null
            try { $receiver.Pane | & "LibTmux\$command" @arguments -WhatIf:$preview -Confirm:$false | Out-Null }
            catch { $failure = $_ }
            Assert-True ($null -ne $failure -and $failure.FullyQualifiedErrorId -like 'Tmux.InvalidInput,*' -and
                [IO.File]::ReadAllLines($trace).Length -eq $before) "$command failed to reject NUL before dispatch."
        }
    }
    $failure = $null
    try { $receiver.Pane | LibTmux\Send-TmuxKey -Key @('Enter', '') -Confirm:$false | Out-Null }
    catch { $failure = $_ }
    Assert-True ($null -ne $failure -and [IO.File]::ReadAllLines($trace).Length -eq $before) 'An empty key token dispatched tmux.'
    $failure = $null
    try { [pscustomobject]@{ Pane = $receiver.Pane; Id = $receiver.Pane.Id } | LibTmux\Send-TmuxText -Text 'never' | Out-Null }
    catch { $failure = $_ }
    Assert-True ($null -ne $failure -and [IO.File]::ReadAllLines($trace).Length -eq $before) 'Input rebound an arbitrary object as a pane.'

    $receiver = New-InputReceiver $fixture $session 2
    $result = @(@($receiver.Pane, $receiver.Pane) | LibTmux\Send-TmuxText -Text 'x' -Confirm:$false)
    Assert-True ($result.Count -eq 0) 'Multiple input owners emitted success objects.'
    Assert-Received $fixture $receiver ([Text.Encoding]::UTF8.GetBytes('xx'))
    $stale = $receiver.Pane
    $null = Invoke-OwnedTmux $fixture -Arguments @('kill-window', '-t', $receiver.Window.Id.ToString())

    foreach ($command in @('Send-TmuxText', 'Send-TmuxKey')) {
        $arguments = if ($command -eq 'Send-TmuxText') { @{ Text = 'Q' } } else { @{ Key = 'Q' } }
        $errorId = if ($command -eq 'Send-TmuxText') { 'Tmux.TextSendFailed,*' } else { 'Tmux.KeySendFailed,*' }
        $receiver = New-InputReceiver $fixture $session 1
        $errors = @()
        $result = @(@($stale, $receiver.Pane) | & "LibTmux\$command" @arguments -Confirm:$false -ErrorAction Continue -ErrorVariable errors 2>$null)
        Assert-True ($result.Count -eq 0 -and $errors.Count -eq 1 -and $errors[0].FullyQualifiedErrorId -like $errorId -and
            $errors[0].TargetObject -eq $stale -and $errors[0].Exception -is [LibTmux.LibTmuxException] -and
            $errors[0].Exception.Dispatch -is [LibTmux.TmuxDispatchState]) "$command lost its per-owner failure or dispatch metadata."
        Assert-Received $fixture $receiver ([Text.Encoding]::UTF8.GetBytes('Q'))

        $receiver = New-InputReceiver $fixture $session 1
        $failure = $null
        try { @($stale, $receiver.Pane) | & "LibTmux\$command" @arguments -Confirm:$false -ErrorAction Stop | Out-Null }
        catch { $failure = $_ }
        Assert-True ($null -ne $failure -and $failure.FullyQualifiedErrorId -like $errorId) "$command ignored ErrorAction Stop."
        $null = Invoke-OwnedTmux $fixture -Arguments @('send-keys', '-t', $receiver.Pane.Id.ToString(), '-l', '--', 'Z')
        Assert-Received $fixture $receiver ([Text.Encoding]::UTF8.GetBytes('Z'))
    }
}

'PASS: installed literal text and ordered keys, exact received bytes, zero output, previews and per-owner errors'
