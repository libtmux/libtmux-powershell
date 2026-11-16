# Records and reports one leg of the macOS trial: the provenance of the packages and
# the binaries it ran, and the conclusion of each suite. MacosTrial.ps1 is the command line.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../verify-package/VerifyPackage.psm1') -Force

function Stop-Trial([string] $Message) {
    throw [InvalidOperationException]::new($Message)
}

function Get-Sha256([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Returns a property of parsed JSON, or $null when the document lacks it.
function Get-JsonProperty($Document, [string] $Name) {
    $property = $Document.PSObject.Properties[$Name]
    if ($property) { $property.Value }
}

# Refuses package evidence that does not list exactly the core and workspace
# packages of its own version.
function Assert-PackageSet($Evidence) {
    $version = Get-JsonProperty $Evidence 'version'
    $files = @(Get-JsonProperty $Evidence 'packages' | ForEach-Object { Get-JsonProperty $_ 'file' } | Sort-Object { $_ } -CaseSensitive)
    $wanted = @("LibTmux.$version.nupkg", "LibTmux.Workspace.$version.nupkg")
    if (($files -join '|') -cne ($wanted -join '|')) {
        Stop-Trial "The package evidence lists $($files -join ', '), not $($wanted -join ', ')."
    }
}

# Refuses a trial whose core dependency version, packages, tmux or core checkout differ from
# the ones the leg asked for, then returns the record of what ran. Parameters name the
# expected values; the files are the downloaded package directory and the installed binaries.
function New-ProvenanceRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Runner,
        [Parameter(Mandatory)] [string] $Architecture,
        [Parameter(Mandatory)] [string] $CoreRevision,
        [Parameter(Mandatory)] [string] $CoreHead,
        [Parameter(Mandatory)] [string] $CoreVersion,
        [Parameter(Mandatory)] [string] $Powershell,
        [Parameter(Mandatory)] [string] $PowershellSha256,
        [Parameter(Mandatory)] [string] $PowershellBinary,
        [Parameter(Mandatory)] [string] $Tmux,
        [Parameter(Mandatory)] [string] $TmuxCommit,
        [Parameter(Mandatory)] [string] $TmuxBinary,
        [Parameter(Mandatory)] [string] $PackageRoot,
        [Parameter(Mandatory)] [string] $DependenciesFile
    )
    Test-TmuxOnPath $TmuxBinary
    if ($CoreHead -cne $CoreRevision) { Stop-Trial "The core checkout is at $CoreHead, not $CoreRevision." }
    $dependencies = Get-Content -LiteralPath (Join-Path $PackageRoot 'core-dependencies.json') -Raw | ConvertFrom-Json
    $found = Get-JsonProperty $dependencies 'corePackageVersion'
    if ($found -cne $CoreVersion) { Stop-Trial "The core dependency is '$found', not '$CoreVersion'." }
    $evidence = Get-Content -LiteralPath (Join-Path $PackageRoot 'package-evidence.json') -Raw | ConvertFrom-Json
    Assert-PackageSet $evidence
    $null = Test-PackageBytes $PackageRoot
    [ordered]@{
        runner                 = $Runner
        arch                   = $Architecture
        coreRevision           = $CoreRevision
        corePackageVersion     = $CoreVersion
        powershell             = $Powershell
        powershellSha256       = $PowershellSha256
        powershellBinarySha256 = Get-Sha256 $PowershellBinary
        tmux                   = $Tmux
        tmuxCommit             = $TmuxCommit
        tmuxSha256             = Get-Sha256 $TmuxBinary
        buildDependencies      = Get-Content -LiteralPath $DependenciesFile -Raw
        packages               = @(Get-JsonProperty $evidence 'packages')
    }
}

# The suites a leg runs, in the order the report lists them.
function Get-SuiteName {
    [ordered]@{ version_check = 'Version check'; features = 'Features'; product = 'Product'; documentation = 'Documentation' }
}

# Returns the one-line record of a leg: its runner, PowerShell, tmux and each suite's outcome.
function New-CellRecord([string] $Runner, [string] $Powershell, [string] $Tmux, $Outcome) {
    $record = [ordered]@{ runner = $Runner; powershell = $Powershell; tmux = $Tmux }
    foreach ($key in (Get-SuiteName).Keys) { $record[$key] = $Outcome[$key] }
    ConvertTo-Json -InputObject $record -Compress
}

# Returns the job summary row of a leg, with its header.
function Get-CellSummary([string] $Runner, [string] $Powershell, [string] $Tmux, $Outcome) {
    $names = (Get-SuiteName).Values
    $cells = @($Runner, $Powershell, $Tmux) + @((Get-SuiteName).Keys | ForEach-Object { $Outcome[$_] })
    "| Runner | PowerShell | tmux | $($names -join ' | ') |`n" +
    "| $((@('---') * ($names.Count + 3)) -join ' | ') |`n" +
    "| $($cells -join ' | ') |`n"
}

# Returns the warning annotation for a leg with a suite that did not succeed, or nothing.
function Get-CellWarning($Outcome) {
    $suites = Get-SuiteName
    if (@($suites.Keys | Where-Object { $Outcome[$_] -cne 'success' }).Count -eq 0) { return }
    $detail = @($suites.Keys | ForEach-Object { "$($suites[$_])=$($Outcome[$_])" }) -join ', '
    "::warning::macOS trial suites failed: $detail"
}

Export-ModuleMember -Function Assert-PackageSet, New-ProvenanceRecord, New-CellRecord, Get-CellSummary, Get-CellWarning
