[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [ValidateSet('1.1.1', '1.2.0')] [string] $PSResourceGetVersion = '1.1.1',
    [switch] $SaveWorker,
    [string] $OwnedRoot,
    [string] $RepositoryName
)

# Integration: local package resolution and fresh consumer processes.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/support/HangGuard.ps1"
Import-Module Microsoft.PowerShell.PSResourceGet -RequiredVersion $PSResourceGetVersion

if ($SaveWorker) {
    Save-PSResource -Name LibTmux.Workspace -Version '0.1.0' `
        -Repository $RepositoryName -Path "$OwnedRoot/modules" `
        -TemporaryPath "$OwnedRoot/download" -TrustRepository -AcceptLicense -Quiet
    'PASS Save-PSResource requested only LibTmux.Workspace 0.1.0'
    return
}

$PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
$owned = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-resource-' + [Guid]::NewGuid().ToString('N'))
$repository = 'libtmux-powershell-' + [Guid]::NewGuid().ToString('N')
$before = @(Get-PSResourceRepository)
$registered = $false
$passed = $false
$timer = [Diagnostics.Stopwatch]::StartNew()

function Get-RepositoryRecord($Repository) {
    $Repository | Select-Object Name, Uri, Priority, Trusted, ApiVersion, CredentialInfo |
        ConvertTo-Json -Depth 6 -Compress
}

function Invoke-ResourceChild([string] $Script, [string[]] $Arguments, [string] $ModuleRoot) {
    $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $owned
    foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $Script) + $Arguments) {
        $start.ArgumentList.Add($argument)
    }
    if ($ModuleRoot) { $start.Environment['PSModulePath'] = $ModuleRoot }
    $null = $start.Environment.Remove('TMUX')
    $null = $start.Environment.Remove('TMUX_PANE')
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $started = $false
    try {
        $started = $process.Start()
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(20000)) {
            throw 'The local package consumer exceeded its deadline.'
        }
        $stdout = $output.GetAwaiter().GetResult()
        $stderr = $errors.GetAwaiter().GetResult()
        if ($stdout) { Write-Output $stdout.TrimEnd() }
        if ($process.ExitCode -ne 0) {
            throw "Local package consumer failed with exit $($process.ExitCode): $stderr"
        }
        if ($stderr) { throw "Local package consumer wrote unexpected stderr: $stderr" }
    } finally {
        if ($started -and !$process.HasExited) {
            $process.Kill($true)
            if (!$process.WaitForExit($HangGuardMilliseconds)) { throw 'The package consumer did not exit after termination.' }
        }
        $process.Dispose()
    }
}

try {
    $null = New-Item "$owned/feed", "$owned/modules", "$owned/download" -ItemType Directory
    foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
        Copy-Item -LiteralPath "$PackageRoot/$name.0.1.0.nupkg" -Destination "$owned/feed"
    }
    Register-PSResourceRepository -Name $repository -Uri "$owned/feed" -Trusted
    $registered = $true
    Invoke-ResourceChild $PSCommandPath @('-PackageRoot', $PackageRoot,
        '-PSResourceGetVersion', $PSResourceGetVersion, '-SaveWorker',
        '-OwnedRoot', $owned, '-RepositoryName', $repository)

    $modules = "$owned/modules"
    foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
        $manifest = "$modules/$name/0.1.0/$name.psd1"
        if (!(Test-Path -LiteralPath $manifest)) {
            throw "Native package resolution did not save $name 0.1.0."
        }
        $data = Import-PowerShellDataFile -LiteralPath $manifest
        if ($data.ModuleVersion -cne '0.1.0') { throw "$name resolved an unexpected version." }
        $versions = @(Get-ChildItem -LiteralPath "$modules/$name" -Directory)
        if ($versions.Count -ne 1 -or $versions[0].Name -cne '0.1.0') {
            throw "$name resolved additional versions."
        }
    }
    $unexpected = @(Get-ChildItem -LiteralPath $modules -Directory | Where-Object {
        $_.Name -cnotin @('LibTmux', 'LibTmux.Workspace')
    })
    if ($unexpected.Count) { throw 'Native package resolution saved an unexpected module.' }
    $forbidden = @(Get-ChildItem -LiteralPath $modules -Recurse -File | Where-Object {
        $_.Name -match '^(System\.Management\.Automation|Microsoft\.PowerShell|pwsh|testhost)' -or
        $_.Extension -in @('.cs', '.csproj')
    })
    if ($forbidden.Count) { throw 'Saved package contains a PowerShell runtime or development file.' }
    $duplicateCore = @(Get-ChildItem -LiteralPath "$modules/LibTmux.Workspace" -Recurse -File |
        Where-Object Name -CEQ 'LibTmux.dll')
    if ($duplicateCore.Count) { throw 'Workspace bundles a duplicate core assembly.' }
    'PASS native dependency resolution: LibTmux.Workspace 0.1.0 -> LibTmux 0.1.0'
    Invoke-ResourceChild "$PSScriptRoot/Package.Tests.ps1" @('-ModuleRoot', $modules,
        '-Order', 'WorkspaceFirst') $modules
    Invoke-ResourceChild "$PSScriptRoot/ResourceWorkspace.Tests.ps1" @('-ModuleRoot', $modules) $modules
    $passed = $true
} finally {
    try {
        if ($registered) { Unregister-PSResourceRepository -Name $repository }
        $after = @(Get-PSResourceRepository)
        if (@($after | Where-Object Name -CEQ $repository).Count) {
            throw 'Owned package repository registration remains.'
        }
        foreach ($entry in $before) {
            $remaining = @($after | Where-Object Name -CEQ $entry.Name)
            if ($remaining.Count -ne 1 -or
                (Get-RepositoryRecord $remaining[0]) -cne (Get-RepositoryRecord $entry)) {
                throw 'A pre-existing package repository changed during consumer verification.'
            }
        }
    } finally {
        if (Test-Path -LiteralPath $owned) { Remove-Item -LiteralPath $owned -Recurse -Force }
        if (Test-Path -LiteralPath $owned) { throw 'Owned package directories remain after cleanup.' }
    }
    'PASS cleanup: owned repository unregistered, prior repositories preserved, temporary directories removed'
}

if ($passed) { "PASS native package consumer ($($timer.Elapsed.TotalSeconds.ToString('F3')) s)" }
