<#
.SYNOPSIS
Record the provenance of a macOS trial leg, or report its suite conclusions.

.DESCRIPTION
`provenance` refuses the leg unless the first tmux on PATH is the one built, the
core checkout is at the pinned revision, the core dependency and the two
packages are the expected version, and each package has the SHA-256 its evidence
records. It then writes the provenance record as JSON to -Output.
`report` writes the one-line record of the leg to -Output, appends a table to
the job summary file, and prints a warning annotation when a suite did not
succeed. The trial is advisory, so a failed suite does not fail the command.

.EXAMPLE
pwsh -NoLogo -NoProfile -File scripts/macos-trial/MacosTrial.ps1 report `
    -Runner macos-15 -Powershell 7.4.20 -Tmux 3.3a -Output build/macos-cell.json `
    -VersionCheck success -Features success -Product failure -Documentation success
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)] [ValidateSet('provenance', 'report')] [string] $Action,
    [Parameter(Mandatory)] [string] $Runner,
    [Parameter(Mandatory)] [string] $Powershell,
    [Parameter(Mandatory)] [string] $Tmux,
    [Parameter(Mandatory)] [string] $Output,
    # provenance: the architecture lipo reports, and the pins the leg asked for.
    [string] $Architecture,
    [string] $CoreRevision,
    [string] $CoreVersion,
    [string] $PowershellSha256,
    [string] $TmuxCommit,
    # provenance: the core checkout, the installed binaries, the downloaded packages and the build record.
    [string] $Core,
    [string] $PowershellBinary,
    [string] $TmuxBinary,
    [string] $PackageRoot,
    [string] $DependenciesFile,
    # report: the outcome of each suite step, and the GITHUB_STEP_SUMMARY file.
    [string] $VersionCheck,
    [string] $Features,
    [string] $Product,
    [string] $Documentation,
    [string] $Summary
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'MacosTrial.psm1') -Force

$utf8 = [Text.UTF8Encoding]::new($false)
$null = New-Item -ItemType Directory -Path (Split-Path -Parent ([IO.Path]::GetFullPath($Output))) -Force
if ($Action -ceq 'report') {
    $outcome = @{ version_check = $VersionCheck; features = $Features; product = $Product; documentation = $Documentation }
    [IO.File]::WriteAllText($Output, (New-CellRecord $Runner $Powershell $Tmux $outcome) + "`n", $utf8)
    if ($Summary) { [IO.File]::AppendAllText($Summary, (Get-CellSummary $Runner $Powershell $Tmux $outcome), $utf8) }
    Get-CellWarning $outcome
    return
}

try {
    $head = (& git -C $Core rev-parse HEAD)
    if ($LASTEXITCODE) { throw [InvalidOperationException]::new("git could not read the core checkout at $Core.") }
    $record = New-ProvenanceRecord -Runner $Runner -Architecture $Architecture -CoreRevision $CoreRevision -CoreHead $head `
        -CoreVersion $CoreVersion -Powershell $Powershell -PowershellSha256 $PowershellSha256 -PowershellBinary $PowershellBinary `
        -Tmux $Tmux -TmuxCommit $TmuxCommit -TmuxBinary $TmuxBinary -PackageRoot $PackageRoot -DependenciesFile $DependenciesFile
} catch [InvalidOperationException] {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
[IO.File]::WriteAllText($Output, (ConvertTo-Json -InputObject $record -Depth 6) + "`n", $utf8)
"PASS provenance of $Runner, PowerShell $Powershell, tmux $Tmux"
