[CmdletBinding()]
param(
    [switch] $Restore,
    [switch] $UpdateLock,
    [string] $CoreSource,
    [switch] $PackCore,
    [string] $CorePackageDirectory,
    [string] $PackageCache
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$timer = [Diagnostics.Stopwatch]::StartNew()
$root = Split-Path $PSScriptRoot
$feed = Join-Path $root 'build/nuget'
$cache = Join-Path $root 'build/packages'
if ($CorePackageDirectory -and !$Restore) { throw '-CorePackageDirectory requires -Restore to resolve the inspected archives.' }
if ($CorePackageDirectory) { $feed = (Resolve-Path -LiteralPath $CorePackageDirectory).Path }
if ($PackageCache) { $cache = [IO.Path]::GetFullPath($PackageCache) }
$modules = Join-Path $root 'build/Modules'
[xml] $versions = Get-Content "$root/Directory.Packages.props" -Raw
$version = $versions.SelectSingleNode('//PackageVersion[@Include="LibTmux"]/@Version').Value.Trim('[', ']')
$sharedPackages = @('LibTmux', 'LibTmux.Query.Json', 'LibTmux.Workspace')
$commands = [Collections.Generic.List[object]]::new()

function Invoke-BuildCommand([string[]] $Arguments) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    & dotnet @Arguments
    $code = $LASTEXITCODE
    $commands.Add(@{ tool = 'dotnet'; arguments = $Arguments; exit = $code; seconds = $watch.Elapsed.TotalSeconds })
    if ($code) { throw "dotnet $($Arguments[0]) failed with exit $code." }
}

Push-Location $root
try {
    if ($CorePackageDirectory) {
        if ($PackCore) { throw '-CorePackageDirectory consumes inspected archives and cannot be combined with -PackCore.' }
        foreach ($name in $sharedPackages) {
            $dependencyVersion = $versions.SelectSingleNode("//PackageVersion[@Include='$name']/@Version").Value.Trim('[', ']')
            if ($dependencyVersion -cne $version) { throw "An inspected review requires matching shared dependency pins: $name differs." }
        }
        $provenance = Get-Content -LiteralPath (Join-Path $feed 'provenance.json') -Raw | ConvertFrom-Json
        if ($provenance.version -cne $version -or $provenance.inspection -cne 'passed' -or
            $provenance.revision -cnotmatch '^[0-9a-f]{40}$') {
            throw 'Review package provenance does not match the pinned dependency version and inspected source.'
        }
        foreach ($name in $sharedPackages) {
            $file = "$name.$version.nupkg"
            $record = @($provenance.packages | Where-Object file -CEQ $file)
            if ($record.Count -ne 1 -or
                (Get-FileHash -LiteralPath (Join-Path $feed $file)).Hash.ToLowerInvariant() -cne $record[0].sha256) {
                throw "Review package bytes differ from the inspected archive: $file"
            }
        }
    } else {
        $null = New-Item $feed -ItemType Directory -Force
    }
    $null = New-Item $cache -ItemType Directory -Force
    if ($PackCore) {
        if (!$CoreSource) { throw '-PackCore requires -CoreSource.' }
        $CoreSource = (Resolve-Path $CoreSource).Path
        foreach ($name in $sharedPackages) {
            if (Test-Path "$feed/$name.$version.nupkg") {
                throw "Local $name $version already exists. Reuse it without -PackCore or choose a new dependency version."
            }
        }
        if (Test-Path "$feed/source-$version.json") { throw "Local source record $version already exists." }
        $candidate = Join-Path $feed ('.candidate-' + [Guid]::NewGuid().ToString('N'))
        $null = New-Item $candidate -ItemType Directory
        Push-Location $CoreSource
        try {
            $sourceRoot = (& git rev-parse --show-toplevel).Trim()
            if ($LASTEXITCODE -or $sourceRoot -cne $CoreSource) {
                throw '-CoreSource must name a Git checkout root, not an archive inside another repository.'
            }
            $revision = (& git rev-parse HEAD).Trim()
            if ($LASTEXITCODE) { throw 'Cannot determine dependency source revision.' }
            $branch = [string] (& git branch --show-current)
            if ($LASTEXITCODE) { throw 'Cannot determine dependency source branch.' }
            $sourceFiles = @(& git ls-files --cached --others --exclude-standard | Sort-Object -Unique | ForEach-Object {
                if (Test-Path -LiteralPath $_ -PathType Leaf) {
                    @{ file = $_; sha256 = (Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant() }
                }
            })
            @{ revision = $revision; branch = $branch; files = $sourceFiles } |
                ConvertTo-Json -Depth 5 | Set-Content "$candidate/source-$version.json"
            foreach ($name in $sharedPackages) {
                $buildArguments = @('pack', "src/$name/$name.csproj", '-c', 'Release',
                    "-p:Version=$version", '-p:RestoreLockedMode=true', '-o', $candidate,
                    "-p:RepositoryCommit=$revision", "-p:RepositoryBranch=$branch", '--warnaserror')
                Invoke-BuildCommand $buildArguments
            }
            foreach ($file in Get-ChildItem $candidate -File) { Move-Item $file.FullName $feed }
        } finally {
            Pop-Location
            Remove-Item $candidate -Recurse -Force
        }
    }
    $projects = @('LibTmux.PowerShell', 'LibTmux.Workspace.PowerShell')
    foreach ($name in $projects) {
        $project = "src/$name/$name.csproj"
        if ($Restore) {
            $buildArguments = @('restore', $project, '--packages', $cache, '--source', $feed,
                '--source', 'https://api.nuget.org/v3/index.json')
            if ($UpdateLock) { $buildArguments += '--force-evaluate' }
            elseif (Test-Path "src/$name/packages.lock.json") { $buildArguments += '--locked-mode' }
            Invoke-BuildCommand $buildArguments
        }
        Invoke-BuildCommand @('build', $project, '-c', 'Release', '--no-restore', '--warnaserror')
    }
    foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
        $destination = Join-Path $modules "$name/0.1.0"
        if (Test-Path $destination) { Remove-Item $destination -Recurse -Force }
        $null = New-Item "$destination/lib" -ItemType Directory -Force
        Copy-Item "$root/module/$name/*" $destination -Recurse
        $binary = "$root/src/$name.PowerShell/bin/Release/net8.0"
        Copy-Item "$binary/$name.PowerShell.dll" $destination
        Copy-Item "$binary/$name.PowerShell.xml" $destination
        $libraries = if ($name -eq 'LibTmux') {
            @('LibTmux', 'LibTmux.Query.Json', 'Microsoft.Extensions.Logging.Abstractions', 'Microsoft.Extensions.DependencyInjection.Abstractions')
        } else { @('LibTmux.Workspace', 'YamlDotNet') }
        foreach ($library in $libraries) { Copy-Item "$binary/$library.dll" "$destination/lib" }
        if ($name -eq 'LibTmux') { Copy-Item "$binary/libtmux-query-v2.schema.json" $destination }
        Copy-Item "$root/LICENSE" $destination
        Copy-Item "$root/THIRD-PARTY-NOTICES.md" $destination
        $null = New-Item "$destination/licenses" -ItemType Directory -Force
        $licenses = if ($name -eq 'LibTmux') { @('LibTmux', 'dotnet') } else { @('LibTmux', 'YamlDotNet') }
        foreach ($license in $licenses) { Copy-Item "$root/licenses/$license.txt" "$destination/licenses" }
        $dependencies = foreach ($library in $libraries) {
            $path = "$destination/lib/$library.dll"
            @{ assembly = $library; identity = [Reflection.AssemblyName]::GetAssemblyName($path).FullName;
                sha256 = (Get-FileHash $path).Hash.ToLowerInvariant() }
        }
        $coreLibrary = "$binary/LibTmux.dll"
        $coreHash = (Get-FileHash $coreLibrary).Hash.ToLowerInvariant()
        if ($name -eq 'LibTmux.Workspace' -and
            $coreHash -cne (Get-FileHash "$modules/LibTmux/0.1.0/lib/LibTmux.dll").Hash.ToLowerInvariant()) {
            throw 'Workspace and core module builds resolved different LibTmux dependencies.'
        }
        @{ corePackageVersion = $version; localBuild = $true; assemblies = @($dependencies);
            requiredCore = @{ identity = [Reflection.AssemblyName]::GetAssemblyName($coreLibrary).FullName; sha256 = $coreHash } } |
            ConvertTo-Json -Depth 5 | Set-Content "$destination/dependencies.json"
    }
    'PASS build and stage'
} finally {
    Pop-Location
    $null = New-Item "$root/build" -ItemType Directory -Force
    @{ seconds = $timer.Elapsed.TotalSeconds; commands = @($commands.ToArray()) } |
        ConvertTo-Json -Depth 8 | Set-Content "$root/build/build-evidence.json"
}
