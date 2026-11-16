# Proves the cleanup check accepts a closed pull request, reads an open one as not
# eligible, refuses each malformed response and number, and names the preview prefix.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../DocsPreviewCleanup.psm1') -Force

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

Assert-That ((Get-CleanupEligibility '{"number": 12, "state": "closed", "title": "x"}' '12') -eq $true) 'A closed pull request was not eligible.'
Assert-That ((Get-CleanupEligibility '{"number": 12, "state": "open"}' '12') -eq $false) 'An open pull request was eligible.'

foreach ($response in
    '[]', 'null', '"closed"', '{', '',
    '{"number": 13, "state": "closed"}', '{"number": "12", "state": "closed"}', '{"state": "closed"}',
    '{"number": 12, "state": "merged"}', '{"number": 12, "state": "Closed"}', '{"number": 12}') {
    Assert-Refused 'invalid current pull request response' { $null = Get-CleanupEligibility $response '12' }
}
foreach ($pr in '', '0', '012', 'abc', '12 ', '-3', '1.5') {
    Assert-Refused 'must be numeric' { $null = Get-CleanupEligibility '{"number": 12, "state": "closed"}' $pr }
    Assert-Refused 'must be numeric' { $null = Get-PreviewPrefix 'bucket' $pr }
}
Assert-That ((Get-PreviewPrefix 'docs-bucket' '34') -ceq 's3://docs-bucket/en/powershell/pr-34/') 'The preview prefix is wrong.'

# The command line refuses a number before it calls gh or aws.
$script = Join-Path $PSScriptRoot '../DocsPreviewCleanup.ps1'
$output = Join-Path ([IO.Path]::GetTempPath()) "libtmux-cleanup-test-$([Guid]::NewGuid().ToString('N'))"
try {
    & (Get-Process -Id $PID).Path -NoLogo -NoProfile -File $script eligibility -Repository a/b -Pr abc -GithubOutput $output 2>$null
    Assert-That ($LASTEXITCODE -eq 1) 'The command line accepted a non-numeric pull request.'
    Assert-That ((Get-Content -LiteralPath $output -Raw) -ceq "should_cleanup=false`n") 'A refused check did not leave the cleanup off.'
    & (Get-Process -Id $PID).Path -NoLogo -NoProfile -File $script delete -Bucket b -Pr abc 2>$null
    Assert-That ($LASTEXITCODE -eq 1) 'The delete action accepted a non-numeric pull request.'
} finally {
    Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
}

'PASS docs preview cleanup: a closed pull request is eligible, each malformed response and number is refused'
