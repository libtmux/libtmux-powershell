param([string] $ArtifactPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot
if (!$ArtifactPath) { $ArtifactPath = Join-Path $root 'build/docs/api.json' }

function Assert-DocsApi($Artifact) {
    if ($Artifact.schema -ne 1 -or $Artifact.port -cne 'powershell') { throw 'Wrong documentation artifact identity.' }
    $revision = (& git -C $root rev-parse HEAD).Trim()
    if ($Artifact.source.revision -cne $revision) { throw 'Documentation is bound to another source revision.' }
    if ($Artifact.exporter.sha256 -cne (Get-FileHash "$root/eng/Export-Docs.ps1").Hash.ToLowerInvariant() -or
        $Artifact.exporter.helpSha256 -cne (Get-FileHash "$root/eng/Export-DocsHelp.ps1").Hash.ToLowerInvariant()) {
        throw 'Documentation is bound to different export tooling.'
    }
    foreach ($module in @('LibTmux', 'LibTmux.Workspace')) {
        $manifest = Import-PowerShellDataFile "$root/module/$module/$module.psd1"
        $commands = @($Artifact.commands | Where-Object module -CEQ $module)
        if (Compare-Object @($manifest.CmdletsToExport | Sort-Object) @($commands.name | Sort-Object)) {
            throw "Documentation omitted or invented an exported $module command."
        }
    }
    foreach ($command in $Artifact.commands) {
        if (!$command.description -or !$command.synopsis -or !$command.help.markdown) {
            throw "$($command.name) lost native help."
        }
        if (!$command.parameterSets.Count -or $command.source.line -lt 1 -or
            !(Test-Path -LiteralPath (Join-Path $root $command.source.file))) {
            throw "$($command.name) lost command syntax or its source link."
        }
        foreach ($example in $command.examples) {
            if ([string]::IsNullOrWhiteSpace($example.code)) {
                throw "$($command.name) lost executable example code."
            }
            if ($example.introduction.Contains([char] 0x80) -or $example.remarks.Contains([char] 0x80)) {
                throw "$($command.name) retained PlatyPS formatting markers."
            }
            $parseErrors = $null
            $null = [Management.Automation.Language.Parser]::ParseInput($example.code, [ref] $null, [ref] $parseErrors)
            if ($parseErrors.Count) { throw "$($command.name) exported invalid example syntax." }
        }
        foreach ($set in $command.parameterSets) {
            foreach ($parameter in $set.parameters) {
                if (!$parameter.type -or $null -eq $parameter.pipeline.byValue -or $null -eq $parameter.pipeline.byPropertyName) {
                    throw "$($command.name).$($parameter.name) lost native binding metadata."
                }
            }
        }
    }
    $pane = $Artifact.commands | Where-Object name -CEQ 'Get-TmuxPane'
    if (($pane.parameterSets.name -join ',') -cne 'Server,Session,Window') {
        throw 'Get-TmuxPane lost an owner-specific parameter set.'
    }
    foreach ($set in $pane.parameterSets) {
        $owner = $set.parameters | Where-Object name -CEQ $set.name
        if (!$owner.mandatory -or $owner.position -ne 0 -or !$owner.pipeline.byValue -or $owner.pipeline.byPropertyName) {
            throw 'Get-TmuxPane lost an owner pipeline contract.'
        }
    }
    if ($pane.outputTypes.Count -ne 1 -or $pane.outputTypes[0] -cne 'LibTmux.Pane') {
        throw 'Get-TmuxPane lost its .NET output type.'
    }
    $id = $pane.parameterSets[0].parameters | Where-Object name -CEQ 'Id'
    if ($id.attributes.type -notcontains 'System.Management.Automation.ValidateNotNullOrEmptyAttribute' -or
        $id.attributes.type -notcontains 'System.Management.Automation.ArgumentCompleterAttribute') {
        throw 'Get-TmuxPane lost validation or completion metadata.'
    }
    $server = $Artifact.commands | Where-Object name -CEQ 'New-TmuxServer'
    $binary = $server.parameterSets[0].parameters | Where-Object name -CEQ 'TmuxBinaryPath'
    if ($binary.declaration.default -cne '"tmux"') { throw 'The source initializer was not retained.' }
    $control = $Artifact.commands | Where-Object name -CEQ 'Connect-TmuxControl'
    if (!$control.supportsShouldProcess -or $control.parameterSets[0].parameters.name -notcontains 'WhatIf' -or
        $control.parameterSets[0].parameters.name -notcontains 'Confirm') {
        throw 'The control command lost its confirmation contract.'
    }
    if (!$control.notes.Contains('Tmux.ControlConnectFailed') -or !$control.examples[0].code.Contains('Connect-TmuxControl')) {
        throw 'The control command lost errors, ownership notes or native examples.'
    }
    $invoke = $Artifact.commands | Where-Object name -CEQ 'Invoke-TmuxPaneCommand'
    $timeout = $invoke.parameterSets[0].parameters | Where-Object name -CEQ 'Timeout'
    $history = $invoke.parameterSets[0].parameters | Where-Object name -CEQ 'SuppressHistory'
    if ($timeout.documentedDefault -cne '30' -or $history.documentedDefault -cne 'True') {
        throw 'Invoke-TmuxPaneCommand lost authored parameter defaults.'
    }
    if ($Artifact.source.files.path -cnotcontains 'eng/Build.ps1') {
        throw 'The executed build script is missing from source provenance.'
    }
    foreach ($file in $Artifact.source.files) {
        if ((Get-FileHash -LiteralPath (Join-Path $root $file.path)).Hash.ToLowerInvariant() -cne $file.sha256) {
            throw "Source provenance changed: $($file.path)"
        }
    }
}

$text = Get-Content -LiteralPath $ArtifactPath -Raw
$artifact = $text | ConvertFrom-Json -Depth 40
Assert-DocsApi $artifact

$broken = $text | ConvertFrom-Json -Depth 40
$pane = $broken.commands | Where-Object name -CEQ 'Get-TmuxPane'
$pane.parameterSets = @($pane.parameterSets | Where-Object name -CNE 'Session')
$rejected = $false
try { Assert-DocsApi $broken }
catch {
    if ($_.Exception.Message -cne 'Get-TmuxPane lost an owner-specific parameter set.') { throw }
    $rejected = $true
}
if (!$rejected) { throw 'The parameter-set negative control did not fail.' }
foreach ($defect in @('example', 'default', 'build')) {
    $broken = $text | ConvertFrom-Json -Depth 40
    switch ($defect) {
        'example' {
            $broken.commands[0].examples[0].code = ''
            $expected = "$($broken.commands[0].name) lost executable example code."
        }
        'default' {
            $invoke = $broken.commands | Where-Object name -CEQ 'Invoke-TmuxPaneCommand'
            ($invoke.parameterSets[0].parameters | Where-Object name -CEQ 'Timeout').documentedDefault = ''
            $expected = 'Invoke-TmuxPaneCommand lost authored parameter defaults.'
        }
        'build' {
            $broken.source.files = @($broken.source.files | Where-Object path -CNE 'eng/Build.ps1')
            $expected = 'The executed build script is missing from source provenance.'
        }
    }
    $rejected = $false
    try { Assert-DocsApi $broken }
    catch {
        if ($_.Exception.Message -cne $expected) { throw }
        $rejected = $true
    }
    if (!$rejected) { throw "The $defect negative control did not fail." }
}
"PASS docs inventory, parameter sets, pipeline binding, native help and source provenance ($($artifact.commands.Count) commands)"
