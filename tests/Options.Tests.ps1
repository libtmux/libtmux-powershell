param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: native option tables, inheritance and mutation readback need owned tmux.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-Option([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Options: $Message" }
}

foreach ($name in @('Get-TmuxOption', 'Set-TmuxOption', 'Remove-TmuxOption')) {
    Assert-Option ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "installed module has no $name"
}
$offline = LibTmux\New-TmuxServer -SocketName 'option-preview' -TmuxBinaryPath '/missing-option-preview'
Assert-Option (@($offline | LibTmux\Set-TmuxOption -Name '@preview' -Value 'x' -PassThru -WhatIf).Count -eq 0) 'set preview dispatched or emitted output'
Assert-Option (@($offline | LibTmux\Remove-TmuxOption -Name '@preview' -WhatIf).Count -eq 0) 'remove preview dispatched or emitted output'
Assert-Option (@(@() | LibTmux\Get-TmuxOption).Count -eq 0) 'empty read emitted output'
Assert-Option (@(@() | LibTmux\Set-TmuxOption -Name '@empty' -Value 'x' -PassThru).Count -eq 0) 'empty set emitted output'
Assert-Option (@(@() | LibTmux\Remove-TmuxOption -Name '@empty').Count -eq 0) 'empty remove emitted output'

Invoke-WithOwnedTmux {
    param($fixture)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $snapshot = $server | LibTmux\Get-TmuxSnapshot
    $session = $snapshot.Sessions[0]
    $window = $snapshot.Windows[0]
    $pane = $snapshot.Panes[0]
    foreach ($owner in @($server, $session, $window, $pane)) {
        $value = $owner.GetType().Name
        Assert-Option (@($owner | LibTmux\Set-TmuxOption -Name '@owner' -Value $value).Count -eq 0) 'set emitted without PassThru'
        $rows = @($owner | LibTmux\Get-TmuxOption -Name '@owner')
        Assert-Option ($rows.Count -eq 1 -and $rows[0] -is [LibTmux.TmuxOption] -and $rows[0].Value.Raw -ceq $value) 'owner scope or native result was lost'
    }
    $server | LibTmux\Set-TmuxOption -Scope Session -Global -Name 'status-keys' -Value 'vi'
    Assert-Option (@($session | LibTmux\Get-TmuxOption -Name 'status-keys' -Quiet).Count -eq 0) 'local read invented inherited membership'
    $inherited = $session | LibTmux\Get-TmuxOption -Name 'status-keys' -IncludeInherited
    Assert-Option ($inherited.Value.Raw -ceq 'vi' -and $inherited.Inherited) 'inherited value lost its marker'
    $session | LibTmux\Set-TmuxOption -Name 'status-keys' -Value 'emacs'
    Assert-Option (($session | LibTmux\Get-TmuxOption -Name 'status-keys').Value.Raw -ceq 'emacs') 'local override was not stored'
    Assert-Option (@($session | LibTmux\Remove-TmuxOption -Name 'status-keys').Count -eq 0) 'unset emitted output'
    Assert-Option (($session | LibTmux\Get-TmuxOption -Name 'status-keys' -IncludeInherited).Value.Raw -ceq 'vi') 'unset did not restore inheritance'

    $server | LibTmux\Set-TmuxOption -Scope Window -Global -Name 'mode-keys' -Value 'emacs'
    $window | LibTmux\Set-TmuxOption -Name 'mode-keys' -Value 'vi'
    $pane | LibTmux\Set-TmuxOption -Name 'mode-keys' -Value 'vi'
    $window | LibTmux\Remove-TmuxOption -Name 'mode-keys' -UnsetPaneOverrides
    Assert-Option (($pane | LibTmux\Get-TmuxOption -Name 'mode-keys' -IncludeInherited).Value.Raw -ceq 'emacs') 'wider unset retained pane override'

    $server | LibTmux\Set-TmuxOption -Name 'command-alias[40]' -Value 'forty=list-panes'
    $server | LibTmux\Set-TmuxOption -Name 'command-alias[90]' -Value 'ninety=list-windows'
    $aliases = @($server | LibTmux\Get-TmuxOption -Name 'command-alias')
    Assert-Option (@($aliases | Where-Object Index -EQ 40).Count -eq 1 -and @($aliases | Where-Object Index -EQ 39).Count -eq 0) 'array membership filled a sparse gap'
    $server | LibTmux\Remove-TmuxOption -Name 'command-alias[40]'
    Assert-Option (($server | LibTmux\Get-TmuxOption -Name 'command-alias[90]').Value.Raw -ceq 'ninety=list-windows') 'indexed removal removed another entry'

    $awkward = 'a"b\c $literal; d' + "`te"
    $stored = $session | LibTmux\Set-TmuxOption -Name '@raw' -Value $awkward -PassThru
    Assert-Option ($stored -is [LibTmux.TmuxOptionValue] -and $stored.Raw -ceq $awkward) 'PassThru lost native readback or literal text'
    $joined = $session | LibTmux\Set-TmuxOption -Name '@raw' -Value '-tail' -Append -PassThru
    Assert-Option ($joined.Raw -ceq ($awkward + '-tail')) 'append echoed only the supplied value'
    $expanded = $session | LibTmux\Set-TmuxOption -Name '@expanded' -Value '#{session_name}' -ExpandFormat -PassThru
    Assert-Option ($expanded.Raw -ceq 'fixture') 'format expansion readback is wrong'
    $empty = $session | LibTmux\Set-TmuxOption -Name '@empty' -Value '' -PassThru
    Assert-Option ($empty.Raw -ceq '' -and $empty.State -ne [LibTmux.TmuxOptionState]::Absent) 'empty value became absent'
    $errors = @()
    $result = @($session | LibTmux\Set-TmuxOption -Name '@raw' -Value 'ignored' -PreventOverwrite -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-Option ($result.Count -eq 0 -and $errors.Count -eq 1 -and $errors[0].Exception -is [LibTmux.TmuxOptionException] -and
        [object]::ReferenceEquals($errors[0].TargetObject, $session)) 'prevent-overwrite lost its original typed failure'
    $null = Invoke-OwnedTmux $fixture -Arguments @('set-hook', '-g', 'alert-bell', 'display-message rang')
    Assert-Option (@($server | LibTmux\Get-TmuxOption -Scope Session -Global -IncludeHooks | Where-Object Name -EQ 'alert-bell').Count -gt 0) 'all-option read omitted requested hooks'

    $gone = $server | LibTmux\New-TmuxSession -Name 'gone' -Command 'exec /bin/sh'
    Register-OwnedTmuxPane $fixture
    $gone | LibTmux\Remove-TmuxSession -Confirm:$false
    $errors = @()
    $output = @(@($gone, $session) | LibTmux\Set-TmuxOption -Name '@continued' -Value 'yes' -PassThru -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-Option ($output.Count -eq 1 -and $output[0].Raw -ceq 'yes' -and $errors.Count -eq 1 -and
        $errors[0].FullyQualifiedErrorId -like 'Tmux.OptionSetFailed,*' -and [object]::ReferenceEquals($errors[0].TargetObject, $gone)) 'per-owner Continue lost target or later result'
    $stopped = $false
    try { @($gone, $session) | LibTmux\Set-TmuxOption -Name '@stopped' -Value 'no' -ErrorAction Stop } catch { $stopped = $true }
    Assert-Option ($stopped -and @($session | LibTmux\Get-TmuxOption -Name '@stopped' -Quiet).Count -eq 0) 'ErrorAction Stop continued mutation'
}
'PASS options: native scopes, inheritance, arrays, readback, previews, errors and cleanup'
