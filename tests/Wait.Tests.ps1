param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: owned real tmux proves channel withdrawal after timeout and stop.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$module = Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1'
Import-Module $module
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-Wait([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Channel wait: $Message" }
}

$command = Get-Command 'LibTmux\Wait-TmuxChannel' -ErrorAction SilentlyContinue
Assert-Wait ($null -ne $command) 'installed module has no native Wait-TmuxChannel command'
Assert-Wait ($command.OutputType.Type -contains [bool]) 'successful wait must declare Boolean output'
Assert-Wait ($command.Parameters['Timeout'].ParameterType -eq [double]) 'Timeout must accept numeric seconds, not TimeSpan ticks'
$references = @(
    [LibTmux.PowerShell.WaitTmuxChannelCommand].Assembly.Location
    [LibTmux.Server].Assembly.Location
    [Management.Automation.PSCmdlet].Assembly.Location
) + @(Get-ChildItem "$PSHOME/ref/*.dll" | Select-Object -ExpandProperty FullName)
Add-Type -Path "$PSScriptRoot/support/WaitContextProbe.cs" -ReferencedAssemblies $references -CompilerOptions '/nowarn:1701'
[LibTmux.Testing.WaitContextProbe]::AssertCancellationDoesNotCaptureContext()

function Assert-NextSignal($Fixture, $Server, [string] $Channel, [double] $Timeout = 0.5) {
    $null = Invoke-OwnedTmux $Fixture -Arguments @('wait-for', '-S', $Channel)
    $result = @($Server | LibTmux\Wait-TmuxChannel -Channel $Channel -Timeout $Timeout)
    Assert-Wait ($result.Count -eq 1 -and $result[0] -is [bool] -and $result[0]) 'withdrawn waiter swallowed the next signal'
}

Invoke-WithOwnedTmux {
    param($fixture)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $anchor = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:0.0',
            '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}')).StdOut
    Assert-NextSignal $fixture $server 'already-signalled' -Timeout 10

    $errors = @()
    $result = @($server | LibTmux\Wait-TmuxChannel -Channel 'timeout' -Timeout 0.025 -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-Wait ($result.Count -eq 0 -and $errors.Count -eq 1 -and
        $errors[0].Exception -is [TimeoutException] -and
        $errors[0].CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::OperationTimeout -and
        $errors[0].FullyQualifiedErrorId -like 'Tmux.ChannelWaitFailed,*' -and
        [object]::ReferenceEquals($errors[0].TargetObject, $server)) 'timeout error lost its type, category or owner'
    Assert-NextSignal $fixture $server 'timeout'

    $wrapper = Join-Path $fixture.DirectoryPath 'waiting-tmux'
    $pidFile = Join-Path $fixture.DirectoryPath 'waiting-client'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    $quotedSocket = "'" + $fixture.SocketPath.Replace("'", "'\''") + "'"
    $quotedPid = "'" + $pidFile.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
previous=''
mode=''
for argument in "`$@"; do
    if [ "`$previous" = wait-for ]; then mode="`$argument"; fi
    previous="`$argument"
done
if [ "`$mode" = -- ] && [ "`$previous" = cancelled ]; then
    printf '%s\n' "`$`$" > $quotedPid
    exec $quotedTmux -S $quotedSocket wait-for -S cancel-registered ';' wait-for -- cancelled
fi
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $cancellable = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper
    $initial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $initial.ImportPSModule(@($module))
    $runspace = [RunspaceFactory]::CreateRunspace($initial)
    $pipeline = [PowerShell]::Create()
    try {
        $runspace.Open()
        $pipeline.Runspace = $runspace
        $null = $pipeline.AddCommand('LibTmux\Wait-TmuxChannel').AddParameter('Server', $cancellable).
            AddParameter('Channel', 'cancelled').AddParameter('Timeout', 10)
        $invocation = $pipeline.BeginInvoke()
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', 'cancel-registered')
        $clientId = [int] [IO.File]::ReadAllText($pidFile)
        $null = $fixture.OwnedProcessIds.Add($clientId)
        $stop = $pipeline.BeginStop($null, $null)
        Assert-Wait ($stop.AsyncWaitHandle.WaitOne(1000)) 'pipeline stop did not withdraw promptly'
        $pipeline.EndStop($stop)
        Assert-Wait ($invocation.AsyncWaitHandle.WaitOne(1000)) 'stopped pipeline did not complete'
        $stopped = $false
        try { $null = $pipeline.EndInvoke($invocation) } catch {
            if ($_.Exception.InnerException -isnot [Management.Automation.PipelineStoppedException]) { throw }
            $stopped = $true
        }
        Assert-Wait ($stopped -and $pipeline.Streams.Error.Count -eq 0) 'pipeline stop became a cmdlet error or success'
        $client = Get-Process -Id $clientId -ErrorAction SilentlyContinue
        if ($client) { $client.Dispose(); throw 'Channel wait: stopped wait left its client alive' }
    } finally {
        $pipeline.Dispose()
        $runspace.Dispose()
    }
    Assert-NextSignal $fixture $server 'cancelled'
    $after = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:0.0',
            '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}')).StdOut
    Assert-Wait ($after -ceq $anchor) 'waiting changed the borrowed session or pane'
}

$offline = LibTmux\New-TmuxServer -SocketName 'validation-only' -TmuxBinaryPath '/missing-libtmux-wait-command'
foreach ($timeout in @(0, -1, 86401, [double]::NaN, [double]::PositiveInfinity, [double]::NegativeInfinity, [double]::Epsilon)) {
    $rejected = $false
    try { $offline | LibTmux\Wait-TmuxChannel -Channel 'validation' -Timeout $timeout } catch {
        if ($_.FullyQualifiedErrorId -notlike 'Tmux.InvalidTimeout,*') { throw }
        $rejected = $true
    }
    Assert-Wait $rejected 'invalid timeout reached tmux'
}
foreach ($channel in @(' ', "bad`0channel")) {
    $rejected = $false
    try { $offline | LibTmux\Wait-TmuxChannel -Channel $channel } catch {
        if ($_.FullyQualifiedErrorId -notlike 'Tmux.InvalidChannel,*') { throw }
        $rejected = $true
    }
    Assert-Wait $rejected 'invalid channel reached tmux'
}
Assert-Wait (@(@() | LibTmux\Wait-TmuxChannel -Channel 'empty').Count -eq 0) 'empty owner pipeline emitted output'
'PASS channel wait: pending signal, timeout and cancellation withdrawal, context-free disposal, native errors, validation and borrowed-server preservation'
