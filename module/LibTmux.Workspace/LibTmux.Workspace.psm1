$ErrorActionPreference = 'Stop'
$core = Get-Module LibTmux
$dependencies = Get-Content "$PSScriptRoot/dependencies.json" -Raw | ConvertFrom-Json
$coreHash = (Get-FileHash "$($core.ModuleBase)/lib/LibTmux.dll").Hash.ToLowerInvariant()
if ($coreHash -cne $dependencies.requiredCore.sha256) {
    throw 'Incompatible LibTmux dependency. Install core and workspace artifacts from the same build in a fresh PowerShell process.'
}
. "$($core.ModuleBase)/AssemblyGuard.ps1"
Import-TmuxAssembly -Path "$($core.ModuleBase)/lib/LibTmux.dll" -ExactBuild
Import-TmuxAssembly -Path "$PSScriptRoot/lib/YamlDotNet.dll" -ExactBuild
Import-TmuxAssembly -Path "$PSScriptRoot/lib/LibTmux.Workspace.dll" -ExactBuild
Import-TmuxAssembly -Path "$PSScriptRoot/LibTmux.Workspace.PowerShell.dll" -ExactBuild
Import-Module "$PSScriptRoot/LibTmux.Workspace.PowerShell.dll" -Scope Local
Export-ModuleMember -Cmdlet (Import-PowerShellDataFile "$PSScriptRoot/LibTmux.Workspace.psd1").CmdletsToExport
