param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: client observations require a live owned control client.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-Client([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Clients: $Message" }
}

foreach ($name in @('Get-TmuxClient', 'Update-TmuxClient', 'Get-TmuxClientAttachment')) {
    Assert-Client ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "installed module has no $name"
}
Assert-Client (@(@() | LibTmux\Get-TmuxClient).Count -eq 0) 'empty list pipeline emitted output'
Assert-Client (@(@() | LibTmux\Update-TmuxClient).Count -eq 0) 'empty refresh pipeline emitted output'
Assert-Client (@(@() | LibTmux\Get-TmuxClientAttachment).Count -eq 0) 'empty attachment pipeline emitted output'

Invoke-WithOwnedTmux {
    param($fixture)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    Assert-Client (@($server | LibTmux\Get-TmuxClient).Count -eq 0) 'no-client server did not return zero objects'
    $session = $server | LibTmux\Get-TmuxSession -Name 'fixture'
    $other = $server | LibTmux\New-TmuxSession -Name 'other' -Command 'exec /bin/cat'
    Register-OwnedTmuxPane $fixture
    $control = $server.EnterControlModeAsync($session.Id.ToString()).GetAwaiter().GetResult()
    try {
        $rows = @($server | LibTmux\Get-TmuxClient)
        Assert-Client ($rows.Count -eq 1 -and $rows[0] -is [LibTmux.Client] -and $rows[0].IsControlClient) 'native client discovery failed'
        $client = $rows[0]
        Assert-Client (@($server | LibTmux\Get-TmuxClient -Name '*').Count -eq 0) 'name selector unexpectedly matched a wildcard'
        Assert-Client (($server | LibTmux\Get-TmuxClient -Name $client.Name).Equals($client)) 'exact name selector failed'
        $attachment = $client | LibTmux\Get-TmuxClientAttachment
        Assert-Client ($attachment -is [LibTmux.ClientAttachment] -and $attachment.Session.Id -eq $session.Id -and
            $attachment.Window -is [LibTmux.Window] -and $attachment.Pane -is [LibTmux.Pane]) 'native attachment graph failed'
        $null = Invoke-OwnedTmux $fixture -Arguments @('switch-client', '-c', $client.Name, '-t', $other.Id.ToString())
        $current = $client | LibTmux\Update-TmuxClient
        Assert-Client ($current -is [LibTmux.Client] -and $current.AttachedSessionId -eq $other.Id -and
            $client.AttachedSessionId -eq $session.Id -and ![object]::ReferenceEquals($client, $current)) 'refresh changed captured attachment or failed to read current state'
        Assert-Client (($client | LibTmux\Get-TmuxClientAttachment).Session.Id -eq $other.Id) 'attachment resolved captured rather than live session'
    } finally {
        $null = $control.DisposeAsync().AsTask().GetAwaiter().GetResult()
    }
    Assert-Client (@($client | LibTmux\Get-TmuxClientAttachment).Count -eq 0) 'detached attachment emitted a null wrapper'
    $errors = @()
    $result = @($client | LibTmux\Update-TmuxClient -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-Client ($result.Count -eq 0 -and $errors.Count -eq 1 -and
        $errors[0].Exception -is [LibTmux.TmuxObjectNotFoundException] -and
        [object]::ReferenceEquals($errors[0].TargetObject, $client)) 'disappeared client lost native error or target'
    Assert-Client (@($server | LibTmux\Get-TmuxSession).Count -eq 2) 'client cleanup removed the daemon or sessions'
}
'PASS clients: typed discovery, literal names, live attachment, captured replacement, disappearance and cleanup'
