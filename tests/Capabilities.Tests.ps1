param([Parameter(Mandatory)] [string] $ModuleRoot)

# Keeps capabilities.json equal to the registry the module refuses with. Setting
# LIBTMUX_WRITE_CAPABILITIES=1 rewrites the manifest from the registry.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')
Import-Module (Join-Path $ModuleRoot 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1')

function Assert-Capabilities([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw "Capabilities: $Message" }
}

$registry = [LibTmux.PowerShell.TmuxCmdlet].Assembly.GetType('LibTmux.PowerShell.Support.Capabilities', $true)
$rendered = $registry.GetMethod('ToManifestJson', [Reflection.BindingFlags] 'Static,NonPublic').Invoke($null, @())
$path = Join-Path (Split-Path $PSScriptRoot) 'capabilities.json'
if ($env:LIBTMUX_WRITE_CAPABILITIES -eq '1') {
    [IO.File]::WriteAllText($path, $rendered, [Text.UTF8Encoding]::new($false))
}
Assert-Capabilities (Test-Path -LiteralPath $path) 'capabilities.json is missing; run with LIBTMUX_WRITE_CAPABILITIES=1'
Assert-Capabilities ([IO.File]::ReadAllText($path) -ceq $rendered) `
    'capabilities.json differs from the registry; run with LIBTMUX_WRITE_CAPABILITIES=1 and review the change'

$manifest = $rendered | ConvertFrom-Json
Assert-Capabilities ($manifest.schema -ceq 'libtmux-capabilities/1' -and $manifest.port -ceq 'powershell') 'the manifest names the wrong schema or port'
Assert-Capabilities ($manifest.floor.minimum -ceq [LibTmux.LibTmuxInfo]::MinimumTmuxVersion.Raw) 'the manifest floor is not the package minimum'

$entries = @($manifest.capabilities) + @($manifest.workarounds)
$ids = @($entries | ForEach-Object { $_.id })
Assert-Capabilities ($ids.Count -eq @($ids | Select-Object -Unique).Count) 'an id repeats'
foreach ($id in $ids) { Assert-Capabilities ($id -cmatch '^[a-z][a-z0-9]*(-[a-z0-9]+)*$') "id '$id' is not kebab-case" }

# A refusal names a public error, and every API name is a cmdlet the modules export.
foreach ($capability in $manifest.capabilities) {
    if ($capability.handling -ceq 'refuse') {
        Assert-Capabilities ($capability.error -and ($capability.error -as [type])) "capability $($capability.id) names no public error type"
    }
}
# One type covers every refusal a release causes: the base type, or its subclass for a plain floor.
# The layout and name entries are the defects and gaps that once raised ArgumentException or
# TmuxWindowException, so each must name the base type itself.
$base = [LibTmux.TmuxUnsupportedOnReleaseException]
$baseOnly = @('layout-without-checksum', 'layout-mirrored-main', 'layout-json', 'name-separators-rejected')
foreach ($entry in $entries) {
    if ($entry.handling -cne 'refuse') { continue }
    $type = $entry.error -as [type]
    Assert-Capabilities ($type -and $base.IsAssignableFrom($type)) "$($entry.id) names '$($entry.error)', which is not a release refusal"
    if ($entry.id -cin $baseOnly) {
        Assert-Capabilities ($type -eq $base) "$($entry.id) names '$($entry.error)' rather than the base release refusal"
    }
}
foreach ($id in $baseOnly) { Assert-Capabilities ($id -cin $ids) "$id is missing from the manifest" }
# A JSON layout is a promise at the release, tmux 3.8: 3.7c is below it and 3.8 is at it. 3.8a is
# only a sample that orders above 3.8; it is not a release.
$jsonLayout = @($manifest.capabilities | Where-Object { $_.id -ceq 'layout-json' })[0]
Assert-Capabilities ($jsonLayout.since -ceq '3.8') "layout-json starts at '$($jsonLayout.since)' rather than 3.8"
$jsonFloor = [LibTmux.TmuxVersion]::Parse($jsonLayout.since)
Assert-Capabilities ([LibTmux.TmuxVersion]::Parse('3.7c') -lt $jsonFloor) 'layout-json admits 3.7c'
Assert-Capabilities ([LibTmux.TmuxVersion]::Parse('3.8') -ge $jsonFloor) 'layout-json refuses 3.8'
Assert-Capabilities ([LibTmux.TmuxVersion]::Parse('3.8a') -gt [LibTmux.TmuxVersion]::Parse('3.8')) '3.8a does not order above 3.8'
foreach ($entry in $entries) {
    Assert-Capabilities (@($entry.apis).Count -gt 0) "$($entry.id) names no API"
    foreach ($api in $entry.apis) {
        $found = Get-Command -Module LibTmux, LibTmux.Workspace -Name $api -CommandType Cmdlet -ErrorAction SilentlyContinue
        Assert-Capabilities ($null -ne $found) "$($entry.id) names '$api', which no module exports"
    }
}

# Every release a workaround lists lies inside the span its gate reads.
$internal = [Reflection.BindingFlags] 'Instance,NonPublic,Public'
foreach ($claim in $registry.GetProperty('Workarounds', [Reflection.BindingFlags] 'Static,NonPublic').GetValue($null)) {
    $type = $claim.GetType()
    $affects = $type.GetMethod('Affects', $internal)
    $id = $type.GetProperty('Id', $internal).GetValue($claim)
    foreach ($release in $type.GetProperty('Releases', $internal).GetValue($claim)) {
        Assert-Capabilities ($affects.Invoke($claim, @([LibTmux.TmuxVersion]::Parse($release)))) "$id lists $release outside its span"
    }
    $until = $type.GetProperty('Until', $internal).GetValue($claim)
    Assert-Capabilities (-not $affects.Invoke($claim, @($until))) "$id still affects the release that fixes it"
}
'PASS capabilities: manifest equals the registry; ids, errors and cmdlet names resolve'
