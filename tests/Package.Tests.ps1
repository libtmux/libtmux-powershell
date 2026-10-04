param(
    [string] $ModuleRoot = "$PSScriptRoot/../build/Modules",
    [ValidateSet('CoreFirst', 'WorkspaceFirst')]
    [string] $Order = 'CoreFirst'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/support/HangGuard.ps1"
$core = Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1'
$workspace = Join-Path $ModuleRoot 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1'
if (!(Test-Path $core)) { throw 'Core module artifact is missing.' }
if (!(Test-Path $workspace)) { throw 'Workspace module artifact is missing.' }
foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
    $license = Join-Path $ModuleRoot "$name/0.1.0/LICENSE"
    if (!(Test-Path -LiteralPath $license -PathType Leaf) -or
        (Get-FileHash -LiteralPath $license).Hash -cne (Get-FileHash -LiteralPath "$PSScriptRoot/../LICENSE").Hash) {
        throw "The $name package does not contain this repository's MIT license."
    }
}
$before = [Environment]::GetEnvironmentVariables()
$pathBefore = $env:PATH
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-import-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item $temporary -ItemType Directory
$socketPath = Join-Path $temporary 'socket'
$tmux = Get-Command tmux -CommandType Application -ErrorAction Ignore | Select-Object -First 1
try {
    # Import and local handle creation must work without any tmux executable.
    $env:PATH = ''
    $isolatedPath = [Environment]::GetEnvironmentVariable('PATH')
    if ($Order -eq 'WorkspaceFirst') {
        Import-Module $workspace
        Import-Module $core
    } else {
        Import-Module $core
        Import-Module $workspace
    }
    $server = LibTmux\New-TmuxServer -SocketPath $socketPath
    if ($server.GetType().FullName -cne 'LibTmux.Server') { throw 'Expected a native Server.' }
    if ($server.IsMaterialized) { throw 'New-TmuxServer performed discovery.' }
    if ($server.ConnectionOptions.SocketPath -cne $socketPath) {
        throw 'The explicit endpoint was not preserved.'
    }
    $parsed = LibTmux.Workspace\Import-TmuxWorkspace -Yaml 'session_name: local'
    if ($parsed.GetType().FullName -cne 'LibTmux.Workspace.WorkspaceFile') {
        throw 'Expected a native workspace declaration.'
    }
    if ([LibTmux.Workspace.WorkspaceBuilder].Assembly.GetReferencedAssemblies().Where({
        $_.Name -eq 'LibTmux'
    }).FullName -cne $server.GetType().Assembly.FullName) {
        throw 'Workspace and core have different assembly identities.'
    }
    $assemblies = @([AppDomain]::CurrentDomain.GetAssemblies().Where({ $_.GetName().Name -eq 'LibTmux' }))
    if ($assemblies.Count -ne 1) { throw 'More than one LibTmux assembly is loaded.' }
    Remove-Module LibTmux.Workspace, LibTmux
    Import-Module $workspace
    if ((LibTmux\New-TmuxServer).GetType().Assembly -ne $assemblies[0]) {
        throw 'Reimport changed core type identity.'
    }
    $after = [Environment]::GetEnvironmentVariables()
    if ([Environment]::GetEnvironmentVariable('PATH') -cne $isolatedPath) { throw 'Import changed PATH.' }
    foreach ($key in $before.Keys) {
        if ($key -eq 'PATH') { continue }
        if ($before[$key] -cne $after[$key]) { throw "Import changed environment variable $key." }
    }
    foreach ($key in $after.Keys) {
        if (!$before.Contains($key)) { throw "Import added environment variable $key." }
    }
    $forbidden = @(Get-ChildItem $ModuleRoot -Recurse -File | Where-Object {
        $_.Name -match '^(System\.Management\.Automation|Microsoft\.PowerShell|pwsh|testhost)' -or
        $_.Extension -in @('.cs', '.csproj')
    })
    if ($forbidden.Count) { throw 'Module package includes runtime or development files.' }
    if (Test-Path $socketPath) { throw 'Local construction started tmux.' }
    "PASS package imports: $Order"
} finally {
    $env:PATH = $pathBefore
    try {
        if (Test-Path $socketPath) {
            if (!$tmux) { throw 'Unexpected socket created; no tmux executable is available for owned cleanup.' }
            $start = [Diagnostics.ProcessStartInfo]::new($tmux.Source)
            foreach ($argument in @('-S', $socketPath, '-f', '/dev/null', 'kill-server')) { $start.ArgumentList.Add($argument) }
            $null = $start.Environment.Remove('TMUX')
            $null = $start.Environment.Remove('TMUX_PANE')
            $client = [Diagnostics.Process]::Start($start)
            try {
                if (!$client.WaitForExit($HangGuardMilliseconds)) { $client.Kill($true); throw 'Unexpected daemon cleanup timed out.' }
            } finally { $client.Dispose() }
        }
    } finally { Remove-Item $temporary -Recurse -Force }
}
