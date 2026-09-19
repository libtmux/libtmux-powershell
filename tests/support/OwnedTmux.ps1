if (-not ('LibTmux.Testing.SocketCreatedSignal' -as [type])) {
    Add-Type -Path "$PSScriptRoot/SocketCreatedSignal.cs"
}

function New-OwnedTmuxStartInfo {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates only a local ProcessStartInfo value without starting a process.')]
    param($Fixture, [string[]] $Arguments)

    $start = [System.Diagnostics.ProcessStartInfo]::new($Fixture.TmuxPath)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $Fixture.DirectoryPath
    $null = $start.Environment.Remove('TMUX')
    $null = $start.Environment.Remove('TMUX_PANE')
    $start.Environment['SHELL'] = '/bin/sh'
    foreach ($argument in @('-S', $Fixture.SocketPath, '-f', '/dev/null') + $Arguments) {
        $start.ArgumentList.Add($argument)
    }
    $start
}

function Invoke-OwnedTmux {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] $Fixture,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [switch] $AllowFailure,
        [scriptblock] $OnStarted,
        [System.Threading.CancellationToken] $CancellationToken = $Fixture.CancellationToken
    )

    if ($CancellationToken.IsCancellationRequested) {
        throw [System.OperationCanceledException]::new($CancellationToken)
    }
    if ($Fixture.Closed) { throw 'The owned tmux fixture has been closed.' }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = New-OwnedTmuxStartInfo $Fixture $Arguments
    $started = $false
    try {
        $started = $process.Start()
        $Fixture.ClientProcesses.Add($process)
        $null = $Fixture.OwnedProcessIds.Add($process.Id)
        $output = $process.StandardOutput.ReadToEndAsync()
        $errorOutput = $process.StandardError.ReadToEndAsync()
        if ($OnStarted) { & $OnStarted $process }
        try {
            $null = $process.WaitForExitAsync($CancellationToken).WaitAsync(
                [TimeSpan]::FromSeconds(1)).GetAwaiter().GetResult()
        } catch {
            if ($_.Exception.InnerException) { throw $_.Exception.InnerException }
            throw
        }
        $result = [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = $output.GetAwaiter().GetResult()
            StdErr = $errorOutput.GetAwaiter().GetResult()
        }
        if ($result.ExitCode -ne 0 -and -not $AllowFailure) {
            throw "tmux $($Arguments[0]) failed ($($result.ExitCode)): $($result.StdErr.Trim())"
        }
        $result
    } finally {
        if ($started -and -not $process.HasExited) {
            $process.Kill($true)
            if (-not $process.WaitForExit(1000)) { throw 'Owned tmux client did not exit.' }
        }
        if (-not $started) { $process.Dispose() }
    }
}

function New-OwnedTmuxFixture {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates only explicitly owned test resources; confirmation would prevent deterministic setup.')]
    [CmdletBinding()]
    param(
        [System.Threading.CancellationToken] $CancellationToken = [System.Threading.CancellationToken]::None,
        [string] $TmuxPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    )

    if ($CancellationToken.IsCancellationRequested) {
        throw [System.OperationCanceledException]::new($CancellationToken)
    }
    $directory = Join-Path '/tmp' ('libtmux-powershell-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $directory -ErrorAction Stop
    $fixture = [pscustomobject]@{
        TmuxPath = $TmuxPath
        DirectoryPath = $directory
        SocketPath = Join-Path $directory 'socket'
        ServerProcess = [System.Diagnostics.Process]::new()
        ServerPid = 0
        ServerStarted = $false
        ServerOutput = $null
        ServerError = $null
        ClientProcesses = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
        PaneProcesses = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
        PaneProcessIds = [System.Collections.Generic.HashSet[int]]::new()
        OwnedProcessIds = [System.Collections.Generic.HashSet[int]]::new()
        CancellationToken = $CancellationToken
        Closed = $false
    }
    $signal = $null
    try {
        [System.IO.File]::SetUnixFileMode($directory, [System.IO.UnixFileMode]::UserRead -bor
            [System.IO.UnixFileMode]::UserWrite -bor [System.IO.UnixFileMode]::UserExecute)
        $signal = [LibTmux.Testing.SocketCreatedSignal]::new($directory)
        $fixture.ServerProcess.StartInfo = New-OwnedTmuxStartInfo $fixture @('-D')
        $fixture.ServerStarted = $fixture.ServerProcess.Start()
        $fixture.ServerPid = $fixture.ServerProcess.Id
        $null = $fixture.OwnedProcessIds.Add($fixture.ServerPid)
        $fixture.ServerOutput = $fixture.ServerProcess.StandardOutput.ReadToEndAsync()
        $fixture.ServerError = $fixture.ServerProcess.StandardError.ReadToEndAsync()
        # Subscribe before startup so a fast socket creation cannot lose its signal.
        $ready = [System.Threading.Tasks.Task]::WhenAny([System.Threading.Tasks.Task[]] @(
            $signal.Ready, $fixture.ServerProcess.WaitForExitAsync()))
        $null = $ready.WaitAsync([TimeSpan]::FromSeconds(1), $CancellationToken).GetAwaiter().GetResult()
        if ($fixture.ServerProcess.HasExited) {
            throw "Owned tmux server exited before socket readiness ($($fixture.ServerProcess.ExitCode))."
        }
        $null = $signal.Ready.GetAwaiter().GetResult()
        if ($CancellationToken.IsCancellationRequested) {
            throw [System.OperationCanceledException]::new($CancellationToken)
        }
        $null = Invoke-OwnedTmux $fixture -Arguments @('new-session', '-d', '-s', 'fixture', '-x', '80', '-y', '24', 'exec /bin/sh')
        $identity = Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid} #{pane_pid}')
        $ids = $identity.StdOut.Trim().Split(' ')
        if ([int] $ids[0] -ne $fixture.ServerPid) {
            throw 'The socket did not identify the owned foreground tmux process.'
        }
        $fixture.PaneProcesses.Add([System.Diagnostics.Process]::GetProcessById([int] $ids[1]))
        $null = $fixture.PaneProcessIds.Add([int] $ids[1])
        $null = $fixture.OwnedProcessIds.Add([int] $ids[1])
        $fixture
    } catch {
        $failure = $_.Exception
        if ($failure -is [System.Management.Automation.MethodInvocationException] -and $failure.InnerException) {
            $failure = $failure.InnerException
        }
        $failure.Data['OwnedTmuxFixture'] = $fixture
        Remove-OwnedTmuxFixture $fixture
        throw $failure
    } finally {
        if ($signal) { $signal.Dispose() }
    }
}

function Register-OwnedTmuxPane {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)] $Fixture)

    if ($Fixture.Closed -or -not $Fixture.ServerStarted -or
        $Fixture.ServerProcess.HasExited -or $Fixture.ServerProcess.Id -ne $Fixture.ServerPid) {
        throw 'The owned tmux daemon is no longer running.'
    }
    $identity = Invoke-OwnedTmux $Fixture -Arguments @('display-message', '-p', '#{pid}') `
        -CancellationToken ([System.Threading.CancellationToken]::None)
    if ([int] $identity.StdOut.Trim() -ne $Fixture.ServerPid) {
        throw 'The socket no longer identifies the owned tmux daemon.'
    }
    $panes = Invoke-OwnedTmux $Fixture -Arguments @('list-panes', '-a', '-F', '#{pane_pid}') `
        -CancellationToken ([System.Threading.CancellationToken]::None)
    foreach ($line in $panes.StdOut.Split("`n", [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $panePid = [int] $line.Trim()
        if (-not $Fixture.PaneProcessIds.Add($panePid)) { continue }
        $null = $Fixture.OwnedProcessIds.Add($panePid)
        try {
            $Fixture.PaneProcesses.Add([System.Diagnostics.Process]::GetProcessById($panePid))
        } catch [System.ArgumentException] {
            # A pane that exited between listing and registration needs no wait.
            continue
        }
    }
}

function Remove-OwnedTmuxFixture {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Teardown must run unconditionally for resources created by this fixture.')]
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)] $Fixture)

    if ($Fixture.Closed) { return }
    try {
        if ($Fixture.ServerStarted -and -not $Fixture.ServerProcess.HasExited) {
            try {
                Register-OwnedTmuxPane $Fixture
                $null = Invoke-OwnedTmux $Fixture -Arguments @('kill-server') -AllowFailure `
                    -CancellationToken ([System.Threading.CancellationToken]::None)
            } finally {
                if (-not $Fixture.ServerProcess.WaitForExit(1000)) {
                    $Fixture.ServerProcess.Kill($true)
                    $null = $Fixture.ServerProcess.WaitForExit(1000)
                    throw 'Owned tmux daemon did not exit after kill-server.'
                }
            }
        }
        foreach ($pane in $Fixture.PaneProcesses) {
            if (-not $pane.WaitForExit(1000)) { throw 'Owned tmux pane process did not exit.' }
        }
        foreach ($client in $Fixture.ClientProcesses) {
            if (-not $client.HasExited) { throw 'Owned tmux client remains alive after teardown.' }
        }
    } finally {
        $Fixture.Closed = $true
        foreach ($process in @($Fixture.ServerProcess) + $Fixture.ClientProcesses.ToArray() + $Fixture.PaneProcesses.ToArray()) {
            $process.Dispose()
        }
        if (Test-Path -LiteralPath $Fixture.DirectoryPath) {
            Remove-Item -LiteralPath $Fixture.DirectoryPath -Recurse -Force
        }
    }
}

function Invoke-WithOwnedTmux {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [scriptblock] $Body,
        [scriptblock] $Setup,
        [System.Threading.CancellationToken] $CancellationToken = [System.Threading.CancellationToken]::None
    )

    $fixture = New-OwnedTmuxFixture -CancellationToken $CancellationToken
    try {
        if ($Setup) { & $Setup $fixture }
        & $Body $fixture
    } finally {
        Remove-OwnedTmuxFixture $fixture
    }
}
