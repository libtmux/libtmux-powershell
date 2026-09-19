param([Parameter(Mandatory)] [string] $ModuleRoot)

# Integration: captured views remain usable after their owned daemon exits.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$directory = [IO.Directory]::CreateTempSubdirectory('libtmux-powershell-format-').FullName
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
        $null = Invoke-OwnedTmux $fixture -Arguments @('rename-window', '-t', 'fixture:0', 'ViewWindow')
        $null = Invoke-OwnedTmux $fixture -Arguments @('select-pane', '-t', 'fixture:0.0', '-T', 'ViewPane')
        $endpoint = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper -ConfigurationFile '/dev/null'
        $server = $endpoint | LibTmux\Connect-TmuxServer
        $snapshot = $server | LibTmux\Get-TmuxSnapshot
        $session = $snapshot.Sessions[0]
        $window = $snapshot.Windows[0]
        $pane = $snapshot.Panes[0]
        $token = [Threading.CancellationToken]::None
        $identitySession = $server.GetSessionAsync($session.Id, $token).GetAwaiter().GetResult()
        $identityWindow = $server.GetWindowAsync($window.Id, $token).GetAwaiter().GetResult()
        $identityPane = $server.GetPaneAsync($pane.Id, $token).GetAwaiter().GetResult()

        $control = $server.EnterControlModeAsync('fixture', $token).WaitAsync([TimeSpan]::FromSeconds(1)).GetAwaiter().GetResult()
        $clientProcess = $null
        try {
            $clients = $server.GetClientsAsync($token).GetAwaiter().GetResult()
            Assert-True ($clients.Count -eq 1 -and $clients[0].IsControlClient) 'The formatting fixture did not capture its control client.'
            $client = $clients[0]
            $clientProcess = [Diagnostics.Process]::GetProcessById([int] $client.RawFormatFields['client_pid'])
            $state.Groups = @(
                @{ Values = @($session, $identitySession); Headers = @('Id', 'Name', 'ServerPID'); Expected = 'fixture' },
                @{ Values = @($window, $identityWindow); Headers = @('Id', 'Name', 'Session', 'Index'); Expected = 'ViewWindow' },
                @{ Values = @($pane, $identityPane); Headers = @('Id', 'Title', 'Window', 'Index'); Expected = 'ViewPane' },
                @{ Values = @($client); Headers = @('Name', 'Session', 'Control', 'ServerPID'); Expected = $client.Name },
                @{ Values = @($endpoint, $server); Headers = @('Socket', 'ServerPID', 'Connected'); Expected = $fixture.SocketPath }
            )
            $state.SocketPath = $fixture.SocketPath
        } finally {
            $null = $control.DisposeAsync().AsTask().WaitAsync([TimeSpan]::FromSeconds(1)).GetAwaiter().GetResult()
            if ($clientProcess) {
                try { Assert-True ($clientProcess.WaitForExit(1000)) 'The formatting control client did not exit.' }
                finally { $clientProcess.Dispose() }
            }
        }
    }

    Assert-True (-not (Test-Path -LiteralPath $state.SocketPath)) 'Formatting began before daemon teardown.'
    $callsBefore = [IO.File]::ReadAllLines($trace).Length
    foreach ($group in $state.Groups) {
        $formatErrors = @()
        $formatFailed = $false
        $text = ''
        try {
            $text = $group.Values | Format-Table -ShowError -DisplayError -ErrorAction Continue -ErrorVariable formatErrors 2>$null | Out-String -Width 160
        } catch { $formatFailed = $true }
        Assert-True (-not $formatFailed -and $formatErrors.Count -eq 0 -and $text -notmatch '#ERR') 'Formatting emitted an error for a captured or identity-only handle.'
        Assert-True ($text -notmatch 'RawFormatFields|CapturedDepth') 'Default formatting exposed the internal field dump.'
        foreach ($header in $group.Headers) {
            Assert-True ($text -match "\b$header\b") "Formatting omitted the $header column."
        }
        Assert-True ($text.Contains($group.Expected)) "Formatting $($group.Values[0].GetType().Name) omitted '$($group.Expected)'. Rendered: $text"
        $memberErrors = @()
        $members = @($group.Values | Get-Member -ErrorVariable memberErrors)
        Assert-True ($members.Count -gt 0 -and $memberErrors.Count -eq 0) 'Get-Member failed after teardown.'
    }
    Assert-True ([IO.File]::ReadAllLines($trace).Length -eq $callsBefore) 'Formatting or Get-Member invoked tmux.'
    'PASS: captured and identity-only views format locally after daemon and client teardown'
} finally {
    Remove-Item -LiteralPath $directory -Recurse -Force
}
