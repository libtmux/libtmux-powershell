# Builds one pinned tmux release from source on a macOS runner with Homebrew, for
# the macOS trial. The shared build-tmux action installs its dependencies with apt,
# so it cannot build there. BuildTmuxMacos.ps1 is the command line; the checks that
# decide whether a build is the one asked for take plain values, so the test runs
# them without brew, autotools or lipo.
Set-StrictMode -Version Latest

$script:Formulae = @('autoconf', 'automake', 'bison', 'pkg-config', 'libevent', 'ncurses', 'utf8proc', 'jemalloc', 'jq')
# brew lists pkg-config under the name of its formula, pkgconf.
$script:Recorded = @('autoconf', 'automake', 'bison', 'pkgconf', 'libevent', 'ncurses', 'utf8proc', 'jemalloc', 'jq')
$script:Libraries = @('libevent', 'ncurses', 'utf8proc', 'jemalloc')

function Stop-Build([string] $Message) {
    throw [InvalidOperationException]::new($Message)
}

# Runs a command whose output belongs in the job log.
function Invoke-Native([string] $File, [string[]] $Arguments = @()) {
    & $File @Arguments | Out-Host
    if ($LASTEXITCODE) { Stop-Build "$File $($Arguments -join ' ') exited $LASTEXITCODE." }
}

# Runs a command and returns its trimmed output, or an empty string when it fails and AllowFailure is set.
function Read-Native([string] $File, [string[]] $Arguments = @(), [switch] $AllowFailure) {
    $output = if ($AllowFailure) { & $File @Arguments 2>$null } else { & $File @Arguments }
    if ($LASTEXITCODE) {
        if ($AllowFailure) { return '' }
        Stop-Build "$File $($Arguments -join ' ') exited $LASTEXITCODE."
    }
    (@($output) -join "`n").Trim()
}

# Returns the environment the build needs: bison first on PATH, pkg-config finding
# the Homebrew libraries, and utf8proc on the compiler and linker paths, which
# Homebrew on Apple silicon keeps outside the default search. Prefix maps a
# formula to the directory brew installed it under.
function Get-BuildEnvironment([scriptblock] $Prefix, [string] $Path) {
    $separator = [IO.Path]::PathSeparator
    $utf8proc = & $Prefix 'utf8proc'
    [ordered]@{
        PATH            = "$(& $Prefix 'bison')/bin$separator$Path"
        PKG_CONFIG_PATH = (@($script:Libraries | ForEach-Object { "$(& $Prefix $_)/lib/pkgconfig" }) -join $separator)
        CPPFLAGS        = "-I$utf8proc/include"
        LDFLAGS         = "-L$utf8proc/lib"
    }
}

# Returns what is wrong with a clone: not at the pinned commit, or not exactly at the tag.
# Head is `git rev-parse HEAD` and Tag is `git describe --tags --exact-match HEAD`.
function Get-SourceProblem([string] $Version, [string] $Commit, [string] $Head, [string] $Tag) {
    if ($Head -cne $Commit) { "tmux $Version is at $Head, not the pinned commit $Commit." }
    if ($Tag -cne $Version) { "HEAD is not exactly the tag $Version." }
}

# Returns what is wrong with a finished build. Found holds Executable, the commit
# recorded in the install, the version tmux reports and the architectures lipo lists.
function Get-BuildProblem($Expected, $Found) {
    if (!$Found.Executable) { return 'The build left no executable tmux.' }
    if ($Found.RecordedCommit -cne $Expected.SourceCommit) {
        "The install records commit $($Found.RecordedCommit), not $($Expected.SourceCommit)."
    }
    if ($Found.Reported -cne "tmux $($Expected.Version)") { "tmux reports '$($Found.Reported)', not 'tmux $($Expected.Version)'." }
    if ($Found.Architectures -cne $Expected.Architecture) {
        "tmux is built for '$($Found.Architectures)', not '$($Expected.Architecture)'."
    }
}

# Reads what Get-BuildProblem checks from an install.
function Read-BuildRecord([string] $Install) {
    $binary = Join-Path $Install 'bin/tmux'
    $executable = (Test-Path -LiteralPath $binary) -and
    (([IO.File]::GetUnixFileMode($binary) -band [IO.UnixFileMode]::UserExecute) -ne 0)
    if (!$executable) { return @{ Executable = $false } }
    @{
        Executable     = $true
        RecordedCommit = (Get-Content -LiteralPath (Join-Path $Install 'source-commit') -Raw).Trim()
        Reported       = Read-Native $binary @('-V')
        Architectures  = Read-Native lipo @('-archs', $binary)
    }
}

# Clones the pinned tag, refuses it unless it is the pinned commit, and builds it.
function Install-PinnedSource([string] $Version, [string] $Commit, [string] $Source, [string] $Install, [int] $Jobs) {
    $null = New-Item -ItemType Directory -Path (Split-Path $Source) -Force
    Invoke-Native git @('clone', '--depth', '1', '--branch', $Version, 'https://github.com/tmux/tmux.git', $Source)
    $head = Read-Native git @('-C', $Source, 'rev-parse', 'HEAD')
    $tag = Read-Native git @('-C', $Source, 'describe', '--tags', '--exact-match', 'HEAD') -AllowFailure
    $problems = @(Get-SourceProblem $Version $Commit $head $tag)
    if ($problems.Count) { Stop-Build ($problems -join ' ') }
    Push-Location $Source
    try {
        # The tmux build script runs a bare configure, which tmux 3.3a rejects
        # without an explicit utf8proc choice; brew installs utf8proc.
        Invoke-Native sh @('autogen.sh')
        Invoke-Native ./configure @("--prefix=$Install", '--enable-utf8proc')
        Invoke-Native make @("--jobs=$Jobs")
        Invoke-Native make @('install')
    } finally {
        Pop-Location
    }
}

# Installs the build dependencies, builds tmux under Root/installs/<version>, checks
# the result, records the Homebrew versions in DependenciesFile, and returns the
# path of the tmux executable.
function Build-Tmux {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Version,
        [Parameter(Mandatory)] [string] $SourceCommit,
        [Parameter(Mandatory)] [string] $Architecture,
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $DependenciesFile,
        [int] $Jobs = 3
    )
    Invoke-Native brew (@('install') + $script:Formulae)
    $environment = Get-BuildEnvironment { param($Formula) Read-Native brew @('--prefix', $Formula) } $env:PATH
    foreach ($name in $environment.Keys) { Set-Item -LiteralPath "env:$name" -Value $environment[$name] }
    Invoke-Native pkg-config @('--exists', 'libutf8proc', 'jemalloc')

    $install = Join-Path $Root "installs/$Version"
    Install-PinnedSource $Version $SourceCommit (Join-Path $Root "sources/$Version") $install $Jobs
    [IO.File]::WriteAllText((Join-Path $install 'source-commit'), "$SourceCommit`n", [Text.UTF8Encoding]::new($false))

    $expected = @{ Version = $Version; SourceCommit = $SourceCommit; Architecture = $Architecture }
    $problems = @(Get-BuildProblem $expected (Read-BuildRecord $install))
    if ($problems.Count) { Stop-Build ($problems -join ' ') }

    $versions = Read-Native brew (@('list', '--versions') + $script:Recorded)
    [IO.File]::WriteAllText($DependenciesFile, "$versions`n", [Text.UTF8Encoding]::new($false))
    Join-Path $install 'bin/tmux'
}

Export-ModuleMember -Function Get-BuildEnvironment, Get-SourceProblem, Get-BuildProblem, Build-Tmux
