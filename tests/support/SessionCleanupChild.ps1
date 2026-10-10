param([Parameter(Mandatory)] [string] $ModuleRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$ModuleRoot/LibTmux/0.1.0/LibTmux.psd1"
$source = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'examples/SessionCleanup.ps1'
$before = (Get-FileHash -LiteralPath $source).Hash
$failure = $null
$session = $null
try { $session = & $source } catch { $failure = $_.Exception }
$loaded = @(Get-Module LibTmux)
if ($loaded.Count -ne 1 -or $loaded[0].ModuleBase -cne "$ModuleRoot/LibTmux/0.1.0") {
    throw 'SessionCleanup imported a different LibTmux module.'
}
if ((Get-FileHash -LiteralPath $source).Hash -cne $before) { throw 'SessionCleanup source changed during execution.' }
$graph = $null
if ($session) {
    if ($session -isnot [LibTmux.Session]) { throw 'SessionCleanup did not return a native Session.' }
    $graph = @($session.Windows | ForEach-Object {
        if ($_ -isnot [LibTmux.Window]) { throw 'SessionCleanup returned a non-native Window.' }
        [pscustomobject]@{
            Name = $_.Name
            PaneIds = @($_.Panes | ForEach-Object {
                if ($_ -isnot [LibTmux.Pane]) { throw 'SessionCleanup returned a non-native Pane.' }
                [string] $_.Id
            })
        }
    })
}
[pscustomobject]@{
    SourceSha256 = $before
    ErrorType = $(if ($failure) { $failure.GetType().FullName })
    Errors = @(
        if ($failure -is [AggregateException]) { $failure.InnerExceptions | ForEach-Object Message }
        elseif ($failure) { $failure.Message }
    )
    Windows = $graph
} | ConvertTo-Json -Depth 5 -Compress
