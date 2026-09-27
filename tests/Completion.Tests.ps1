param([Parameter(Mandatory)] [string] $ModuleRoot)

# Integration: Tab completion reads a captured graph after its daemon exits.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-Completion([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Completion: $Message" }
}

$directory = [IO.Directory]::CreateTempSubdirectory('libtmux-powershell-completion-').FullName
$trace = Join-Path $directory 'calls'
$wrapper = Join-Path $directory 'tmux'
$tmux = (Get-Command tmux -CommandType Application | Select-Object -First 1).Source
$quotedTmux = "'" + $tmux.Replace("'", "'\''") + "'"
$quotedTrace = "'" + $trace.Replace("'", "'\''") + "'"
@"
#!/bin/sh
printf '%s\n' tmux >> $quotedTrace
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
[IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor
    [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)

try {
    $state = @{}
    Invoke-WithOwnedTmux {
        param($fixture)
        $null = Invoke-OwnedTmux $fixture -Arguments @('rename-window', '-t', 'fixture:0', 'Main Window')
        $endpoint = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper -ConfigurationFile '/dev/null'
        $snapshot = $endpoint | LibTmux\Get-TmuxSnapshot
        Assert-Completion ($snapshot.Sessions.IsCaptured -and $snapshot.Windows.IsCaptured -and $snapshot.Panes.IsCaptured) 'fixture did not capture the graph'
        $state.Server = $snapshot
        $state.Session = $snapshot.Sessions[0]
        $state.Window = $snapshot.Windows[0]
        $state.Pane = $snapshot.Panes[0]
        $state.SocketPath = $fixture.SocketPath
    }

    Assert-Completion (!(Test-Path -LiteralPath $state.SocketPath)) 'completion began before daemon teardown'
    $before = @([IO.File]::ReadAllLines($trace)).Count
    Set-Variable -Name capturedServer -Value $state.Server
    Set-Variable -Name capturedSession -Value $state.Session
    Set-Variable -Name capturedWindow -Value $state.Window

    $line = 'Get-TmuxSession -Server $capturedServer -Name fi'
    $completion = TabExpansion2 -InputScript $line -CursorColumn $line.Length
    $sessions = @($completion.CompletionMatches | ForEach-Object CompletionText)
    Assert-Completion ($sessions -contains "'fixture'") 'captured session name was not offered'

    $line = 'Get-TmuxSession -Server $capturedServer -Id '
    $completion = TabExpansion2 -InputScript $line -CursorColumn $line.Length
    $sessionIds = @($completion.CompletionMatches | ForEach-Object CompletionText)
    Assert-Completion ($sessionIds -contains "'$($state.Session.Id)'") 'captured session ID was not quoted as a literal'

    $line = 'Get-TmuxWindow -Session $capturedSession -Name Ma'
    $completion = TabExpansion2 -InputScript $line -CursorColumn $line.Length
    $windows = @($completion.CompletionMatches | ForEach-Object CompletionText)
    Assert-Completion ($windows -contains "'Main Window'") 'captured window name was not quoted and offered'

    $line = 'Get-TmuxPane -Window $capturedWindow -Id %'
    $completion = TabExpansion2 -InputScript $line -CursorColumn $line.Length
    $panes = @($completion.CompletionMatches | ForEach-Object CompletionText)
    Assert-Completion ($panes -contains "'$($state.Pane.Id)'") 'captured pane ID was not offered as a literal'

    Set-Variable -Name uncaptured -Value (LibTmux\New-TmuxServer -SocketPath $state.SocketPath -TmuxBinaryPath $wrapper)
    $line = 'Get-TmuxSession -Server $uncaptured -Name fi'
    $completion = TabExpansion2 -InputScript $line -CursorColumn $line.Length
    Assert-Completion (@($completion.CompletionMatches | ForEach-Object CompletionText) -notcontains "'fixture'") 'uncaptured owner invented a live suggestion'

    $spoof = [pscustomobject] @{}
    $propertyRead = Join-Path $directory 'arbitrary-property-read'
    $spoof | Add-Member -MemberType ScriptProperty -Name Sessions -Value ({
        [IO.File]::WriteAllText($propertyRead, 'read')
        throw 'arbitrary property was read'
    }.GetNewClosure())
    $line = 'Get-TmuxSession -Server $spoof -Name fi'
    $null = TabExpansion2 -InputScript $line -CursorColumn $line.Length
    Assert-Completion (!(Test-Path -LiteralPath $propertyRead)) 'Tab completion read an arbitrary Sessions property'
    Assert-Completion (@([IO.File]::ReadAllLines($trace)).Count -eq $before) 'Tab completion invoked tmux or an arbitrary property'

    'PASS completion: captured literal selectors and no tmux I/O after teardown'
} finally {
    Remove-Item -LiteralPath $directory -Recurse -Force
}
