# Proves the review dependency script derives a unique version, rewrites only the
# shared pins, and accepts only lock changes that come from the review packages.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../ReviewDependencies.psm1') -Force

$base = '0.0.0-alpha.17.ps.4'
$ci = "$base.ci.123.1"
$projects = @('LibTmux.PowerShell', 'LibTmux.Workspace.PowerShell')

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

function New-Checkout {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-review-test-' + [Guid]::NewGuid().ToString('N'))
    foreach ($project in $projects) { $null = New-Item -ItemType Directory -Path (Join-Path $root "src/$project") -Force }
    Set-Content -LiteralPath (Join-Path $root 'Directory.Packages.props') -Value ('<Project><ItemGroup>' +
        "<PackageVersion Include=`"LibTmux`" Version=`"[$base]`" />" +
        "<PackageVersion Include=`"LibTmux.Query.Json`" Version=`"[$base]`" />" +
        "<PackageVersion Include=`"LibTmux.Workspace`" Version=`"[$base]`" />" +
        '</ItemGroup></Project>')
    $lock = @{
        version      = 1
        dependencies = @{ 'net8.0' = @{
                LibTmux              = @{ resolved = $base; contentHash = 'original-core' }
                'LibTmux.Query.Json' = @{ resolved = $base; contentHash = 'original-query'; dependencies = @{ LibTmux = $base } }
                ThirdParty           = @{ resolved = '1.0.0'; contentHash = 'original-third-party' }
            }
        }
    }
    foreach ($project in $projects) { Write-Lock (Join-Path $root "src/$project/packages.lock.json") $lock }
    $root
}

function Write-Lock([string] $Path, $Lock) {
    Set-Content -LiteralPath $Path -Value (ConvertTo-Json -InputObject $Lock -Depth 10)
}

function Update-Lock([string] $Root, [scriptblock] $Change) {
    foreach ($project in $projects) {
        $path = Join-Path $Root "src/$project/packages.lock.json"
        $lock = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
        & $Change $lock
        Write-Lock $path $lock
    }
}

# What a restore against the review packages writes: the review version and new hashes.
function Set-ReviewLocks([string] $Root) {
    Update-Lock $Root {
        param($lock)
        $packages = $lock.dependencies['net8.0']
        $packages.LibTmux.resolved = $ci
        $packages.LibTmux.contentHash = 'new-core'
        $packages['LibTmux.Query.Json'].resolved = $ci
        $packages['LibTmux.Query.Json'].contentHash = 'new-query'
        $packages['LibTmux.Query.Json'].dependencies.LibTmux = $ci
    }
}

$cleanup = [Collections.Generic.List[string]]::new()
try {
    # The version extends the pin and a prepared checkout accepts only review hashes.
    $root = New-Checkout
    $cleanup.Add($root)
    $baseline = Join-Path $root 'baseline'
    Assert-That ((Get-ReviewVersion -Root $root -RunId 123 -Attempt 1) -ceq $ci) 'The review version does not extend the pin.'
    Initialize-ReviewPins -Root $root -Version $ci -Baseline $baseline
    $props = Get-Content -LiteralPath (Join-Path $root 'Directory.Packages.props') -Raw
    Assert-That (([regex]::Matches($props, [regex]::Escape("Version=`"[$ci]`""))).Count -eq 3) `
        'Prepare did not rewrite the three shared pins.'
    foreach ($project in $projects) {
        Assert-That (Test-Path -LiteralPath (Join-Path $baseline "src/$project/packages.lock.json")) `
            "Prepare did not save the $project lock."
    }
    Set-ReviewLocks $root
    Test-ReviewLocks -Root $root -Version $ci -Baseline $baseline

    # Transitive package drift is refused.
    Update-Lock $root { param($lock) $lock.dependencies['net8.0'].ThirdParty.contentHash = 'changed' }
    Assert-Refused 'unexpected dependency graph change' { Test-ReviewLocks -Root $root -Version $ci -Baseline $baseline }

    # Locks that do not resolve the review version are refused.
    $root = New-Checkout
    $cleanup.Add($root)
    $baseline = Join-Path $root 'baseline'
    Initialize-ReviewPins -Root $root -Version $ci -Baseline $baseline
    Assert-Refused 'does not resolve CI review version' { Test-ReviewLocks -Root $root -Version $ci -Baseline $baseline }

    # Mismatched shared pins are refused.
    $root = New-Checkout
    $cleanup.Add($root)
    $props = Join-Path $root 'Directory.Packages.props'
    (Get-Content -LiteralPath $props -Raw).Replace("Include=`"LibTmux.Workspace`" Version=`"[$base]`"", 'Include="LibTmux.Workspace" Version="[0.0.0-other.1]"') |
        Set-Content -LiteralPath $props
    Assert-Refused 'matching exact versions' { Initialize-ReviewPins -Root $root -Version $ci -Baseline (Join-Path $root 'baseline') }

    # A version that does not extend the pin, and an existing baseline, are refused.
    $root = New-Checkout
    $cleanup.Add($root)
    Assert-Refused 'must extend the exact shared pin' { Initialize-ReviewPins -Root $root -Version '9.9.9.ci.1.1' -Baseline (Join-Path $root 'baseline') }
    $null = New-Item -ItemType Directory -Path (Join-Path $root 'baseline')
    Assert-Refused 'baseline already exists' { Initialize-ReviewPins -Root $root -Version $ci -Baseline (Join-Path $root 'baseline') }
    Assert-Refused 'must be positive' { Get-ReviewVersion -Root $root -RunId 0 -Attempt 1 }
} finally {
    foreach ($path in $cleanup) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
}
'PASS review dependencies: version, prepare and verify accept review hashes only'
