[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [Parameter(Mandatory)] [string] $ReviewRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Identity([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw $Message }
}

Import-Module "$PSScriptRoot/PackageIdentity.psm1" -Force -ErrorAction Stop
$packageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
$reviewRoot = (Resolve-Path -LiteralPath $ReviewRoot).Path
$package = Join-Path $packageRoot 'LibTmux.0.1.0.nupkg'
$receipt = Get-Content -LiteralPath (Join-Path $reviewRoot 'bootstrap.json') -Raw | ConvertFrom-Json
$temporary = Join-Path ([IO.Path]::GetTempPath()) (
    'libtmux-benchmark-identity-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
try {
    $original = Join-Path $temporary 'original'
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $original)
    $basic = Get-BenchmarkPackageIdentity -PackageRoot $packageRoot -ModuleRoot $original
    Assert-Identity ($basic.sourceProvenance -ceq 'unverified' -and
        $basic.corePackageVersion -ceq $receipt.version -and
        $basic.packageSha256 -ceq (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()) `
        'Basic package identity did not report its exact bytes without claiming source inspection.'

    $strict = Get-BenchmarkPackageIdentity -PackageRoot $packageRoot -ModuleRoot $original -ReviewRoot $reviewRoot
    Assert-Identity ($strict.sourceProvenance -ceq 'verified' -and
        $strict.corePackageVersion -ceq $receipt.version -and
        $strict.reviewCoreRevision -ceq $receipt.coreRevision -and
        $strict.reviewPortRevision -ceq $receipt.portRevision) `
        'The clean review receipt did not verify the installed package source.'

    $alteredRoot = Join-Path $temporary 'altered'
    $alteredModule = Join-Path $alteredRoot 'module'
    $null = New-Item -ItemType Directory -Path $alteredRoot
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $alteredModule)
    $coreArchive = Join-Path $reviewRoot "feed/LibTmux.$($receipt.version).nupkg"
    $archive = [IO.Compression.ZipFile]::OpenRead($coreArchive)
    try {
        $entry = $archive.GetEntry('lib/net10.0/LibTmux.dll')
        Assert-Identity ($null -ne $entry) 'The review feed lacks the net10 negative-control assembly.'
        $inputStream = $entry.Open()
        $outputStream = [IO.File]::Create((Join-Path $alteredModule 'lib/LibTmux.dll'))
        try { $inputStream.CopyTo($outputStream) }
        finally { $outputStream.Dispose(); $inputStream.Dispose() }
    } finally { $archive.Dispose() }
    $alternateHash = (Get-FileHash -LiteralPath (Join-Path $alteredModule 'lib/LibTmux.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
    $dependenciesPath = Join-Path $alteredModule 'dependencies.json'
    $dependencies = Get-Content -LiteralPath $dependenciesPath -Raw | ConvertFrom-Json
    @($dependencies.assemblies | Where-Object assembly -CEQ 'LibTmux')[0].sha256 = $alternateHash
    $dependencies.requiredCore.sha256 = $alternateHash
    $dependencies | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $dependenciesPath
    $wrongArchiveRejected = $false
    try {
        $null = Get-BenchmarkPackageIdentity -PackageRoot $packageRoot -ModuleRoot $alteredModule
    } catch { $wrongArchiveRejected = $true }
    Assert-Identity $wrongArchiveRejected 'Package identity accepted an extracted module from another archive.'
    $alteredPackage = Join-Path $alteredRoot 'LibTmux.0.1.0.nupkg'
    [IO.Compression.ZipFile]::CreateFromDirectory($alteredModule, $alteredPackage)
    @{ packages = @(@{ file = 'LibTmux.0.1.0.nupkg';
                sha256 = (Get-FileHash -LiteralPath $alteredPackage -Algorithm SHA256).Hash.ToLowerInvariant() }) } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $alteredRoot 'package-evidence.json')

    $selfConsistent = Get-BenchmarkPackageIdentity -PackageRoot $alteredRoot -ModuleRoot $alteredModule
    Assert-Identity ($selfConsistent.sourceProvenance -ceq 'unverified' -and
        $selfConsistent.coreAssemblySha256 -ceq $alternateHash) `
        'A self-consistent repack must remain explicitly unverified.'
    $rejected = $false
    try {
        $null = Get-BenchmarkPackageIdentity -PackageRoot $alteredRoot -ModuleRoot $alteredModule -ReviewRoot $reviewRoot
    } catch { $rejected = $_.Exception.Message.Contains('differs from the inspected .NET package') }
    Assert-Identity $rejected 'Strict source inspection accepted a repacked core assembly.'

    'PASS benchmark package identity: honest basic tier, inspected source, and repack rejection'
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
