# Proves the macOS tmux build checks accept the build asked for and report each
# fault planted in the clone and the build, and that the build environment puts
# bison first and points the compiler at utf8proc. The build needs macOS.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../BuildTmuxMacos.psm1') -Force

function Assert-That([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw $Message }
}

$prefix = { param($Formula) "/opt/brew/opt/$Formula" }
$environment = Get-BuildEnvironment $prefix '/usr/bin:/bin'
Assert-That ($environment.PATH -ceq '/opt/brew/opt/bison/bin:/usr/bin:/bin') 'bison is not first on PATH.'
$libraries = @('libevent', 'ncurses', 'utf8proc', 'jemalloc') | ForEach-Object { "/opt/brew/opt/$_/lib/pkgconfig" }
Assert-That ($environment.PKG_CONFIG_PATH -ceq ($libraries -join [IO.Path]::PathSeparator)) 'pkg-config does not see each library.'
Assert-That ($environment.CPPFLAGS -ceq '-I/opt/brew/opt/utf8proc/include') 'The compiler does not see utf8proc.'
Assert-That ($environment.LDFLAGS -ceq '-L/opt/brew/opt/utf8proc/lib') 'The linker does not see utf8proc.'

$commit = '0b355ae8114511e1ff6359272b164f1cdf718e80'
Assert-That (@(Get-SourceProblem '3.3a' $commit $commit '3.3a').Count -eq 0) 'The pinned clone was refused.'
Assert-That (@(Get-SourceProblem '3.3a' $commit ('f' * 40) '3.3a')[0] -cmatch 'not the pinned commit') 'A clone at another commit passed.'
Assert-That (@(Get-SourceProblem '3.3a' $commit $commit '')[0] -cmatch 'not exactly the tag') 'A commit without the tag passed.'
Assert-That (@(Get-SourceProblem '3.3a' $commit $commit '3.3')[0] -cmatch 'not exactly the tag') 'A commit at another tag passed.'

$expected = @{ Version = '3.3a'; SourceCommit = $commit; Architecture = 'arm64' }
$good = @{ Executable = $true; RecordedCommit = $commit; Reported = 'tmux 3.3a'; Architectures = 'arm64' }
Assert-That (@(Get-BuildProblem $expected $good).Count -eq 0) 'The build asked for was refused.'
foreach ($fault in @(
        @{ Change = @{ Executable = $false }; Reported = 'no executable' },
        @{ Change = @{ RecordedCommit = 'f' * 40 }; Reported = 'records commit' },
        @{ Change = @{ Reported = 'tmux 3.3' }; Reported = "reports 'tmux 3.3'" },
        @{ Change = @{ Reported = 'tmux next-3.4' }; Reported = 'reports' },
        @{ Change = @{ Architectures = 'x86_64' }; Reported = 'is built for' },
        @{ Change = @{ Architectures = 'x86_64 arm64' }; Reported = 'is built for' })) {
    $found = $good.Clone()
    foreach ($key in $fault.Change.Keys) { $found[$key] = $fault.Change[$key] }
    $problems = @(Get-BuildProblem $expected $found)
    Assert-That ($problems.Count -eq 1 -and $problems[0].Contains($fault.Reported)) "A planted build fault went unreported: $($fault.Reported)"
}

'PASS macOS tmux build: the build environment is right and each planted fault in the clone and the build is reported'
