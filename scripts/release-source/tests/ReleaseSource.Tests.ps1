# Proves the release source check accepts an annotated tag at the released commit
# and refuses a malformed name, a missing tag, a lightweight tag, a tag at another
# commit and a short commit, and that the command line writes the commit.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../ReleaseSource.psm1') -Force

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

function Invoke-TestGit([string] $Repository, [string[]] $Arguments) {
    $output = & git -C $Repository -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false -c tag.gpgsign=false @Arguments
    if ($LASTEXITCODE) { throw "git $($Arguments -join ' ') failed." }
    (@($output) -join "`n").Trim()
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) "libtmux-release-source-test-$([Guid]::NewGuid().ToString('N'))"
$repository = Join-Path $scratch 'repository'
$null = New-Item -ItemType Directory -Path $repository
try {
    $null = Invoke-TestGit $repository @('init', '--quiet')
    $null = Invoke-TestGit $repository @('commit', '--quiet', '--allow-empty', '--message', 'first')
    $older = Invoke-TestGit $repository @('rev-parse', 'HEAD')
    $null = Invoke-TestGit $repository @('tag', '--annotate', '--message', 'release', 'v0.1.2')
    $null = Invoke-TestGit $repository @('tag', '--annotate', '--message', 'release', 'v0.1.0-alpha3')
    $null = Invoke-TestGit $repository @('tag', 'v0.1.3')
    $null = Invoke-TestGit $repository @('commit', '--quiet', '--allow-empty', '--message', 'second')
    $head = Invoke-TestGit $repository @('rev-parse', 'HEAD')
    $null = Invoke-TestGit $repository @('tag', '--annotate', '--message', 'release', 'v0.1.4')

    Assert-That ((Resolve-ReleaseSource $head -Repository $repository) -ceq $head) 'No tag did not resolve to the commit.'
    Assert-That ((Resolve-ReleaseSource $head 'v0.1.4' $repository) -ceq $head) 'An annotated tag at the commit was refused.'
    Assert-That ((Resolve-ReleaseSource $older 'v0.1.0-alpha3' $repository) -ceq $older) 'An annotated alpha tag at the commit was refused.'

    Assert-Refused 'must use v0\.1\.N' { $null = Resolve-ReleaseSource $head 'v0.2.0' $repository }
    Assert-Refused 'must use v0\.1\.N' { $null = Resolve-ReleaseSource $head 'v0.1.01' $repository }
    Assert-Refused 'must use v0\.1\.N' { $null = Resolve-ReleaseSource $head 'v0.1.0-alpha0' $repository }
    Assert-Refused 'does not exist' { $null = Resolve-ReleaseSource $head 'v0.1.9' $repository }
    Assert-Refused 'must be annotated' { $null = Resolve-ReleaseSource $head 'v0.1.3' $repository }
    Assert-Refused 'must point at the commit' { $null = Resolve-ReleaseSource $head 'v0.1.2' $repository }
    Assert-Refused 'full lowercase SHA' { $null = Resolve-ReleaseSource $head.Substring(0, 12) '' $repository }
    Assert-Refused 'full lowercase SHA' { $null = Resolve-ReleaseSource $head.ToUpperInvariant() '' $repository }

    $output = Join-Path $scratch 'github-output'
    $script = Join-Path $PSScriptRoot '../ReleaseSource.ps1'
    Push-Location $repository
    try {
        & (Get-Process -Id $PID).Path -NoLogo -NoProfile -File $script -Tag v0.1.4 -Commit $head -GithubOutput $output | Out-Null
        Assert-That ($LASTEXITCODE -eq 0) 'The command line refused an annotated tag at the commit.'
        Assert-That ((Get-Content -LiteralPath $output -Raw) -ceq "commit=$head`n") 'The command line did not write the commit.'
        & (Get-Process -Id $PID).Path -NoLogo -NoProfile -File $script -Tag v0.1.3 -Commit $head -GithubOutput $output 2>$null | Out-Null
        Assert-That ($LASTEXITCODE -eq 1) 'The command line accepted a lightweight tag.'
    } finally {
        Pop-Location
    }
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
}

'PASS release source: an annotated tag at the commit passes, each other tag and a short commit are refused'
