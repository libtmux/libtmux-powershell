param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: source equality and native output are part of example execution.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$ModuleRoot/LibTmux/0.1.0/LibTmux.psd1"
$root = Split-Path $PSScriptRoot
$source = Join-Path $root 'examples/Lifecycle.ps1'
$document = if ($env:LIBTMUX_SCOPE_DOCUMENT) { $env:LIBTMUX_SCOPE_DOCUMENT } else { Join-Path $root 'docs/lifecycle.md' }
$pattern = '(?ms)^<!-- example: lifecycle.scope -->\r?\n\r?\n```powershell\r?\n(?<code>.*?)^```'
$matches = [regex]::Matches([IO.File]::ReadAllText($document), $pattern)
if ($matches.Count -ne 1 -or $matches[0].Groups['code'].Value -cne [IO.File]::ReadAllText($source)) {
    throw 'Displayed lifecycle example differs from its executable source.'
}
$hash = (Get-FileHash $source).Hash
$mode = $env:LIBTMUX_SCOPE_MODE
$server = New-TmuxServer
$failure = $null
$output = @()
try { $output = @(& $source) } catch { $failure = $_.Exception }
if ($hash -cne (Get-FileHash $source).Hash) { throw 'Lifecycle source changed while executing.' }
$module = @(Get-Module LibTmux)
if ($module.Count -ne 1 -or $module[0].ModuleBase -cne "$ModuleRoot/LibTmux/0.1.0") { throw 'Example imported another LibTmux module.' }
if ($mode -in @('body', 'cleanup', 'both')) {
    if (!$failure) { throw 'Injected example failure disappeared.' }
    if ($mode -in @('body', 'both') -and !$failure.ToString().Contains('injected scope body failure')) { throw 'Example lost its body error.' }
    $cleanup = $null
    $retry = $null
    for ($item = $failure; $null -ne $item; $item = $item.InnerException) {
        if (!$cleanup) { $cleanup = [LibTmux.OwnedScope]::CleanupFailure($item) }
        if (!$retry) { $retry = $item.Data['LibTmux.PowerShell.Owner'] }
    }
    if ($mode -eq 'both' -and (!$cleanup -or !$cleanup.ToString().Contains('injected scope cleanup failure'))) { throw 'Example lost its paired cleanup error.' }
    if ($mode -in @('cleanup', 'both')) {
        if (!$retry -or @($server | Get-TmuxSession).Count -ne 2) { throw 'Example failure lost retry authority or its known session.' }
        [IO.File]::WriteAllText($env:LIBTMUX_SCOPE_FAULT, '')
        $retry | Close-TmuxScope
    }
    if ($output.Count) { throw 'Failed example emitted buffered success output.' }
} else {
    if ($failure) { throw $failure }
    if ($output.Count -ne 1 -or $output[0] -isnot [LibTmux.Window]) { throw 'Example did not return its captured initial window.' }
}
$remaining = @($server | Get-TmuxSession)
if ($remaining.Count -ne 1 -or $remaining[0].Name -cne 'fixture') { throw 'Example leaked its created session.' }
[pscustomobject] @{ Passed = $true; Mode = $mode; SourceSHA256 = $hash } | ConvertTo-Json -Compress
