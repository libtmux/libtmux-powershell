param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [Parameter(Mandatory)] [string] $ExampleRunner,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string[]] $TmuxPath = @('tmux')
)

# Outer integration: the external supervisor owns all endpoint setup and teardown.
$ErrorActionPreference = 'Stop'
$arguments = @("$PSScriptRoot/support/run_ordinary_examples.py", '--runner', $ExampleRunner,
    '--pwsh', [Environment]::ProcessPath, '--module-root', $ModuleRoot, '--output', $OutputPath)
foreach ($binary in $TmuxPath) {
    $arguments += '--tmux', (Get-Command $binary -CommandType Application | Select-Object -First 1).Source
}
& python3 @arguments
if ($LASTEXITCODE) { throw 'Ordinary example checks failed; inspect the retained receipts.' }
