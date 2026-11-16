# Proves the documents and the macOS trial still agree with the CI table.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../PlanMatrix.psm1') -Force
$root = Split-Path (Split-Path (Split-Path $PSScriptRoot))
$manifest = Read-MatrixManifest (Join-Path $PSScriptRoot '../matrix.json')
$supported = @($manifest.supported | ForEach-Object { $_.tmux })
$shells = @($manifest.powershell | ForEach-Object { $_.version })
$shellFloor = ($shells[0] -split '\.')[0..1] -join '.'

function Assert-That([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw $Message }
}

# Names the versions that a text does not mention as whole words.
function Get-MissingVersion([string] $Text, [string[]] $Versions) {
    @($Versions | Where-Object { $Text -cnotmatch "(?<![\w.])$([regex]::Escape($_))(?!\w)" })
}

# Returns a list item, including the lines it wraps onto.
function Get-Bullet([string] $Text, [string] $Start) {
    $lines = $Text -split "`n"
    $first = [array]::FindIndex($lines, [Predicate[string]] { param($line) $line.StartsWith($Start) })
    Assert-That ($first -ge 0) "No bullet starts with $Start."
    $last = $first + 1
    while ($last -lt $lines.Count -and $lines[$last].StartsWith('  ')) { $last++ }
    $lines[$first..($last - 1)] -join ' '
}

# Names the repository paths in a text that do not exist.
function Get-MissingPath([string] $Text) {
    @([regex]::Matches($Text, '(?<![\w./-])[\w.-]+(?:/[\w.-]+)+\.\w+') |
            ForEach-Object { $_.Value } |
            Where-Object { !(Test-Path -LiteralPath (Join-Path $root $_)) })
}

# Reads each tmux release and source commit pair from the macOS trial.
function Get-TrialPin([string] $Text) {
    foreach ($match in [regex]::Matches($Text, "tmux: '([^']+)'\s+tmux_commit: ([0-9a-f]{40})")) {
        , @($match.Groups[1].Value, $match.Groups[2].Value)
    }
}

function Get-DriftedPin([string] $Text) {
    $pins = @{}
    foreach ($each in $manifest.supported) { $pins[$each.tmux] = $each.commit }
    @(Get-TrialPin $Text | Where-Object { !$pins.ContainsKey($_[0]) -or $pins[$_[0]] -cne $_[1] })
}

$guide = Get-Content -LiteralPath (Join-Path $root 'docs/compatibility.md') -Raw
$row = ($guide -split "`n" | Where-Object { $_.StartsWith('| Linux x64') } | Select-Object -First 1)
Assert-That ($null -ne $row) 'The compatibility guide has no Linux x64 row.'
$gone = @(Get-MissingVersion $row @($supported + $shells + 'master'))
Assert-That (!$gone.Count) "The compatibility guide row omits: $($gone -join ', ')."
Assert-That ($guide.Contains("The minimum for ordinary operations is tmux $($supported[0])")) `
    'The guide floor is not the first supported release.'

$readme = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw
Assert-That (!@(Get-MissingVersion (Get-Bullet $readme '- **tmux.**') @($supported[0])).Count) 'The README names no tmux floor.'
Assert-That (!@(Get-MissingVersion (Get-Bullet $readme '- **PowerShell.**') @($shellFloor)).Count) 'The README names no PowerShell floor.'
Assert-That $readme.Contains('docs/compatibility.md') 'The README does not point at the compatibility guide.'

$trial = Get-Content -LiteralPath (Join-Path $root '.github/workflows/macos-trial.yml') -Raw
Assert-That (@(Get-TrialPin $trial).Count -gt 0) 'The macOS trial lists no tmux pin.'
Assert-That (!@(Get-DriftedPin $trial).Count) 'A macOS trial pin differs from the table.'
$trialShells = [regex]::Matches($trial, "powershell: '([^']+)'") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
Assert-That (!@($trialShells | Where-Object { $_ -cnotin $shells }).Count) 'The macOS trial runs a PowerShell version outside the table.'

$gone = @(Get-MissingPath $manifest['$comment'])
Assert-That (!$gone.Count) "The manifest comment names paths that do not exist: $($gone -join ', ')."

# Each check above can fail: plant the fault and expect it reported.
Assert-That ((Get-MissingPath 'eng/ci/plan_matrix.py runs it.') -ceq 'eng/ci/plan_matrix.py') 'A deleted path passed.'
Assert-That (@(Get-MissingPath 'scripts/plan-matrix/PlanMatrix.ps1 runs it.').Count -eq 0) 'An existing path was reported.'
Assert-That (@(Get-MissingVersion 'tmux 3.4 or newer.' @($supported[0])).Count -eq 1) 'A drifted tmux floor passed.'
Assert-That (@(Get-MissingVersion '- **PowerShell.** 7.2 or newer.' @($shellFloor)).Count -eq 1) 'A drifted PowerShell floor passed.'
$dropped = 'tmux ' + ($supported[0..($supported.Count - 2)] -join ', ') + ' and master with PowerShell ' + ($shells -join ' and ')
Assert-That ((Get-MissingVersion $dropped @($supported + $shells + 'master')) -ceq $supported[-1]) 'A dropped version passed.'
Assert-That (@(Get-MissingVersion '3.7ab' @('3.7a')).Count -eq 1) 'A longer word counted as a version.'
Assert-That (@(Get-MissingVersion 'tmux 3.10' @('3.1')).Count -eq 1) 'A longer number counted as a version.'
$first = @(Get-TrialPin $trial)[0]
Assert-That (@(Get-DriftedPin $trial.Replace($first[1], 'f' * 40)).Count -gt 0) 'A drifted trial pin passed.'

foreach ($group in 'supported', 'rejected', 'oldDaemon') {
    foreach ($each in $manifest[$group]) {
        Assert-That ($each.commit -cmatch '^[0-9a-f]{40}$') "The $group pin of tmux $($each.tmux) is not a full commit."
    }
}
foreach ($each in $manifest.powershell) {
    Assert-That ($each.sha256 -cmatch '^[0-9a-f]{64}$') "The digest of PowerShell $($each.version) is not a SHA-256."
}
foreach ($each in $manifest.development) { Assert-That ($each.commit -ceq '') 'A development lane is pinned.' }
'PASS matrix manifest agrees with the documents and the macOS trial'
