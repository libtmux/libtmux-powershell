# Resolves the commit a Gallery release publishes and checks the release tag
# against it. ReleaseSource.ps1 is the command line.
Set-StrictMode -Version Latest

$script:TagPattern = '^v0\.1\.(0-alpha[1-9][0-9]*|0|[1-9][0-9]*)\z'

function Stop-Release([string] $Message) {
    throw [InvalidOperationException]::new($Message)
}

# Runs git in a repository and returns its exit code and trimmed output.
function Invoke-Git([string] $Repository, [string[]] $Arguments) {
    $output = & git -C $Repository @Arguments 2>$null
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = (@($output) -join "`n").Trim() }
}

# Refuses a tag that is not named v0.1.N or v0.1.0-alphaN, is not annotated, or
# does not point at the commit being released.
function Assert-ReleaseTag([string] $Tag, [string] $Commit, [string] $Repository = '.') {
    if ($Tag -cnotmatch $script:TagPattern) { Stop-Release 'Release tag must use v0.1.N or v0.1.0-alphaN.' }
    $ref = "refs/tags/$Tag"
    if ((Invoke-Git $Repository @('show-ref', '--verify', '--quiet', $ref)).ExitCode) {
        Stop-Release "Release tag $Tag does not exist."
    }
    if ((Invoke-Git $Repository @('cat-file', '-t', $ref)).Output -cne 'tag') { Stop-Release 'Release tag must be annotated.' }
    if ((Invoke-Git $Repository @('rev-parse', '--verify', "$ref^{commit}")).Output -cne $Commit) {
        Stop-Release 'Release tag must point at the commit being released.'
    }
}

# Returns the commit to publish: the commit of the run, which an optional tag
# must name.
function Resolve-ReleaseSource([string] $Commit, [string] $Tag = '', [string] $Repository = '.') {
    if ($Tag) { Assert-ReleaseTag $Tag $Commit $Repository }
    if ($Commit -cnotmatch '^[0-9a-f]{40}\z') { Stop-Release 'The release commit must be a full lowercase SHA.' }
    $Commit
}

Export-ModuleMember -Function Assert-ReleaseTag, Resolve-ReleaseSource
