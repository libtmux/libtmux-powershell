param([Parameter(Mandatory)] [string] $ModuleRoot)

# Integration: removals use owned daemons and retain unrelated anchor sessions.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

foreach ($name in @('Remove-TmuxSession', 'Remove-TmuxWindow', 'Remove-TmuxPane')) {
    Assert-True ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "Installed module does not export $name."
}

. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-EntityPresent($Fixture, [string] $Kind, [string] $Id, [bool] $Present) {
    $arguments = switch ($Kind) {
        'Session' { @('list-sessions', '-F', '#{session_id}') }
        'Window' { @('list-windows', '-a', '-F', '#{window_id}') }
        'Pane' { @('list-panes', '-a', '-F', '#{pane_id}') }
    }
    $result = Invoke-OwnedTmux $Fixture -Arguments $arguments
    $ids = $result.StdOut.Split("`n", [StringSplitOptions]::RemoveEmptyEntries)
    Assert-True (($ids -ccontains $Id) -eq $Present) "$Kind $Id presence at $($Fixture.SocketPath) differs from requested presence $Present."
}

function Invoke-CreationForRemoval([string] $Kind, $Server, $Session, $Pane) {
    $name = 'remove-' + [Guid]::NewGuid().ToString('N')
    switch ($Kind) {
        'Session' { $Server | LibTmux\New-TmuxSession -Name $name -Command 'exec /bin/sh' -Confirm:$false }
        'Window' { $Session | LibTmux\New-TmuxWindow -Name $name -Command 'exec /bin/sh' -Confirm:$false }
        'Pane' { $Pane | LibTmux\Split-TmuxPane -Command 'exec /bin/sh' -Confirm:$false }
    }
}

function Invoke-OwnedServerReplacement($Fixture, [Threading.Tasks.Task] $SocketReadyTask) {
    $previous = $Fixture.ServerProcess
    $signal = $null
    try {
        Register-OwnedTmuxPane $Fixture
        $null = Invoke-OwnedTmux $Fixture -Arguments @('kill-server')
        Assert-True ($previous.WaitForExit(1000)) 'The replaced owned daemon did not exit.'
        $signal = [LibTmux.Testing.SocketCreatedSignal]::new($Fixture.DirectoryPath)
        $Fixture.ServerStarted = $false
        $Fixture.ServerProcess = [Diagnostics.Process]::new()
        $Fixture.ServerProcess.StartInfo = New-OwnedTmuxStartInfo $Fixture @('-D')
        $Fixture.ServerStarted = $Fixture.ServerProcess.Start()
        $Fixture.ServerPid = $Fixture.ServerProcess.Id
        $null = $Fixture.OwnedProcessIds.Add($Fixture.ServerPid)
        $Fixture.ServerOutput = $Fixture.ServerProcess.StandardOutput.ReadToEndAsync()
        $Fixture.ServerError = $Fixture.ServerProcess.StandardError.ReadToEndAsync()
        $socketSignal = if ($SocketReadyTask) { $SocketReadyTask } else { $signal.Ready }
        Wait-OwnedTmuxSocketReady $Fixture $socketSignal
        Assert-True (-not $Fixture.ServerProcess.HasExited) 'The replacement daemon exited before socket readiness.'
        if ($socketSignal.IsCompleted) { $null = $socketSignal.GetAwaiter().GetResult() }
        $null = Invoke-OwnedTmux $Fixture -Arguments @('new-session', '-d', '-s', 'fixture', 'exec /bin/sh')
        Register-OwnedTmuxPane $Fixture
    } finally {
        if ($signal) { $signal.Dispose() }
        if (-not [Object]::ReferenceEquals($previous, $Fixture.ServerProcess)) { $previous.Dispose() }
    }
}

Invoke-WithOwnedTmux {
    param($fixture)

    $trace = Join-Path $fixture.DirectoryPath 'calls'
    $wrapper = Join-Path $fixture.DirectoryPath 'tmux'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    $quotedTrace = "'" + $trace.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' tmux >> $quotedTrace
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper -ConfigurationFile '/dev/null'
    $anchor = $server | LibTmux\Get-TmuxSession -Name 'fixture'
    $anchorWindow = $anchor | LibTmux\Get-TmuxWindow | Select-Object -First 1
    $anchorPane = $anchorWindow | LibTmux\Get-TmuxPane | Select-Object -First 1

    foreach ($kind in @('Session', 'Window', 'Pane')) {
        $command = "LibTmux\Remove-Tmux$kind"
        $entity = Invoke-CreationForRemoval $kind $server $anchor $anchorPane
        Register-OwnedTmuxPane $fixture
        $entityId = $entity.Id.ToString()
        $fields = $entity.RawFormatFields
        $before = [IO.File]::ReadAllLines($trace).Length
        $output = @($entity | & $command -WhatIf)
        $output += @(@() | & $command -Confirm:$false)
        Assert-True ($output.Count -eq 0 -and [IO.File]::ReadAllLines($trace).Length -eq $before) "$command preview or empty pipeline dispatched or emitted output."
        $errors = @()
        [pscustomobject]@{ Id = $entityId } | & $command -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable errors
        Assert-True ($errors.Count -eq 1 -and [IO.File]::ReadAllLines($trace).Length -eq $before) "$command rebound an arbitrary Id property or ignored invalid input."

        $output = @($entity | & $command -Confirm:$false)
        Assert-True ($output.Count -eq 0) "$command emitted a success object."
        Assert-EntityPresent $fixture $kind $entityId $false
        Assert-True ([Object]::ReferenceEquals($fields, $entity.RawFormatFields)) "$command changed the removed handle's captured fields."

        $continued = Invoke-CreationForRemoval $kind $server $anchor $anchorPane
        Register-OwnedTmuxPane $fixture
        $errors = @()
        $output = @(@($entity, $continued) | & $command -Confirm:$false -ErrorAction Continue -ErrorVariable errors 2>$null)
        Assert-True ($output.Count -eq 0 -and $errors.Count -eq 1 -and
            $errors[0].FullyQualifiedErrorId -like "Tmux.${kind}RemoveFailed,*" -and
            [Object]::ReferenceEquals($errors[0].TargetObject, $entity) -and
            $errors[0].Exception -is [LibTmux.TmuxCommandException] -and
            $errors[0].Exception.Dispatch -eq [LibTmux.TmuxDispatchState]::Dispatched) "$command lost a target failure or its dispatch state."
        Assert-EntityPresent $fixture $kind $continued.Id.ToString() $false

        $retained = Invoke-CreationForRemoval $kind $server $anchor $anchorPane
        Register-OwnedTmuxPane $fixture
        $stopped = $null
        try { @($entity, $retained) | & $command -Confirm:$false -ErrorAction Stop | Out-Null }
        catch { $stopped = $_ }
        Assert-True ($null -ne $stopped -and $stopped.FullyQualifiedErrorId -like "Tmux.${kind}RemoveFailed,*") "$command ignored ErrorAction Stop."
        Assert-EntityPresent $fixture $kind $retained.Id.ToString() $true

        $many = @(
            Invoke-CreationForRemoval $kind $server $anchor $anchorPane
            Invoke-CreationForRemoval $kind $server $anchor $anchorPane
        )
        Register-OwnedTmuxPane $fixture
        $output = @($many | & $command -Confirm:$false)
        Assert-True ($output.Count -eq 0) "$command emitted results for a multiple-owner pipeline."
        foreach ($item in $many) { Assert-EntityPresent $fixture $kind $item.Id.ToString() $false }
        Assert-EntityPresent $fixture $kind $retained.Id.ToString() $true
    }

    $first = $server | LibTmux\New-TmuxSession -Name 'links-first' -Command 'exec /bin/sh' -Confirm:$false
    $second = $server | LibTmux\New-TmuxSession -Name 'links-second' -Command 'exec /bin/sh' -Confirm:$false
    $shared = $first | LibTmux\New-TmuxWindow -Name 'shared' -Command 'exec /bin/sh' -Confirm:$false
    Register-OwnedTmuxPane $fixture
    $null = Invoke-OwnedTmux $fixture -Arguments @('link-window', '-s', $shared.Id.ToString(), '-t', "$($first.Id):5")
    $null = Invoke-OwnedTmux $fixture -Arguments @('link-window', '-s', $shared.Id.ToString(), '-t', "$($second.Id):5")
    $links = @($first | LibTmux\Get-TmuxWindow | Where-Object Id -EQ $shared.Id)
    Assert-True ($links.Count -eq 2) 'Linked-window removal setup did not create repeated same-session placements.'
    $output = @($links[1] | LibTmux\Remove-TmuxWindow -Confirm:$false)
    Assert-True ($output.Count -eq 0) 'Removing a linked physical window emitted output.'
    Assert-EntityPresent $fixture 'Window' $shared.Id.ToString() $false
    Assert-EntityPresent $fixture 'Session' $first.Id.ToString() $true
    Assert-EntityPresent $fixture 'Session' $second.Id.ToString() $true

    $survivor = $first | LibTmux\Get-TmuxWindow | Select-Object -First 1
    $survivorPane = $survivor | LibTmux\Get-TmuxPane | Select-Object -First 1
    $null = Invoke-OwnedTmux $fixture -Arguments @('link-window', '-s', $survivor.Id.ToString(), '-t', "$($second.Id):6")
    $output = @($first | LibTmux\Remove-TmuxSession -Confirm:$false)
    Assert-True ($output.Count -eq 0) 'Removing a session emitted output.'
    Assert-EntityPresent $fixture 'Session' $first.Id.ToString() $false
    Assert-EntityPresent $fixture 'Window' $survivor.Id.ToString() $true
    Assert-EntityPresent $fixture 'Pane' $survivorPane.Id.ToString() $true

    $cascade = $server | LibTmux\New-TmuxSession -Name 'cascade' -Command 'exec /bin/sh' -Confirm:$false
    $cascadeWindow = $cascade | LibTmux\Get-TmuxWindow | Select-Object -First 1
    $cascadePane = $cascadeWindow | LibTmux\Get-TmuxPane | Select-Object -First 1
    Register-OwnedTmuxPane $fixture
    $output = @($cascadePane | LibTmux\Remove-TmuxPane -Confirm:$false)
    Assert-True ($output.Count -eq 0) 'Removing the last pane emitted output.'
    Assert-EntityPresent $fixture 'Pane' $cascadePane.Id.ToString() $false
    Assert-EntityPresent $fixture 'Window' $cascadeWindow.Id.ToString() $false
    Assert-EntityPresent $fixture 'Session' $cascade.Id.ToString() $false

    $primaryFixture = $fixture
    Invoke-WithOwnedTmux {
        param($other)
        $otherServer = LibTmux\New-TmuxServer -SocketPath $other.SocketPath -ConfigurationFile '/dev/null'
        $otherWindow = $otherServer | LibTmux\Get-TmuxWindow | Select-Object -First 1
        Assert-True ($otherWindow.Id -eq $anchorWindow.Id) 'Endpoint isolation setup did not produce overlapping window IDs.'
        $output = @($anchorWindow | LibTmux\Remove-TmuxWindow -Confirm:$false)
        Assert-True ($output.Count -eq 0) 'Endpoint-scoped removal emitted output.'
        Assert-EntityPresent $primaryFixture 'Window' $anchorWindow.Id.ToString() $false
        Assert-EntityPresent $other 'Window' $otherWindow.Id.ToString() $true
    }
}

Invoke-WithOwnedTmux {
    param($fixture)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -ConfigurationFile '/dev/null'
    $snapshot = $server | LibTmux\Get-TmuxSnapshot
    $old = @{ Session = $snapshot.Sessions[0]; Window = $snapshot.Windows[0]; Pane = $snapshot.Panes[0] }
    $missedSignal = [Threading.Tasks.TaskCompletionSource[bool]]::new()
    Invoke-OwnedServerReplacement $fixture $missedSignal.Task
    foreach ($kind in @('Session', 'Window', 'Pane')) {
        $target = $old[$kind]
        $failure = $null
        try { $target | & "LibTmux\Remove-Tmux$kind" -Confirm:$false -ErrorAction Stop | Out-Null }
        catch { $failure = $_ }
        Assert-True ($null -ne $failure -and $failure.FullyQualifiedErrorId -like "Tmux.${kind}RemoveFailed,*" -and
            [Object]::ReferenceEquals($failure.TargetObject, $target) -and
            $failure.Exception -is [LibTmux.StaleServerGenerationException] -and
            $failure.Exception.Expected.Equals($target.Generation) -and
            $failure.Exception.Actual.ProcessId -eq $fixture.ServerPid) "Remove-Tmux$kind lost its original generation failure."
        Assert-EntityPresent $fixture $kind $target.Id.ToString() $true
    }
}

'PASS: installed native removals, zero output, confirmation previews, target errors, shared topology and generation isolation'
