param([switch] $Online)

# Mid loop: the README pages link their packages, public APIs and MCP tools.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot
. "$PSScriptRoot/support/ReadmeLinks.ps1"

$tracked = @(git -C $root ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE) { throw 'git ls-files failed.' }
$pages = @('README.md', 'docs/mcp.md') + @($tracked | Where-Object {
    $_ -cmatch '^src/[^/]+/README\.md$'
})
$cmdlets = @{}
foreach ($module in @('LibTmux', 'LibTmux.Workspace')) {
    foreach ($file in Get-ChildItem "$root/docs/reference/$module" -Filter '*.md') {
        $cmdlets[$file.BaseName] = $module
    }
}
if ($cmdlets.Count -eq 0) { throw 'No cmdlet reference pages found.' }

# Products: every src project directory that builds a module, plus the separate MCP tool.
$projectDirectories = @($tracked | Where-Object { $_ -cmatch '^src/[^/]+/[^/]+\.csproj$' } |
    ForEach-Object { Split-Path $_ })
$headingLinks = @($projectDirectories | ForEach-Object { "$script:RepositoryTree/tree/master/$_" }) +
    'https://github.com/libtmux/libtmux-dotnet/tree/master/src/LibTmux.Mcp'

function Read-Page([string] $Relative, [string] $Text) {
    Get-MarkdownDocument (Join-Path $root $Relative) $Text
}

function Get-PageProblem($Document, [bool] $IsRoot) {
    Test-ReadmeApiLink $Document $cmdlets
    Test-ReadmeCodeLink $Document
    Test-ReadmeAnchor $Document $root
    Test-ReadmeRepositoryLink $Document $tracked
    Test-ReadmeToolLink $Document @()
    if ($IsRoot) {
        Test-ReadmePackageHeading $Document $headingLinks
        Test-ReadmeTypeLinked $Document
    }
}

$problems = [Collections.Generic.List[string]]::new()
$documents = @{}
foreach ($page in $pages) {
    $document = Read-Page $page ([IO.File]::ReadAllText("$root/$page"))
    $documents[$page] = $document
    foreach ($problem in Get-PageProblem $document ($page -ceq 'README.md')) { $problems.Add($problem) }
}
foreach ($directory in $projectDirectories) {
    if ("$directory/README.md" -cnotin $tracked) { $problems.Add("$directory has no README.md") }
}
if ($problems.Count) { throw ("README links:`n" + ($problems -join "`n")) }

# Negative controls: each planted fault must produce its named problem, and a clean page none.
function Assert-Planted([string] $Name, [string] $Markdown, [string] $Expected, [bool] $IsRoot = $false, [string[]] $Tools = @()) {
    $document = Get-MarkdownDocument (Join-Path $root 'planted.md') $Markdown
    $found = @(Get-PageProblem $document $IsRoot) + @(Test-ReadmeToolLink $document $Tools)
    if ($Expected -and !($found | Where-Object { $_.Contains($Expected) })) {
        throw "README links control '$Name' did not report '$Expected'. Reported: $($found -join '; ')"
    }
    if (!$Expected -and $found.Count) { throw "README links control '$Name' rejected a clean page: $($found -join '; ')" }
}

$paneUrl = Get-CmdletReferenceUrl 'LibTmux' 'Get-TmuxPane'
Assert-Planted 'clean' "Use [``Get-TmuxPane``][pane].`n`n[pane]: $paneUrl`n" ''
Assert-Planted 'unlinked cmdlet' "Use ``Get-TmuxPane`` here.`n" 'first mention of `Get-TmuxPane` is not a link'
Assert-Planted 'late link' "Use ``Get-TmuxPane``, then [``Get-TmuxPane``][pane].`n`n[pane]: $paneUrl`n" 'first mention of `Get-TmuxPane` is not a link'
Assert-Planted 'wrong cmdlet page' "Use [``Get-TmuxPane``](https://libtmux.org/en/powershell/latest/reference/libtmux-get-tmuxsession/).`n" 'not https://libtmux.org/en/powershell/latest/reference/libtmux-get-tmuxpane/'
Assert-Planted 'unlinked type' "A ``LibTmux.Session`` appears.`n" 'first mention of `LibTmux.Session` is not a link'
Assert-Planted 'no type link' "Plain text.`n" 'no public type is linked' $true
$fence = '```'
Assert-Planted 'link in code' "Text.`n`n${fence}powershell`n# https://libtmux.org/en/powershell/latest/`n${fence}`n" 'a link sits inside a code block'
Assert-Planted 'missing heading' "See [it](#nowhere).`n" 'no heading for #nowhere'
Assert-Planted 'untracked path' "See [dir](https://github.com/libtmux/libtmux-powershell/tree/master/src/Nope).`n" 'src/Nope is not tracked'
Assert-Planted 'missing package heading' "### Plain`n" 'no package heading links' $true
$toolUrl = Get-ToolPageUrl 'list_panes'
Assert-Planted 'linked tool' "Use [``list_panes``][t].`n`n[t]: $toolUrl`n" '' $false @('list_panes')
Assert-Planted 'unlinked tool' "Use ``list_panes`` now.`n" 'tool `list_panes` is not linked' $false @('list_panes')
Assert-Planted 'bare tool' "Use list_panes now.`n" 'tool name list_panes is outside backticks' $false @('list_panes')
Assert-Planted 'tool link names another' "Use [``list_panes``](https://libtmux.org/en/csharp/latest/mcp/tools/list_windows/).`n" 'does not name list_windows' $false @('list_panes')
Assert-Planted 'unknown tool' "Use [``no_such``][t].`n`n[t]: $(Get-ToolPageUrl 'no_such')`n" 'no_such is not a tool of the installed server' $false @('list_panes')

if ($Online) {
    $urls = @($documents.Values | ForEach-Object {
        $_.Links.Url
        $_.Definitions.Values
    } | Where-Object { $_ -and $_ -cmatch '^https?://' } | ForEach-Object { ($_ -split '#')[0] } | Sort-Object -Unique)
    $failed = [Collections.Generic.List[string]]::new()
    $redirected = [Collections.Generic.List[string]]::new()
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(20)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0')
    try {
        foreach ($url in $urls) {
            $target = [Uri] $url
            $statuses = @()
            for ($hop = 0; $hop -lt 5; $hop++) {
                $response = $client.GetAsync($target).GetAwaiter().GetResult()
                try {
                    $statuses += [int] $response.StatusCode
                    if ($response.StatusCode -in 301, 302, 307, 308 -and $response.Headers.Location) {
                        $target = [Uri]::new($target, $response.Headers.Location)
                    } else { break }
                } finally { $response.Dispose() }
            }
            if ($statuses.Count -gt 1) { $redirected.Add("$($statuses -join ' -> ') $url") }
            if ($statuses[-1] -ne 200) { $failed.Add("$($statuses -join ' -> ') $url") }
        }
    } finally { $client.Dispose() }
    $redirected | ForEach-Object { "REDIRECT $_" }
    if ($failed.Count) { throw ("README links answer something other than 200:`n" + ($failed -join "`n")) }
    "PASS $($urls.Count) README URLs answer 200 ($($redirected.Count) after a redirect)"
}

"PASS README links: $($pages.Count) pages, package headings, anchors, repository paths, API and tool links, controls"
