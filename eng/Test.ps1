[CmdletBinding()]
param(
    [ValidateSet('Package', 'Install', 'Read', 'Snapshot', 'Formatting', 'Capture', 'Create', 'Remove', 'Input', 'Wait', 'Runtime', 'Help', 'Examples', 'Guides', 'Fixture', 'All')] [string] $Suite = 'All',
    [string] $PackageRoot,
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

function Invoke-TestScript([string] $Script, [string[]] $Arguments = @(), [string] $ModuleRoot) {
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
    if ($Suite -in @('Install', 'All')) {
        if (!$PackageRoot) { throw '-PackageRoot must name the artifact directory to test.' }
        Invoke-TestScript 'tests/ResourceInstall.Tests.ps1' @('-PackageRoot', (Resolve-Path $PackageRoot).Path,
            '-PSResourceGetVersion', $PSResourceGetVersion)
    }
    if ($Suite -in @('Fixture', 'All')) { Invoke-TestScript 'tests/Fixture.Tests.ps1' }
    if ($Suite -in @('Package', 'Read', 'Snapshot', 'Formatting', 'Capture', 'Create', 'Remove', 'Input', 'Wait', 'Runtime', 'Help', 'Examples', 'Guides', 'All')) {
        if (!$PackageRoot) { throw '-PackageRoot must name the artifact directory to test.' }
        $PackageRoot = (Resolve-Path $PackageRoot).Path
        $installed = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-install-' + [Guid]::NewGuid().ToString('N'))
        try {
            foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
                $package = Join-Path $PackageRoot "$name.0.1.0.nupkg"
                $destination = Join-Path $installed "$name/0.1.0"
                [IO.Compression.ZipFile]::ExtractToDirectory($package, $destination)
            }
            if ($Suite -in @('Package', 'All')) {
                foreach ($order in @('CoreFirst', 'WorkspaceFirst')) {
                    Invoke-TestScript 'tests/Package.Tests.ps1' @('-ModuleRoot', $installed, '-Order', $order) $installed
                }
                Invoke-TestScript 'tests/PackageConflict.Tests.ps1' @('-ModuleRoot', $installed) $installed
                Invoke-TestScript 'tests/AssemblyReplacement.Tests.ps1' @('-ModuleRoot', $installed) $installed
                Invoke-TestScript 'tests/MixedCore.Tests.ps1' @('-ModuleRoot', $installed) $installed
                foreach ($case in @('PublicKeyToken', 'Culture', 'CompatibleVersion')) {
                    Invoke-TestScript 'tests/DependencyIdentity.Tests.ps1' @('-ModuleRoot', $installed, '-Case', $case) $installed
                }
            }
            if ($Suite -in @('Read', 'All')) {
                Invoke-TestScript 'tests/Read.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -in @('Snapshot', 'All')) {
                Invoke-TestScript 'tests/Snapshot.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -in @('Formatting', 'All')) {
                Invoke-TestScript 'tests/Formatting.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -in @('Capture', 'All')) {
                Invoke-TestScript 'tests/Capture.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -in @('Create', 'All')) {
                Invoke-TestScript 'tests/Create.Tests.ps1' @('-ModuleRoot', $installed) $installed
                Invoke-TestScript 'tests/CreateStartup.Tests.ps1' @('-ModuleRoot', $installed) $installed
                Invoke-TestScript 'tests/CreateStartup.Tests.ps1' @('-ModuleRoot', $installed, '-FailAfterCreation') $installed
            }
            if ($Suite -in @('Remove', 'All')) {
                Invoke-TestScript 'tests/Remove.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -in @('Wait', 'All')) {
                Invoke-TestScript 'tests/Wait.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -in @('Input', 'All')) {
                Invoke-TestScript 'tests/Input.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -eq 'Help') {
                Invoke-TestScript 'tests/Help.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
            if ($Suite -in @('Examples', 'All')) {
                Invoke-TestScript 'tests/Help.Tests.ps1' @('-ModuleRoot', $installed, '-RunExamples') $installed
            }
            if ($Suite -in @('Guides', 'All')) {
                Invoke-TestScript 'tests/GuideExamples.Tests.ps1' @('-ModuleRoot', $installed, '-RunExamples') $installed
            }
            if ($Suite -in @('Runtime', 'All')) {
                Invoke-TestScript 'tests/Runtime.Tests.ps1' @('-ModuleRoot', $installed) $installed
            }
        } finally {
            if (Test-Path $installed) { Remove-Item $installed -Recurse -Force }
        }
    }
    $passed = $true
} finally {
    $null = New-Item "$root/build" -ItemType Directory -Force
    @{ suite = $Suite; status = $(if ($passed) { 'PASS' } else { 'FAIL' });
        seconds = $timer.Elapsed.TotalSeconds; commands = @($records.ToArray()) } |
        ConvertTo-Json -Depth 8 | Set-Content "$root/build/test-$Suite.json"
}
