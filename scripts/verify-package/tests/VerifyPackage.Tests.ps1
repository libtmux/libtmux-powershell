# Proves the package verifier accepts matching packages and refuses a changed file, a missing
# file, empty evidence, and a PATH whose first tmux is not the expected one.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../VerifyPackage.psm1') -Force

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

function New-Packages([string] $Root, [string[]] $Names) {
    $null = New-Item -ItemType Directory -Path $Root
    $rows = foreach ($name in $Names) {
        Set-Content -LiteralPath (Join-Path $Root $name) -Value "package $name"
        @{ file = $name; sha256 = (Get-FileHash -LiteralPath (Join-Path $Root $name)).Hash.ToLowerInvariant() }
    }
    @{ packages = @($rows) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Root 'package-evidence.json')
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) "libtmux-verify-test-$([Guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $scratch
$previousPath = $env:PATH
try {
    $good = Join-Path $scratch 'good'
    New-Packages $good @('LibTmux.1.nupkg', 'LibTmux.Workspace.1.nupkg')
    Assert-That ((@(Test-PackageBytes $good)).Count -eq 2) 'Matching packages were not both checked.'

    $changed = Join-Path $scratch 'changed'
    New-Packages $changed @('LibTmux.1.nupkg')
    Add-Content -LiteralPath (Join-Path $changed 'LibTmux.1.nupkg') -Value 'tampered'
    Assert-Refused 'SHA-256' { $null = Test-PackageBytes $changed }

    $missing = Join-Path $scratch 'missing'
    New-Packages $missing @('LibTmux.1.nupkg')
    Remove-Item -LiteralPath (Join-Path $missing 'LibTmux.1.nupkg')
    Assert-Refused 'is missing' { $null = Test-PackageBytes $missing }

    $empty = Join-Path $scratch 'empty'
    $null = New-Item -ItemType Directory -Path $empty
    '{"packages": []}' | Set-Content -LiteralPath (Join-Path $empty 'package-evidence.json')
    Assert-Refused 'lists no package' { $null = Test-PackageBytes $empty }
    Assert-Refused 'does not exist' { $null = Test-PackageBytes (Join-Path $scratch 'nowhere') }

    $first = Join-Path $scratch 'first'
    $second = Join-Path $scratch 'second'
    foreach ($directory in @($first, $second)) {
        $null = New-Item -ItemType Directory -Path $directory
        $tmux = Join-Path $directory 'tmux'
        Set-Content -LiteralPath $tmux -Value 'a tmux'
        [IO.File]::SetUnixFileMode($tmux, [IO.File]::GetUnixFileMode($tmux) -bor [IO.UnixFileMode]::UserExecute)
    }
    $env:PATH = "$first$([IO.Path]::PathSeparator)$second$([IO.Path]::PathSeparator)$previousPath"
    Test-TmuxOnPath (Join-Path $first 'tmux')
    Assert-Refused 'not' { Test-TmuxOnPath (Join-Path $second 'tmux') }
} finally {
    $env:PATH = $previousPath
    Remove-Item -LiteralPath $scratch -Recurse -Force
}

'PASS package verifier: matching packages pass, each tampering and the wrong tmux are refused'
