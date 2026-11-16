# Checks that the packages a CI job downloaded are the ones the package job built,
# and that the tmux it will test is the one first on PATH.
# VerifyPackage.ps1 is the command line.
Set-StrictMode -Version Latest

function Stop-Verify([string] $Message) {
    throw [InvalidOperationException]::new($Message)
}

# Refuses a package directory whose evidence lists no package, or lists a file that is
# missing or whose SHA-256 differs from the evidence. Returns the files checked.
function Test-PackageBytes([string] $PackageRoot) {
    $evidencePath = Join-Path $PackageRoot 'package-evidence.json'
    if (!(Test-Path -LiteralPath $evidencePath)) { Stop-Verify "$evidencePath does not exist." }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    $packages = @($evidence.packages)
    if (!$packages.Count) { Stop-Verify 'The package evidence lists no package.' }
    foreach ($package in $packages) {
        $path = Join-Path $PackageRoot $package.file
        if (!(Test-Path -LiteralPath $path)) { Stop-Verify "Package $($package.file) is missing." }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -cne $package.sha256) { Stop-Verify "Package $($package.file) has SHA-256 $actual, not $($package.sha256)." }
        $package.file
    }
}

# Refuses a PATH whose first tmux is not the expected one.
function Test-TmuxOnPath([string] $Expected) {
    $found = Get-Command tmux -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (!$found) { Stop-Verify 'No tmux is on PATH.' }
    if ($found.Source -cne $Expected) { Stop-Verify "tmux on PATH is $($found.Source), not $Expected." }
}

Export-ModuleMember -Function Test-PackageBytes, Test-TmuxOnPath
