param([Parameter(Mandatory)] [string] $ModuleRoot)

$ErrorActionPreference = 'Stop'
$ModuleRoot = (Resolve-Path $ModuleRoot).Path
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-conflict-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item $temporary -ItemType Directory
try {
    $assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        [Reflection.AssemblyName]::new('LibTmux, Version=9.0.0.0'),
        [Reflection.Emit.AssemblyBuilderAccess]::Run)
    if ($assembly.GetName().Name -cne 'LibTmux') { throw 'Invalid conflict test assembly identity.' }
    $failure = $null
    try { Import-Module "$ModuleRoot/LibTmux/0.1.0/LibTmux.psd1" -ErrorAction Stop }
    catch { $failure = $_ }
    if (!$failure -or $failure.ToString() -notmatch 'Incompatible LibTmux build is already loaded') {
        throw "Import did not reject the conflicting core with an actionable error. Received: $failure"
    }
    if (Get-Command New-TmuxServer -ErrorAction Ignore) { throw 'Failed import leaked cmdlets.' }
    'PASS incompatible assembly rejection'
} finally { Remove-Item $temporary -Recurse -Force }
