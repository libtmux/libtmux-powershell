param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: indexed hook mutation and invocation need an owned tmux server.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"
function Assert-Hook([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Hooks: $Message" }
}
foreach ($name in @('Get-TmuxHook', 'Set-TmuxHook', 'Invoke-TmuxHook', 'Remove-TmuxHook')) {
    Assert-Hook ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "installed module has no $name"
}
$offline = LibTmux\New-TmuxServer -SocketName 'hook-preview' -TmuxBinaryPath '/missing-hook-preview'
Assert-Hook (@($offline | LibTmux\Set-TmuxHook -Name 'alert-bell' -Command 'display-message preview' -PassThru -WhatIf).Count -eq 0) 'set preview dispatched or emitted output'
Assert-Hook (@($offline | LibTmux\Invoke-TmuxHook -Name 'alert-bell' -WhatIf).Count -eq 0) 'invoke preview dispatched or emitted output'
Assert-Hook (@($offline | LibTmux\Remove-TmuxHook -Name 'alert-bell' -WhatIf).Count -eq 0) 'remove preview dispatched or emitted output'
$rejected = $false
try { $offline | LibTmux\Get-TmuxHook -Name 'alert-bell[7]' } catch {
    if ($_.FullyQualifiedErrorId -notlike 'Tmux.IndexedHookReadNotSupported,*') { throw }
    $rejected = $true
}
Assert-Hook $rejected 'indexed Get silently became a missing grouped hook'
Assert-Hook (@(@() | LibTmux\Get-TmuxHook).Count -eq 0) 'empty read emitted output'
Assert-Hook (@(@() | LibTmux\Set-TmuxHook -Name 'alert-bell' -Command 'display-message x' -PassThru).Count -eq 0) 'empty set emitted output'
Assert-Hook (@(@() | LibTmux\Invoke-TmuxHook -Name 'alert-bell').Count -eq 0) 'empty invoke emitted output'
Assert-Hook (@(@() | LibTmux\Remove-TmuxHook -Name 'alert-bell').Count -eq 0) 'empty remove emitted output'
Invoke-WithOwnedTmux {
    param($fixture)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $snapshot = $server | LibTmux\Get-TmuxSnapshot
    $session, $window, $pane = $snapshot.Sessions[0], $snapshot.Windows[0], $snapshot.Panes[0]
    foreach ($owner in @($server, $session, $window, $pane)) {
        $marker = $owner.GetType().Name
        $hookName = switch ($marker) { 'Window' { 'pane-focus-in' } 'Pane' { 'pane-focus-out' } default { 'alert-bell' } }
        Assert-Hook (@($owner | LibTmux\Set-TmuxHook -Name $hookName -Command "display-message $marker").Count -eq 0) 'set emitted without PassThru'
        $hook = $owner | LibTmux\Get-TmuxHook -Name $hookName
        Assert-Hook ($hook -is [LibTmux.TmuxHook] -and $hook.Values.Count -eq 1 -and $hook.Values[0].Command.Contains($marker)) "owner scope or native grouped result lost for $marker`: $($hook | Out-String)"
    }
    $global = $session | LibTmux\Get-TmuxHook -Global -Name 'alert-bell'
    Assert-Hook ($global.Values[0].Command.Contains('Server')) 'global read selected the local session hook'
    $session | LibTmux\Remove-TmuxHook -Name 'alert-bell'
    Assert-Hook (@($session | LibTmux\Get-TmuxHook -Name 'alert-bell').Count -eq 0) 'missing local hook emitted a null row or inherited global hook'
    $first = $session | LibTmux\Set-TmuxHook -Name 'alert-bell[7]' -Command 'display-message "hello world"' -PassThru
    Assert-Hook ($first -is [LibTmux.TmuxHook] -and $first.Values[0].Index -eq 7) 'indexed set lost native readback'
    $again = $session | LibTmux\Set-TmuxHook -Name 'alert-bell[7]' -Command $first.Values[0].Command -PassThru
    Assert-Hook ($again.Values[0].Command -ceq $first.Values[0].Command) 'normalized tmux command did not round-trip'
    $session | LibTmux\Set-TmuxHook -Name 'alert-bell[19]' -Command 'display-message nineteen'
    $sparse = $session | LibTmux\Get-TmuxHook -Name 'alert-bell'
    Assert-Hook (($sparse.Values.Index -join ',') -ceq '7,19') 'sparse hook entries lost indices'
    $appended = $session | LibTmux\Set-TmuxHook -Name 'alert-bell' -Command 'display-message appended' -Append -PassThru
    Assert-Hook (($appended.Values.Index -join ',') -ceq '0,7,19' -and $appended.Values[0].Command.Contains('appended')) 'append replaced existing entries'
    $session | LibTmux\Remove-TmuxHook -Name 'alert-bell[7]'
    $remaining = $session | LibTmux\Get-TmuxHook -Name 'alert-bell'
    Assert-Hook (($remaining.Values.Index -join ',') -ceq '0,19') 'indexed remove erased unrelated entries'
    Assert-Hook (@($session | LibTmux\Get-TmuxHook | Where-Object Name -EQ 'alert-bell').Count -eq 1) 'Get all omitted grouped hook'

    $channel = 'hook-' + [Guid]::NewGuid().ToString('N')
    $session | LibTmux\Set-TmuxHook -Name 'alert-bell' -Command "wait-for -S $channel"
    Assert-Hook (@($session | LibTmux\Invoke-TmuxHook -Name 'alert-bell').Count -eq 0) 'invoke emitted output'
    Assert-Hook ($server | LibTmux\Wait-TmuxChannel -Channel $channel -Timeout 10) 'hook command did not signal completion'
    $session | LibTmux\Remove-TmuxHook -Name 'alert-bell'
    Assert-Hook (@($session | LibTmux\Get-TmuxHook -Name 'alert-bell').Count -eq 0 -and
        @($server | LibTmux\Get-TmuxHook -Name 'alert-bell').Count -eq 1) 'local removal changed global table'

    $gone = $server | LibTmux\New-TmuxSession -Name 'gone' -Command 'exec /bin/sh'
    Register-OwnedTmuxPane $fixture
    $gone | LibTmux\Remove-TmuxSession -Confirm:$false
    $errors = @()
    $result = @(@($gone, $session) | LibTmux\Set-TmuxHook -Name 'alert-bell' -Command 'display-message continued' -PassThru -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-Hook ($result.Count -eq 1 -and $errors.Count -eq 1 -and
        $errors[0].FullyQualifiedErrorId -like 'Tmux.HookSetFailed,*' -and [object]::ReferenceEquals($errors[0].TargetObject, $gone)) 'Continue lost failed owner or later result'
    $session | LibTmux\Remove-TmuxHook -Name 'alert-bell'
    $stopped = $false
    try { @($gone, $session) | LibTmux\Set-TmuxHook -Name 'alert-bell' -Command 'display-message stopped' -ErrorAction Stop } catch { $stopped = $true }
    Assert-Hook ($stopped -and @($session | LibTmux\Get-TmuxHook -Name 'alert-bell').Count -eq 0) 'Stop continued mutation'
}
'PASS hooks: native scopes, indexed mutations, grouped readback, invocation signal, previews and errors'
