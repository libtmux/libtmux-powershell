[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [Parameter(Mandatory)] [string] $OutputRoot,
    [string] $ReviewRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$package = Join-Path (Resolve-Path -LiteralPath $PackageRoot).Path 'LibTmux.0.1.0.nupkg'
if (!(Test-Path -LiteralPath $package -PathType Leaf)) {
    throw 'PackageRoot must contain the Product-tested LibTmux.0.1.0.nupkg.'
}
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputRoot)
if (Test-Path -LiteralPath $destination) { throw 'OutputRoot already exists; choose a new preparation directory.' }
$dotnet = (Get-Command dotnet -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$project = Join-Path $PSScriptRoot 'StandaloneCore.csproj'
$null = New-Item -ItemType Directory -Path $destination
try {
    $extracted = Join-Path $destination 'package'
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $extracted)
    $identityModule = Join-Path $PSScriptRoot '../PackageIdentity.psm1'
    Import-Module $identityModule -Force
    $packageIdentity = Get-BenchmarkPackageIdentity -PackageRoot $PackageRoot -ModuleRoot $extracted -ReviewRoot $ReviewRoot
    $dependenciesPath = Join-Path $extracted 'dependencies.json'
    $dependencies = Get-Content -LiteralPath $dependenciesPath -Raw | ConvertFrom-Json
    $expectedNames = @('LibTmux', 'LibTmux.Query.Json',
        'Microsoft.Extensions.Logging.Abstractions', 'Microsoft.Extensions.DependencyInjection.Abstractions')
    $assemblies = @($dependencies.assemblies)
    if ($assemblies.Count -ne $expectedNames.Count) {
        throw 'The package dependency manifest does not list the expected assembly closure.'
    }
    $verified = foreach ($entry in $assemblies) {
        if ($entry.assembly -cnotin $expectedNames) {
            throw "The package dependency manifest lists unexpected assembly $($entry.assembly)."
        }
        $library = Join-Path $extracted "lib/$($entry.assembly).dll"
        if (!(Test-Path -LiteralPath $library -PathType Leaf)) {
            throw "The module archive is missing $($entry.assembly).dll."
        }
        $hash = (Get-FileHash -LiteralPath $library -Algorithm SHA256).Hash.ToLowerInvariant()
        $identity = [Reflection.AssemblyName]::GetAssemblyName($library).FullName
        if ($hash -cne $entry.sha256 -or $identity -cne $entry.identity) {
            throw "The module archive changed the inspected $($entry.assembly) assembly."
        }
        @{ assembly = $entry.assembly; sha256 = $hash; identity = $identity }
    }
    $core = @($verified | Where-Object assembly -CEQ 'LibTmux')
    if ($core.Count -ne 1 -or $core[0].sha256 -cne $dependencies.requiredCore.sha256 -or
        $core[0].identity -cne $dependencies.requiredCore.identity) {
        throw 'The inspected core identity does not match dependencies.json.'
    }

    $offline = Join-Path $destination 'offline-feed'
    $obj = Join-Path $destination 'obj'
    $bin = Join-Path $destination 'bin'
    $null = New-Item -ItemType Directory -Path $offline
    $null = New-Item -ItemType Directory -Path $obj
    $libraryDirectory = Join-Path $extracted 'lib'
    $properties = @("-p:BaseIntermediateOutputPath=$obj/", "-p:MSBuildProjectExtensionsPath=$obj/",
        "-p:CoreLibraryDirectory=$libraryDirectory", '-p:NuGetAudit=false')
    & $dotnet restore $project --source $offline --verbosity quiet @properties
    if ($LASTEXITCODE -ne 0) { throw 'Offline standalone-core restore failed.' }
    & $dotnet build $project --no-restore --configuration Release --output $bin --verbosity quiet @properties
    if ($LASTEXITCODE -ne 0) { throw 'Standalone-core build failed.' }
    $app = Join-Path $bin 'LibTmux.StandaloneCoreBenchmark.dll'
    if (!(Test-Path -LiteralPath $app -PathType Leaf)) { throw 'Standalone-core build omitted its executable DLL.' }
    foreach ($entry in $verified) {
        $copy = Join-Path $bin "$($entry.assembly).dll"
        if (!(Test-Path -LiteralPath $copy -PathType Leaf) -or
            (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.sha256) {
            throw "Standalone-core build did not copy the inspected $($entry.assembly) assembly."
        }
    }
    $sdkVersion = (& $dotnet --version).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'dotnet --version failed after standalone-core build.' }
    $manifest = [ordered]@{
        schema = 1
        status = 'PASS'
        packageArchive = 'LibTmux.0.1.0.nupkg'
        packageSha256 = $packageIdentity.packageSha256
        dependenciesSha256 = (Get-FileHash -LiteralPath $dependenciesPath -Algorithm SHA256).Hash.ToLowerInvariant()
        corePackageVersion = $packageIdentity.corePackageVersion
        sourceProvenance = $packageIdentity.sourceProvenance
        reviewCoreRevision = $packageIdentity.reviewCoreRevision
        reviewPortRevision = $packageIdentity.reviewPortRevision
        assemblies = @($verified)
        benchmarkSha256 = (Get-FileHash -LiteralPath $app -Algorithm SHA256).Hash.ToLowerInvariant()
        sourceSha256 = @{
            project = (Get-FileHash -LiteralPath $project -Algorithm SHA256).Hash.ToLowerInvariant();
            program = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'Program.cs') -Algorithm SHA256).Hash.ToLowerInvariant();
            packageIdentity = (Get-FileHash -LiteralPath $identityModule -Algorithm SHA256).Hash.ToLowerInvariant();
            prepare = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant() }
        sdkVersion = $sdkVersion
        restore = 'explicit local empty feed; no PackageReference'
        build = 'dotnet build --no-restore; direct references to verified embedded assemblies'
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $destination 'manifest.json') -NoNewline
    "PASS standalone core preparation: $destination"
} catch {
    Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
    throw
}
