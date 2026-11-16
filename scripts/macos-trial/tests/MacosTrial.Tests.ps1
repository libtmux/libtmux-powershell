# Proves the macOS trial records provenance for the packages and binaries it ran, refuses each
# way they can differ from what the leg asked for, and reports a leg's suite outcomes.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../MacosTrial.psm1') -Force

function Assert-That([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw $Message }
}

function Assert-Refused([string] $Pattern, [scriptblock] $Action) {
    try { & $Action } catch [InvalidOperationException] {
        Assert-That ($_.Exception.Message -cmatch $Pattern) "Refused for the wrong reason: $($_.Exception.Message)"
        return
    }
    throw "Not refused: $Pattern"
}

function New-File([string] $Path, [string] $Text) {
    $null = New-Item -ItemType Directory -Path (Split-Path $Path) -Force
    Set-Content -LiteralPath $Path -Value $Text -NoNewline
}

# Writes a package directory whose evidence lists the named files with their real digests.
function New-Packages([string] $Root, [string[]] $Files, [string] $Version = '0.1.1', [string] $CoreVersion = '0.1.1') {
    $rows = foreach ($file in $Files) {
        New-File (Join-Path $Root $file) "package $file"
        @{ file = $file; sha256 = (Get-FileHash -LiteralPath (Join-Path $Root $file)).Hash.ToLowerInvariant() }
    }
    @{ version = $Version; packages = @($rows) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Root 'package-evidence.json')
    @{ corePackageVersion = $CoreVersion } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Root 'core-dependencies.json')
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) "libtmux-macos-trial-test-$([Guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $scratch
$previousPath = $env:PATH
try {
    $revision = '8d47af7d89638ad267528ac56897cec67df597f7'
    $packages = Join-Path $scratch 'package'
    New-Packages $packages @('LibTmux.0.1.1.nupkg', 'LibTmux.Workspace.0.1.1.nupkg')
    $bin = Join-Path $scratch 'bin'
    New-File (Join-Path $bin 'tmux') 'a tmux'
    [IO.File]::SetUnixFileMode((Join-Path $bin 'tmux'), [IO.File]::GetUnixFileMode((Join-Path $bin 'tmux')) -bor [IO.UnixFileMode]::UserExecute)
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$previousPath"
    New-File (Join-Path $scratch 'pwsh') 'a pwsh'
    New-File (Join-Path $scratch 'dependencies.txt') "autoconf 2.72`n"

    $arguments = @{
        Runner = 'macos-15'; Architecture = 'arm64'; CoreRevision = $revision; CoreHead = $revision; CoreVersion = '0.1.1'
        Powershell = '7.4.20'; PowershellSha256 = 'a' * 64; PowershellBinary = (Join-Path $scratch 'pwsh')
        Tmux = '3.3a'; TmuxCommit = 'b' * 40; TmuxBinary = (Join-Path $bin 'tmux')
        PackageRoot = $packages; DependenciesFile = (Join-Path $scratch 'dependencies.txt')
    }
    $record = New-ProvenanceRecord @arguments
    Assert-That (@($record.packages).Count -eq 2) 'The record lacks the packages.'
    Assert-That ($record.tmuxSha256 -ceq (Get-FileHash -LiteralPath (Join-Path $bin 'tmux')).Hash.ToLowerInvariant()) 'The record has the wrong tmux digest.'
    Assert-That ($record.powershellBinarySha256 -cmatch '^[0-9a-f]{64}$') 'The record has no PowerShell digest.'
    Assert-That ($record.buildDependencies -ceq "autoconf 2.72`n") 'The record lacks the build dependencies.'
    Assert-That ((($record | ConvertTo-Json -Depth 6 | ConvertFrom-Json).corePackageVersion) -ceq '0.1.1') 'The record does not serialise.'

    # Each way the leg can differ from what it asked for is refused.
    function Assert-Provenance([string] $Pattern, [hashtable] $Change) {
        $changed = $arguments.Clone()
        foreach ($key in $Change.Keys) { $changed[$key] = $Change[$key] }
        Assert-Refused $Pattern { $null = New-ProvenanceRecord @changed }
    }
    Assert-Provenance 'core checkout is at' @{ CoreHead = 'f' * 40 }
    Assert-Provenance 'core dependency is' @{ CoreVersion = '0.1.2' }
    $other = Join-Path $scratch 'other'
    New-File (Join-Path $other 'tmux') 'another tmux'
    [IO.File]::SetUnixFileMode((Join-Path $other 'tmux'), [IO.File]::GetUnixFileMode((Join-Path $other 'tmux')) -bor [IO.UnixFileMode]::UserExecute)
    Assert-Provenance 'not' @{ TmuxBinary = (Join-Path $other 'tmux') }

    $three = Join-Path $scratch 'three'
    New-Packages $three @('LibTmux.0.1.1.nupkg', 'LibTmux.Workspace.0.1.1.nupkg', 'Extra.0.1.1.nupkg')
    Assert-Provenance 'lists' @{ PackageRoot = $three }
    $renamed = Join-Path $scratch 'renamed'
    New-Packages $renamed @('LibTmux.0.1.0.nupkg', 'LibTmux.Workspace.0.1.1.nupkg')
    Assert-Provenance 'lists' @{ PackageRoot = $renamed }
    $tampered = Join-Path $scratch 'tampered'
    New-Packages $tampered @('LibTmux.0.1.1.nupkg', 'LibTmux.Workspace.0.1.1.nupkg')
    Add-Content -LiteralPath (Join-Path $tampered 'LibTmux.0.1.1.nupkg') -Value 'tampered'
    Assert-Provenance 'SHA-256' @{ PackageRoot = $tampered }
    $versionless = Join-Path $scratch 'versionless'
    New-Packages $versionless @('LibTmux.0.1.1.nupkg')
    Assert-Provenance 'lists' @{ PackageRoot = $versionless }

    # The report names each suite and warns when one did not succeed.
    $good = @{ version_check = 'success'; features = 'success'; product = 'success'; documentation = 'success' }
    $failed = $good.Clone()
    $failed.product = 'failure'
    $line = New-CellRecord 'macos-15' '7.4.20' '3.3a' $failed
    Assert-That ($line -ceq '{"runner":"macos-15","powershell":"7.4.20","tmux":"3.3a","version_check":"success","features":"success","product":"failure","documentation":"success"}') "The cell record is wrong: $line"
    $table = (Get-CellSummary 'macos-15' '7.4.20' '3.3a' $failed) -split "`n"
    Assert-That ($table[0] -ceq '| Runner | PowerShell | tmux | Version check | Features | Product | Documentation |') 'The summary header is wrong.'
    Assert-That ($table[1] -ceq '| --- | --- | --- | --- | --- | --- | --- |') 'The summary rule is wrong.'
    Assert-That ($table[2] -ceq '| macos-15 | 7.4.20 | 3.3a | success | success | failure | success |') 'The summary row is wrong.'
    Assert-That ((Get-CellWarning $failed) -ceq '::warning::macOS trial suites failed: Version check=success, Features=success, Product=failure, Documentation=success') 'A failed suite was not warned about.'
    Assert-That ($null -eq (Get-CellWarning $good)) 'A green leg was warned about.'
    $skipped = $good.Clone()
    $skipped.features = 'skipped'
    Assert-That ($null -ne (Get-CellWarning $skipped)) 'A skipped suite was not warned about.'

    # The command line writes the record and the summary, and prints the warning.
    $output = Join-Path $scratch 'out/cell.json'
    $summary = Join-Path $scratch 'summary.md'
    $printed = & (Get-Process -Id $PID).Path -NoLogo -NoProfile -File (Join-Path $PSScriptRoot '../MacosTrial.ps1') report `
        -Runner macos-15 -Powershell 7.4.20 -Tmux 3.3a -Output $output -Summary $summary `
        -VersionCheck success -Features success -Product failure -Documentation success
    Assert-That ($LASTEXITCODE -eq 0) 'The report command failed.'
    Assert-That ((Get-Content -LiteralPath $output -Raw) -ceq "$line`n") 'The report command wrote another record.'
    Assert-That ((Get-Content -LiteralPath $summary -Raw) -ceq (Get-CellSummary 'macos-15' '7.4.20' '3.3a' $failed)) 'The report command wrote another summary.'
    Assert-That ($printed -ceq (Get-CellWarning $failed)) 'The report command did not print the warning.'
} finally {
    $env:PATH = $previousPath
    Remove-Item -LiteralPath $scratch -Recurse -Force
}

'PASS macOS trial: provenance recorded for the packages and binaries, each difference refused, each suite outcome reported'
