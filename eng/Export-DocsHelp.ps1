[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SourceRoot,
    [Parameter(Mandatory)] [string] $OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$toolRoot = Join-Path (Split-Path $PSScriptRoot) 'build/tool-modules/Microsoft.PowerShell.PlatyPS/1.0.3'
$manifest = Join-Path $toolRoot 'Microsoft.PowerShell.PlatyPS.psd1'
if (!(Test-Path -LiteralPath $manifest)) { throw 'Run eng/Setup.ps1 before exporting documentation help.' }
# PlatyPS and the product use different YAML assemblies; keep their load contexts separate.
Import-Module $manifest
$commands = [ordered]@{}
foreach ($module in @('LibTmux', 'LibTmux.Workspace')) {
    foreach ($file in (Get-ChildItem "$SourceRoot/docs/reference/$module" -Filter '*.md' | Sort-Object Name)) {
        $help = Import-MarkdownCommandHelp -Path $file.FullName
        $examples = @(foreach ($example in $help.Examples) {
            $text = $example.Remarks.Replace("`r`n", "`n")
            $blocks = [regex]::Matches($text, '(?ms)^```powershell[ \t]*\n(?<code>.*?)^```[ \t]*$')
            if ($blocks.Count -ne 1) { throw "$($file.Name) must have one executable PowerShell block per example." }
            $block = $blocks[0]
            $code = $block.Groups['code'].Value.TrimEnd()
            $errors = $null
            $null = [Management.Automation.Language.Parser]::ParseInput($code, [ref] $null, [ref] $errors)
            if (!$code -or $errors.Count) { throw "$($file.Name) has invalid example code." }
            [ordered]@{
                title = $example.Title
                introduction = $text.Substring(0, $block.Index).Trim()
                code = $code
                remarks = $text.Substring($block.Index + $block.Length).Trim()
            }
        })
        $parameters = [ordered]@{}
        foreach ($parameter in $help.Parameters) {
            $parameters[$parameter.Name] = [ordered]@{
                description = $parameter.Description
                default = $parameter.DefaultValue
            }
        }
        $commands["$module\$($file.BaseName)"] = [ordered]@{
            synopsis = $help.Synopsis
            description = $help.Description
            notes = $help.Notes
            parameters = $parameters
            examples = $examples
        }
    }
}
$artifact = [ordered]@{
    commands = $commands
    tool = [ordered]@{
        name = 'Microsoft.PowerShell.PlatyPS'
        version = (Get-Module Microsoft.PowerShell.PlatyPS).Version.ToString()
        files = @(Get-ChildItem $toolRoot -File -Recurse | Sort-Object FullName | ForEach-Object {
            [ordered]@{
                path = [IO.Path]::GetRelativePath($toolRoot, $_.FullName).Replace('\', '/')
                sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()
            }
        })
    }
}
[IO.File]::WriteAllText($OutputPath, ($artifact | ConvertTo-Json -Depth 15), [Text.UTF8Encoding]::new($false))
