param([switch] $Worker)

# Pure release guards; only HTTP download and upload boundaries are simulated.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$timer = [Diagnostics.Stopwatch]::StartNew()
$publisher = Join-Path (Split-Path $PSScriptRoot) 'eng/Publish.ps1'

if (!$Worker) {
    $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
    $start.UseShellExecute = $false
    $null = $start.Environment.Remove('PSGALLERY_API_KEY')
    foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $PSCommandPath, '-Worker')) {
        $start.ArgumentList.Add($argument)
    }
    $child = [Diagnostics.Process]::Start($start)
    try {
        if (!$child.WaitForExit(10000)) { $child.Kill($true); throw 'Publisher tests exceeded their deadline.' }
        if ($child.ExitCode) { throw 'Publisher guard tests failed.' }
    } finally { $child.Dispose() }
    "PASS publisher guards ($($timer.Elapsed.TotalSeconds.ToString('F3')) s)"
    return
}

$owned = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-publish-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $owned
$source = '1111111111111111111111111111111111111111'
$public = @{}
$uploads = [Collections.Generic.List[string]]::new()
$reads = [Collections.Generic.List[string]]::new()
$failureCode = 0
$failWorkspace = $false

function New-TestPackage([string] $Name, [string] $Path, [string] $Version = '0.1.0', [string] $Payload = 'tested', [string] $Prerelease = 'alpha1') {
    $packageVersion = if ($Prerelease) { "$Version-$Prerelease" } else { $Version }
    $required = if ($Name -ceq 'LibTmux.Workspace') {
        "RequiredModules = @(@{ ModuleName = 'LibTmux'; RequiredVersion = '0.1.0' })"
    } else { 'RequiredModules = @()' }
    $manifest = "@{ ModuleVersion = '$Version'; $required; PrivateData = @{ PSData = @{ " +
        "LicenseUri = 'https://github.com/libtmux/libtmux-powershell/blob/master/LICENSE'; " +
        "Prerelease = '$Prerelease'; ReleaseNotes = 'First alpha release; LibTmux .NET alpha.20.' } } }"
    $dependency = if ($Name -ceq 'LibTmux.Workspace') { "<dependency id=`"LibTmux`" version=`"[$packageVersion]`" />" } else { '' }
    $items = @{
        "$Name.psd1" = $manifest
        "$Name.dll" = $Payload
        'LICENSE' = 'MIT'
        "$Name.nuspec" = "<package><metadata><id>$Name</id><version>$packageVersion</version><dependencies>$dependency</dependencies></metadata></package>"
    }
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($item in $items.GetEnumerator()) {
            $writer = [IO.StreamWriter]::new($zip.CreateEntry($item.Key).Open())
            try { $writer.Write($item.Value) } finally { $writer.Dispose() }
        }
    } finally { $zip.Dispose() }
}

function Set-TestEvidence {
    @{ sourceCommit = $source; packages = @(foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
        @{ file = "$name.0.1.0-alpha1.nupkg"; sha256 = (Get-FileHash "$owned/$name.0.1.0-alpha1.nupkg").Hash.ToLowerInvariant() }
    }) } | ConvertTo-Json -Depth 5 | Set-Content "$owned/package-evidence.json"
    @{ schemaVersion = 1; repository = 'libtmux/libtmux-powershell'; sourceCommit = $source
        workflowPath = '.github/workflows/ci.yml'; runId = 123; runAttempt = 1; artifactId = 456
        artifactName = 'port-package'; artifactDigest = ('sha256:' + ('a' * 64))
        runUrl = 'https://github.com/libtmux/libtmux-powershell/actions/runs/123'
        jobs = @(@{ id = 11; name = 'build and pack PowerShell modules' }, @{ id = 12; name = 'required Linux checks' })
    } | ConvertTo-Json -Depth 5 | Set-Content "$owned/release-provenance.json"
}

function Assert-PublishFailure([string] $Reason, [switch] $Upload, [string] $Revision = $source) {
    $failure = $null
    try { & $publisher -PackageRoot $owned -SourceCommit $Revision -Publish:$Upload | Out-Null }
    catch { $failure = $_ }
    if (!$failure -or $failure.Exception.Message -notmatch $Reason) {
        throw "Publisher did not reject the invalid candidate for $Reason."
    }
}

function Invoke-WebRequest {
    param([string] $Uri, [string] $OutFile, [int] $TimeoutSec, [string] $ErrorAction)
    $name = if ($Uri -cmatch '/package/(LibTmux(?:\.Workspace)?)/0\.1\.0-alpha1$') { $Matches[1] } else { throw 'Unexpected Gallery endpoint.' }
    if ($TimeoutSec -le 0 -or $TimeoutSec -gt 20) { throw 'Unbounded Gallery request.' }
    $reads.Add($name)
    $code = if ($failureCode) { $failureCode } elseif (!$public.ContainsKey($name)) { 404 } else { 0 }
    if ($code) { throw [Net.Http.HttpRequestException]::new('Transport fixture', $null, [Net.HttpStatusCode] $code) }
    Copy-Item -LiteralPath $public[$name] -Destination $OutFile
}

function Publish-PSResource {
    param([string] $NupkgPath, [string] $Repository, [string] $ApiKey, [string] $ErrorAction)
    if ($Repository -cne 'PSGallery' -or $ApiKey -cne 'fixture-credential') { throw 'Wrong publishing boundary.' }
    $name = [IO.Path]::GetFileName($NupkgPath).Replace('.0.1.0-alpha1.nupkg', '')
    $uploads.Add($name)
    if ($name -ceq 'LibTmux.Workspace' -and $failWorkspace) { throw 'Sensitive upload diagnostics must not escape.' }
    $public[$name] = $NupkgPath
}

try {
    foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
        New-TestPackage $name "$owned/$name.0.1.0-alpha1.nupkg" -Prerelease ''
    }
    Set-TestEvidence
    if (!(Test-Path -LiteralPath $publisher)) { throw 'Publisher does not implement offline candidate validation.' }
    Assert-PublishFailure 'version|prerelease'
    if ($reads.Count -or $uploads.Count) { throw 'Stable candidate reached publication.' }
    foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
        Remove-Item -LiteralPath "$owned/$name.0.1.0-alpha1.nupkg"
        New-TestPackage $name "$owned/$name.0.1.0-alpha1.nupkg"
    }
    Set-TestEvidence
    & $publisher -PackageRoot $owned -SourceCommit $source | Out-Null
    if ($reads.Count -or $uploads.Count) { throw 'Dry run performed network I/O.' }
    Assert-PublishFailure 'source' -Revision ('2' * 40)
    Add-Content "$owned/LibTmux.0.1.0-alpha1.nupkg" 'modified'
    Assert-PublishFailure 'hash'
    Remove-Item "$owned/LibTmux.0.1.0-alpha1.nupkg"
    New-TestPackage 'LibTmux' "$owned/LibTmux.0.1.0-alpha1.nupkg" -Version '0.2.0'
    Set-TestEvidence
    Assert-PublishFailure 'version'
    Remove-Item "$owned/LibTmux.0.1.0-alpha1.nupkg"
    New-TestPackage 'LibTmux' "$owned/LibTmux.0.1.0-alpha1.nupkg"
    Set-TestEvidence
    $provenance = Get-Content "$owned/release-provenance.json" -Raw | ConvertFrom-Json
    $provenance.repository = 'other/repository'
    $provenance | ConvertTo-Json -Depth 5 | Set-Content "$owned/release-provenance.json"
    Assert-PublishFailure 'provenance'
    Set-TestEvidence
    Assert-PublishFailure 'PSGALLERY_API_KEY' -Upload
    if ($reads.Count -or $uploads.Count) { throw 'Missing credentials reached Gallery.' }

    $env:PSGALLERY_API_KEY = 'fixture-credential'
    $failureCode = 500
    Assert-PublishFailure 'Gallery' -Upload
    if ($uploads.Count) { throw 'Gallery server failure was treated as a missing package.' }
    $failureCode = 0
    $failWorkspace = $true
    Assert-PublishFailure 'upload' -Upload
    $journal = Get-Content "$owned/publication-evidence.json" -Raw | ConvertFrom-Json
    if (($uploads -join ',') -cne 'LibTmux,LibTmux.Workspace' -or
        $journal.packages[0].status -cne 'published' -or !$journal.packages[0].verified -or
        $journal.packages[1].status -cne 'failed' -or
        (Get-Content "$owned/publication-evidence.json" -Raw) -match 'Sensitive|fixture-credential') {
        throw 'Partial publication did not retain safe per-package outcomes.'
    }
    $failWorkspace = $false
    $uploads.Clear()
    & $publisher -PackageRoot $owned -SourceCommit $source -Publish | Out-Null
    $journal = Get-Content "$owned/publication-evidence.json" -Raw | ConvertFrom-Json
    if (($uploads -join ',') -cne 'LibTmux.Workspace' -or
        $journal.packages[0].status -cne 'reused' -or !$journal.packages[1].verified) {
        throw 'Retry republished core or failed to verify Workspace.'
    }
    $changed = "$owned/changed.nupkg"
    New-TestPackage 'LibTmux' $changed -Payload 'different public bytes'
    $public['LibTmux'] = $changed
    $uploads.Clear()
    Assert-PublishFailure 'payload' -Upload
    if ($uploads.Count) { throw 'Different public bytes permitted a subsequent upload.' }
    $public['LibTmux'] = "$owned/LibTmux.0.1.0-alpha1.nupkg"
    $wrongDependency = "$owned/wrong-dependency.nupkg"
    Copy-Item -LiteralPath "$owned/LibTmux.Workspace.0.1.0-alpha1.nupkg" -Destination $wrongDependency
    $archive = [IO.Compression.ZipFile]::Open($wrongDependency, [IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry = $archive.GetEntry('LibTmux.Workspace.nuspec')
        $reader = [IO.StreamReader]::new($entry.Open())
        try { $nuspec = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $entry.Delete()
        $writer = [IO.StreamWriter]::new($archive.CreateEntry('LibTmux.Workspace.nuspec').Open())
        try { $writer.Write($nuspec.Replace('version="[0.1.0-alpha1]"', 'version="[0.2.0-alpha1]"')) }
        finally { $writer.Dispose() }
    } finally { $archive.Dispose() }
    $public['LibTmux.Workspace'] = $wrongDependency
    Assert-PublishFailure 'invalid release archive' -Upload
    $journal = Get-Content "$owned/publication-evidence.json" -Raw | ConvertFrom-Json
    if ($uploads.Count -or $journal.packages[1].verified) {
        throw 'Retry reused a Gallery package with an altered core dependency.'
    }
    'PASS offline archives, provenance, missing key, HTTP failure, upload order and partial recovery'
} finally {
    $null = [Environment]::SetEnvironmentVariable('PSGALLERY_API_KEY', $null)
    Remove-Item -LiteralPath $owned -Recurse -Force
}
