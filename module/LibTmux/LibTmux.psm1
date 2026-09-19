$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/AssemblyGuard.ps1"
Import-TmuxAssembly -Path "$PSScriptRoot/lib/Microsoft.Extensions.DependencyInjection.Abstractions.dll"
Import-TmuxAssembly -Path "$PSScriptRoot/lib/Microsoft.Extensions.Logging.Abstractions.dll"
Import-TmuxAssembly -Path "$PSScriptRoot/lib/LibTmux.dll" -ExactBuild
Import-TmuxAssembly -Path "$PSScriptRoot/LibTmux.PowerShell.dll" -ExactBuild
Import-Module "$PSScriptRoot/LibTmux.PowerShell.dll" -Scope Local
Export-ModuleMember -Cmdlet (Import-PowerShellDataFile "$PSScriptRoot/LibTmux.psd1").CmdletsToExport
