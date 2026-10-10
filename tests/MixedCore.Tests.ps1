param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [string] $AlternativeCorePackage
)

$ErrorActionPreference = 'Stop'
$workspace = Join-Path $ModuleRoot 'LibTmux.Workspace/0.1.0'
$metadataPath = Join-Path $workspace 'dependencies.json'
$original = [IO.File]::ReadAllText($metadataPath)
$corePath = Join-Path $ModuleRoot 'LibTmux/0.1.0/lib/LibTmux.dll'
$coreBytes = [IO.File]::ReadAllBytes($corePath)
try {
    $metadata = $original | ConvertFrom-Json
    if (!$metadata.requiredCore.sha256) { throw 'Workspace does not declare its required core build.' }
    if ($AlternativeCorePackage) {
        $archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $AlternativeCorePackage).Path)
        try {
            [IO.Compression.ZipFileExtensions]::ExtractToFile(
                $archive.GetEntry('lib/net8.0/LibTmux.dll'), $corePath, $true)
        } finally { $archive.Dispose() }
        if ((Get-FileHash $corePath).Hash.ToLowerInvariant() -ceq $metadata.requiredCore.sha256) {
            throw 'The alternate package must contain a different core build.'
        }
    } else {
        $metadata.requiredCore.sha256 = '0' * 64
        $metadata | ConvertTo-Json -Depth 8 | Set-Content $metadataPath
    }
    $failure = $null
    try { Import-Module "$workspace/LibTmux.Workspace.psd1" -ErrorAction Stop }
    catch { $failure = $_ }
    if (!$failure -or $failure.ToString() -notmatch 'Incompatible LibTmux dependency') {
        throw 'Workspace accepted a different required core build.'
    }
    if (Get-Command Import-TmuxWorkspace -ErrorAction Ignore) { throw 'Rejected workspace leaked a cmdlet.' }
    'PASS workspace required core build rejection'
} finally {
    [IO.File]::WriteAllText($metadataPath, $original)
    [IO.File]::WriteAllBytes($corePath, $coreBytes)
}
