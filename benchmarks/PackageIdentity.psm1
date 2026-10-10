Set-StrictMode -Version Latest

function Get-BenchmarkFileHash([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-BenchmarkArchiveEntryHash([string] $ArchivePath, [string] $EntryName) {
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entries = @($archive.Entries | Where-Object FullName -CEQ $EntryName)
        if ($entries.Count -ne 1) { throw "Inspected archive must contain one $EntryName entry." }
        $stream = $entries[0].Open()
        try {
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()
        } finally { $stream.Dispose() }
    } finally { $archive.Dispose() }
}

function Assert-BenchmarkEvidence($Evidence, [string] $File, [string] $Hash) {
    $records = @($Evidence.packages | Where-Object file -CEQ $File)
    if ($records.Count -ne 1 -or $records[0].sha256 -cne $Hash) {
        throw "Package bytes differ from recorded evidence: $File"
    }
}

function Assert-BenchmarkArchiveExtraction([string] $ArchivePath, [string] $ModuleRoot) {
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName
            if ($name.EndsWith('/')) { continue }
            if ($name.StartsWith('/') -or $name.Contains('\') -or $name.Contains(':') -or
                @($name.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -or
                !$names.Add($name)) {
                throw "The package archive has an invalid or duplicate entry: $name"
            }
            $extracted = Join-Path $ModuleRoot $name
            if (!(Test-Path -LiteralPath $extracted -PathType Leaf)) {
                throw "The package extraction is missing $name."
            }
            $stream = $entry.Open()
            try {
                $archiveHash = [Convert]::ToHexString(
                    [Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()
            } finally { $stream.Dispose() }
            if ($archiveHash -cne (Get-BenchmarkFileHash $extracted)) {
                throw "The package extraction differs from its archive: $name"
            }
        }
    } finally { $archive.Dispose() }
    foreach ($file in Get-ChildItem -LiteralPath $ModuleRoot -Recurse -File) {
        $relative = [IO.Path]::GetRelativePath($ModuleRoot, $file.FullName).Replace('\', '/')
        if (!$names.Contains($relative)) {
            throw "The package extraction contains an unrecorded file: $relative"
        }
    }
}

function Get-BenchmarkPackageIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $PackageRoot,
        [Parameter(Mandatory)] [string] $ModuleRoot,
        [string] $ReviewRoot
    )

    $packageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
    $moduleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
    $packageName = 'LibTmux.0.1.0.nupkg'
    $package = Join-Path $packageRoot $packageName
    if (!(Test-Path -LiteralPath $package -PathType Leaf)) {
        throw "PackageRoot must contain $packageName."
    }
    $packageHash = Get-BenchmarkFileHash $package
    $evidencePath = Join-Path $packageRoot 'package-evidence.json'
    $evidence = $null
    if (Test-Path -LiteralPath $evidencePath -PathType Leaf) {
        $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
        Assert-BenchmarkEvidence $evidence $packageName $packageHash
    }
    Assert-BenchmarkArchiveExtraction $package $moduleRoot

    $dependenciesPath = Join-Path $moduleRoot 'dependencies.json'
    $dependencies = Get-Content -LiteralPath $dependenciesPath -Raw | ConvertFrom-Json
    $version = [string] $dependencies.corePackageVersion
    if ($version -cnotmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*)?$') {
        throw 'The embedded core package version is invalid.'
    }
    $libraries = Join-Path $moduleRoot 'lib'
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $core = $null
    foreach ($entry in @($dependencies.assemblies)) {
        $name = [string] $entry.assembly
        if ($name -cnotmatch '^[A-Za-z][A-Za-z0-9.]*$' -or !$names.Add($name)) {
            throw "The embedded dependency list has an invalid or duplicate assembly: $name"
        }
        $library = Join-Path $libraries "$name.dll"
        if (!(Test-Path -LiteralPath $library -PathType Leaf)) {
            throw "The module archive is missing $name.dll."
        }
        $hash = Get-BenchmarkFileHash $library
        $identity = [Reflection.AssemblyName]::GetAssemblyName($library).FullName
        if ($hash -cne $entry.sha256 -or $identity -cne $entry.identity) {
            throw "The embedded $name.dll differs from dependencies.json."
        }
        if ($name -ceq 'LibTmux') { $core = @{ sha256 = $hash; identity = $identity } }
    }
    if (!$core -or !$names.Contains('LibTmux.Query.Json') -or
        $core.sha256 -cne $dependencies.requiredCore.sha256 -or
        $core.identity -cne $dependencies.requiredCore.identity) {
        throw 'The embedded core identity or query dependency is incomplete.'
    }
    $embeddedFiles = @(Get-ChildItem -LiteralPath $libraries -File -Filter '*.dll')
    if ($embeddedFiles.Count -ne $names.Count -or
        @($embeddedFiles | Where-Object { !$names.Contains($_.BaseName) }).Count) {
        throw 'The module contains an unrecorded library DLL.'
    }
    $cmdlet = Join-Path $moduleRoot 'LibTmux.PowerShell.dll'
    if ([Reflection.AssemblyName]::GetAssemblyName($cmdlet).Name -cne 'LibTmux.PowerShell') {
        throw 'The module does not contain the expected cmdlet assembly.'
    }
    $identity = [ordered]@{
        packageSha256 = $packageHash
        corePackageVersion = $version
        coreAssemblySha256 = $core.sha256
        cmdletAssemblySha256 = Get-BenchmarkFileHash $cmdlet
        sourceProvenance = 'unverified'
        reviewCoreRevision = $null
        reviewPortRevision = $null
    }
    if (!$ReviewRoot) { return [pscustomobject] $identity }

    $reviewRoot = (Resolve-Path -LiteralPath $ReviewRoot).Path
    $receipt = Get-Content -LiteralPath (Join-Path $reviewRoot 'bootstrap.json') -Raw | ConvertFrom-Json
    $feed = Join-Path $reviewRoot 'feed'
    $provenance = Get-Content -LiteralPath (Join-Path $feed 'provenance.json') -Raw | ConvertFrom-Json
    if ($receipt.status -cne 'PASS' -or $receipt.version -cne $version -or
        $receipt.coreRevision -cnotmatch '^[0-9a-f]{40}$' -or
        $receipt.portRevision -cnotmatch '^[0-9a-f]{40}$' -or
        $provenance.inspection -cne 'passed' -or $provenance.version -cne $version -or
        $provenance.revision -cne $receipt.coreRevision) {
        throw 'The review receipt and inspected core provenance disagree.'
    }
    if (!$evidence) { throw 'Strict source verification requires package-evidence.json.' }
    foreach ($name in @('LibTmux', 'LibTmux.Query.Json', 'LibTmux.Workspace')) {
        $file = "$name.$version.nupkg"
        Assert-BenchmarkEvidence $provenance $file (Get-BenchmarkFileHash (Join-Path $feed $file))
    }
    foreach ($name in @('LibTmux', 'LibTmux.Query.Json')) {
        $inspected = Get-BenchmarkArchiveEntryHash (Join-Path $feed "$name.$version.nupkg") "lib/net8.0/$name.dll"
        if ($inspected -cne (Get-BenchmarkFileHash (Join-Path $libraries "$name.dll"))) {
            throw "Embedded $name.dll differs from the inspected .NET package."
        }
    }

    $staged = Join-Path $reviewRoot 'port/build/Modules/LibTmux/0.1.0'
    $stagedFiles = @(Get-ChildItem -LiteralPath $staged -Recurse -File)
    $stagedNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($file in $stagedFiles) {
        $relative = [IO.Path]::GetRelativePath($staged, $file.FullName).Replace('\', '/')
        $null = $stagedNames.Add($relative)
        $embedded = Join-Path $moduleRoot $relative
        if (!(Test-Path -LiteralPath $embedded -PathType Leaf) -or
            (Get-BenchmarkFileHash $embedded) -cne (Get-BenchmarkFileHash $file.FullName)) {
            throw "The module archive differs from the reviewed PowerShell build: $relative"
        }
    }
    foreach ($file in Get-ChildItem -LiteralPath $moduleRoot -Recurse -File) {
        $relative = [IO.Path]::GetRelativePath($moduleRoot, $file.FullName).Replace('\', '/')
        if ($stagedNames.Contains($relative) -or
            $relative -cin @('LibTmux.nuspec', '[Content_Types].xml', '_rels/.rels') -or
            $relative -cmatch '^package/services/metadata/core-properties/[^/]+\.psmdcp$') {
            continue
        }
        throw "The module archive contains a file outside the reviewed build: $relative"
    }
    $identity.sourceProvenance = 'verified'
    $identity.reviewCoreRevision = $receipt.coreRevision
    $identity.reviewPortRevision = $receipt.portRevision
    [pscustomobject] $identity
}

Export-ModuleMember -Function Get-BenchmarkPackageIdentity
