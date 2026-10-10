param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [Parameter(Mandatory)] [string] $OutputPath,
    [ValidateSet('plain', 'aggregate', 'action', 'stopped')] [string] $Case = 'plain'
)

# Outer integration: each accepted owner must survive native exception wrapping and retries.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$manifest = "$ModuleRoot/LibTmux/0.1.0/LibTmux.psd1"
Import-Module $manifest
$references = @(
    [LibTmux.PowerShell.TmuxCmdlet].Assembly.Location
    [LibTmux.Server].Assembly.Location
    [Management.Automation.PSCmdlet].Assembly.Location
) + @(Get-ChildItem "$PSHOME/ref/*.dll" | Select-Object -ExpandProperty FullName)
Add-Type -Path "$PSScriptRoot/support/RecoveryProbe.cs" -ReferencedAssemblies $references -CompilerOptions '/nowarn:1701'
$server = Start-TmuxServer
$outer = $server | New-TmuxSession -Name outer -Owned
$inner = $server | New-TmuxSession -Name inner -Owned
[IO.File]::WriteAllText($env:LIBTMUX_ORDINARY_FAULT, 'cleanup-session')
$original = [LibTmux.Testing.RecoveryProbe]::FailNestedAsync($outer, $inner).GetAwaiter().GetResult()
$owners = [LibTmux.OwnedScope]::CleanupOwners($original)
if ($owners.Count -ne 2 -or @(Get-TmuxScopeFailure -Pending).Count) { throw 'Core setup did not retain two distinct unregistered owners.' }
$wrapped = [LibTmux.Testing.RecoveryProbe]::Wrap($original, $Case)
$observations = [Collections.Generic.List[object]]::new()
function Publish-Failure {
    $initial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $entry = [Management.Automation.Runspaces.SessionStateCmdletEntry]::new(
        'Test-TmuxRecoveryProbe', [LibTmux.Testing.RecoveryProbeCommand], $null)
    $initial.Commands.Add($entry)
    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initial)
    $pipeline = [Management.Automation.PowerShell]::Create()
    try {
        $runspace.Open()
        $pipeline.Runspace = $runspace
        $null = $pipeline.AddCommand('Test-TmuxRecoveryProbe').AddParameter('Failure', $wrapped).AddParameter('ErrorAction', 'Stop')
        $caught = $null
        $output = @()
        try { $output = @($pipeline.Invoke()) } catch { $caught = $_.Exception }
        $observations.Add(@{ State = [string] $pipeline.InvocationStateInfo.State;
            HadErrors = $pipeline.HadErrors; Caught = [string] $caught; OutputCount = $output.Count })
        # Invoke can consume a directly thrown PipelineStoppedException without a
        # caller exception. Actual pipeline cancellation has its separate native case.
        if ($Case -eq 'stopped') {
            if ($output.Count) { throw 'A stopped callback emitted success output.' }
        } elseif (!$caught) { throw 'Wrapped recovery error became success.' }
    } finally {
        $pipeline.Dispose()
        $runspace.Dispose()
    }
}
Publish-Failure
Publish-Failure
$records = @(Get-TmuxScopeFailure -Pending)
if ($records.Count -ne 2) { throw 'A wrapped failure lost or duplicated a core owner.' }
foreach ($record in $records) {
    if (![object]::ReferenceEquals($record.BodyFailure, $original) -or
        ![object]::ReferenceEquals($record.CleanupFailure, [LibTmux.OwnedScope]::CleanupFailure($original)) -or
        @($owners | Where-Object { [object]::ReferenceEquals($_, $record.Owner) }).Count -ne 1) {
        throw 'A nested failure changed original errors or owner identity.'
    }
}
[IO.File]::WriteAllText($env:LIBTMUX_ORDINARY_FAULT, '')
foreach ($record in $records) {
    $record.Owner | Close-TmuxScope
    $record.Owner | Close-TmuxScope
    if (![object]::ReferenceEquals(($record.Owner | Get-TmuxScopeFailure), $record)) { throw 'Retry changed failure history.' }
}
Publish-Failure
if (@(Get-TmuxScopeFailure -Pending).Count -or @($server | Get-TmuxSession).Count) { throw 'Reobserving a resolved failure restored a pending owner or leaked a session.' }
$arbitrary = [IO.MemoryStream]::new()
try {
    foreach ($command in @('Close-TmuxScope', 'Get-TmuxScopeFailure')) {
        $caught = $null
        try { & $command $arbitrary } catch { $caught = $_.Exception }
        if ($caught -isnot [ArgumentException]) { throw 'An unregistered disposable gained cleanup authority.' }
    }
} finally { $arbitrary.Dispose() }
[pscustomobject] @{ Passed = $true; Case = $Case; Owners = 2; Assertions = 15;
    PipelineObservations = @($observations.ToArray()) } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath
