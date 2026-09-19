param([Parameter(Mandatory)] [string] $ModuleRoot)

$ErrorActionPreference = 'Stop'
$module = Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-replacement-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item $temporary -ItemType Directory
try {
    . "$module/AssemblyGuard.ps1"
    $path = Join-Path $temporary 'LibTmux.dll'
    Copy-Item "$module/lib/LibTmux.dll" $path
    $assembly = [Reflection.Assembly]::LoadFrom($path)
    $original = $assembly.ManifestModule.ModuleVersionId
    $bytes = [IO.File]::ReadAllBytes($path)
    $hex = [Convert]::ToHexString($bytes)
    $needle = [Convert]::ToHexString($original.ToByteArray())
    $offset = $hex.IndexOf($needle, [StringComparison]::Ordinal)
    if ($offset -lt 0 -or $hex.LastIndexOf($needle, [StringComparison]::Ordinal) -ne $offset) {
        throw 'The assembly mutation does not identify a unique module ID.'
    }
    [Guid]::NewGuid().ToByteArray().CopyTo($bytes, [int] ($offset / 2))
    [IO.File]::WriteAllBytes("$path.new", $bytes)
    # Replace the inode as a build does, preserving the loaded image's mapping.
    [IO.File]::Move("$path.new", $path, $true)
    $failure = $null
    try { Import-TmuxAssembly -Path $path -ExactBuild }
    catch { $failure = $_ }
    if (!$failure -or $failure.ToString() -notmatch 'Incompatible LibTmux build is already loaded') {
        throw 'Import accepted a replaced file that differs from the loaded assembly.'
    }
    'PASS replaced assembly rejection'
} finally { Remove-Item $temporary -Recurse -Force }
