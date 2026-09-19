[CmdletBinding()]
param([switch] $Check)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot
$tool = "$root/build/tool-modules/Microsoft.PowerShell.PlatyPS/1.0.3/Microsoft.PowerShell.PlatyPS.psd1"
if (!(Test-Path $tool)) { throw 'Run eng/Setup.ps1 before generating native help.' }
# The authoring tool has its own YAML dependency; keep product imports out of this process.
Import-Module $tool
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-help-' + [Guid]::NewGuid().ToString('N'))
try {
    foreach ($module in @('LibTmux', 'LibTmux.Workspace')) {
        $files = @(Get-ChildItem "$root/docs/reference/$module" -Filter '*.md' | Sort-Object Name)
        if (!$files.Count) { throw "No command help exists for $module." }
        foreach ($file in $files) {
            if (!(Test-MarkdownCommandHelp -Path ([WildcardPattern]::Escape($file.FullName)))) {
                throw "Invalid native help: $($file.Name)."
            }
            if ((Get-Content $file.FullName -Raw) -match '\{\{.*\}\}') {
                throw "Unfinished native help: $($file.Name)."
            }
        }
        $models = @(Import-MarkdownCommandHelp -LiteralPath $files.FullName)
        $output = Join-Path $temporary $module
        $null = $models | Export-MamlCommandHelp -OutputFolder $output -Encoding ([Text.UTF8Encoding]::new($false))
        $name = "$module.PowerShell.dll-Help.xml"
        $generated = @(Get-ChildItem $output -Filter $name -Recurse)
        if ($generated.Count -ne 1) { throw "Expected one generated $name." }
        $destination = "$root/module/$module/en-US/$name"
        if ($Check) {
            if (!(Test-Path $destination) -or
                (Get-FileHash $destination).Hash -cne (Get-FileHash $generated[0].FullName).Hash) {
                throw "$name is stale. Run eng/Help.ps1 and review the generated change."
            }
        } else {
            $null = New-Item (Split-Path $destination) -ItemType Directory -Force
            Copy-Item $generated[0].FullName $destination
        }
    }
} finally {
    if (Test-Path $temporary) { Remove-Item $temporary -Recurse -Force }
}
'PASS native help generation'
