param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: child environments distinguish empty, absent, hidden and removed values.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"
function Assert-Environment([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Environment: $Message" }
}
foreach ($name in @('Get-TmuxEnvironment', 'Set-TmuxEnvironment', 'Remove-TmuxEnvironment')) {
    Assert-Environment ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "installed module has no $name"
}
$offline = LibTmux\New-TmuxServer -SocketName 'environment-preview' -TmuxBinaryPath '/missing-environment-preview'
Assert-Environment (@($offline | LibTmux\Set-TmuxEnvironment -Name 'APP_MODE' -Value '' -PassThru -WhatIf).Count -eq 0) 'set preview dispatched or emitted output'
Assert-Environment (@($offline | LibTmux\Remove-TmuxEnvironment -Name 'APP_MODE' -WhatIf).Count -eq 0) 'unset preview dispatched or emitted output'
Assert-Environment (@($offline | LibTmux\Remove-TmuxEnvironment -Name 'APP_MODE' -MarkRemoved -WhatIf).Count -eq 0) 'removal marker preview dispatched or emitted output'
Assert-Environment (@(@() | LibTmux\Get-TmuxEnvironment).Count -eq 0) 'empty read emitted output'
Assert-Environment (@(@() | LibTmux\Set-TmuxEnvironment -Name 'APP_MODE' -Value 'x' -PassThru).Count -eq 0) 'empty set emitted output'
Assert-Environment (@(@() | LibTmux\Remove-TmuxEnvironment -Name 'APP_MODE').Count -eq 0) 'empty removal emitted output'

function Get-ChildEnvironment($Fixture, $Session) {
    $name = 'environment-' + [Guid]::NewGuid().ToString('N')
    $program = Join-Path $Fixture.DirectoryPath "$name.sh"
    $output = Join-Path $Fixture.DirectoryPath "$name.txt"
    @'
printf '%s|%s|%s\n' "${LIBTMUX_PORT_ENV+x}" "${LIBTMUX_PORT_ENV-}" "${LIBTMUX_PORT_HIDDEN+x}" > "$1"
"$2" -S "$3" wait-for -S "$4"
exec /bin/cat
'@ | Set-Content -LiteralPath $program
    $arguments = @($program, $output, $Fixture.TmuxPath, $Fixture.SocketPath, $name) | ForEach-Object { "'" + $_.Replace("'", "'\''") + "'" }
    $window = $Session | LibTmux\New-TmuxWindow -Name $name -Command ('/bin/sh ' + ($arguments -join ' '))
    try {
        Register-OwnedTmuxPane $Fixture
        $null = $Session.Server | LibTmux\Wait-TmuxChannel -Channel $name -Timeout 0.5
        [IO.File]::ReadAllText($output).TrimEnd("`n")
    } finally { $window | LibTmux\Remove-TmuxWindow -Confirm:$false }
}

Invoke-WithOwnedTmux {
    param($fixture)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $session = $server | LibTmux\Get-TmuxSession -Name 'fixture'
    Assert-Environment (@($server | LibTmux\Set-TmuxEnvironment -Name 'LIBTMUX_PORT_ENV' -Value 'global').Count -eq 0) 'set emitted without PassThru'
    Assert-Environment (@($session | LibTmux\Get-TmuxEnvironment -Name 'LIBTMUX_PORT_ENV').Count -eq 0) 'local read invented inherited entry'
    $stored = $session | LibTmux\Set-TmuxEnvironment -Name 'LIBTMUX_PORT_ENV' -Value 'session' -PassThru
    Assert-Environment ($stored -is [LibTmux.TmuxEnvironmentEntry] -and $stored.Name -ceq 'LIBTMUX_PORT_ENV' -and $stored.Value -ceq 'session' -and !$stored.IsRemoved) 'native set readback lost value or state'
    Assert-Environment ((Get-ChildEnvironment $fixture $session) -ceq 'x|session|') 'new pane did not receive the local override'
    $empty = $session | LibTmux\Set-TmuxEnvironment -Name 'LIBTMUX_PORT_ENV' -Value '' -PassThru
    Assert-Environment ($empty.Value -ceq '' -and !$empty.IsRemoved -and (Get-ChildEnvironment $fixture $session) -ceq 'x||') 'empty value became absent'
    Assert-Environment (@($session | LibTmux\Remove-TmuxEnvironment -Name 'LIBTMUX_PORT_ENV' -MarkRemoved).Count -eq 0) 'mark removed emitted output'
    $removed = $session | LibTmux\Get-TmuxEnvironment -Name 'LIBTMUX_PORT_ENV'
    Assert-Environment ($removed.IsRemoved -and $null -eq $removed.Value -and (Get-ChildEnvironment $fixture $session) -ceq '||') 'removal marker did not suppress inheritance'
    $session | LibTmux\Remove-TmuxEnvironment -Name 'LIBTMUX_PORT_ENV'
    Assert-Environment (@($session | LibTmux\Get-TmuxEnvironment -Name 'LIBTMUX_PORT_ENV').Count -eq 0 -and
        (Get-ChildEnvironment $fixture $session) -ceq 'x|global|') 'unset did not forget the marker and restore global inheritance'

    $hidden = $server | LibTmux\Set-TmuxEnvironment -Name 'LIBTMUX_PORT_HIDDEN' -Value 'secret-for-formats' -Hidden -PassThru
    Assert-Environment ($hidden -is [LibTmux.TmuxEnvironmentEntry] -and $null -eq $hidden.Value -and !$hidden.IsRemoved -and
        @($server | LibTmux\Get-TmuxEnvironment -Name 'LIBTMUX_PORT_HIDDEN').Count -eq 0) 'hidden readback invented a visible value or removal marker'
    Assert-Environment ((Get-ChildEnvironment $fixture $session) -ceq 'x|global|') 'hidden variable leaked into a new child environment'
    $format = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $session.Id.ToString(), '#{LIBTMUX_PORT_HIDDEN}')).StdOut.TrimEnd("`n")
    Assert-Environment ($format -ceq 'secret-for-formats') 'hidden value was not available to tmux formats'
    $expanded = $session | LibTmux\Set-TmuxEnvironment -Name 'LIBTMUX_EXPANDED' -Value '#{session_name}' -ExpandFormats -PassThru
    Assert-Environment ($expanded.Value -ceq 'fixture') 'format expansion echoed the input'
    Assert-Environment (@($server | LibTmux\Get-TmuxEnvironment | Where-Object Name -EQ 'LIBTMUX_PORT_ENV').Count -eq 1 -and
        @($server | LibTmux\Get-TmuxEnvironment | Where-Object Name -EQ 'LIBTMUX_PORT_HIDDEN').Count -eq 0) 'all-environment read lost visible or hidden membership'

    $gone = $server | LibTmux\New-TmuxSession -Name 'gone' -Command 'exec /bin/sh'
    Register-OwnedTmuxPane $fixture
    $gone | LibTmux\Remove-TmuxSession -Confirm:$false
    $errors = @()
    $result = @(@($gone, $session) | LibTmux\Set-TmuxEnvironment -Name 'LIBTMUX_CONTINUED' -Value 'yes' -PassThru -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-Environment ($result.Count -eq 1 -and $result[0].Value -ceq 'yes' -and $errors.Count -eq 1 -and
        $errors[0].FullyQualifiedErrorId -like 'Tmux.EnvironmentSetFailed,*' -and [object]::ReferenceEquals($errors[0].TargetObject, $gone)) 'Continue lost failed owner or later result'
    $stopped = $false
    try { @($gone, $session) | LibTmux\Set-TmuxEnvironment -Name 'LIBTMUX_STOPPED' -Value 'no' -ErrorAction Stop } catch { $stopped = $true }
    Assert-Environment ($stopped -and @($session | LibTmux\Get-TmuxEnvironment -Name 'LIBTMUX_STOPPED').Count -eq 0) 'Stop continued mutation'
}
'PASS environment: native scopes, actual child inheritance, empty/unset/removed/hidden values, previews and errors'
