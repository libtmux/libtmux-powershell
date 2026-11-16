# Decides whether a closed pull request's documentation preview may be deleted
# and names the preview to delete. DocsPreviewCleanup.ps1 is the command line.
Set-StrictMode -Version Latest

function Stop-Cleanup([string] $Message) {
    throw [InvalidOperationException]::new($Message)
}

# Refuses a pull request number that is not a positive decimal integer.
function Assert-PullRequestNumber([string] $Pr) {
    if ($Pr -cnotmatch '^[1-9][0-9]*\z') { Stop-Cleanup 'pull request number must be numeric' }
}

# Returns whether the pull request in a GitHub API response is closed. It refuses
# a response that is not an object, names another number, or has no open or closed state.
function Get-CleanupEligibility([string] $Response, [string] $Pr) {
    Assert-PullRequestNumber $Pr
    try {
        $pull = $Response | ConvertFrom-Json -AsHashtable -NoEnumerate
    } catch {
        Stop-Cleanup 'invalid current pull request response'
    }
    $valid = $pull -is [Collections.IDictionary] -and
    $pull.Contains('number') -and ($pull['number'] -is [int] -or $pull['number'] -is [long]) -and
    $pull['number'] -eq [long] $Pr -and
    $pull.Contains('state') -and $pull['state'] -cin @('open', 'closed')
    if (!$valid) { Stop-Cleanup 'invalid current pull request response' }
    $pull['state'] -ceq 'closed'
}

# Returns the S3 prefix that holds the preview of one pull request.
function Get-PreviewPrefix([string] $Bucket, [string] $Pr) {
    Assert-PullRequestNumber $Pr
    "s3://$Bucket/en/powershell/pr-$Pr/"
}

Export-ModuleMember -Function Assert-PullRequestNumber, Get-CleanupEligibility, Get-PreviewPrefix
