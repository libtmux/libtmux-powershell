[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ModulePath,
    [Parameter(Mandatory)] [string] $SocketPath,
    [Parameter(Mandatory)] [string] $TmuxBinaryPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertTo-NanosecondCount([long] $Ticks) {
    [long] [Math]::Round($Ticks * 1000000000.0 / [Diagnostics.Stopwatch]::Frequency)
}

$importWatch = [Diagnostics.Stopwatch]::StartNew()
Import-Module $ModulePath -ErrorAction Stop
$importWatch.Stop()

$serverWatch = [Diagnostics.Stopwatch]::StartNew()
$server = LibTmux\New-TmuxServer -SocketPath $SocketPath -TmuxBinaryPath $TmuxBinaryPath `
    -ConfigurationFile '/dev/null' -ErrorAction Stop
$serverWatch.Stop()

$snapshotWatch = [Diagnostics.Stopwatch]::StartNew()
$ids = [string[]] @($server | LibTmux\Get-TmuxPane -ErrorAction Stop |
    ForEach-Object { $_.Id.ToString() })
$snapshotWatch.Stop()

[ordered]@{
    paneIds = $ids
    importNanoseconds = ConvertTo-NanosecondCount $importWatch.ElapsedTicks
    serverConstructionNanoseconds = ConvertTo-NanosecondCount $serverWatch.ElapsedTicks
    firstSnapshotNanoseconds = ConvertTo-NanosecondCount $snapshotWatch.ElapsedTicks
    moduleVersion = (Get-Module LibTmux).Version.ToString()
    modulePath = (Get-Module LibTmux).Path
    moduleBase = (Get-Module LibTmux).ModuleBase
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    dotnetRuntimeVersion = [Environment]::Version.ToString()
    coreAssemblyMvid = [LibTmux.Server].Assembly.ManifestModule.ModuleVersionId.ToString()
    cmdletAssemblyMvid = [LibTmux.PowerShell.GetTmuxPaneCommand].Assembly.ManifestModule.ModuleVersionId.ToString()
} | ConvertTo-Json -Compress -Depth 5
