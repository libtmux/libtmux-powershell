# Each module keeps a changelog of its own, ships it in its package, links it from its
# release notes and from its README. The first check holds this checkout to that; the others
# break a copy of it one way at a time, because a check that cannot fail checks nothing.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot
$readmes = @{ 'LibTmux' = 'src/LibTmux.PowerShell/README.md'; 'LibTmux.Workspace' = 'src/LibTmux.Workspace.PowerShell/README.md' }
$blob = 'https://github.com/libtmux/libtmux-powershell/blob/master'

function Get-ChangelogFailure([string] $Root) {
    foreach ($name in $readmes.Keys | Sort-Object) {
        $path = Join-Path $Root "module/$name/CHANGELOG.md"
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { "$name has no module/$name/CHANGELOG.md"; continue }
        $lines = @(); $fenced = $false
        foreach ($line in Get-Content -LiteralPath $path) {
            if ($line -match '^ {0,3}(`{3,}|~{3,})') { $fenced = !$fenced } elseif (!$fenced) { $lines += $line }
        }
        $opening = $lines | Where-Object { $_ -notmatch '^#' -and $_.Trim() } | Select-Object -First 1
        if ($opening -cne "Notable changes to ``$name``.") { "$name's changelog does not open with its own name" }
        if (!($lines -match '^## .+ - Unreleased$')) { "$name's changelog has no Unreleased section" }
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $Root "module/$name/$name.psd1")
        if (!$manifest.PrivateData.PSData.ReleaseNotes.Contains("$blob/module/$name/CHANGELOG.md")) {
            "$name's release notes do not link its changelog"
        }
        if (!(Get-Content -LiteralPath (Join-Path $Root $readmes[$name]) -Raw).Contains("$blob/module/$name/CHANGELOG.md")) {
            "$name's README does not link its changelog"
        }
    }
}

function Assert-Failure([string] $Expected, [scriptblock] $Break) {
    $copy = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-changelog-' + [Guid]::NewGuid().ToString('N'))
    try {
        foreach ($name in $readmes.Keys) {
            $null = New-Item "$copy/module/$name" -ItemType Directory -Force
            Copy-Item "$root/module/$name/CHANGELOG.md", "$root/module/$name/$name.psd1" "$copy/module/$name"
            $null = New-Item (Split-Path "$copy/$($readmes[$name])") -ItemType Directory -Force
            Copy-Item "$root/$($readmes[$name])" "$copy/$($readmes[$name])"
        }
        & $Break $copy
        $failures = @(Get-ChangelogFailure $copy)
        if ($failures.Count -ne 1 -or $failures[0] -cne $Expected) {
            throw "Expected exactly '$Expected', got: $($failures -join '; ')"
        }
    } finally { Remove-Item -LiteralPath $copy -Recurse -Force }
}

$failures = @(Get-ChangelogFailure $root)
if ($failures.Count) { throw ($failures -join "`n") }
Assert-Failure 'LibTmux.Workspace has no module/LibTmux.Workspace/CHANGELOG.md' { param($c) Remove-Item "$c/module/LibTmux.Workspace/CHANGELOG.md" }
Assert-Failure "LibTmux.Workspace's changelog does not open with its own name" { param($c)
    Copy-Item "$root/module/LibTmux/CHANGELOG.md" "$c/module/LibTmux.Workspace/CHANGELOG.md" -Force }
Assert-Failure "LibTmux's changelog has no Unreleased section" { param($c)
    $p = "$c/module/LibTmux/CHANGELOG.md"; (Get-Content $p -Raw) -replace '(?m)^## (.+) - Unreleased$', '## $1 - 2026-01-01' | Set-Content $p }
Assert-Failure "LibTmux's changelog has no Unreleased section" { param($c)
    Set-Content "$c/module/LibTmux/CHANGELOG.md" "Notable changes to ``LibTmux``.`n`n``````markdown`n## 0.1.2 - Unreleased`n``````" }
Assert-Failure "LibTmux's release notes do not link its changelog" { param($c)
    $p = "$c/module/LibTmux/LibTmux.psd1"; (Get-Content $p -Raw).Replace('/module/LibTmux/CHANGELOG.md', '/CHANGELOG.md') | Set-Content $p }
Assert-Failure "LibTmux.Workspace's README does not link its changelog" { param($c)
    $p = "$c/src/LibTmux.Workspace.PowerShell/README.md"; (Get-Content $p -Raw).Replace('/module/LibTmux.Workspace/CHANGELOG.md', '/CHANGELOG.md') | Set-Content $p }
'PASS module changelogs'
