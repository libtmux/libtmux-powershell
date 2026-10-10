param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: layout geometry and mutation readback require owned tmux.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-Layout([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Layout: $Message" }
}

foreach ($name in @('Set-TmuxLayout', 'Set-TmuxWindowSize', 'Set-TmuxPaneSize')) {
    Assert-Layout ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "installed module has no $name"
}

Invoke-WithOwnedTmux {
    param($fixture)
    $trace = Join-Path $fixture.DirectoryPath 'dispatch'
    $wrapper = Join-Path $fixture.DirectoryPath 'tmux'
    $quotedTrace = "'" + $trace.Replace("'", "'\''") + "'"
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' dispatch >> $quotedTrace
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper
    $window = $server | LibTmux\Get-TmuxWindow | Select-Object -First 1
    $originalWidth = $window.Width
    $resized = $window | LibTmux\Set-TmuxWindowSize -Width 120 -Height 40 -PassThru
    Assert-Layout ($resized -is [LibTmux.Window] -and $resized.Width -eq 120 -and $resized.Height -eq 40 -and
        $window.Width -eq $originalWidth -and ![object]::ReferenceEquals($window, $resized)) 'window size or immutable replacement failed'
    Assert-Layout (($resized | LibTmux\Get-TmuxOption -Name 'window-size').Value.Raw -ceq 'manual') 'resize did not select manual sizing'
    Assert-Layout (@($resized | LibTmux\Set-TmuxWindowSize -Height 38).Count -eq 0) 'window resize emitted without PassThru'
    $resized = $resized | LibTmux\Set-TmuxWindowSize -Direction Right -Adjustment 5 -PassThru
    Assert-Layout ($resized.Width -eq 125 -and $resized.Height -eq 38) 'directional window resize was not applied'
    $pane = $resized | LibTmux\Get-TmuxPane
    $null = $pane | LibTmux\Split-TmuxPane -Horizontal -Command 'exec /bin/cat'
    Register-OwnedTmuxPane $fixture
    $laidOut = $resized | LibTmux\Set-TmuxLayout -Layout 'even-horizontal' -PassThru
    $panes = @($laidOut | LibTmux\Get-TmuxPane)
    Assert-Layout ($laidOut -is [LibTmux.Window] -and $panes.Count -eq 2 -and
        $panes[0].Height -eq 38 -and $panes[0].Width -eq 62 -and $panes[1].Width -eq 62) 'horizontal layout geometry is wrong'
    $sized = $panes[0] | LibTmux\Set-TmuxPaneSize -Width '40' -PassThru
    Assert-Layout ($sized -is [LibTmux.Pane] -and $sized.Width -eq 40 -and $panes[0].Width -eq 62) 'pane absolute size or captured state changed'
    $sized = $sized | LibTmux\Set-TmuxPaneSize -Direction Right -Adjustment 3 -PassThru
    Assert-Layout ($sized.Width -eq 43) 'pane direction was ignored'
    $sized = $sized | LibTmux\Set-TmuxPaneSize -Width '50%' -PassThru
    Assert-Layout ($sized.Width -eq 62) 'pane percentage was not preserved'
    Assert-Layout (@($sized | LibTmux\Set-TmuxPaneSize -Zoom).Count -eq 0) 'zoom emitted without PassThru'
    $zoomed = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $sized.Id.ToString(), '#{window_zoomed_flag}')).StdOut.Trim()
    Assert-Layout ($zoomed -ceq '1') 'zoom did not toggle on'
    $sized | LibTmux\Set-TmuxPaneSize -Zoom
    Assert-Layout ((Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $sized.Id.ToString(), '#{window_zoomed_flag}')).StdOut.Trim() -ceq '0') 'second zoom did not toggle off'
    $null = $laidOut | LibTmux\Set-TmuxLayout -Mode Next -PassThru
    $null = $laidOut | LibTmux\Set-TmuxLayout -Mode Previous -PassThru
    $null = $laidOut | LibTmux\Set-TmuxLayout -Mode Spread -PassThru
    $saved = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $laidOut.Id.ToString(), '#{window_layout}')).StdOut.Trim()
    Assert-Layout (@($laidOut | LibTmux\Set-TmuxLayout -Layout $saved).Count -eq 0) 'saved layout emitted without PassThru'

    $beforeInvalid = [IO.File]::ReadAllLines($trace).Length
    foreach ($operation in @(
        { $window | LibTmux\Set-TmuxWindowSize },
        { $window | LibTmux\Set-TmuxWindowSize -Width 0 },
        { $window | LibTmux\Set-TmuxWindowSize -Width 10 -Mode Expand },
        { $pane | LibTmux\Set-TmuxPaneSize },
        { $pane | LibTmux\Set-TmuxPaneSize -Width '' },
        { $pane | LibTmux\Set-TmuxPaneSize -Width '0%' },
        { $pane | LibTmux\Set-TmuxPaneSize -Width 20 -Zoom },
        { $pane | LibTmux\Set-TmuxPaneSize -Width 40 -TrimBelow },
        { $pane | LibTmux\Set-TmuxPaneSize -Zoom:$false },
        { $window | LibTmux\Set-TmuxLayout -Layout '' },
        { $window | LibTmux\Set-TmuxLayout -Layout 'even' }
    )) {
        $failed = $false
        try { & $operation } catch { $failed = $true }
        Assert-Layout $failed "invalid operation was accepted: $($operation.ToString().Trim())"
    }
    Assert-Layout ([IO.File]::ReadAllLines($trace).Length -eq $beforeInvalid) 'invalid input dispatched tmux'
    $beforePreview = [IO.File]::ReadAllLines($trace).Length
    $before = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $window.Id.ToString(), '#{window_layout}')).StdOut
    $transcript = Join-Path $fixture.DirectoryPath 'preview.txt'
    $null = Start-Transcript -Path $transcript
    try {
        Assert-Layout (@($window | LibTmux\Set-TmuxWindowSize -Width 90 -WhatIf -PassThru).Count -eq 0) 'window preview output'
        Assert-Layout (@($pane | LibTmux\Set-TmuxPaneSize -Width 30 -WhatIf -PassThru).Count -eq 0) 'pane preview output'
        Assert-Layout (@($window | LibTmux\Set-TmuxLayout -Layout tiled -WhatIf -PassThru).Count -eq 0) 'layout preview output'
    } finally { $null = Stop-Transcript }
    $preview = [IO.File]::ReadAllText($transcript)
    Assert-Layout ([regex]::Matches($preview, [regex]::Escape("$($fixture.SocketPath) window $($window.Id)")).Count -eq 2 -and
        [regex]::Matches($preview, [regex]::Escape("$($fixture.SocketPath) pane $($pane.Id)")).Count -eq 1) 'mutation previews omitted the owning endpoint or native target'
    Assert-Layout ([IO.File]::ReadAllLines($trace).Length -eq $beforePreview) 'preview dispatched tmux'
    Assert-Layout ((Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $window.Id.ToString(), '#{window_layout}')).StdOut -ceq $before) 'preview mutated layout'
    $gone = $server | LibTmux\New-TmuxSession -Name 'gone' -Command 'exec /bin/cat'
    Register-OwnedTmuxPane $fixture
    $goneWindow = $gone | LibTmux\Get-TmuxWindow
    $gone | LibTmux\Remove-TmuxSession -Confirm:$false
    $errors = @()
    $output = @(@($goneWindow, $window) | LibTmux\Set-TmuxLayout -Layout tiled -PassThru -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-Layout ($output.Count -eq 1 -and $errors.Count -eq 1 -and
        $errors[0].FullyQualifiedErrorId -like 'Tmux.LayoutSetFailed,*' -and
        [object]::ReferenceEquals($errors[0].TargetObject, $goneWindow)) 'per-window error lost target or later result'
}
'PASS layout: native sizes, geometry, zoom toggle, captured state, validation, preview and cleanup'
