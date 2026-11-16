# Proves the PowerShell installer refuses an archive with the wrong digest before it
# extracts anything, refuses a version the table lacks or the install does not report,
# and installs an archive that matches its entry.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../InstallPowerShell.psm1') -Force

function Assert-That([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw $Message }
}

function Assert-Refused([string] $Pattern, [scriptblock] $Action) {
    try { & $Action } catch [InvalidOperationException] {
        Assert-That ($_.Exception.Message -cmatch $Pattern) "Refused for the wrong reason: $($_.Exception.Message)"
        return
    }
    throw "Not refused: $Pattern"
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) "libtmux-install-test-$([Guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $scratch
try {
    $payload = Join-Path $scratch 'payload'
    $null = New-Item -ItemType Directory -Path $payload
    Set-Content -LiteralPath (Join-Path $payload 'pwsh') -Value 'not a real pwsh'
    $archive = Join-Path $scratch 'powershell.tar.gz'
    & tar -czf $archive -C $payload pwsh
    if ($LASTEXITCODE) { throw 'The test could not make an archive.' }
    $digest = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = Join-Path $scratch 'matrix.json'
    @{ powershell = @(@{ version = '9.9.9'; sha256 = $digest }, @{ version = '9.9.8'; sha256 = '0' * 64 }) } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifest

    $destination = Join-Path $scratch 'installed'
    $pwsh = Install-PowerShellArchive -Version '9.9.9' -Manifest $manifest -Destination $destination -Source $archive
    Assert-That ($pwsh -ceq (Join-Path $destination 'pwsh')) 'The installer did not return the path of pwsh.'
    Assert-That (([IO.File]::GetUnixFileMode($pwsh) -band [IO.UnixFileMode]::UserExecute) -ne 0) 'pwsh is not executable.'

    $refused = Join-Path $scratch 'refused'
    Assert-Refused 'SHA-256' {
        Install-PowerShellArchive -Version '9.9.8' -Manifest $manifest -Destination $refused -Source $archive
    }
    Assert-That (!(Test-Path -LiteralPath $refused)) 'An archive with the wrong digest was extracted.'
    Assert-Refused 'not in' {
        Install-PowerShellArchive -Version '1.2.3' -Manifest $manifest -Destination $refused -Source $archive
    }

    $running = [Environment]::ProcessPath
    $version = $PSVersionTable.PSVersion.ToString()
    Assert-PowerShellVersion $running $version
    Assert-Refused 'not 0.0.1' { Assert-PowerShellVersion $running '0.0.1' }
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
}

'PASS PowerShell installer: digest checked before extraction, version checked after, each refusal named'
