[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [Parameter(Mandatory)] [string] $SourceCommit,
    [switch] $Publish
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$timer = [Diagnostics.Stopwatch]::StartNew()
$names = @('LibTmux', 'LibTmux.Workspace')
$moduleVersion = '0.1.0'
$prerelease = 'alpha2'
$version = '0.1.0-alpha2'
$root = (Resolve-Path -LiteralPath $PackageRoot).Path
$owned = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-publish-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $owned
$journal = $null

function Read-ReleaseArchive([string] $Path, [string] $Name, [switch] $ValidateMetadata) {
    $payload = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $manifest = $null
    $nuspec = $null
    $totalBytes = 0L
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        if ($archive.Entries.Count -gt 1000) { throw 'Release archive exceeds its entry limit.' }
        foreach ($entry in $archive.Entries) {
            $entryName = $entry.FullName
            if ($entryName.StartsWith('/') -or $entryName.Contains('\') -or
                $entryName.Split('/') -contains '..' -or !$seen.Add($entryName)) {
                throw 'Release archive contains an unsafe or duplicate entry.'
            }
            if ($entryName.EndsWith('/')) { continue }
            $totalBytes += $entry.Length
            if ($totalBytes -gt 134217728) { throw 'Release archive exceeds its payload limit.' }
            if ($entryName -ceq "$Name.nuspec" -or $entryName -ceq "$Name.psd1") {
                if ($entry.Length -gt 1048576) { throw 'Release metadata exceeds its size limit.' }
                $reader = [IO.StreamReader]::new($entry.Open())
                try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
                if ($entryName -ceq "$Name.nuspec") { $nuspec = $content }
                else { $manifest = $content }
            }
            # Gallery may replace NuGet transport metadata, never module payloads.
            if ($entryName -match '\.nuspec$' -or $entryName -ceq '[Content_Types].xml' -or
                $entryName -ceq '.signature.p7s' -or $entryName.StartsWith('_rels/') -or
                $entryName.StartsWith('package/')) { continue }
            $stream = $entry.Open()
            $hash = [Security.Cryptography.SHA256]::Create()
            try { $payload.Add($entryName, [Convert]::ToHexString($hash.ComputeHash($stream)).ToLowerInvariant()) }
            finally { $hash.Dispose(); $stream.Dispose() }
        }
    } finally { $archive.Dispose() }
    if (!$manifest -or !$nuspec -or !$payload.ContainsKey('LICENSE')) {
        throw 'Release archive is missing module metadata or its license.'
    }
    if ($ValidateMetadata) {
        $manifestPath = Join-Path $owned "$Name.psd1"
        Set-Content -LiteralPath $manifestPath -Value $manifest -Encoding utf8
        $data = Import-PowerShellDataFile -LiteralPath $manifestPath
        [xml] $spec = $nuspec
        $metadata = $spec.SelectSingleNode('/*[local-name()="package"]/*[local-name()="metadata"]')
        $id = $metadata.SelectSingleNode('*[local-name()="id"]').InnerText
        $packageVersion = $metadata.SelectSingleNode('*[local-name()="version"]').InnerText
        if ($id -cne $Name -or $packageVersion -cne $version -or $data.ModuleVersion -cne $moduleVersion) {
            throw 'Release package name or version differs from the approved release.'
        }
        if (!$data.PrivateData.PSData.ContainsKey('Prerelease') -or
            $data.PrivateData.PSData.Prerelease -cne $prerelease) {
            throw 'Release package prerelease differs from the approved alpha release.'
        }
        if ($data.PrivateData.PSData.LicenseUri -cne
            'https://github.com/libtmux/libtmux-powershell/blob/master/LICENSE' -or
            [string]::IsNullOrWhiteSpace($data.PrivateData.PSData.ReleaseNotes)) {
            throw 'Release package metadata lacks the MIT link or release notes.'
        }
        $dependencies = @($metadata.SelectNodes('*[local-name()="dependencies"]//*[local-name()="dependency"]'))
        $required = @(if ($data.ContainsKey('RequiredModules')) { $data.RequiredModules })
        if ($Name -ceq 'LibTmux.Workspace') {
            if ($dependencies.Count -ne 1 -or $dependencies[0].id -cne 'LibTmux' -or
                $dependencies[0].version -cne '[0.1.0-alpha2]' -or $required.Count -ne 1 -or
                $required[0].ModuleName -cne 'LibTmux' -or $required[0].RequiredVersion -cne $moduleVersion) {
                throw 'Workspace does not require the exact approved core dependency.'
            }
        } elseif ($dependencies.Count -or $required.Count) {
            throw 'Core release declares unexpected module dependencies.'
        }
    }
    return $payload
}

function Assert-ReleasePayload($Expected, $Actual) {
    if ($Expected.Count -ne $Actual.Count) { throw 'Existing Gallery package has a different module payload.' }
    foreach ($entry in $Expected.GetEnumerator()) {
        if (!$Actual.ContainsKey($entry.Key) -or $Actual[$entry.Key] -cne $entry.Value) {
            throw 'Existing Gallery package has a different module payload.'
        }
    }
}

function Get-GalleryPayload([string] $Name) {
    $download = Join-Path $owned "$Name.gallery.nupkg"
    try {
        # The Gallery API can return the latest package for an absent version.
        $uri = "https://cdn.powershellgallery.com/packages/$($Name.ToLowerInvariant()).$version.nupkg"
        $null = Invoke-WebRequest -Uri $uri `
            -OutFile $download -TimeoutSec 20 -ErrorAction Stop
    } catch {
        $exception = $_.Exception
        if ($exception -is [Net.Http.HttpRequestException] -and
            $exception.StatusCode -eq [Net.HttpStatusCode]::NotFound) { return $null }
        if ($exception.PSObject.Properties['Response'] -and $exception.Response -and
            $exception.Response.StatusCode -eq [Net.HttpStatusCode]::NotFound) { return $null }
        throw 'Gallery download failed; publication stopped without treating the failure as absence.'
    }
    try { return Read-ReleaseArchive $download $Name -ValidateMetadata }
    catch { throw 'Gallery download returned an invalid release archive.' }
    finally { Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue }
}

function Save-PublicationEvidence {
    $journal.seconds = $timer.Elapsed.TotalSeconds
    $journal | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'publication-evidence.json') -Encoding utf8
}

try {
    if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$') { throw 'The source commit must be a full lowercase Git revision.' }
    $evidence = Get-Content (Join-Path $root 'package-evidence.json') -Raw | ConvertFrom-Json
    $provenance = Get-Content (Join-Path $root 'release-provenance.json') -Raw | ConvertFrom-Json
    if ($evidence.sourceCommit -cne $SourceCommit -or $provenance.sourceCommit -cne $SourceCommit) {
        throw 'Release source does not match the tested archive source.'
    }
    if ($provenance.schemaVersion -ne 1 -or $provenance.repository -cne 'libtmux/libtmux-powershell' -or
        $provenance.workflowPath -cne '.github/workflows/ci.yml' -or $provenance.artifactName -cne 'port-package' -or
        $provenance.runId -le 0 -or $provenance.runAttempt -le 0 -or $provenance.artifactId -le 0 -or
        $provenance.artifactDigest -cnotmatch '^sha256:[0-9a-f]{64}$' -or
        $provenance.runUrl -cne "https://github.com/libtmux/libtmux-powershell/actions/runs/$($provenance.runId)" -or
        @($provenance.jobs).Count -lt 2 -or @($provenance.jobs | Where-Object { $_.id -le 0 -or !$_.name }).Count) {
        throw 'Release provenance does not identify the approved repository, workflow and artifact.'
    }
    if (@($evidence.packages).Count -ne 2) { throw 'Release evidence must contain exactly the two approved packages.' }
    $candidates = @{}
    $records = @()
    foreach ($name in $names) {
        $file = "$name.$version.nupkg"
        $record = @($evidence.packages | Where-Object file -CEQ $file)
        if ($record.Count -ne 1 -or $record[0].sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'Release evidence contains an unexpected filename or hash.'
        }
        $path = Join-Path $root $file
        if ((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $record[0].sha256) {
            throw 'Release archive hash does not match the tested package.'
        }
        $candidates[$name] = @{ path = $path; payload = Read-ReleaseArchive $path $name -ValidateMetadata }
        $records += @{ name = $name; version = $version; file = $file; sha256 = $record[0].sha256
            status = 'pending'; dispatched = $false; published = $false; verified = $false; error = $null }
    }
    if (!$Publish) {
        'PASS release archive hashes, source, metadata, dependency and CI provenance; no publication requested'
        return
    }
    $apiKey = [Environment]::GetEnvironmentVariable('PSGALLERY_API_KEY')
    if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'PSGALLERY_API_KEY is required for publication.' }
    Import-Module Microsoft.PowerShell.PSResourceGet -RequiredVersion 1.1.1
    $repository = Get-PSResourceRepository -Name PSGallery
    if ($repository.Uri.AbsoluteUri.TrimEnd('/') -cne 'https://www.powershellgallery.com/api/v2') {
        throw 'PSGallery does not point to the official public feed.'
    }
    $journal = @{ sourceCommit = $SourceCommit; provenance = $provenance; packages = $records; seconds = 0.0 }
    Save-PublicationEvidence
    foreach ($record in $records) {
        try {
            $candidate = $candidates[$record.name]
            $existing = Get-GalleryPayload $record.name
            if ($null -ne $existing) {
                Assert-ReleasePayload $candidate.payload $existing
                $record.status = 'reused'
                $record.verified = $true
            } else {
                $record.dispatched = $true
                Save-PublicationEvidence
                try {
                    $null = Publish-PSResource -NupkgPath $candidate.path -Repository PSGallery -ApiKey $apiKey -ErrorAction Stop
                } catch { throw 'Gallery upload failed; dispatch may have occurred. Reconcile the public version before retrying.' }
                $record.published = $true
                $record.status = 'published'
                Save-PublicationEvidence
                # Immediate bounded checks handle visibility lag without hiding a partial release.
                for ($attempt = 0; $attempt -lt 3; $attempt++) {
                    $existing = Get-GalleryPayload $record.name
                    if ($null -ne $existing) { break }
                }
                if ($null -eq $existing) { throw 'Gallery upload is not yet downloadable; release remains partial.' }
                Assert-ReleasePayload $candidate.payload $existing
                $record.verified = $true
            }
            Save-PublicationEvidence
            "PASS $($record.name) $($version): $($record.status), public payload verified"
        } catch {
            $record.status = 'failed'
            $record.error = if ($_.Exception.Message -match '^(Gallery (download|upload)|Existing Gallery package)') {
                $_.Exception.Message
            } else { 'Publication verification failed; release remains partial.' }
            Save-PublicationEvidence
            throw $record.error
        }
    }
} finally {
    $apiKey = $null
    Remove-Item -LiteralPath $owned -Recurse -Force
}
