param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: placement changes require an owned tmux server.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-Placement([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Placement: $Message" }
}

foreach ($name in @('New-TmuxWindowLink', 'Move-TmuxWindow', 'Remove-TmuxWindowLink')) {
    Assert-Placement ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "installed module has no $name"
}

Invoke-WithOwnedTmux {
    param($fixture)
    $trace = Join-Path $fixture.DirectoryPath 'dispatch'
    $wrapper = Join-Path $fixture.DirectoryPath 'tmux'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    $quotedTrace = "'" + $trace.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' dispatch >> $quotedTrace
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper -ConfigurationFile '/dev/null'
    $source = $server | LibTmux\Get-TmuxSession -Name fixture
    $guest = $server | LibTmux\New-TmuxSession -Name placement-guest -Command 'exec /bin/sh' -Confirm:$false
    Register-OwnedTmuxPane $fixture
    $window = $source | LibTmux\New-TmuxWindow -Name shared -Index 4 -Command 'exec /bin/sh' -Confirm:$false
    Register-OwnedTmuxPane $fixture

    $linked = @($window | LibTmux\New-TmuxWindowLink -Session $guest -Index 5 -NoSelect -Confirm:$false)
    $guestLink = @($guest | LibTmux\Get-TmuxWindow | Where-Object { $_.Id -eq $window.Id -and $_.Index -eq 5 })
    Assert-Placement ($linked.Count -eq 0 -and $guestLink.Count -eq 1 -and
        $guestLink[0].EntityKey.SessionId -eq $guest.Id) 'link did not create only the requested session placement'
    Assert-Placement (@($source | LibTmux\Get-TmuxWindow | Where-Object { $_.Id -eq $window.Id -and $_.Index -eq 4 }).Count -eq 1) 'link changed its source placement'

    $moved = @($guestLink[0] | LibTmux\Move-TmuxWindow -Index 6 -NoSelect -PassThru -Confirm:$false)
    Assert-Placement ($moved.Count -eq 1 -and $moved[0] -is [LibTmux.Window] -and
        $moved[0].Id -eq $window.Id -and $moved[0].Index -eq 6 -and
        $moved[0].EntityKey.SessionId -eq $guest.Id -and $guestLink[0].Index -eq 5) 'move did not return a replacement placement'
    Assert-Placement (@($guest | LibTmux\Get-TmuxWindow | Where-Object { $_.Id -eq $window.Id -and $_.Index -eq 5 }).Count -eq 0) 'move retained the old guest placement'
    $staleFailure = $null
    try { $guestLink[0] | LibTmux\Remove-TmuxWindowLink -Confirm:$false -ErrorAction Stop }
    catch { $staleFailure = $_ }
    Assert-Placement ($null -ne $staleFailure -and $staleFailure.FullyQualifiedErrorId -like 'Tmux.WindowUnlinkFailed,*' -and
        @($guest | LibTmux\Get-TmuxWindow | Where-Object { $_.Id -eq $window.Id -and $_.Index -eq 6 }).Count -eq 1) 'stale placement unlinked a moved window'
    $unlinked = @($moved[0] | LibTmux\Remove-TmuxWindowLink -Confirm:$false)
    Assert-Placement ($unlinked.Count -eq 0 -and
        @($guest | LibTmux\Get-TmuxWindow | Where-Object Id -EQ $window.Id).Count -eq 0 -and
        @($source | LibTmux\Get-TmuxWindow | Where-Object Id -EQ $window.Id).Count -eq 1) 'unlink removed more than its captured placement'

    $traveller = $source | LibTmux\New-TmuxWindow -Name traveller -Index 9 -Command 'exec /bin/sh' -Confirm:$false
    Register-OwnedTmuxPane $fixture
    $travelled = @($traveller | LibTmux\Move-TmuxWindow -DestinationSession $guest -Index 8 -PassThru -Confirm:$false)
    Assert-Placement ($travelled.Count -eq 1 -and $travelled[0].Id -eq $traveller.Id -and
        $travelled[0].Index -eq 8 -and $travelled[0].EntityKey.SessionId -eq $guest.Id -and
        @($source | LibTmux\Get-TmuxWindow | Where-Object Id -EQ $traveller.Id).Count -eq 0 -and
        @($guest | LibTmux\Get-TmuxWindow | Where-Object Id -EQ $traveller.Id).Count -eq 1) 'cross-session move lost contextual placement'
    $travelled[0] | LibTmux\Remove-TmuxWindowLink -KillIfLast -Confirm:$false

    $beforePreview = [IO.File]::ReadAllLines($trace).Length
    $preview = @($window | LibTmux\New-TmuxWindowLink -Session $guest -Index 7 -WhatIf)
    $preview += @($window | LibTmux\Move-TmuxWindow -Index 7 -PassThru -WhatIf)
    $preview += @($window | LibTmux\Remove-TmuxWindowLink -KillIfLast -WhatIf)
    Assert-Placement ($preview.Count -eq 0 -and
        [IO.File]::ReadAllLines($trace).Length -eq $beforePreview -and
        @($guest | LibTmux\Get-TmuxWindow | Where-Object Id -EQ $window.Id).Count -eq 0 -and
        @($source | LibTmux\Get-TmuxWindow | Where-Object { $_.Id -eq $window.Id -and $_.Index -eq 4 }).Count -eq 1) 'WhatIf dispatched tmux, changed topology or returned output'

    $refused = $null
    try { $window | LibTmux\Remove-TmuxWindowLink -Confirm:$false -ErrorAction Stop }
    catch { $refused = $_ }
    Assert-Placement ($null -ne $refused -and $refused.FullyQualifiedErrorId -like 'Tmux.WindowUnlinkFailed,*' -and
        @($source | LibTmux\Get-TmuxWindow | Where-Object Id -EQ $window.Id).Count -eq 1) 'unlink removed the last link without KillIfLast'

    $foreignFixture = $fixture
    Invoke-WithOwnedTmux {
        param($other)
        $otherServer = LibTmux\New-TmuxServer -SocketPath $other.SocketPath -TmuxBinaryPath $other.TmuxPath -ConfigurationFile '/dev/null'
        $foreignSession = $otherServer | LibTmux\Get-TmuxSession -Name fixture
        $failure = $null
        try { $window | LibTmux\New-TmuxWindowLink -Session $foreignSession -Confirm:$false -ErrorAction Stop }
        catch { $failure = $_ }
        Assert-Placement ($null -ne $failure -and $failure.FullyQualifiedErrorId -like 'Tmux.WindowLinkFailed,*' -and
            @($foreignSession | LibTmux\Get-TmuxWindow | Where-Object Id -EQ $window.Id).Count -eq 0) 'link accepted a foreign endpoint with overlapping IDs'
        $failure = $null
        try { $window | LibTmux\Move-TmuxWindow -DestinationSession $foreignSession -Index 8 -Confirm:$false -ErrorAction Stop }
        catch { $failure = $_ }
        Assert-Placement ($null -ne $failure -and $failure.FullyQualifiedErrorId -like 'Tmux.WindowMoveFailed,*' -and
            @($source | LibTmux\Get-TmuxWindow | Where-Object { $_.Id -eq $window.Id -and $_.Index -eq 4 }).Count -eq 1) 'move accepted a foreign endpoint'
    }
    Assert-Placement (!$foreignFixture.Closed) 'foreign fixture cleanup closed the source server'

    $killed = @($window | LibTmux\Remove-TmuxWindowLink -KillIfLast -Confirm:$false)
    Assert-Placement ($killed.Count -eq 0 -and
        @($source | LibTmux\Get-TmuxWindow | Where-Object Id -EQ $window.Id).Count -eq 0) 'KillIfLast did not remove the final placement'
}

'PASS placement: linked identity, move replacement, unlink scope, previews, endpoint refusal and last-link guard'
