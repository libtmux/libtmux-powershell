param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [ValidateSet('OwnedLifecycle', 'ScopeCancellation', 'ScopeIdentity', 'ScopeExample')]
    [string] $Case = 'OwnedLifecycle',
    [ValidateSet('path', 'name')] [string] $Selector = 'path',
    [ValidateSet('', 'body', 'cleanup', 'both', 'timeout', 'crash', 'no-cleanup')]
    [string] $Fault = ''
)

# Outer integration: a separate supervisor survives a timed-out or killed example worker.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot
$python = (Get-Command python3 -CommandType Application | Select-Object -First 1).Source
$tmux = (Get-Command tmux -CommandType Application | Select-Object -First 1).Source
$output = Join-Path $root ('build/ownership-checks/' + [Guid]::NewGuid().ToString('N'))
$reason = if ($Fault -eq 'timeout') { 'timeout' } elseif ($Fault -eq 'crash') { 'killed-after-marker' } else { 'completed' }
$timeout = if ($Fault -eq 'timeout') { '2' } else { '16' }
$arguments = @(
    "$PSScriptRoot/support/run_owned_lifecycle.py", '--pwsh', [Environment]::ProcessPath,
    '--tmux', $tmux, '--module-root', (Resolve-Path $ModuleRoot).Path,
    '--script', "$PSScriptRoot/$Case.Tests.ps1", '--selector', $Selector,
    '--output', $output, '--fault', $Fault, '--timeout', $timeout,
    '--expected-reason', $reason
)
& $python @arguments
$code = $LASTEXITCODE
if ($Fault -eq 'no-cleanup') {
    if ($code -ne 1 -or !(Get-Content "$output/worker.log" -Raw).Contains('Example leaked its created session.')) {
        throw 'Omitted-cleanup control did not fail the example leak assertion.'
    }
} elseif ($code) { throw "Owned lifecycle runner failed; retained $output." }
$receipt = Get-Content "$output/receipt.json" -Raw | ConvertFrom-Json
if (!$receipt.rootRemoved -or $receipt.exitObserved.PSObject.Properties.Value -contains $false) {
    throw 'An accepted process survived exact-root removal.'
}
"PASS supervised $Case/$Selector/$Fault; receipt $output/receipt.json"
