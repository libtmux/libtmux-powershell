[CmdletBinding()]
param([string] $ManifestPath = (Join-Path $PSScriptRoot '../module/LibTmux/LibTmux.psd1'))

# The manifest is the one source of the release identity: ModuleVersion plus an
# optional Prerelease label, which a final release leaves unset.
$ErrorActionPreference = 'Stop'
$data = Import-PowerShellDataFile -LiteralPath $ManifestPath
$moduleVersion = [string] $data.ModuleVersion
# A final release omits the key, and strict mode (inherited from a caller) rejects a missing one.
$prerelease = if ($data.PrivateData.PSData.ContainsKey('Prerelease')) { [string] $data.PrivateData.PSData.Prerelease } else { '' }
if ($moduleVersion -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "The manifest ModuleVersion is not numeric: $ManifestPath"
}
if ($prerelease -and $prerelease -cnotmatch '^[A-Za-z][0-9A-Za-z]*$') {
    throw "The manifest Prerelease label is invalid: $ManifestPath"
}
[pscustomobject] @{
    ModuleVersion = $moduleVersion
    Prerelease = $prerelease
    PackageVersion = if ($prerelease) { "$moduleVersion-$prerelease" } else { $moduleVersion }
}
