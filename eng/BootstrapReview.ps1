[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-review-' + [Guid]::NewGuid().ToString('N'))),
    [string] $CoreSource
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Keep review builds from reusing MSBuild workers across checkouts.
$env:MSBUILDDISABLENODEREUSE = '1'
$coreRevision = '2608c181c1a56453a573dd4f749463cddac5850b'
$coreRemote = 'https://github.com/libtmux/libtmux-dotnet.git'
$portRemote = 'https://github.com/libtmux/libtmux-powershell.git'
$root = (Resolve-Path -LiteralPath (Split-Path $PSScriptRoot)).Path
$output = [IO.Path]::GetFullPath($OutputDirectory, (Get-Location).Path)
$git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$dotnet = (Get-Command dotnet -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$python = $null
foreach ($name in @('python3', 'python')) {
    $command = Get-Command $name -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if (!$command) { continue }
    try {
        $candidateVersion = & $command.Source -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")'
        if (!$LASTEXITCODE -and $candidateVersion -match '^[0-9]+\.[0-9]+$' -and
            [version] $candidateVersion -ge [version] '3.9') {
            $python = $command.Source
            break
        }
    } catch { continue }
}
if (!$python) { throw 'Python 3.9 or later is required for the .NET package review recipe.' }
$pwsh = [Environment]::ProcessPath

function Invoke-Native([string] $Executable, [string[]] $Arguments, [string] $Operation) {
    & $Executable @Arguments
    if ($LASTEXITCODE) { throw "$Operation failed with exit $LASTEXITCODE." }
}

function Get-GitRevision([string] $Path) {
    $actualRoot = & $git -C $Path rev-parse --show-toplevel
    if ($LASTEXITCODE -or !$actualRoot -or $actualRoot.Trim() -cne $Path) {
        throw "Source must be a Git checkout root: $Path"
    }
    $changes = @(& $git -C $Path status --porcelain --untracked-files=normal)
    if ($LASTEXITCODE) { throw "Cannot inspect source changes: $Path" }
    if ($changes.Count) { throw "Source checkout has uncommitted changes: $Path" }
    $revision = & $git -C $Path rev-parse HEAD
    if ($LASTEXITCODE -or !$revision -or $revision.Trim() -notmatch '^[0-9a-f]{40}$') {
        throw "Cannot identify source revision: $Path"
    }
    $revision.Trim()
}

function Assert-OutsideSource([string] $Path, [string] $Source) {
    $prefix = $Source.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($Path.Equals($Source, [StringComparison]::OrdinalIgnoreCase) -or
        $Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Output directory must be outside both source checkouts.'
    }
}

function Get-CanonicalPath([string] $Path) {
    $canonical = & $python -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' $Path
    if ($LASTEXITCODE -or [string]::IsNullOrWhiteSpace($canonical)) {
        throw "Cannot resolve directory path: $Path"
    }
    [IO.Path]::GetFullPath($canonical.Trim())
}

if (Test-Path -LiteralPath $output) { throw "Output directory already exists: $output" }
$parent = Split-Path $output
if (!(Test-Path -LiteralPath $parent -PathType Container)) {
    throw "Output parent directory does not exist: $parent"
}
$canonicalOutput = Join-Path (Get-CanonicalPath $parent) (Split-Path $output -Leaf)
Assert-OutsideSource $canonicalOutput (Get-CanonicalPath $root)
$portRevision = Get-GitRevision $root
if ($CoreSource) {
    $CoreSource = (Resolve-Path -LiteralPath $CoreSource).Path
    Assert-OutsideSource $canonicalOutput (Get-CanonicalPath $CoreSource)
    if ((Get-GitRevision $CoreSource) -cne $coreRevision) {
        throw "Core source revision must be $coreRevision."
    }
}

$sdks = @(& $dotnet --list-sdks)
if ($LASTEXITCODE) { throw 'Cannot list installed .NET SDKs.' }
foreach ($version in @('8.0.425', '10.0.302')) {
    if (!@($sdks | Where-Object { $_ -match ('^' + [regex]::Escape($version) + '\s+\[') }).Count) {
        throw "The .NET SDK $version is required. Install the pinned SDKs with mise before bootstrap."
    }
}

$null = New-Item -ItemType Directory -Path $output
# SDK library packs can have a different hash than the locked NuGet archive.
$env:NUGET_PACKAGES = Join-Path $output 'core-package-cache'
"ReviewOutput=$output"
try {
    $port = Join-Path $output 'port'
    $core = Join-Path $output 'core'
    $feed = Join-Path $output 'feed'
    $baseline = Join-Path $output 'lock-baseline'
    $cache = Join-Path $output 'package-cache'

    Invoke-Native $git @('clone', '--quiet', '--no-hardlinks', $root, $port) 'Clone PowerShell source'
    Invoke-Native $git @('-C', $port, 'remote', 'set-url', 'origin', $portRemote) 'Set PowerShell source URL'
    if ((Get-GitRevision $port) -cne $portRevision) { throw 'PowerShell source changed during bootstrap.' }
    if ($CoreSource) {
        Invoke-Native $git @('clone', '--quiet', '--no-hardlinks', $CoreSource, $core) 'Clone .NET core source'
    } else {
        Invoke-Native $git @('clone', '--quiet', '--no-checkout', $coreRemote, $core) 'Clone .NET core source'
        Invoke-Native $git @('-C', $core, 'checkout', '--quiet', '--detach', $coreRevision) 'Select .NET core revision'
    }
    Invoke-Native $git @('-C', $core, 'remote', 'set-url', 'origin', $coreRemote) 'Set .NET core source URL'
    if ((Get-GitRevision $core) -cne $coreRevision) { throw 'Cloned .NET core revision differs from the reviewed source.' }

    foreach ($selection in @(@($core, '10.0.302'), @($port, '8.0.425'))) {
        Push-Location $selection[0]
        try {
            $selected = (& $dotnet --version).Trim()
            if ($LASTEXITCODE -or $selected -cne $selection[1]) {
                throw "Source requires .NET SDK $($selection[1]); selected $selected."
            }
        } finally { Pop-Location }
    }

    $review = Join-Path $port 'eng/ci/review_dependencies.py'
    $runId = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $attempt = [Security.Cryptography.RandomNumberGenerator]::GetInt32(1, [int]::MaxValue)
    $version = & $python $review version --run-id $runId --attempt $attempt
    if ($LASTEXITCODE -or [string]::IsNullOrWhiteSpace($version)) {
        throw 'Cannot create a unique review package version from the committed dependency pin.'
    }
    $version = $version.Trim()

    Invoke-Native $python @((Join-Path $core 'eng/package_review.py'), '--version', $version,
        '--revision', $coreRevision, '--output', $feed) 'Build and inspect .NET review packages'
    $provenance = Get-Content -LiteralPath (Join-Path $feed 'provenance.json') -Raw | ConvertFrom-Json
    if ($provenance.version -cne $version -or $provenance.revision -cne $coreRevision -or
        $provenance.inspection -cne 'passed') {
        throw 'Inspected .NET package provenance differs from the requested version or revision.'
    }

    Invoke-Native $python @($review, 'prepare', '--version', $version,
        '--baseline', $baseline) 'Prepare disposable dependency pins'
    Invoke-Native $pwsh @('-NoLogo', '-NoProfile', '-File', (Join-Path $port 'eng/Build.ps1'),
        '-Restore', '-UpdateLock', '-CorePackageDirectory', $feed, '-PackageCache', $cache) 'Build PowerShell modules'
    Invoke-Native $python @($review, 'verify', '--version', $version,
        '--baseline', $baseline) 'Verify disposable dependency locks'

    foreach ($name in @('LibTmux', 'LibTmux.Query.Json', 'LibTmux.Workspace')) {
        $file = "$name.$version.nupkg"
        $records = @($provenance.packages | Where-Object file -CEQ $file)
        if ($records.Count -ne 1 -or
            (Get-FileHash -LiteralPath (Join-Path $feed $file)).Hash.ToLowerInvariant() -cne $records[0].sha256) {
            throw "Review package differs from inspected provenance: $file"
        }
    }

    $modulePath = Join-Path $port 'build/Modules'
    foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
        if (!(Test-Path -LiteralPath (Join-Path $modulePath "$name/0.1.0/$name.psd1") -PathType Leaf)) {
            throw "Staged PowerShell module is missing: $name"
        }
    }
    $smoke = @'
    $ErrorActionPreference = 'Stop'
    $coreRoot = Join-Path $env:LIBTMUX_REVIEW_MODULES 'LibTmux/0.1.0'
    $workspaceRoot = Join-Path $env:LIBTMUX_REVIEW_MODULES 'LibTmux.Workspace/0.1.0'
    $coreModule = Import-Module (Join-Path $coreRoot 'LibTmux.psd1') -PassThru -ErrorAction Stop
    $workspaceModule = Import-Module (Join-Path $workspaceRoot 'LibTmux.Workspace.psd1') -PassThru -ErrorAction Stop
    if ($coreModule.ModuleBase -cne $coreRoot -or $workspaceModule.ModuleBase -cne $workspaceRoot -or
        $coreModule.Version.ToString() -cne '0.1.0' -or $workspaceModule.Version.ToString() -cne '0.1.0') {
        throw 'Loaded modules differ from the staged manifests.'
    }
    $server = LibTmux\New-TmuxServer
    if ($server.GetType().FullName -cne 'LibTmux.Server' -or
        $server.GetType().Assembly.Location -cne (Join-Path $coreRoot 'lib/LibTmux.dll')) {
        throw 'The staged native server type is unavailable.'
    }
    'PASS staged module imports'
'@
    $previousModulePath = $env:PSModulePath
    $previousReviewModules = $env:LIBTMUX_REVIEW_MODULES
    try {
        $env:PSModulePath = $modulePath
        $env:LIBTMUX_REVIEW_MODULES = $modulePath
        Invoke-Native $pwsh @('-NoLogo', '-NoProfile', '-Command', $smoke) 'Import staged PowerShell modules'
    } finally {
        $env:PSModulePath = $previousModulePath
        $env:LIBTMUX_REVIEW_MODULES = $previousReviewModules
    }

    $modulePackages = Join-Path $output 'module-packages'
    try {
        $env:PSModulePath = "$modulePath$([IO.Path]::PathSeparator)$previousModulePath"
        Invoke-Native $pwsh @('-NoLogo', '-NoProfile', '-File', (Join-Path $port 'eng/Package.ps1'),
            '-DestinationPath', $modulePackages) 'Package PowerShell modules'
    } finally {
        $env:PSModulePath = $previousModulePath
    }
    $moduleEvidence = Get-Content -LiteralPath (Join-Path $modulePackages 'package-evidence.json') -Raw |
        ConvertFrom-Json
    if (@($moduleEvidence.packages).Count -ne 2) {
        throw 'PowerShell package evidence must identify both modules.'
    }
    foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
        $file = "$name.0.1.0.nupkg"
        $records = @($moduleEvidence.packages | Where-Object file -CEQ $file)
        if ($records.Count -ne 1 -or
            (Get-FileHash -LiteralPath (Join-Path $modulePackages $file)).Hash.ToLowerInvariant() -cne $records[0].sha256) {
            throw "PowerShell package differs from its recorded hash: $file"
        }
    }

    $checks = [Collections.Generic.List[object]]::new()
    foreach ($suite in @('Package', 'Install')) {
        Invoke-Native $pwsh @('-NoLogo', '-NoProfile', '-File', (Join-Path $port 'eng/Test.ps1'),
            '-Suite', $suite, '-PackageRoot', $modulePackages) "Verify installed $suite suite"
        $receipt = Get-Content -LiteralPath (Join-Path $port "build/test-$suite.json") -Raw |
            ConvertFrom-Json
        if ($receipt.suite -cne $suite -or $receipt.status -cne 'PASS') {
            throw "Installed $suite receipt did not pass."
        }
        $checks.Add(@{ suite = $suite; status = $receipt.status; seconds = $receipt.seconds;
            receipt = "port/build/test-$suite.json" })
    }

    @{ status = 'PASS'; version = $version; portRevision = $portRevision;
        coreRevision = $coreRevision; modulePath = $modulePath; packageFeed = $feed;
        modulePackageRoot = $modulePackages; modulePackages = @($moduleEvidence.packages);
        coreProvenance = 'feed/provenance.json';
        modulePackageEvidence = 'module-packages/package-evidence.json';
        checks = @($checks.ToArray()) } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'bootstrap.json')
    "PSModulePath=$modulePath"
    "ModulePackages=$modulePackages"
} catch {
    throw "Bootstrap failed: $($_.Exception.Message)`nPartial output remains at $output. Inspect it, then choose a new -OutputDirectory or remove it after inspection."
}
