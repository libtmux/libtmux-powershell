<#
.SYNOPSIS
Build a pinned tmux release from source on a macOS runner.

.DESCRIPTION
Installs the build dependencies with Homebrew, clones the tmux tag, refuses it
unless it is at the pinned commit, builds it with utf8proc under
<Root>/installs/<version>, and refuses the build unless it records that commit,
reports the version and has the architecture asked for. It records the Homebrew
versions in -DependenciesFile, appends the install's bin directory to the
GITHUB_PATH file, and appends `TMUX_BINARY=<path>` to the GITHUB_ENV file.

.EXAMPLE
pwsh -NoLogo -NoProfile -File scripts/build-tmux-macos/BuildTmuxMacos.ps1 `
    -Version 3.3a -SourceCommit 0b355ae8114511e1ff6359272b164f1cdf718e80 -Architecture arm64 `
    -Root core/artifacts/tmux -DependenciesFile build/tmux-build-dependencies.txt `
    -GithubPath $env:GITHUB_PATH -GithubEnv $env:GITHUB_ENV
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Version,
    [Parameter(Mandatory)] [string] $SourceCommit,
    # The architecture lipo reports: x86_64 or arm64.
    [Parameter(Mandatory)] [string] $Architecture,
    # The directory that holds sources/<version> and installs/<version>.
    [Parameter(Mandatory)] [string] $Root,
    [Parameter(Mandatory)] [string] $DependenciesFile,
    # The GITHUB_PATH file.
    [Parameter(Mandatory)] [string] $GithubPath,
    # The GITHUB_ENV file.
    [Parameter(Mandatory)] [string] $GithubEnv,
    [ValidateRange(1, 64)] [int] $Jobs = 3
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'BuildTmuxMacos.psm1') -Force

try {
    $binary = Build-Tmux -Version $Version -SourceCommit $SourceCommit -Architecture $Architecture -Root $Root `
        -DependenciesFile $DependenciesFile -Jobs $Jobs
} catch [InvalidOperationException] {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::AppendAllText($GithubPath, "$(Split-Path $binary)`n", $utf8)
[IO.File]::AppendAllText($GithubEnv, "TMUX_BINARY=$binary`n", $utf8)
"Built tmux $Version at $binary"
