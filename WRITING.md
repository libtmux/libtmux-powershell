# Writing

This guide governs documentation, user-facing text, comments, Markdown,
commit messages, changelogs, and release notes. [CONTRIBUTING.md](CONTRIBUTING.md)
governs development workflow.

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

Code blocks are paste-and-run units:

- Put one command in each block. An explicit `&&`, `;`, or `\` continuation
  counts as one command.
- Put explanations in prose above the block, not comments inside it.
- Mark shell commands as `console` and prefix them with `$ `.
- Split long commands with `\`, one flag per continuation line.
- Use the actual language tag for source examples. Keep executed examples
  valid for their runner.

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
