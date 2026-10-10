[CmdletBinding()]
param(
    [ValidateSet('Package', 'Install', 'Read', 'Snapshot', 'Formatting', 'Completion', 'Capture', 'Create', 'Remove', 'Input', 'PaneRun', 'PaneTextWait', 'Wait', 'Options', 'Hooks', 'Environment', 'Layout', 'Placement', 'Clients', 'Attachment', 'Commands', 'Watch', 'Criteria', 'Selectors', 'SourceQuery', 'WorkspaceFiles', 'WorkspaceDiscovery', 'WorkspaceValidation', 'WorkspaceApply', 'WorkspaceCorpus', 'WorkspaceSerialization', 'Runtime', 'Help', 'Examples', 'Guides', 'Mcp', 'Fixture', 'Product', 'Documentation', 'All')] [string] $Suite = 'All',
    [string] $PackageRoot,
    [string] $McpCommand,
    [string] $McpVersion,
    [ValidateSet('1.1.1', '1.2.0')]
    [string] $PSResourceGetVersion = $(if ($PSVersionTable.PSVersion -ge [version] '7.6') { '1.2.0' } else { '1.1.1' })
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$timer = [Diagnostics.Stopwatch]::StartNew()
$root = Split-Path $PSScriptRoot
$pwsh = [Environment]::ProcessPath
$records = [Collections.Generic.List[object]]::new()
$passed = $false
$runProduct = $Suite -in @('Product', 'All')
$runDocumentation = $Suite -in @('Documentation', 'All')
$parallelTests = $false
$workerLimit = 2
$activeTests = [Collections.Generic.List[object]]::new()
$workerFailures = [Collections.Generic.List[Management.Automation.ErrorRecord]]::new()
$unreapedChildren = [Collections.Generic.List[int]]::new()
$retainedModule = $null

function Wait-TestScript {
    if (!$activeTests.Count) { return }
    $tasks = [Threading.Tasks.Task[]] @($activeTests | ForEach-Object { $_.completion })
    $completed = [Threading.Tasks.Task]::WhenAny($tasks).GetAwaiter().GetResult()
    $worker = @($activeTests | Where-Object {
        [object]::ReferenceEquals($_.completion, $completed)
    })[0]
    $timedOut = $false
    $exitCode = $null
    try {
        try { $null = $worker.completion.GetAwaiter().GetResult() }
        catch [OperationCanceledException] {
            if (!$worker.deadline.IsCancellationRequested) { throw }
            $timedOut = $true
            throw "$($worker.script) exceeded the test deadline."
        }
        $exitCode = $worker.process.ExitCode
        if ($exitCode) { throw "$($worker.script) failed with exit $exitCode." }
    } catch {
        $workerFailures.Add($_)
    } finally {
        try {
            if (!$worker.process.HasExited) {
                $worker.process.Kill($true)
                if (!$worker.process.WaitForExit(1000)) {
                    throw "$($worker.script) did not exit after termination."
                }
            }
        } catch {
            $workerFailures.Add($_)
            $confirmedExited = $false
            try { $confirmedExited = $worker.process.HasExited } catch {}
            if (!$confirmedExited) { $unreapedChildren.Add($worker.process.Id) }
        } finally {
            $records.Add(@{ script = $worker.script; arguments = $worker.arguments;
                exit = $exitCode; timedOut = $timedOut; seconds = $worker.watch.Elapsed.TotalSeconds })
            $null = $activeTests.Remove($worker)
            $worker.deadline.Dispose()
            $worker.process.Dispose()
        }
    }
}

function Invoke-TestScript([string] $Script, [string[]] $Arguments = @(), [string] $ModuleRoot) {
    if ($parallelTests) {
        while ($activeTests.Count -ge $workerLimit) { Wait-TestScript }
        if ($workerFailures.Count) { return }
    }
    $start = [Diagnostics.ProcessStartInfo]::new($pwsh)
    $start.UseShellExecute = $false
    $start.WorkingDirectory = $root
    $null = $start.Environment.Remove('TMUX')
    $null = $start.Environment.Remove('TMUX_PANE')
    $start.ArgumentList.Add('-NoLogo')
    $start.ArgumentList.Add('-NoProfile')
    $start.ArgumentList.Add('-File')
    $start.ArgumentList.Add((Join-Path $root $Script))
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    if ($ModuleRoot) { $start.Environment['PSModulePath'] = $ModuleRoot }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = $null
    $timedOut = $false
    $exitCode = $null
    if ($parallelTests) {
        $deadline = [Threading.CancellationTokenSource]::new(30000)
        try {
            $process = [Diagnostics.Process]::Start($start)
            $activeTests.Add(@{ script = $Script; arguments = $Arguments;
                process = $process; watch = $watch; deadline = $deadline;
                completion = $process.WaitForExitAsync($deadline.Token) })
        } catch {
            $startFailure = $_
            $workerFailures.Add($startFailure)
            try {
                if ($process -and !$process.HasExited) {
                    $process.Kill($true)
                    if (!$process.WaitForExit(1000)) {
                        throw 'Child did not exit after termination.'
                    }
                }
            } catch {
                $startFailure.Exception.Data['TestCleanupFailure'] = $_.Exception
                $workerFailures.Add($_)
                $confirmedExited = $false
                try { $confirmedExited = $process.HasExited } catch {}
                if (!$confirmedExited) { $unreapedChildren.Add($process.Id) }
            } finally {
                $records.Add(@{ script = $Script; arguments = $Arguments; exit = $null;
                    timedOut = $false; seconds = $watch.Elapsed.TotalSeconds })
                $deadline.Dispose()
                if ($process) { $process.Dispose() }
            }
            throw $startFailure
        }
        return
    }
    try {
        $process = [Diagnostics.Process]::Start($start)
        if (!$process.WaitForExit(30000)) {
            $timedOut = $true
            $process.Kill($true)
            $process.WaitForExit()
            throw "$Script exceeded the test deadline."
        }
        $exitCode = $process.ExitCode
        if ($process.ExitCode) { throw "$Script failed with exit $($process.ExitCode)." }
    } finally {
        $records.Add(@{ script = $Script; arguments = $Arguments; exit = $exitCode;
            timedOut = $timedOut; seconds = $watch.Elapsed.TotalSeconds })
        if ($process) { $process.Dispose() }
    }
}

try {
    if ($Suite -eq 'Mcp') {
        if (!$McpCommand -or !$McpVersion) { throw '-McpCommand and -McpVersion must identify the independently installed tool.' }
        Invoke-TestScript 'tests/Mcp.Tests.ps1' @('-McpCommand', $McpCommand, '-McpVersion', $McpVersion)
    }
    if ($Suite -eq 'Install') {
        if (!$PackageRoot) { throw '-PackageRoot must name the artifact directory to test.' }
        Invoke-TestScript 'tests/ResourceInstall.Tests.ps1' @('-PackageRoot', (Resolve-Path $PackageRoot).Path,
            '-PSResourceGetVersion', $PSResourceGetVersion)
    }
    if ($Suite -eq 'Fixture') { Invoke-TestScript 'tests/Fixture.Tests.ps1' }
    if ($Suite -in @('Package', 'Read', 'Snapshot', 'Formatting', 'Completion', 'Capture', 'Create', 'Remove', 'Input', 'PaneRun', 'PaneTextWait', 'Wait', 'Options', 'Hooks', 'Environment', 'Layout', 'Placement', 'Clients', 'Attachment', 'Commands', 'Watch', 'Criteria', 'Selectors', 'SourceQuery', 'WorkspaceFiles', 'WorkspaceDiscovery', 'WorkspaceValidation', 'WorkspaceApply', 'WorkspaceCorpus', 'WorkspaceSerialization', 'Runtime', 'Help', 'Examples', 'Guides', 'Product', 'Documentation', 'All')) {
        if (!$PackageRoot) { throw '-PackageRoot must name the artifact directory to test.' }
        $PackageRoot = (Resolve-Path $PackageRoot).Path
        $installed = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-install-' + [Guid]::NewGuid().ToString('N'))
        try {
            foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
                $package = Join-Path $PackageRoot "$name.0.1.0.nupkg"
                $destination = Join-Path $installed "$name/0.1.0"
                [IO.Compression.ZipFile]::ExtractToDirectory($package, $destination)
            }
            if ($runProduct) {
                # MixedCore changes shared files; finish before starting their readers.
                Invoke-TestScript 'tests/MixedCore.Tests.ps1' @('-ModuleRoot', $installed) $installed
                $workerLimit = 3
                $parallelTests = $true
                Invoke-TestScript 'tests/ResourceInstall.Tests.ps1' @('-PackageRoot', $PackageRoot,
                    '-PSResourceGetVersion', $PSResourceGetVersion)
                Invoke-TestScript 'tests/Fixture.Tests.ps1'
            }
            if ($Suite -eq 'Package' -or $runProduct) {
                foreach ($order in @('CoreFirst', 'WorkspaceFirst')) {
                    Invoke-TestScript 'tests/Package.Tests.ps1' @('-ModuleRoot', $installed, '-Order', $order) $installed
                }
                Invoke-TestScript 'tests/PackageConflict.Tests.ps1' @('-ModuleRoot', $installed) $installed
                Invoke-TestScript 'tests/AssemblyReplacement.Tests.ps1' @('-ModuleRoot', $installed) $installed
                if (!$runProduct) {
                    Invoke-TestScript 'tests/MixedCore.Tests.ps1' @('-ModuleRoot', $installed) $installed
                }
                foreach ($case in @('PublicKeyToken', 'Culture', 'CompatibleVersion')) {
                    Invoke-TestScript 'tests/DependencyIdentity.Tests.ps1' @('-ModuleRoot', $installed, '-Case', $case) $installed
                }
            }
            $parallelTests = $runProduct
            if ($Suite -eq 'Read' -or $runProduct) {
                Invoke-TestScript 'tests/Read.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Snapshot' -or $runProduct) {
                Invoke-TestScript 'tests/Snapshot.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Formatting' -or $runProduct) {
                Invoke-TestScript 'tests/Formatting.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Completion' -or $runProduct) {
                Invoke-TestScript 'tests/Completion.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Capture' -or $runProduct) {
                Invoke-TestScript 'tests/Capture.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Create' -or $runProduct) {
                Invoke-TestScript 'tests/Create.Tests.ps1' @('-ModuleRoot', $installed) $installed
                Invoke-TestScript 'tests/CreateStartup.Tests.ps1' @('-ModuleRoot', $installed) $installed
                Invoke-TestScript 'tests/CreateStartup.Tests.ps1' @('-ModuleRoot', $installed, '-FailAfterCreation') $installed
            }
            if ($Suite -eq 'Remove' -or $runProduct) {
                Invoke-TestScript 'tests/Remove.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Layout' -or $runProduct) {
                Invoke-TestScript 'tests/Layout.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Placement' -or $runProduct) {
                Invoke-TestScript 'tests/Placement.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Watch' -or $runProduct) {
                Invoke-TestScript 'tests/Watch.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Criteria' -or $runProduct) {
                Invoke-TestScript 'tests/Criteria.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Selectors' -or $runProduct) {
                Invoke-TestScript 'tests/Selectors.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'SourceQuery' -or $runProduct) {
                Invoke-TestScript 'tests/SourceQuery.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'WorkspaceFiles' -or $runProduct) {
                Invoke-TestScript 'tests/WorkspaceFiles.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'WorkspaceDiscovery' -or $runProduct) {
                Invoke-TestScript 'tests/WorkspaceDiscovery.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'WorkspaceValidation' -or $runProduct) {
                Invoke-TestScript 'tests/WorkspaceValidation.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'WorkspaceSerialization' -or $runProduct) {
                Invoke-TestScript 'tests/WorkspaceSerialization.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'WorkspaceApply' -or $runProduct) {
                Invoke-TestScript 'tests/WorkspaceApply.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'WorkspaceCorpus' -or $runProduct) {
                Invoke-TestScript 'tests/WorkspaceCorpus.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Commands' -or $runProduct) {
                Invoke-TestScript 'tests/Commands.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Clients' -or $runProduct) {
                Invoke-TestScript 'tests/Clients.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Attachment' -or $runProduct) {
                Invoke-TestScript 'tests/Attachment.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Environment' -or $runProduct) {
                Invoke-TestScript 'tests/Environment.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Hooks' -or $runProduct) {
                Invoke-TestScript 'tests/Hooks.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Options' -or $runProduct) {
                Invoke-TestScript 'tests/Options.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Wait' -or $runProduct) {
                Invoke-TestScript 'tests/Wait.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Input' -or $runProduct) {
                Invoke-TestScript 'tests/Input.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'PaneRun' -or $runProduct) {
                Invoke-TestScript 'tests/PaneRun.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'PaneTextWait' -or $runProduct) {
                Invoke-TestScript 'tests/PaneTextWait.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Runtime' -or $runProduct) {
                Invoke-TestScript 'tests/Runtime.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            while ($activeTests.Count) { Wait-TestScript }
            if ($workerFailures.Count) { throw $workerFailures[0] }
            $parallelTests = $false
            if ($runDocumentation) {
                $helpAdmission = Join-Path $installed 'help-admission.json'
                $guideAdmission = Join-Path $installed 'guide-admission.json'
                Invoke-TestScript 'tests/Help.Tests.ps1' @('-ModuleRoot', $installed,
                    '-Phase', 'Metadata', '-AdmissionPath', $helpAdmission) $installed
                Invoke-TestScript 'tests/GuideExamples.Tests.ps1' @('-ModuleRoot', $installed,
                    '-Phase', 'Metadata', '-AdmissionPath', $guideAdmission) $installed
            }
            $workerLimit = 2
            $parallelTests = $runDocumentation
            if ($Suite -eq 'Help') {
                Invoke-TestScript 'tests/Help.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Examples' -or $runDocumentation) {
                foreach ($group in @('CoreFirst', 'CoreSecond', 'CoreThird', 'CoreFourth', 'CoreFifth', 'Workspace', 'Terminal')) {
                    $arguments = @('-ModuleRoot', $installed, '-RunExamples', '-ExampleGroup', $group)
                    if ($runDocumentation) { $arguments += '-Phase', 'Examples', '-AdmissionPath', $helpAdmission }
                    Invoke-TestScript 'tests/Help.Tests.ps1' $arguments $installed
                }
            }
            if ($Suite -eq 'Guides' -or $runDocumentation) {
                Invoke-TestScript 'tests/ReadmeWorkflow.Tests.ps1' @('-ModuleRoot', $installed) $installed
                foreach ($group in @('Lifecycle', 'OperationsConfiguration', 'OperationsInteraction', 'Planning')) {
                    $arguments = @('-ModuleRoot', $installed, '-RunExamples', '-ExampleGroup', $group)
                    if ($runDocumentation) { $arguments += '-Phase', 'Examples', '-AdmissionPath', $guideAdmission }
                    Invoke-TestScript 'tests/GuideExamples.Tests.ps1' $arguments $installed
                }
            }
            while ($activeTests.Count) { Wait-TestScript }
            if ($workerFailures.Count) { throw $workerFailures[0] }
            if ($runDocumentation) {
                foreach ($entry in @(@{ Script = 'tests/Help.Tests.ps1'; Admission = $helpAdmission },
                    @{ Script = 'tests/GuideExamples.Tests.ps1'; Admission = $guideAdmission })) {
                    $admitted = Get-Content -LiteralPath $entry.Admission -Raw | ConvertFrom-Json -AsHashtable
                    $executed = @($records | Where-Object {
                        $_.script -ceq $entry.Script -and $_.arguments -ccontains 'Examples'
                    } | ForEach-Object { $_.arguments[[array]::IndexOf($_.arguments, '-ExampleGroup') + 1] })
                    if (Compare-Object @($admitted.Groups | Sort-Object) @($executed | Sort-Object)) {
                        throw "$($entry.Script) did not execute every admitted example group."
                    }
                }
            }
        } finally {
            try {
                while ($activeTests.Count) { Wait-TestScript }
            } finally {
                if ($unreapedChildren.Count) { $retainedModule = $installed }
                elseif (Test-Path $installed) { Remove-Item $installed -Recurse -Force }
            }
        }
    }
    $passed = $true
} finally {
    $null = New-Item "$root/build" -ItemType Directory -Force
    @{ suite = $Suite; status = $(if ($passed) { 'PASS' } else { 'FAIL' });
        seconds = $timer.Elapsed.TotalSeconds; commands = @($records.ToArray());
        retainedModule = $retainedModule; unreapedChildProcessIds = @($unreapedChildren.ToArray());
        workerFailures = @($workerFailures | ForEach-Object { $_.Exception.Message }) } |
        ConvertTo-Json -Depth 8 | Set-Content "$root/build/test-$Suite.json"
}
