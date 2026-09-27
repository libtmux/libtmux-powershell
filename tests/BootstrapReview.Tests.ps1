# Outer integration: checks source isolation with disposable Git repositories.
param([string] $BootstrapScript = (Join-Path (Split-Path $PSScriptRoot) 'eng/BootstrapReview.ps1'))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-bootstrap-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary

function Invoke-Git([string[]] $Arguments) {
    & git @Arguments
    if ($LASTEXITCODE) { throw "git $($Arguments[0]) failed in the bootstrap test." }
}

function Assert-BootstrapFailure([string] $Script, [string] $Output, [string] $Reason, [string] $CoreSource = '') {
    $failure = $null
    try {
        if ($CoreSource) { & $Script -OutputDirectory $Output -CoreSource $CoreSource }
        else { & $Script -OutputDirectory $Output }
    } catch {
        $failure = $_
    }
    if (!$failure) { throw "Bootstrap accepted an invalid source or output: $Reason" }
    if ($failure.Exception.Message -notmatch $Reason) {
        throw "Bootstrap failed for the wrong reason: $($failure.Exception.Message)"
    }
}

try {
    $checkout = Join-Path $temporary 'port'
    Invoke-Git @('clone', '--quiet', '--shared', $root, $checkout)
    $script = Join-Path $checkout 'eng/BootstrapReview.ps1'
    $candidate = $BootstrapScript
    if (!(Test-Path -LiteralPath $candidate)) { throw 'The source bootstrap script is missing.' }
    Copy-Item -LiteralPath $candidate -Destination $script
    Invoke-Git @('-C', $checkout, 'add', '--', 'eng/BootstrapReview.ps1')
    Invoke-Git @('-C', $checkout, '-c', 'user.name=Bootstrap Test', '-c', 'user.email=bootstrap@example.invalid',
        'commit', '--quiet', '--allow-empty', '-m', 'Add bootstrap test candidate')

    $existing = Join-Path $temporary 'existing'
    $null = New-Item -ItemType Directory -Path $existing
    Set-Content -LiteralPath (Join-Path $existing 'sentinel') -Value 'keep'
    Assert-BootstrapFailure $script $existing 'already exists'
    if ((Get-Content -LiteralPath (Join-Path $existing 'sentinel') -Raw).Trim() -cne 'keep') {
        throw 'Bootstrap changed an existing output directory.'
    }

    Add-Content -LiteralPath (Join-Path $checkout 'README.md') -Value 'dirty'
    $dirtyOutput = Join-Path $temporary 'dirty-output'
    Assert-BootstrapFailure $script $dirtyOutput 'uncommitted changes'
    if (Test-Path -LiteralPath $dirtyOutput) { throw 'Bootstrap created output for a dirty source.' }
    Invoke-Git @('-C', $checkout, 'restore', '--', 'README.md')

    $wrongCore = Join-Path $temporary 'wrong-core'
    Invoke-Git @('init', '--quiet', $wrongCore)
    Set-Content -LiteralPath (Join-Path $wrongCore 'README.md') -Value 'wrong revision'
    Invoke-Git @('-C', $wrongCore, 'add', '--', 'README.md')
    Invoke-Git @('-C', $wrongCore, '-c', 'user.name=Bootstrap Test', '-c', 'user.email=bootstrap@example.invalid',
        'commit', '--quiet', '-m', 'Create wrong core revision')
    $wrongOutput = Join-Path $temporary 'wrong-output'
    Assert-BootstrapFailure $script $wrongOutput 'revision' $wrongCore
    if (Test-Path -LiteralPath $wrongOutput) { throw 'Bootstrap created output for the wrong core revision.' }

    $insideOutput = Join-Path $checkout 'bootstrap-output'
    Assert-BootstrapFailure $script $insideOutput 'outside both source checkouts' $wrongCore
    if (Test-Path -LiteralPath $insideOutput) { throw 'Bootstrap wrote inside the source checkout.' }

    $sourceLink = Join-Path $temporary 'source-link'
    $null = New-Item -ItemType SymbolicLink -Path $sourceLink -Target $checkout
    $linkedOutput = Join-Path $sourceLink 'bootstrap-output'
    Assert-BootstrapFailure $script $linkedOutput 'outside both source checkouts' $wrongCore
    if (Test-Path -LiteralPath $insideOutput) { throw 'Bootstrap followed an output link into source.' }

    $onlyPython3 = Join-Path $temporary 'only-python3'
    $null = New-Item -ItemType Directory -Path $onlyPython3
    foreach ($name in @('git', 'dotnet', 'python3')) {
        $sourceName = if ($name -eq 'python3') { @('python3', 'python') } else { @($name) }
        $binary = Get-Command $sourceName -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $onlyPython3 $name) -Target $binary.Source
    }
    $originalPath = $env:PATH
    try {
        $env:PATH = $onlyPython3
        Assert-BootstrapFailure $script $existing 'already exists'
    } finally { $env:PATH = $originalPath }

    $fallback = Join-Path $temporary 'python-fallback'
    $null = New-Item -ItemType Directory -Path $fallback
    foreach ($name in @('git', 'dotnet', 'python')) {
        $sourceName = if ($name -eq 'python') { @('python3', 'python') } else { @($name) }
        $binary = Get-Command $sourceName -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $fallback $name) -Target $binary.Source
    }
    $oldPython = Join-Path $fallback 'python3'
    Set-Content -LiteralPath $oldPython -NoNewline -Value "#!/bin/sh`nprintf '3.8\n'`n"
    & chmod +x $oldPython
    if ($LASTEXITCODE) { throw 'Cannot create an old-Python fixture.' }
    try {
        $env:PATH = $fallback
        Assert-BootstrapFailure $script $existing 'already exists'
    } finally { $env:PATH = $originalPath }

    'PASS bootstrap source guards and Python interpreter selection'
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
