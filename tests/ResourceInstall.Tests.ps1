[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [ValidateSet('1.1.1', '1.2.0')] [string] $PSResourceGetVersion = '1.1.1',
    [switch] $Gallery,
    [switch] $SaveWorker,
    [string] $OwnedRoot,
    [string] $RepositoryName
)

# Outer integration: package resolution and live consumers need isolated processes.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Gallery) { $galleryTimer = [Diagnostics.Stopwatch]::StartNew() }
Import-Module Microsoft.PowerShell.PSResourceGet -RequiredVersion $PSResourceGetVersion

if ($Gallery) {
    if ($RepositoryName -and $RepositoryName -cne 'PSGallery') {
        throw 'Gallery verification requires the PSGallery repository.'
    }
    $galleryRepository = @(Get-PSResourceRepository -Name PSGallery)
    if ($galleryRepository.Count -ne 1 -or
        $galleryRepository[0].Uri.AbsoluteUri.TrimEnd('/') -cne
        'https://www.powershellgallery.com/api/v2') {
        throw 'PSGallery must use https://www.powershellgallery.com/api/v2.'
    }
    $RepositoryName = 'PSGallery'
}

if ($SaveWorker) {
    Save-PSResource -Name LibTmux.Workspace -Version '0.1.0-alpha1' -Prerelease `
        -Repository $RepositoryName -Path "$OwnedRoot/modules" `
        -TemporaryPath "$OwnedRoot/download" -TrustRepository -AcceptLicense -Quiet
    'PASS Save-PSResource requested only LibTmux.Workspace 0.1.0-alpha1'
    return
}

$PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
$owned = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-resource-' + [Guid]::NewGuid().ToString('N'))
$repository = if ($Gallery) { 'PSGallery' } else {
    'libtmux-powershell-' + [Guid]::NewGuid().ToString('N')
}
$before = @(Get-PSResourceRepository)
$registered = $false
$feedProcess = $null
$feedStarted = $false
$feedErrors = $null
$passed = $false
$timer = if ($Gallery) { $galleryTimer } else { [Diagnostics.Stopwatch]::StartNew() }

function Get-RepositoryRecord($Repository) {
    $Repository | Select-Object Name, Uri, Priority, Trusted, ApiVersion, CredentialInfo |
        ConvertTo-Json -Depth 6 -Compress
}

function Invoke-ResourceChild([string] $Script, [string[]] $Arguments, [string] $ModuleRoot) {
    $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $owned
    foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $Script) + $Arguments) {
        $start.ArgumentList.Add($argument)
    }
    if ($ModuleRoot) { $start.Environment['PSModulePath'] = $ModuleRoot }
    $null = $start.Environment.Remove('TMUX')
    $null = $start.Environment.Remove('TMUX_PANE')
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $started = $false
    try {
        $deadline = 20000
        if ($Gallery) {
            $remaining = 60000 - [int] $timer.Elapsed.TotalMilliseconds
            if ($remaining -le 0) { throw 'Gallery verification exceeded 60 seconds.' }
            $deadline = [Math]::Min($deadline, $remaining)
        }
        $started = $process.Start()
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit($deadline)) {
            throw 'The package consumer exceeded its deadline.'
        }
        $stdout = $output.GetAwaiter().GetResult()
        $stderr = $errors.GetAwaiter().GetResult()
        if ($stdout) { Write-Output $stdout.TrimEnd() }
        if ($process.ExitCode -ne 0) {
            throw "Local package consumer failed with exit $($process.ExitCode): $stderr"
        }
        if ($stderr) { throw "Local package consumer wrote unexpected stderr: $stderr" }
    } finally {
        if ($started -and !$process.HasExited) {
            $process.Kill($true)
            if (!$process.WaitForExit(1000)) { throw 'The package consumer did not exit after termination.' }
        }
        $process.Dispose()
    }
}

function Assert-ResourcePayload([string] $Name, [string] $Modules) {
    $modulePath = Join-Path $Modules "$Name/0.1.0"
    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $archive = [IO.Compression.ZipFile]::OpenRead("$PackageRoot/$Name.0.1.0-alpha1.nupkg")
    try {
        foreach ($entry in $archive.Entries) {
            $relative = $entry.FullName
            if ($relative.EndsWith('/')) { continue }
            if ($relative -cmatch
                '^([^/]+\.nuspec|_rels/\.rels|\[Content_Types\]\.xml|package/.*|\.signature\.p7s)$') {
                continue
            }
            if ($relative.StartsWith('/') -or $relative.Contains('\') -or
                $relative.Contains(':') -or
                @($relative.Split('/') | Where-Object { $_ -cin @('', '.', '..') }).Count) {
                throw "The tested $Name archive has an unsafe payload path."
            }
            if (!$expected.Add($relative)) {
                throw "The tested $Name archive repeats a payload path."
            }
            $savedPath = Join-Path $modulePath $relative
            if (!(Test-Path -LiteralPath $savedPath -PathType Leaf)) {
                throw "The saved $Name payload is missing $relative."
            }
            $stream = $entry.Open()
            $hasher = [Security.Cryptography.SHA256]::Create()
            try { $hash = [Convert]::ToHexString($hasher.ComputeHash($stream)) }
            finally { $hasher.Dispose(); $stream.Dispose() }
            if ($hash -cne (Get-FileHash -LiteralPath $savedPath -Algorithm SHA256).Hash) {
                throw "The saved $Name payload differs at $relative."
            }
        }
    } finally { $archive.Dispose() }
    if (!$expected.Count) { throw "The tested $Name archive has no module payload." }
    foreach ($file in Get-ChildItem -LiteralPath $modulePath -Recurse -File) {
        $relative = [IO.Path]::GetRelativePath($modulePath, $file.FullName).Replace('\', '/')
        # PSResourceGet adds installation metadata outside the package payload.
        if ($relative -ceq 'PSGetModuleInfo.xml') { continue }
        if (!$expected.Contains($relative)) {
            throw "The saved $Name payload has an unexpected file: $relative."
        }
    }
    "PASS saved payload identity: $Name ($($expected.Count) files)"
}

try {
    $null = New-Item "$owned/modules", "$owned/download" -ItemType Directory
    if (!$Gallery) {
        # File feeds read numeric manifest dependencies instead of alpha nuspec pins.
        $feedStart = [Diagnostics.ProcessStartInfo]::new('python3')
        $feedStart.UseShellExecute = $false
        $feedStart.RedirectStandardInput = $true
        $feedStart.RedirectStandardOutput = $true
        $feedStart.RedirectStandardError = $true
        $feedStart.WorkingDirectory = $owned
        foreach ($argument in @("$PSScriptRoot/support/resource_feed.py", '--package-root', $PackageRoot)) {
            $feedStart.ArgumentList.Add($argument)
        }
        $feedProcess = [Diagnostics.Process]::new()
        $feedProcess.StartInfo = $feedStart
        $feedStarted = $feedProcess.Start()
        if (!$feedStarted) { throw 'The owned package feed did not start.' }
        $feedErrors = $feedProcess.StandardError.ReadToEndAsync()
        $ready = $feedProcess.StandardOutput.ReadLineAsync()
        if (!$ready.Wait(1000)) { throw 'The owned package feed did not report readiness within one second.' }
        $uri = $ready.GetAwaiter().GetResult()
        if ($uri -cnotmatch '^http://127\.0\.0\.1:[0-9]+/api/v2$') {
            throw 'The owned package feed returned an unexpected endpoint.'
        }
        Register-PSResourceRepository -Name $repository -Uri $uri -ApiVersion V2 -Trusted
        $registered = $true
    }
    $saveArguments = @('-PackageRoot', $PackageRoot,
        '-PSResourceGetVersion', $PSResourceGetVersion, '-SaveWorker',
        '-OwnedRoot', $owned, '-RepositoryName', $repository)
    if ($Gallery) { $saveArguments += '-Gallery' }
    Invoke-ResourceChild $PSCommandPath $saveArguments

    $modules = "$owned/modules"
    foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
        $manifest = "$modules/$name/0.1.0/$name.psd1"
        if (!(Test-Path -LiteralPath $manifest)) {
            throw "Native package resolution did not save $name 0.1.0."
        }
        $data = Import-PowerShellDataFile -LiteralPath $manifest
        if ($data.ModuleVersion -cne '0.1.0' -or
            $data.PrivateData.PSData.Prerelease -cne 'alpha1') {
            throw "$name resolved an unexpected prerelease."
        }
        $versions = @(Get-ChildItem -LiteralPath "$modules/$name" -Directory)
        if ($versions.Count -ne 1 -or $versions[0].Name -cne '0.1.0') {
            throw "$name resolved additional versions."
        }
        Assert-ResourcePayload $name $modules
    }
    $unexpected = @(Get-ChildItem -LiteralPath $modules -Directory | Where-Object {
        $_.Name -cnotin @('LibTmux', 'LibTmux.Workspace')
    })
    if ($unexpected.Count) { throw 'Native package resolution saved an unexpected module.' }
    $forbidden = @(Get-ChildItem -LiteralPath $modules -Recurse -File | Where-Object {
        $_.Name -match '^(System\.Management\.Automation|Microsoft\.PowerShell|pwsh|testhost)' -or
        $_.Extension -in @('.cs', '.csproj')
    })
    if ($forbidden.Count) { throw 'Saved package contains a PowerShell runtime or development file.' }
    $duplicateCore = @(Get-ChildItem -LiteralPath "$modules/LibTmux.Workspace" -Recurse -File |
        Where-Object Name -CEQ 'LibTmux.dll')
    if ($duplicateCore.Count) { throw 'Workspace bundles a duplicate core assembly.' }
    'PASS native dependency resolution: LibTmux.Workspace 0.1.0-alpha1 -> LibTmux 0.1.0-alpha1'
    if ($Gallery) {
        Invoke-ResourceChild "$PSScriptRoot/Package.Tests.ps1" @('-ModuleRoot', $modules,
            '-Order', 'CoreFirst') $modules
    }
    Invoke-ResourceChild "$PSScriptRoot/Package.Tests.ps1" @('-ModuleRoot', $modules,
        '-Order', 'WorkspaceFirst') $modules
    Invoke-ResourceChild "$PSScriptRoot/ResourceWorkspace.Tests.ps1" @('-ModuleRoot', $modules) $modules
    if ($Gallery) {
        foreach ($script in @('ReadmeWorkflow', 'Capture', 'Input')) {
            Invoke-ResourceChild "$PSScriptRoot/$script.Tests.ps1" @('-ModuleRoot', $modules) $modules
        }
    }
    $passed = $true
} finally {
    try {
        if ($registered) { Unregister-PSResourceRepository -Name $repository }
        $after = @(Get-PSResourceRepository)
        if (!$Gallery -and @($after | Where-Object Name -CEQ $repository).Count) {
            throw 'Owned package repository registration remains.'
        }
        foreach ($entry in $before) {
            $remaining = @($after | Where-Object Name -CEQ $entry.Name)
            if ($remaining.Count -ne 1 -or
                (Get-RepositoryRecord $remaining[0]) -cne (Get-RepositoryRecord $entry)) {
                throw 'A pre-existing package repository changed during consumer verification.'
            }
        }
    } finally {
        try {
            if ($feedProcess) {
                try {
                    if ($feedStarted) {
                        $feedProcess.StandardInput.Close()
                        if (!$feedProcess.WaitForExit(1000)) {
                            $feedProcess.Kill($true)
                            if (!$feedProcess.WaitForExit(1000)) { throw 'The owned package feed did not exit after termination.' }
                            throw 'The owned package feed did not stop when stdin closed.'
                        }
                        if ($feedProcess.ExitCode -ne 0 -or $feedErrors.GetAwaiter().GetResult()) {
                            throw 'The owned package feed failed or wrote unexpected stderr.'
                        }
                    }
                } finally { $feedProcess.Dispose() }
            }
        } finally {
            if (Test-Path -LiteralPath $owned) { Remove-Item -LiteralPath $owned -Recurse -Force }
            if (Test-Path -LiteralPath $owned) { throw 'Owned package directories remain after cleanup.' }
        }
    }
    if ($Gallery) {
        'PASS cleanup: Gallery repositories unchanged, temporary directories removed'
    } else {
        'PASS cleanup: owned repository unregistered, prior repositories preserved, temporary directories removed'
    }
}

if ($Gallery -and $timer.Elapsed.TotalSeconds -ge 60) {
    throw 'Gallery verification exceeded 60 seconds.'
}
if ($passed) { "PASS native package consumer ($($timer.Elapsed.TotalSeconds.ToString('F3')) s)" }
