param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [ValidateSet('Cancellation', 'Native', 'All')] [string] $Case = 'All'
)

# Native is integration: a dispatched tmux wait proves client cleanup on stop.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path $ModuleRoot).Path
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')
$references = @(
    [LibTmux.PowerShell.TmuxCmdlet].Assembly.Location
    [LibTmux.Server].Assembly.Location
    [System.Management.Automation.PSCmdlet].Assembly.Location
) + @(Get-ChildItem "$PSHOME/ref/*.dll" | Select-Object -ExpandProperty FullName)
# The probe combines the installed 7.4-baseline module with the current host API.
# Execute that binding below; other compiler diagnostics still fail the test.
Add-Type -Path "$PSScriptRoot/support/RuntimeProbe.cs" -ReferencedAssemblies $references -CompilerOptions '/nowarn:1701'

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-RuntimeProbe([LibTmux.Testing.RuntimeProbeState] $State, [LibTmux.Server] $Server, [scriptblock] $Ready) {
    $initial = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $entry = [System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new(
        'Test-TmuxRuntimeProbe', [LibTmux.Testing.RuntimeProbeCommand], $null)
    $initial.Commands.Add($entry)
    $runspace = [RunspaceFactory]::CreateRunspace($initial)
    $pipeline = [PowerShell]::Create()
    try {
        $runspace.Open()
        $pipeline.Runspace = $runspace
        $null = $pipeline.AddCommand('Test-TmuxRuntimeProbe').AddParameter('State', $State)
        if ($Server) { $null = $pipeline.AddParameter('Server', $Server) }
        $invocation = $pipeline.BeginInvoke()
        if (-not $State.StopBeforeRecord) {
            Assert-True ($State.Started.Wait(1000)) 'The runtime operation did not start.'
            if ($Ready) { & $Ready }
            $stop = $pipeline.BeginStop($null, $null)
            Assert-True ($stop.AsyncWaitHandle.WaitOne(2000)) 'Stopping the runtime operation did not finish.'
            $pipeline.EndStop($stop)
        }
        Assert-True ($invocation.AsyncWaitHandle.WaitOne(1000)) 'The stopped pipeline did not complete.'
        $stopped = $false
        try { $null = $pipeline.EndInvoke($invocation) } catch {
            $stopped = $_.Exception.InnerException -is [System.Management.Automation.PipelineStoppedException]
            if (-not $stopped) { throw }
        }
        Assert-True $stopped 'Cancellation lost PipelineStoppedException.'
        Assert-True ($pipeline.Streams.Error.Count -eq 0) 'Pipeline stop became a cmdlet error record.'
    } finally {
        $pipeline.Dispose()
        $runspace.Dispose()
    }
}

if ($Case -in @('Cancellation', 'All')) {
    $state = [LibTmux.Testing.RuntimeProbeState]::new()
    try {
        Invoke-RuntimeProbe $state
        Assert-True $state.DisposeFinishedDuringCallback 'Dispose blocked behind a running cancellation callback.'
        Assert-True $state.RecordFinishedDuringCallback 'Operation completion blocked behind a running cancellation callback.'
        Assert-True $state.TokenAliveDuringCallback 'The cancellation source was disposed while its callback was running.'
    } finally { $state.Dispose() }

    $state = [LibTmux.Testing.RuntimeProbeState]::new()
    try {
        $state.StopBeforeRecord = $true
        Invoke-RuntimeProbe $state
        Assert-True (-not $state.OperationStarted) 'A stopped cmdlet started a later operation.'
    } finally { $state.Dispose() }
}

if ($Case -in @('Native', 'All')) {
    . "$PSScriptRoot/support/OwnedTmux.ps1"
    Invoke-WithOwnedTmux {
        param($fixture)
        $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -ConfigurationFile '/dev/null'
        $state = [LibTmux.Testing.RuntimeProbeState]::new()
        try {
            Invoke-RuntimeProbe $state $server {
                $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', 'runtime-ready')
            }
            Assert-True ($null -ne $state.NativeCancellation) 'Cancellation did not reach the dispatched core operation.'
            Assert-True $state.NativeCancellation.CommandMayHaveExecuted 'Post-dispatch cancellation lost its dispatch metadata.'
            $client = Get-Process -Id $state.NativeCancellation.ClientProcessId -ErrorAction SilentlyContinue
            Assert-True ($null -eq $client) 'Stopping the pipeline left its native tmux client running.'
            $result = Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid}')
            Assert-True ([int] $result.StdOut -eq $fixture.ServerPid) 'Stopping a client killed the borrowed tmux server.'
        } finally { $state.Dispose() }
    }
}

"PASS: runtime $Case cancellation, disposal, and pipeline stop"
