[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$destination = Join-Path $root 'build/tool-modules'
$null = New-Item $destination -ItemType Directory -Force
Import-Module Microsoft.PowerShell.PSResourceGet -RequiredVersion 1.1.1
Save-PSResource -Name PSScriptAnalyzer -Version 1.25.0 -Repository PSGallery `
    -Path $destination -TrustRepository -AcceptLicense -Quiet
Save-PSResource -Name Microsoft.PowerShell.PlatyPS -Version 1.0.3 -Repository PSGallery `
    -Path $destination -TrustRepository -AcceptLicense -Quiet
