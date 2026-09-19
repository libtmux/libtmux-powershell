# Agent instructions

Follow the existing project conventions and keep changes scoped to the
requested work.

## Change discipline

- Check the current branch, working tree, and relevant source before editing.
  Preserve unrelated changes and stage explicit paths.
- Make the smallest coherent change that solves the verified problem. Keep
  unrelated cleanup out of it.
- Reuse an existing file, helper, API, or test before adding a new one.
- Keep new types and members internal until an external caller needs them.
- Add files for distinct responsibilities or independent reuse, not one-line
  re-exports or single-use wrappers.
- Follow language-native conventions. Sibling ports are references for
  behavior; their tooling and package layouts do not automatically apply here.
- Add tests for critical behavior. Show that a regression test fails for the
  intended reason before relying on its passing result.
- Verify claims against the checked-out source and the commands actually run.
  Report what passed, failed, or was skipped; a skipped check is not a pass.
- Prefer `rg`, `ag`, and `fd` for discovery. Use `jq` for JSON.

## Which policy applies

- Setup, testing, tmux isolation, and pull requests:
  [CONTRIBUTING.md](CONTRIBUTING.md).
- Documentation, user-facing text, comments, and commit messages:
  [WRITING.md](WRITING.md).

Each guide is the single home for its subject. `CLAUDE.md` is a relative
symlink to this file; keep the instructions here.
