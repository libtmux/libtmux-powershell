# Installs an official PowerShell release for CI from the table in matrix.json.
# InstallPowerShell.ps1 is the command line.
Set-StrictMode -Version Latest

function Stop-Install([string] $Message) {
    throw [InvalidOperationException]::new($Message)
}

# Returns the matrix.json entry, with its version and SHA-256, for one PowerShell release.
function Get-PowerShellRelease([string] $Version, [string] $Manifest) {
    $table = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json -AsHashtable
    $found = @($table.powershell | Where-Object { $_.version -ceq $Version })
    if ($found.Count -ne 1) { Stop-Install "PowerShell $Version is not in $Manifest." }
    $found[0]
}

function Get-PowerShellArchiveUrl([string] $Version) {
    "https://github.com/PowerShell/PowerShell/releases/download/v$Version/powershell-$Version-linux-x64.tar.gz"
}

# Refuses an archive whose SHA-256 is not the one the table lists.
function Assert-ArchiveDigest([string] $Path, [string] $Expected) {
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $Expected) { Stop-Install "The PowerShell archive has SHA-256 $actual, not $Expected." }
}

# Refuses a pwsh that reports a version other than the one asked for.
function Assert-PowerShellVersion([string] $Pwsh, [string] $Expected) {
    $actual = & $Pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
    if ($actual -cne $Expected) { Stop-Install "The installed PowerShell is $actual, not $Expected." }
}

# Fetches the archive, checks its digest, and only then extracts it into Destination.
# Source is a local archive that stands in for the download, which tests use.
function Install-PowerShellArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Version,
        [Parameter(Mandatory)] [string] $Manifest,
        [Parameter(Mandatory)] [string] $Destination,
        [string] $Source
    )
    $release = Get-PowerShellRelease $Version $Manifest
    $staging = Join-Path ([IO.Path]::GetTempPath()) "libtmux-powershell-$([Guid]::NewGuid().ToString('N'))"
    $null = New-Item -ItemType Directory -Path $staging
    try {
        $archive = Join-Path $staging "powershell-$Version-linux-x64.tar.gz"
        if ($Source) {
            Copy-Item -LiteralPath $Source -Destination $archive
        } else {
            Invoke-WebRequest -Uri (Get-PowerShellArchiveUrl $Version) -OutFile $archive -MaximumRetryCount 3 -RetryIntervalSec 2
        }
        Assert-ArchiveDigest $archive $release.sha256
        $null = New-Item -ItemType Directory -Path $Destination -Force
        & tar -xzf $archive -C $Destination
        if ($LASTEXITCODE) { Stop-Install "tar could not extract the PowerShell archive (exit $LASTEXITCODE)." }
        $pwsh = Join-Path $Destination 'pwsh'
        if (!(Test-Path -LiteralPath $pwsh)) { Stop-Install 'The PowerShell archive holds no pwsh.' }
        [IO.File]::SetUnixFileMode($pwsh, [IO.File]::GetUnixFileMode($pwsh) -bor [IO.UnixFileMode]::UserExecute)
        $pwsh
    } finally {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}

Export-ModuleMember -Function Get-PowerShellRelease, Assert-ArchiveDigest, Assert-PowerShellVersion, Install-PowerShellArchive
