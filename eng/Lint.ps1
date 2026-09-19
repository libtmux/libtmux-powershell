[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$timer = [Diagnostics.Stopwatch]::StartNew()
$root = Split-Path $PSScriptRoot
$analyzer = "$root/build/tool-modules/PSScriptAnalyzer/1.25.0/PSScriptAnalyzer.psd1"
if (!(Test-Path $analyzer)) { throw 'Run eng/Setup.ps1 to install the pinned analyzer before linting.' }
Import-Module $analyzer
$previousPath = $env:PATH
$previousModules = $env:PSModulePath
try {
    # Analyzer command discovery must not scan arbitrary mounted executable paths.
    $env:PATH = ''
    $env:PSModulePath = @("$root/build/tool-modules", "$root/build/Modules", "$PSHOME/Modules") -join [IO.Path]::PathSeparator
    $diagnostics = @(foreach ($directory in @('eng', 'module', 'tests', 'examples')) {
        Invoke-ScriptAnalyzer -Path "$root/$directory" -Recurse -Severity Error, Warning
    })
} finally {
    $env:PATH = $previousPath
    $env:PSModulePath = $previousModules
}
$diagnostics | Format-Table RuleName, ScriptName, Line, Message -AutoSize
if ($diagnostics.Count) { throw "PowerShell analysis reported $($diagnostics.Count) diagnostics." }
"PASS PowerShell analysis ($($timer.Elapsed.TotalSeconds.ToString('F3')) s)"
