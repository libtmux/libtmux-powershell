[CmdletBinding()]
param(
    [string] $SourceRoot = (Split-Path $PSScriptRoot),
    [string] $OutputPath,
    [switch] $Restore
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
if (!$OutputPath) { $OutputPath = Join-Path $root 'build/docs/api.json' }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$repository = 'libtmux/libtmux-powershell'
$sourcePaths = @('src', 'module', 'docs/reference', 'eng/Build.ps1',
    'Directory.Build.props', 'Directory.Packages.props', 'global.json')

function Get-RelativeSource([string] $Path) {
    $relative = [IO.Path]::GetRelativePath($root, $Path).Replace('\', '/')
    if ($relative.StartsWith('../') -or [IO.Path]::IsPathRooted($relative)) {
        throw "Documentation source is outside the checkout: $Path"
    }
    return $relative
}

function Get-SourceInventory {
    $paths = @(& git -C $root ls-files -- @sourcePaths)
    if ($LASTEXITCODE) { throw 'Cannot enumerate documentation source files.' }
    return @(foreach ($path in ($paths | Sort-Object -CaseSensitive)) {
        [ordered]@{ path = $path; sha256 = (Get-FileHash -LiteralPath (Join-Path $root $path)).Hash.ToLowerInvariant() }
    })
}

function Get-XmlText($Node, [string] $XPath) {
    if ($null -eq $Node) { return '' }
    return (@($Node.SelectNodes($XPath) | ForEach-Object { $_.InnerText.Trim() }) -join "`n`n").Trim()
}

function Get-SourceLocation($Node, [string] $File) {
    return [ordered]@{
        file = Get-RelativeSource $File
        line = $Node.GetLocation().GetLineSpan().StartLinePosition.Line + 1
        endLine = $Node.GetLocation().GetLineSpan().EndLinePosition.Line + 1
    }
}

function Get-AttributeValue($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [Type]) { return $Value.FullName }
    if ($Value -is [Enum]) { return $Value.ToString() }
    if ($Value -is [Reflection.CustomAttributeTypedArgument]) { return Get-AttributeValue $Value.Value }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        return , @(foreach ($item in $Value) { Get-AttributeValue $item })
    }
    return $Value
}

function Get-DeclaredAttributes($Member) {
    if ($null -eq $Member) { return @() }
    return @(foreach ($attribute in $Member.GetCustomAttributesData()) {
        $named = [ordered]@{}
        foreach ($argument in ($attribute.NamedArguments | Sort-Object MemberName)) {
            $named[$argument.MemberName] = Get-AttributeValue $argument.TypedValue
        }
        [ordered]@{
            type = $attribute.AttributeType.FullName
            arguments = @(foreach ($argument in $attribute.ConstructorArguments) { Get-AttributeValue $argument })
            namedArguments = $named
        }
    })
}

Push-Location $root
try {
    $revision = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -or $revision -cnotmatch '^[0-9a-f]{40}$') { throw 'Cannot determine source revision.' }
    $changes = @(& git status --porcelain -- @sourcePaths)
    if ($LASTEXITCODE -or $changes.Count) { throw 'Commit API and help sources before exporting documentation.' }
    $sourcesBefore = Get-SourceInventory
    $helpArtifactPath = [IO.Path]::GetTempFileName()
    try {
        & "$PSHOME/pwsh" -NoLogo -NoProfile -File "$PSScriptRoot/Export-DocsHelp.ps1" `
            -SourceRoot $root -OutputPath $helpArtifactPath
        if ($LASTEXITCODE) { throw 'Native Markdown help extraction failed.' }
        $authoredHelp = Get-Content -LiteralPath $helpArtifactPath -Raw | ConvertFrom-Json -AsHashtable -Depth 20
    } finally {
        Remove-Item -LiteralPath $helpArtifactPath
    }
    & "$root/eng/Build.ps1" -Restore:$Restore
    if (!$?) { throw 'Module build failed before documentation extraction.' }

    # PowerShell already loads its pinned Roslyn assemblies for Add-Type.
    # A second compiler version cannot share that assembly load context.
    $sdkVersion = (& dotnet --version).Trim()
    if ($LASTEXITCODE) { throw 'Cannot determine the selected .NET SDK.' }
    $compiler = [Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree].Assembly
    $declarations = @{}
    foreach ($file in (Get-ChildItem "$root/src" -Filter '*.cs' -Recurse | Where-Object {
        $_.FullName -notmatch '[/\\](bin|obj)[/\\]'
    } | Sort-Object FullName)) {
        $tree = [Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([IO.File]::ReadAllText($file.FullName))
        $errors = @($tree.GetDiagnostics() | Where-Object Severity -EQ Error)
        if ($errors.Count) { throw "C# parse errors in $($file.FullName): $errors" }
        foreach ($node in $tree.GetRoot().DescendantNodes()) {
            if ($node -isnot [Microsoft.CodeAnalysis.CSharp.Syntax.BaseTypeDeclarationSyntax]) { continue }
            $owners = @($node.Ancestors() | Where-Object {
                $_ -is [Microsoft.CodeAnalysis.CSharp.Syntax.BaseNamespaceDeclarationSyntax] -or
                $_ -is [Microsoft.CodeAnalysis.CSharp.Syntax.BaseTypeDeclarationSyntax]
            })
            [array]::Reverse($owners)
            $names = @(foreach ($owner in $owners) {
                if ($owner -is [Microsoft.CodeAnalysis.CSharp.Syntax.BaseNamespaceDeclarationSyntax]) { $owner.Name.ToString() }
                else { $owner.Identifier.ValueText }
            }) + $node.Identifier.ValueText
            $name = $names -join '.'
            if ($declarations.ContainsKey($name)) { throw "Multiple source declarations require explicit partial-type handling: $name" }
            $properties = @{}
            foreach ($property in $node.Members) {
                if ($property -is [Microsoft.CodeAnalysis.CSharp.Syntax.PropertyDeclarationSyntax]) {
                    $properties[$property.Identifier.ValueText] = [ordered]@{
                        source = Get-SourceLocation $property $file.FullName
                        declaration = $property.ToString()
                        default = if ($null -ne $property.Initializer) { $property.Initializer.Value.ToString() } else { $null }
                    }
                }
            }
            $declarations[$name] = [ordered]@{
                source = Get-SourceLocation $node $file.FullName
                properties = $properties
            }
        }
    }

    $moduleRecords = [Collections.Generic.List[object]]::new()
    $commandRecords = [Collections.Generic.List[object]]::new()
    foreach ($moduleName in @('LibTmux', 'LibTmux.Workspace')) {
        $moduleDirectory = "$root/build/Modules/$moduleName/0.1.0"
        $manifestPath = "$moduleDirectory/$moduleName.psd1"
        $manifest = Import-PowerShellDataFile $manifestPath
        $module = Import-Module $manifestPath -PassThru
        $product = if ($moduleName -eq 'LibTmux') { 'core' } else { 'workspace' }
        $commands = @($module.ExportedCommands.Values | Where-Object CommandType -In @('Cmdlet', 'Function') | Sort-Object Name)
        $expected = @($manifest.CmdletsToExport) + @($manifest.FunctionsToExport)
        if (@($expected | Where-Object { [WildcardPattern]::ContainsWildcardCharacters($_) }).Count) {
            throw "Declare explicit command exports before documenting $moduleName."
        }
        if (Compare-Object @($expected | Sort-Object) @($commands.Name | Sort-Object)) {
            throw "Native command inventory differs from $moduleName's manifest."
        }
        [xml] $maml = Get-Content "$moduleDirectory/en-US/$moduleName.PowerShell.dll-Help.xml" -Raw
        [xml] $xmlDocs = Get-Content "$moduleDirectory/$moduleName.PowerShell.xml" -Raw
        $helpCommands = @{}
        foreach ($help in $maml.SelectNodes('/*/*[local-name()="command"]')) {
            $name = Get-XmlText $help '*[local-name()="details"]/*[local-name()="name"]'
            if ($helpCommands.ContainsKey($name)) { throw "Duplicate help for $name." }
            $helpCommands[$name] = $help
        }
        if (Compare-Object @($expected | Sort-Object) @($helpCommands.Keys | Sort-Object)) {
            throw "Packaged help inventory differs from $moduleName's manifest."
        }
        $aliases = @(foreach ($alias in ($module.ExportedAliases.Values | Sort-Object Name)) {
            [ordered]@{ name = $alias.Name; target = $alias.Definition }
        })
        $moduleRecords.Add([ordered]@{
            name = $moduleName
            version = "$($manifest.ModuleVersion)-$($manifest.PrivateData.PSData.Prerelease)"
            product = $product
            description = $manifest.Description
            powerShellVersion = $manifest.PowerShellVersion
            source = [ordered]@{ file = "module/$moduleName/$moduleName.psd1"; line = 1 }
            commands = @($commands.Name)
            aliases = $aliases
            requiredModules = @(foreach ($required in @($manifest['RequiredModules'] | Where-Object { $null -ne $_ })) {
                if ($required -is [Collections.IDictionary]) {
                    $record = [ordered]@{}
                    foreach ($key in ($required.Keys | Sort-Object)) { $record[$key] = $required[$key] }
                    $record
                } else { [ordered]@{ ModuleName = [string] $required } }
            })
        })
        foreach ($command in $commands) {
            $help = $helpCommands[$command.Name]
            $authored = $authoredHelp.commands["$moduleName\$($command.Name)"]
            if ($null -eq $authored) { throw "Missing authored help for $($command.Name)." }
            $metadata = [Management.Automation.CommandMetadata]::new($command)
            $implementation = $null
            $source = $null
            $typeDocs = $null
            if ($command -is [Management.Automation.CmdletInfo]) {
                $type = $command.ImplementingType
                if (!$declarations.ContainsKey($type.FullName)) { throw "Missing source declaration for $($type.FullName)." }
                $source = $declarations[$type.FullName].source
                $implementation = [ordered]@{
                    type = $type.FullName
                    assemblySha256 = (Get-FileHash -LiteralPath $type.Assembly.Location).Hash.ToLowerInvariant()
                }
                $typeDocs = $xmlDocs.SelectSingleNode("/doc/members/member[@name='T:$($type.FullName)']")
            } else {
                $source = [ordered]@{
                    file = Get-RelativeSource $command.ScriptBlock.File
                    line = $command.ScriptBlock.Ast.Extent.StartLineNumber
                    endLine = $command.ScriptBlock.Ast.Extent.EndLineNumber
                }
            }
            $parameterHelp = @{}
            foreach ($entry in $help.SelectNodes('*[local-name()="parameters"]/*[local-name()="parameter"]')) {
                $parameterHelp[(Get-XmlText $entry '*[local-name()="name"]')] = $entry
            }
            $documentedParameters = @($command.Parameters.Keys | Where-Object {
                $_ -notin [Management.Automation.PSCmdlet]::CommonParameters
            } | Sort-Object)
            if (Compare-Object $documentedParameters @($parameterHelp.Keys | Sort-Object)) {
                throw "$($command.Name) help and native parameter inventories disagree."
            }
            if (Compare-Object $documentedParameters @($authored.parameters.Keys | Sort-Object)) {
                throw "$($command.Name) authored help and native parameter inventories disagree."
            }
            $sets = @(foreach ($set in ($command.ParameterSets | Sort-Object Name)) {
                $parameters = @(foreach ($parameter in $set.Parameters) {
                    $detail = $command.Parameters[$parameter.Name]
                    $property = $null
                    $syntax = $null
                    if ($command -is [Management.Automation.CmdletInfo]) {
                        $property = $command.ImplementingType.GetProperty($parameter.Name)
                        if ($null -ne $property -and $declarations.ContainsKey($property.DeclaringType.FullName)) {
                            $syntax = $declarations[$property.DeclaringType.FullName].properties[$parameter.Name]
                        }
                    } else {
                        $parameterAst = $command.ScriptBlock.Ast.Find({ param($node)
                            $node -is [Management.Automation.Language.ParameterAst] -and $node.Name.VariablePath.UserPath -eq $parameter.Name
                        }, $true)
                        if ($null -ne $parameterAst) {
                            $syntax = [ordered]@{
                                source = [ordered]@{
                                    file = Get-RelativeSource $parameterAst.Extent.File
                                    line = $parameterAst.Extent.StartLineNumber
                                    endLine = $parameterAst.Extent.EndLineNumber
                                }
                                declaration = $parameterAst.Extent.Text
                                default = if ($null -ne $parameterAst.DefaultValue) { $parameterAst.DefaultValue.Extent.Text } else { $null }
                            }
                        }
                    }
                    $entry = $parameterHelp[$parameter.Name]
                    $common = $parameter.Name -in [Management.Automation.PSCmdlet]::CommonParameters
                    if (!$common -and $null -eq $entry) { throw "$($command.Name) has no help for $($parameter.Name)." }
                    [ordered]@{
                        name = $parameter.Name
                        type = $parameter.ParameterType.FullName
                        mandatory = $parameter.IsMandatory
                        position = if ($parameter.Position -ge 0) { $parameter.Position } else { $null }
                        switch = $parameter.ParameterType -eq [Management.Automation.SwitchParameter]
                        common = $common
                        dynamic = $detail.IsDynamic
                        aliases = @($parameter.Aliases)
                        pipeline = [ordered]@{
                            byValue = $parameter.ValueFromPipeline
                            byPropertyName = $parameter.ValueFromPipelineByPropertyName
                            remainingArguments = $parameter.ValueFromRemainingArguments
                        }
                        description = if ($common) { '' } else { $authored.parameters[$parameter.Name].description }
                        documentedDefault = if ($common) { '' } else { $authored.parameters[$parameter.Name].default }
                        declaration = $syntax
                        attributes = @(Get-DeclaredAttributes $property)
                    }
                })
                [ordered]@{ name = $set.Name; isDefault = $set.IsDefault; syntax = $set.ToString(); parameters = $parameters }
            })
            $types = @{}
            foreach ($section in @('inputTypes', 'returnValues')) {
                $types[$section] = @(foreach ($entry in $help.SelectNodes("*[local-name()='$section']/*")) {
                    [ordered]@{
                        type = Get-XmlText $entry '*[local-name()="type"]/*[local-name()="name"]'
                        description = Get-XmlText $entry '*[local-name()="description"]/*'
                    }
                })
            }
            $examples = @($authored.examples)
            if ($examples.Count -ne $help.SelectNodes('*[local-name()="examples"]/*').Count) {
                throw "$($command.Name) authored and packaged example inventories disagree."
            }
            $markdownPath = "docs/reference/$moduleName/$($command.Name).md"
            $commandRecords.Add([ordered]@{
                id = "$moduleName\$($command.Name)"
                name = $command.Name
                module = $moduleName
                product = $product
                kind = $command.CommandType.ToString().ToLowerInvariant()
                source = $source
                implementation = $implementation
                xmlDocumentation = if ($null -ne $typeDocs) { $typeDocs.OuterXml } else { $null }
                synopsis = $authored.synopsis
                description = $authored.description
                notes = $authored.notes
                help = [ordered]@{ file = $markdownPath; markdown = [IO.File]::ReadAllText((Join-Path $root $markdownPath)) }
                aliases = @($aliases | Where-Object target -EQ $command.Name | ForEach-Object name)
                defaultParameterSet = $metadata.DefaultParameterSetName
                supportsShouldProcess = $metadata.SupportsShouldProcess
                supportsPaging = $metadata.SupportsPaging
                supportsTransactions = $metadata.SupportsTransactions
                confirmImpact = $metadata.ConfirmImpact.ToString()
                positionalBinding = $metadata.PositionalBinding
                parameterSets = $sets
                inputTypes = $types.inputTypes
                outputTypes = @($command.OutputType | ForEach-Object Name)
                documentedOutputs = $types.returnValues
                examples = $examples
                relatedLinks = @(foreach ($link in $help.SelectNodes('*[local-name()="relatedLinks"]/*')) {
                    [ordered]@{ text = Get-XmlText $link '*[local-name()="linkText"]'; href = Get-XmlText $link '*[local-name()="uri"]' }
                })
            })
        }
    }
    $sourcesAfter = Get-SourceInventory
    if (($sourcesBefore | ConvertTo-Json -Depth 5 -Compress) -cne ($sourcesAfter | ConvertTo-Json -Depth 5 -Compress)) {
        throw 'API or help sources changed during documentation extraction.'
    }
    $artifact = [ordered]@{
        schema = 1
        port = 'powershell'
        source = [ordered]@{ repository = $repository; revision = $revision; files = $sourcesAfter }
        exporter = [ordered]@{
            name = 'PowerShell command metadata + Roslyn + PlatyPS + MAML'
            version = 1
            sha256 = (Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant()
            powershell = $PSVersionTable.PSVersion.ToString()
            dotnet = $sdkVersion
            roslyn = $compiler.GetName().Version.ToString()
            roslynSha256 = (Get-FileHash -LiteralPath $compiler.Location).Hash.ToLowerInvariant()
            helpSha256 = (Get-FileHash -LiteralPath "$PSScriptRoot/Export-DocsHelp.ps1").Hash.ToLowerInvariant()
            platyps = $authoredHelp.tool
        }
        modules = @($moduleRecords.ToArray())
        commands = @($commandRecords.ToArray())
    }
    $null = New-Item (Split-Path $OutputPath) -ItemType Directory -Force
    [IO.File]::WriteAllText($OutputPath, ($artifact | ConvertTo-Json -Depth 40) + "`n", [Text.UTF8Encoding]::new($false))
    Write-Host "Exported $($commandRecords.Count) commands to $OutputPath"
} finally {
    Pop-Location
}
