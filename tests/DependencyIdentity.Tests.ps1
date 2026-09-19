param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [ValidateSet('PublicKeyToken', 'Culture', 'CompatibleVersion')]
    [string] $Case = 'PublicKeyToken'
)

# Each identity needs a fresh process because assemblies cannot be unloaded.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$module = Join-Path (Resolve-Path -LiteralPath $ModuleRoot).Path 'LibTmux/0.1.0'
$path = Join-Path $module 'lib/Microsoft.Extensions.Logging.Abstractions.dll'
$expected = [Reflection.AssemblyName]::GetAssemblyName($path)
$preloadedName = [Reflection.AssemblyName]::new($expected.Name)
$preloadedName.CultureName = $expected.CultureName
$preloadedName.Version = [Version]::new($expected.Version.Major + 1, 0, 0, 0)
if ($Case -ne 'PublicKeyToken') { $preloadedName.SetPublicKey($expected.GetPublicKey()) }
if ($Case -eq 'Culture') {
    $preloadedName.CultureName = 'fr'
}
$assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
    $preloadedName, [Reflection.Emit.AssemblyBuilderAccess]::Run)
if ($assembly.GetName().Version -le $expected.Version) { throw 'The dependency probe must preload a higher version.' }
$tokenMatches = ($assembly.GetName().GetPublicKeyToken() -join ',') -ceq ($expected.GetPublicKeyToken() -join ',')
$cultureMatches = $assembly.GetName().CultureName -ieq $expected.CultureName
if ($tokenMatches -ne ($Case -ne 'PublicKeyToken') -or $cultureMatches -ne ($Case -ne 'Culture')) {
    throw "The dependency probe did not construct the requested $Case identity: $($assembly.FullName)"
}

if ($Case -eq 'CompatibleVersion') {
    # This checks the guard's identity policy, not the synthetic assembly's API.
    . "$module/AssemblyGuard.ps1"
    Import-TmuxAssembly -Path $path
    $loaded = @([AppDomain]::CurrentDomain.GetAssemblies().Where({ $_.GetName().Name -ceq $expected.Name }))
    if ($loaded.Count -ne 1 -or $loaded[0].FullName -cne $assembly.FullName) {
        throw 'The guard did not reuse a higher version with matching identity.'
    }
} else {
    $failure = $null
    try { Import-Module "$module/LibTmux.psd1" -ErrorAction Stop }
    catch { $failure = $_ }
    if (!$failure -or $failure.ToString() -notmatch "Incompatible $([regex]::Escape($expected.Name))" -or
        $failure.ToString() -notmatch 'fresh PowerShell process') {
        throw "Module import accepted an incompatible $Case or lost fresh-process guidance. Received: $failure"
    }
    if (Get-Command New-TmuxServer -ErrorAction Ignore) { throw 'Rejected dependency import leaked cmdlets.' }
}

"PASS dependency identity: $Case"
