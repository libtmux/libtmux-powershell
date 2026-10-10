[CmdletBinding()]
param([Parameter(Mandatory)] [string] $DestinationPath)

$ErrorActionPreference = 'Stop'
$timer = [Diagnostics.Stopwatch]::StartNew()
$root = Split-Path $PSScriptRoot
$moduleVersion = '0.1.0'
$prerelease = 'alpha1'
$packageVersion = "$moduleVersion-$prerelease"
$sourceCommit = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -or $sourceCommit -cnotmatch '^[0-9a-f]{40}$') {
    throw 'Cannot identify the package source commit.'
}
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)
$names = @('LibTmux', 'LibTmux.Workspace')
foreach ($name in $names) {
    if (Test-Path "$destination/$name.$packageVersion.nupkg") { throw 'The destination already contains a package. Choose a new artifact directory.' }
    $manifest = Import-PowerShellDataFile "$root/build/Modules/$name/$moduleVersion/$name.psd1"
    if ($manifest.ModuleVersion -cne $moduleVersion -or
        $manifest.PrivateData.PSData.Prerelease -cne $prerelease) {
        throw 'The staged manifest does not identify the approved prerelease.'
    }
}

function Set-WorkspacePackageDependency([string] $Path) {
    $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry = $archive.GetEntry('LibTmux.Workspace.nuspec')
        if (!$entry) { throw 'The Workspace package has no expected nuspec.' }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { $document = [xml] $reader.ReadToEnd() } finally { $reader.Dispose() }
        $metadata = $document.SelectSingleNode('/*[local-name()="package"]/*[local-name()="metadata"]')
        $id = $metadata.SelectSingleNode('./*[local-name()="id"]')
        $version = $metadata.SelectSingleNode('./*[local-name()="version"]')
        $dependencies = $metadata.SelectNodes('./*[local-name()="dependencies"]/*[local-name()="dependency"]')
        if ($id.InnerText -cne 'LibTmux.Workspace' -or
            $version.InnerText -cne $packageVersion -or $dependencies.Count -ne 1 -or
            $dependencies[0].GetAttribute('id') -cne 'LibTmux' -or
            $dependencies[0].GetAttribute('version') -cne "[$moduleVersion]") {
            throw 'The compressed Workspace package has unexpected identity or dependencies.'
        }
        # PowerShell requires a numeric runtime version; Gallery needs the alpha pin.
        $dependencies[0].SetAttribute('version', "[$packageVersion]")
        $entry.Delete()
        $writer = [IO.StreamWriter]::new($archive.CreateEntry('LibTmux.Workspace.nuspec').Open())
        try { $document.Save($writer) } finally { $writer.Dispose() }
    } finally { $archive.Dispose() }
}

$null = New-Item $destination -ItemType Directory -Force
Import-Module Microsoft.PowerShell.PSResourceGet -RequiredVersion 1.1.1
foreach ($name in $names) {
    Compress-PSResource -Path "$root/build/Modules/$name/$moduleVersion" -DestinationPath $destination
}
Set-WorkspacePackageDependency "$destination/LibTmux.Workspace.$packageVersion.nupkg"
@{ sourceCommit = $sourceCommit; version = $packageVersion; seconds = $timer.Elapsed.TotalSeconds; packages = @(Get-ChildItem $destination -Filter '*.nupkg' | ForEach-Object {
    @{ file = $_.Name; sha256 = (Get-FileHash $_.FullName).Hash.ToLowerInvariant() }
}) } | ConvertTo-Json -Depth 5 | Set-Content "$destination/package-evidence.json"
