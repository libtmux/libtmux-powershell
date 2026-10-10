[CmdletBinding()]
param([Parameter(Mandatory)] [string] $DestinationPath)

$ErrorActionPreference = 'Stop'
$timer = [Diagnostics.Stopwatch]::StartNew()
$root = Split-Path $PSScriptRoot
$sourceCommit = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -or $sourceCommit -cnotmatch '^[0-9a-f]{40}$') {
    throw 'Cannot identify the package source commit.'
}
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)
$names = @('LibTmux', 'LibTmux.Workspace')
foreach ($name in $names) {
    if (Test-Path "$destination/$name.0.1.0.nupkg") { throw 'The destination already contains a package. Choose a new artifact directory.' }
}
$null = New-Item $destination -ItemType Directory -Force
Import-Module Microsoft.PowerShell.PSResourceGet -RequiredVersion 1.1.1
foreach ($name in $names) {
    Compress-PSResource -Path "$root/build/Modules/$name/0.1.0" -DestinationPath $destination
}
@{ sourceCommit = $sourceCommit; seconds = $timer.Elapsed.TotalSeconds; packages = @(Get-ChildItem $destination -Filter '*.nupkg' | ForEach-Object {
    @{ file = $_.Name; sha256 = (Get-FileHash $_.FullName).Hash.ToLowerInvariant() }
}) } | ConvertTo-Json -Depth 5 | Set-Content "$destination/package-evidence.json"
