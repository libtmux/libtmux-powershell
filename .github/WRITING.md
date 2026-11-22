# Writing

Repository-specific rules for documentation, help text, comments, changelogs,
and commits in libtmux for PowerShell. Shared organization voice, CommonMark
wrapping, code-fence formatting, source-comment gates, slop prevention, and
commit conventions live in [`libtmux/.github` `WRITING.md`][org-writing];
development workflow lives in [CONTRIBUTING.md](CONTRIBUTING.md).

Consult Microsoft's [PowerShell-Docs style guide][ps-style] and
[Markdown best practices][ps-markdown] for PowerShell examples and markup; this
guide and the shared organization guide take precedence where they differ.

## Terminology and documentation

Use "libtmux for PowerShell" in prose and titles. Reserve `LibTmux`,
`LibTmux.Workspace`, `LibTmux.PowerShell`, and `LibTmux.Workspace.PowerShell`
for module, type, and assembly identifiers. Write PowerShell, `tmux`, `server`,
`session`, `window`, and `pane` consistently.

Document what exists: distinguish a scaffold, an implemented capability, a
tested capability, and a published release, and do not advertise planned
cmdlets or copy compatibility claims from another port. State prerequisites,
defaults, errors, side effects, ownership, ordering, and concurrency when they
affect the caller contract. Prefer quoting tested source over maintaining a
second copy, and attach every performance figure to its reproduction command.

## Comments and errors

Follow the Loss, Ceiling, and Upkeep gates in
[`libtmux/.github` `WRITING.md`][org-comments]: keep one or two lines for a
non-obvious invariant, protocol or `tmux` version constraint, ordering rule, or
code that looks wrong but is intentional, and preserve analyzer directives.
Error messages name the failed operation, the concrete cause, and a useful next
action when one exists.

## Markdown

Follow [`libtmux/.github` `WRITING.md`][org-commonmark] for plain CommonMark
(no GitHub alert markers in repository `.md` files), 80-column prose wrapping,
and unwrapped GitHub issue and pull request bodies.

### Code blocks

Follow [`libtmux/.github` `WRITING.md`][org-code-blocks]: keep one paste-and-run
command per `console` fence with a `$ ` prompt (`\` continuations, one flag per
line) and prose explanations above the fence. Use `powershell` on PowerShell
source fences and keep executed examples valid for their runner.

## Examples

<!-- shared:examples -->

An example is code written for a reader: a program under `examples/`, code in
a doc comment or docstring, and every fenced block in a README or docs page.
Shell blocks also follow [Code blocks](#code-blocks).

The text between the shared markers is the same in every libtmux port.
Change it in all of them together.

### Width

- **Examples stay within 80 columns.** They render in fixed-width boxes that
  scroll sideways, and 80 columns fits a libtmux.org code block in a
  laptop-width window. Comments inside examples wrap at 80 too.
- **The width check enforces it.** It reads the tracked files that
  `.github/example-width.toml` names and fails on a wider line. It measures
  the whole source line, so code in a doc comment counts its indent and
  comment marker. It skips output (a fence tagged `text`, and what a
  `console` block prints), hidden setup lines, and a line that is only a URL;
  an untagged fence counts as code.
- **A line that must stay wider is listed there with its reason.** An entry
  that no longer matches a line fails the check, so no stale entry stays.
- **The formatter's width is the hard limit for all other source.** Example
  directories set their formatter to 80 where the formatter takes a width.

### Reaching 80

- **Change the code, not the line breaks.** A formatter rejoins any line that
  fits its width. Name a sub-expression, use a short example name, hide setup
  the reader does not need, or print less.
- **Break at the outermost level when a break is still needed:** after an
  opening parenthesis with one argument per line, one call per line in a
  chain, one field per line in a literal.
- **Put a comment on its own line above the code it explains.** Never trail
  one after code in an example, unless the repository's example runner reads
  it there, as with an assertion marker.
- **Break a long string at a word boundary,** never inside a tmux format
  (`#{...}`) or an escape sequence; the joined text stays the same.
- **Continue a long command in a `console` block the way its shell does:**
  `\` after a `$ ` prompt, a backtick after `PS> `, one flag per continuation
  line.

### What never breaks

- **Output a test compares.** Wrapping it changes what the test expects.
- **A block copied from a source file.** Fix the width in the source and run
  the sync command; never edit the copy.
- **Marker lines and URLs,** which tools and readers take whole.

<!-- /shared:examples -->

### In this repository

- **Hard limit:** no formatter here takes a width. PSScriptAnalyzer
  (`PSScriptAnalyzerSettings.psd1`, installed by `eng/Setup.ps1`) checks
  braces and whitespace but never wraps, and `dotnet format` never wraps
  either. The example files and pages are held to 80 columns by the width
  check, the `check-example-width` action of libtmux/.github, which
  [CONTRIBUTING](CONTRIBUTING.md#build-and-check-modules) shows how to run.
- **Not formatted:** every example: README and `docs/` fences,
  `examples/*.ps1`, and the `docs/reference/` help examples. Hold them to
  80 by hand.
- **Runs, compiles, exempt:** `<!-- example: ID -->` over a fence copies the
  region of `examples/Guides.ps1` with that ID, and the guide tests run it.
  README blocks run in order, and `docs/reference/` help examples run
  against owned tmux. A fence tagged `text` and the lines a `console` block
  prints are exempt.
- **Compared output and copied blocks:** never wrap output a test compares.
  Edit `examples/Guides.ps1`, then copy the region into every fence with its
  ID; `pwsh -NoLogo -NoProfile -File tests/GuideExamples.Tests.ps1` fails on
  drift. Edit `docs/reference/` and run `eng/Help.ps1` to rebuild the MAML.

Bad, over 80:

```powershell
    $session = $server | New-TmuxSession `
        -Name ('pane-run-' + [Guid]::NewGuid().ToString('N')) -Command 'exec /bin/sh'
```

Good, name the value first:

```powershell
    $name = 'pane-run-' + [Guid]::NewGuid().ToString('N')
    $session = $server | New-TmuxSession -Name $name -Command 'exec /bin/sh'
```

## README shape

The root `README.md` and each module `README.md` follow the shared
[`libtmux/.github` `README shape`][org-readme-shape] with these PowerShell
specifics:

- **Header and install:** the logo block, centred title, badge row (CI,
  PowerShell Gallery version when published, `libtmux.org`, license), and
  one-sentence summary inside the centred block, followed by Gallery install
  commands, runtime floors (`PowerShell 7.4 or newer`, `tmux 3.3a or newer`),
  and a checkout pointer ahead of or within `Quick start`.
- **Tasks and linked APIs:** `##` task headings and `###` headings linking each
  cmdlet or native type on `libtmux.org`. `tests/ReadmeLinks.Tests.ps1` fails on
  unlinked first API mentions, broken anchors, or any paragraph or list item
  over 240 rendered characters.
- **Examples:** start each section's first example with `Import-Module`, use
  `New-TmuxServer` on a unique socket with cmdlet cleanup (never shell `tmux`),
  and copy every displayed `powershell` fence from `examples/Guides.ps1` or
  `examples/`.
- **Headline features:** show query and filter cmdlets, `Get-TmuxQueryPlan`,
  command chains, and control-mode clients and events (or link the tested guide
  program).
- **Packages and closing:** keep the package table and per-module trunk
  headings linking the reference, Gallery page, and module changelog, then
  close with `What it leaves out`, `Support and status`, compact reference
  links, and the `libtmux.org` family line.

## Commit messages

Follow the `Scope(type[detail]): Description` format, 50/72 limits, and `why:`
/ `what:` body in [`libtmux/.github` `WRITING.md`][org-commits]. Use `docs`,
`chore`, `feat`, `fix`, `refactor`, `test`, `style`, or `ci`, and use
`Ai(rules[AGENTS])` or `Ai(rules[CLAUDE])` for agent entry points.

## Pull requests, changelogs, and releases

Follow [`libtmux/.github` `WRITING.md`][org-commits] for pull requests and
release notes. Report the checks run and distinguish passing, failing, skipped,
and unverified work. Record caller-visible changes and migration guidance under
the unreleased changelog section without inventing versions or dates.

Each module keeps its own `CHANGELOG.md` in its `module/` directory, which the
build copies into the package: `module/LibTmux/CHANGELOG.md` for `LibTmux` and
`module/LibTmux.Workspace/CHANGELOG.md` for `LibTmux.Workspace`. An entry goes
in the file of the module it changes. The root `CHANGELOG.md` holds what
belongs to no single module: a change that spans both, and documentation,
development and packaging. An entry lives in exactly one file. The modules
share one version, so every release has a section in each file, and a release
with nothing for a module says ``No entries for `LibTmux`.`` under its heading.
The unreleased heading of every file is dated at the release. A module's
`PSData.ReleaseNotes` links its changelog, and the publisher refuses a package
that ships none. When the first entry lands in a release that says ``No entries
for `LibTmux`.``, delete that line.

[org-writing]: https://github.com/libtmux/.github/blob/main/WRITING.md
[org-commonmark]: https://github.com/libtmux/.github/blob/main/WRITING.md#commonmark
[org-code-blocks]: https://github.com/libtmux/.github/blob/main/WRITING.md#code-blocks
[org-readme-shape]: https://github.com/libtmux/.github/blob/main/WRITING.md#readme-shape
[org-comments]: https://github.com/libtmux/.github/blob/main/WRITING.md#source-comments
[org-commits]: https://github.com/libtmux/.github/blob/main/WRITING.md#commits-and-pull-requests
[ps-style]: https://learn.microsoft.com/en-us/powershell/scripting/community/contributing/powershell-style-guide?view=powershell-7.6
[ps-markdown]: https://learn.microsoft.com/en-us/powershell/scripting/community/contributing/general-markdown?view=powershell-7.6
