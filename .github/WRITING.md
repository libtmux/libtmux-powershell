# Writing

This guide governs documentation, user-facing text, comments, Markdown,
commit messages, changelogs, and release notes. [CONTRIBUTING.md](CONTRIBUTING.md)
governs development workflow.

Consult Microsoft's
[PowerShell-Docs style guide](https://learn.microsoft.com/en-us/powershell/scripting/community/contributing/powershell-style-guide?view=powershell-7.6)
and [Markdown best practices](https://learn.microsoft.com/en-us/powershell/scripting/community/contributing/general-markdown?view=powershell-7.6)
for PowerShell examples and markup. This guide's conventions take precedence
where they differ.

## Voice

Lead with the conclusion or observable behavior, then give the evidence or
constraints needed to understand it. Use active voice, present tense, concrete
nouns, and short sentences. Assume no shared conversation history; explain
what a referenced ticket or decision means rather than relying on its ID.

State facts rather than praising them. Replace vague claims such as "robust"
or "optimized" with the handled failure or measured improvement. Remove
filler, promotional language, emoji, agent attribution, and tool metadata.

Use "libtmux for PowerShell" in prose and titles. Reserve `LibTmux` and
`LibTmux.PowerShell` for their module, type, and assembly identifiers. Write
PowerShell, tmux, server, session, window, and pane consistently.

## Documentation and examples

Document what exists. Distinguish a scaffold, an implemented capability, a
tested capability, and a published release. Do not advertise planned cmdlets
as available or copy compatibility promises from another port.

Explain the reader's task before APIs or flags. State prerequisites,
defaults, errors, side effects, ownership, ordering, and concurrency when
they affect the contract. Do not repeat signatures or language basics.

Examples must match available APIs and include required setup and cleanup.
When executable examples exist, prefer quoting their tested source over
maintaining a second copy. A performance claim needs a measurement and a
reproduction command. Link to the source of a rule instead of copying it
across documents.

## Comments and errors

Keep comments that explain a non-obvious invariant, protocol constraint,
platform workaround, ordering requirement, or failure mode. Prefer one or
two direct lines. Preserve tool directives and comments that explain code
which appears wrong but is required.

Remove narration of the next lines, duplicated names or defaults,
speculative future work, and history already held by Git. Put rejected
alternatives and the reasoning behind a change in its commit message.

Error messages name the failed operation and concrete cause. Include a
useful next action when one exists; omit empty phrases such as "an error
occurred".

## Markdown

Use plain CommonMark with descriptive sentence-case headings. Put a blank
line before lists and after headings. Wrap repository prose at 80 columns
where practical; do not break URLs, identifiers, or tables to meet the width.
Do not hard-wrap GitHub issue or pull request paragraphs.

Avoid personal information, machine-specific paths, brittle line references,
bare commit hashes, and counts that duplicate source state.

### Code blocks

Code blocks are paste-and-run units:

- Put one command in each block. An explicit `&&`, `;`, or `\` continuation
  counts as one command.
- Put explanations in prose above the block, not comments inside it.
- Mark shell commands as `console` and prefix them with `$ `.
- Split long commands with `\`, one flag per continuation line.
- Use the actual language tag for source examples. Keep executed examples
  valid for their runner.

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
  check, `python3 eng/check_example_width.py`.
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

## Commit messages

Use `Scope(type[detail]): Description`. The detail qualifier is optional.
Name the affected component and use an imperative, capitalized description
without a trailing period. Keep subjects within 50 characters and body
lines within 72, except indivisible URLs or identifiers.

Use `docs` for documentation, `chore` for configuration, and `rules[AGENTS]`
or `rules[CLAUDE]` under the `Ai` scope for agent entry points. Use `feat`,
`fix`, `refactor`, `test`, `style`, or `ci` when they describe the change.

A small, self-explanatory change can use a subject alone. For a change that
needs a body, explain the reason in a `why:` paragraph, then list the
concrete changes under `what:`. Separate those sections with a blank line.
Use a heredoc or message file to preserve newlines.

Keep each commit focused on one logical change. Do not add emoji, tool
signatures, attribution trailers, or pull request numbers to ordinary
commits. Keep intermediate attempts and rejected approaches in commit
history when they explain a decision, not in product documentation.

## Pull requests, changelogs, and releases

Describe the final change for someone who has not read the conversation.
Lead with the problem and resulting behavior, then give relevant validation
and limits. Name the checks that ran and distinguish passing, failing,
skipped, and unverified work.

When a changelog exists, record caller-visible changes under its unreleased
section. State changed defaults and incompatibilities with migration
guidance. Do not invent versions or release dates. Mention old behavior only
when users of a published release experienced it.

Release notes explain why an upgrader should care and what action is needed.
Link the detailed changelog instead of repeating it. Internal refactors and
branch history belong in commits unless they affect users.
