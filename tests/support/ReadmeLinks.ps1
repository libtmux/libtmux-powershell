# Markdown link checks shared by tests/ReadmeLinks.Tests.ps1 and tests/Mcp.Tests.ps1.
# Each check returns problem strings; callers decide whether any problem fails.
Set-StrictMode -Version Latest

$script:SiteRoot = 'https://libtmux.org/en'
$script:RepositoryTree = 'https://github.com/libtmux/libtmux-powershell'

function Split-MarkdownText([string] $Text) {
    $lines = $Text.Replace("`r`n", "`n").Split("`n")
    $prose = [Collections.Generic.List[string]]::new()
    $fences = [Collections.Generic.List[object]]::new()
    $open = $null
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($null -eq $open) {
            if ($line -match '^(?<mark>`{3,}|~{3,})(?<info>.*)$') {
                $open = @{ Mark = $Matches.mark; Info = $Matches.info.Trim(); Line = $index + 1
                    Code = [Collections.Generic.List[string]]::new() }
                $prose.Add('')
            } else { $prose.Add($line) }
            continue
        }
        $prose.Add('')
        if ($line -match '^(?<mark>`{3,}|~{3,})[ \t]*$' -and
            $Matches.mark[0] -ceq $open.Mark[0] -and $Matches.mark.Length -ge $open.Mark.Length) {
            $fences.Add([pscustomobject]@{ Info = $open.Info; Line = $open.Line; Code = $open.Code -join "`n" })
            $open = $null
        } else { $open.Code.Add($line) }
    }
    if ($null -ne $open) { throw "Unclosed code fence at line $($open.Line)." }
    [pscustomobject]@{ Prose = $prose.ToArray(); Fences = $fences.ToArray() }
}

function Get-MarkdownDocument([string] $Path, [string] $Text) {
    $parts = Split-MarkdownText $Text
    $definitions = @{}
    $body = [Collections.Generic.List[string]]::new()
    foreach ($line in $parts.Prose) {
        if ($line -match '^\[(?<label>[^\]]+)\]:\s*(?<url>\S+)\s*$') {
            $definitions[$Matches.label.ToLowerInvariant()] = $Matches.url
            $body.Add('')
        } else { $body.Add($line) }
    }
    $links = [Collections.Generic.List[object]]::new()
    $offset = 0
    $lineStarts = [Collections.Generic.List[int]]::new()
    foreach ($line in $body) { $lineStarts.Add($offset); $offset += $line.Length + 1 }
    $joined = $body -join "`n"
    $pattern = '\[(?<text>(?:[^\[\]]|\[[^\]]*\])+)\](?:\((?<url>[^)\s]+)\)|\[(?<label>[^\]]*)\])'
    foreach ($match in [regex]::Matches($joined, $pattern)) {
        $url = $null
        if ($match.Groups['url'].Success) { $url = $match.Groups['url'].Value }
        else {
            $label = $match.Groups['label'].Value
            if (!$label) { $label = $match.Groups['text'].Value }
            $key = $label.ToLowerInvariant()
            if ($definitions.ContainsKey($key)) { $url = $definitions[$key] }
        }
        $links.Add([pscustomobject]@{ Text = $match.Groups['text'].Value; Url = $url
            Start = $match.Index; End = $match.Index + $match.Length; Line = 0 })
    }
    # BinarySearch returns the bitwise complement of the next larger element when absent.
    foreach ($link in $links) {
        $position = $lineStarts.BinarySearch($link.Start)
        if ($position -lt 0) { $position = (-bnot $position) - 1 }
        $link.Line = $position + 1
    }
    [pscustomobject]@{ Path = $Path; Lines = $body.ToArray(); Text = $joined; LineStarts = $lineStarts.ToArray()
        Definitions = $definitions; Links = $links.ToArray(); Fences = $parts.Fences }
}

function Get-MarkdownLineNumber($Document, [int] $Index) {
    $position = [array]::BinarySearch($Document.LineStarts, $Index)
    if ($position -lt 0) { $position = (-bnot $position) - 1 }
    $position + 1
}

function ConvertTo-GitHubSlug([string] $Heading) {
    $plain = [regex]::Replace($Heading, '\[(?<t>[^\]]*)\]\([^)]*\)', '${t}').Replace('`', '')
    $plain = [regex]::Replace($plain.ToLowerInvariant(), '[^\p{L}\p{N}_ \-]', '')
    $plain.Trim().Replace(' ', '-')
}

function Get-MarkdownAnchor($Document) {
    $slugs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $seen = @{}
    foreach ($line in $Document.Lines) {
        if ($line -notmatch '^#{1,6}\s+(?<h>.+?)\s*#*\s*$') { continue }
        $slug = ConvertTo-GitHubSlug $Matches.h
        if ($seen.ContainsKey($slug)) { $seen[$slug]++; $null = $slugs.Add("$slug-$($seen[$slug])") }
        else { $seen[$slug] = 0; $null = $slugs.Add($slug) }
    }
    , $slugs
}

# A cmdlet's page on libtmux.org: lowercase verb-noun behind the module prefix.
function Get-CmdletReferenceUrl([string] $Module, [string] $Name) {
    $slug = $Name.ToLowerInvariant()
    if ($Module -ceq 'LibTmux') { return "$script:SiteRoot/powershell/latest/reference/libtmux-$slug/" }
    "$script:SiteRoot/powershell/latest/workspace/reference/libtmux-workspace-$slug/"
}

# A native type's page: the dotted name in lowercase, Workspace types under workspace/.
function Get-TypeReferenceUrl([string] $FullName) {
    $slug = $FullName.ToLowerInvariant().Replace('.', '-')
    if ($FullName.StartsWith('LibTmux.Workspace.', [StringComparison]::Ordinal)) {
        return "$script:SiteRoot/csharp/latest/workspace/reference/$slug/"
    }
    "$script:SiteRoot/csharp/latest/reference/$slug/"
}

function Get-ToolPageUrl([string] $Tool) { "$script:SiteRoot/csharp/latest/mcp/tools/$Tool/" }

function Get-MarkdownCodeSpan($Document) {
    foreach ($match in [regex]::Matches($Document.Text, '`(?<code>[^`\n]+)`')) {
        $line = Get-MarkdownLineNumber $Document $match.Index
        $text = $Document.Lines[$line - 1]
        $link = $Document.Links | Where-Object {
            $_.Start -le $match.Index -and $match.Index + $match.Length -le $_.End -and
            $_.Text -ceq $match.Value
        } | Select-Object -First 1
        [pscustomobject]@{ Code = $match.Groups['code'].Value; Line = $line
            Heading = $text -match '^#{1,6}\s'; Table = $text -match '^\s*\|'
            Link = $link }
    }
}

# The first prose mention of each public cmdlet and native type links to its page.
function Test-ReadmeApiLink($Document, [hashtable] $Cmdlets) {
    $problems = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($span in Get-MarkdownCodeSpan $Document) {
        if ($span.Heading -or $span.Table) { continue }
        $expected = $null
        if ($Cmdlets.ContainsKey($span.Code)) {
            $expected = Get-CmdletReferenceUrl $Cmdlets[$span.Code] $span.Code
        } elseif ($span.Code -cmatch '^LibTmux(\.Workspace)?\.[A-Z]\w+$' -and
            $span.Code -cnotin @('LibTmux.Workspace', 'LibTmux.PowerShell')) {
            $expected = Get-TypeReferenceUrl $span.Code
        } else { continue }
        if (!$seen.Add($span.Code)) { continue }
        if ($null -eq $span.Link) {
            $problems.Add("$($Document.Path):$($span.Line): first mention of ``$($span.Code)`` is not a link")
        } elseif ($span.Link.Url -cne $expected) {
            $problems.Add("$($Document.Path):$($span.Line): ``$($span.Code)`` links to $($span.Link.Url), not $expected")
        }
    }
    foreach ($link in $Document.Links) {
        if ($link.Url -cmatch '^https://libtmux\.org/en/powershell/latest/(workspace/)?reference/libtmux-[a-z-]+/$') {
            $named = $Cmdlets.Keys | Where-Object { $link.Url -ceq (Get-CmdletReferenceUrl $Cmdlets[$_] $_) }
            if (!$named) {
                $problems.Add("$($Document.Path): $($link.Url) is not the page of a public cmdlet")
            } elseif ($link.Text -cne ('`' + $named + '`')) {
                $problems.Add("$($Document.Path): link text $($link.Text) does not name $named")
            }
        }
    }
    $problems
}

function Test-ReadmeTypeLinked($Document) {
    $types = @($Document.Links | Where-Object {
        $_.Url -cmatch '^https://libtmux\.org/en/csharp/latest/(workspace/)?reference/libtmux-[a-z-]+/$' -and
        $_.Text -cmatch '^`LibTmux(\.Workspace)?\.[A-Z]\w+`$' -and
        $_.Url -ceq (Get-TypeReferenceUrl $_.Text.Trim('`'))
    })
    if (!$types) { return @("$($Document.Path): no public type is linked to its libtmux.org page") }
    @()
}

# Every MCP tool name links to its page; every linked tool exists on the server.
function Test-ReadmeToolLink($Document, [string[]] $ToolNames) {
    $problems = [Collections.Generic.List[string]]::new()
    foreach ($link in $Document.Links) {
        if ($link.Url -cnotmatch '^https://libtmux\.org/en/[a-z]+/latest/mcp/tools/(?<tool>[a-z_]+)/$') { continue }
        $tool = $Matches.tool
        if ($link.Url -cne (Get-ToolPageUrl $tool)) {
            $problems.Add("$($Document.Path): $($link.Url) is not the csharp page of $tool")
        }
        if ($link.Text -cne ('`' + $tool + '`')) {
            $problems.Add("$($Document.Path): link text $($link.Text) does not name $tool")
        }
        if ($ToolNames -and $tool -cnotin $ToolNames) {
            $problems.Add("$($Document.Path): $tool is not a tool of the installed server")
        }
    }
    if (!$ToolNames) { return $problems }
    foreach ($span in Get-MarkdownCodeSpan $Document) {
        if ($span.Heading -or $span.Code -cnotin $ToolNames) { continue }
        $expected = Get-ToolPageUrl $span.Code
        if ($null -eq $span.Link -or $span.Link.Url -cne $expected) {
            $problems.Add("$($Document.Path):$($span.Line): tool ``$($span.Code)`` is not linked to $expected")
        }
    }
    # A tool name outside backticks and outside a URL is still a name to link.
    $withoutCode = [regex]::Replace($Document.Text, '`[^`\n]+`|<!--[\s\S]*?-->', { param($m) ' ' * $m.Length })
    $withoutUrls = [regex]::Replace($withoutCode, '\]\([^)]*\)|\]\[[^\]]*\]', { param($m) ' ' * $m.Length })
    foreach ($tool in $ToolNames) {
        foreach ($match in [regex]::Matches($withoutUrls, "(?<![\w/.-])$([regex]::Escape($tool))(?![\w/-])")) {
            $line = Get-MarkdownLineNumber $Document $match.Index
            $problems.Add("$($Document.Path):${line}: tool name $tool is outside backticks")
        }
    }
    $problems
}

# Links never sit inside a code block: the introducing sentence carries them.
function Test-ReadmeCodeLink($Document) {
    foreach ($fence in $Document.Fences) {
        if ($fence.Code -match '\]\(https?://|https?://libtmux\.org') {
            "$($Document.Path):$($fence.Line): a link sits inside a code block"
        }
    }
}

function Test-ReadmeAnchor($Document, [string] $Root) {
    $own = Get-MarkdownAnchor $Document
    foreach ($link in $Document.Links) {
        $url = $link.Url
        if ($null -eq $url) { "$($Document.Path):$($link.Line): link $($link.Text) has no target"; continue }
        if ($url -match '^[a-z][a-z0-9+.-]*:') { continue }
        $path, $fragment = $url -split '#', 2
        if (!$path) {
            if ($fragment -and !$own.Contains($fragment)) { "$($Document.Path):$($link.Line): no heading for #$fragment" }
            continue
        }
        $target = [IO.Path]::GetFullPath((Join-Path (Split-Path $Document.Path) $path))
        $isFile = Test-Path -LiteralPath $target -PathType Leaf
        if (!$isFile -and !(Test-Path -LiteralPath $target -PathType Container)) {
            "$($Document.Path):$($link.Line): $path does not exist"
        } elseif ($fragment -and $isFile -and $target.EndsWith('.md', [StringComparison]::Ordinal)) {
            $other = Get-MarkdownDocument $target ([IO.File]::ReadAllText($target))
            if (!(Get-MarkdownAnchor $other).Contains($fragment)) {
                "$($Document.Path):$($link.Line): $path has no heading for #$fragment"
            }
        }
    }
}

# Absolute links into this repository name a tracked file or directory.
function Test-ReadmeRepositoryLink($Document, [string[]] $Tracked) {
    $pattern = '^' + [regex]::Escape($script:RepositoryTree) + '/(?:tree|blob)/(?<ref>[^/]+)/(?<path>[^#?]+)'
    foreach ($link in $Document.Links) {
        if ($null -eq $link.Url -or $link.Url -cnotmatch $pattern) { continue }
        $path = $Matches.path.TrimEnd('/')
        if ($Matches.ref -cne 'master') { "$($Document.Path):$($link.Line): $($link.Url) names a ref other than master"; continue }
        $exists = $Tracked -ccontains $path -or [bool]($Tracked | Where-Object { $_.StartsWith("$path/", [StringComparison]::Ordinal) } | Select-Object -First 1)
        if (!$exists) { "$($Document.Path):$($link.Line): $path is not tracked" }
    }
}

# The root page gives each product a heading that links its directory.
function Test-ReadmePackageHeading($Document, [string[]] $Directories) {
    $headings = @($Document.Lines | ForEach-Object {
        if ($_ -match '^###\s+\[[^\]]+\]\((?<url>[^)]+)\)') { $Matches.url }
    })
    foreach ($directory in $Directories) {
        if ($directory -cnotin $headings) { "$($Document.Path): no package heading links $directory" }
    }
}

# Every README opens with the shared centred logo block and ships its art beside it.
function Test-ReadmeLogoHeader($Document, [string] $Alt) {
    $expected = @(
        '<!-- libtmux-logo -->', '<div align="center">', '  <picture>',
        '    <source srcset="assets/logo.svg" type="image/svg+xml">',
        "    <img src=`"assets/logo.png`" width=`"128`" height=`"128`" alt=`"$Alt`">",
        '  </picture>', '</div>', '<!-- /libtmux-logo -->', '', '<div align="center">')
    for ($index = 0; $index -lt $expected.Count; $index++) {
        $actual = if ($index -lt $Document.Lines.Count) { $Document.Lines[$index] } else { '' }
        if ($actual -cne $expected[$index]) {
            "$($Document.Path):$($index + 1): logo header line is '$actual', not '$($expected[$index])'"
            break
        }
    }
    $directory = Split-Path $Document.Path
    $png = Join-Path $directory 'assets/logo.png'
    $svg = Join-Path $directory 'assets/logo.svg'
    if (!(Test-Path -LiteralPath $svg -PathType Leaf)) { "$($Document.Path): assets/logo.svg is missing" }
    elseif ([IO.File]::ReadAllText($svg).TrimStart([char] 0xFEFF).TrimStart() -cnotmatch '^(<\?xml|<svg)') {
        "$($Document.Path): assets/logo.svg is not an SVG"
    }
    if (!(Test-Path -LiteralPath $png -PathType Leaf)) { "$($Document.Path): assets/logo.png is missing"; return }
    $bytes = [IO.File]::ReadAllBytes($png)
    $signature = [byte[]] (0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    $isPng = $bytes.Length -ge 24 -and !(Compare-Object $signature $bytes[0..7] -SyncWindow 0)
    # The logo kit ships 512 x 512 PNGs; a smaller file means someone resized the art.
    $isSized = $false
    if ($isPng) {
        # A Byte shifted left stays a Byte, so widen the IHDR fields first.
        $field = { param([int] $At) ([int] $bytes[$At] * 16777216) + ([int] $bytes[$At + 1] * 65536) + ([int] $bytes[$At + 2] * 256) + [int] $bytes[$At + 3] }
        $isSized = (& $field 16) -eq 512 -and (& $field 20) -eq 512
    }
    if (!$isSized) { "$($Document.Path): assets/logo.png is not a 512 x 512 PNG" }
}
