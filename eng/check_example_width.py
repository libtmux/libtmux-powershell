"""Fail when code a reader sees in rendered documentation is too wide.

Shared by every libtmux port; change it in all of them together. It
enforces the example rules in WRITING.md. Configuration lives in
``.github/example-width.toml``::

    width = 80
    tab_width = 4
    markdown = ["**/*.md"]
    sources = ["examples/**/*.rs"]
    doc_comments = ["src/**/*.rs"]
    shared_digest = "<sha256 printed by --digest>"
    checker_digest = "<sha256 printed by --digest>"
    allow_ceiling = 1

    [[exclude]]
    glob = "docs/decisions/**"
    reason = "dated decision records, not reader-facing examples"

    [[formatter_copies]]
    copy = "examples/rustfmt.toml"
    root = "rustfmt.toml"
    key = "max_width"

    [[allow]]
    path = "README.md"
    line = "the exact line, as it appears in the file"
    reason = "why breaking it would make the example worse"

It checks fenced code in ``markdown`` files (literal and ``code-block``
blocks in a ``.rst`` one), every line of ``sources`` files, and the code
inside doc comments of ``doc_comments`` files: fences, ``>>>`` doctests,
and reST literal blocks in Python docstrings. Output is not checked:
fences tagged ``text`` and the lines a ``console`` block prints. An
untagged Markdown fence is code. A line that is only a URL (after an
optional comment, list or quote marker) and a hidden line (a rustdoc
``# `` line, a doctest marked ``# doctest: +HIDE``) are skipped. Wide
characters count as two columns; a tab advances to the next multiple of
``tab_width`` (default 4).

``width`` must be 80, the shared rule. Every glob must match a tracked
file and every exclusion a checked one; every exclusion and allow entry
must give a reason, and every allow entry must match a line. Every
tracked file under a directory named ``examples`` must be checked or
excluded, so a new example file cannot go unread.
``allow_ceiling`` must equal the number of allow entries, so the list
grows only through a reviewed change to that number and a fixed line must
lower it. Each formatter copy must equal its root file except for the
lines naming ``key``, and the digests of this checker and of WRITING.md's
shared section must equal ``checker_digest`` and ``shared_digest``, so a
local edit to either fails until every port changes together. AGENTS.md
must link the WRITING.md heading the shared section sits under, so an
agent is routed to the rules, and WRITING.md's ``### In this repository``
block must hold the four labelled bullets in order, then one Bad and one
Good example.

Run ``--self-test`` to prove the checker can fail. ``--digest`` prints the
SHA-256 of this file and of WRITING.md's shared example section (between
``<!-- shared:examples -->`` and ``<!-- /shared:examples -->``), so a job
that reads every port can confirm they still agree.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import os
import pathlib
import re
import subprocess
import sys
import typing as t
import unicodedata

try:
    import tomllib
except ModuleNotFoundError:  # tomllib is in the standard library from 3.11.
    sys.exit("check_example_width.py needs Python 3.11 or newer")

CONFIG = pathlib.PurePosixPath(".github/example-width.toml")
KEYS = frozenset(
    {
        "width",
        "tab_width",
        "markdown",
        "sources",
        "doc_comments",
        "exclude",
        "allow",
        "allow_ceiling",
        "formatter_copies",
        "shared_digest",
        "checker_digest",
    }
)
GLOB_KEYS = ("markdown", "sources", "doc_comments")
CODE_DIRECTIVES = frozenset({"code-block", "code", "code-cell", "sourcecode"})
# gp-libs hides a doctest line carrying this directive from the rendered page.
HIDDEN = re.compile(r"^\s*(?:>>>|\.\.\.) .*# doctest: \+HIDE\b")
OUTPUT_TAGS = frozenset({"text"})
# A reST line that opens an indented code block: a paragraph ending in
# ``::`` or a code directive. Other directives, such as toctree, hold no code.
REST_BLOCK = re.compile(
    r"^\s*(?!\.\. )\S.*::\s*$|^\s*\.\. (code-block|code|sourcecode)::"
)
FENCE = re.compile(r"^(?P<indent>\s*)(?P<mark>`{3,}|~{3,})\s*(?P<info>[^`]*)$")
RUSTDOC_TAGS = frozenset({"rust", "no_run", "ignore", "should_panic", "compile_fail"})
SHARED = re.compile(
    r"<!-- shared:examples -->\n(?P<body>.*?)<!-- /shared:examples -->", re.DOTALL
)
DOC_LINE = re.compile(r"^\s*(?:///|//!|\*(?!/)|#'|--- ?)\s?")
BLOCK_OPEN = re.compile(r"<pre>\s*\{@code|<code>\s*$")
BLOCK_CLOSE = re.compile(r"\}\s*</pre>|^\s*</code>")
URL = re.compile(r"^(?:(?:#+|//+!?|-+|\*|>|<!--)\s*)?<?[a-z][a-z0-9+.-]*://\S+$")
EXAMPLE_DIR = re.compile(r"(^|/)examples/", re.IGNORECASE)
HEADING = re.compile(r"^(#{1,6}) (.+)$", re.MULTILINE)
PORT_BLOCK = re.compile(
    r"^### In this repository\n(?P<body>.*?)(?=^#{1,3} |\Z)", re.MULTILINE | re.DOTALL
)
PORT_LABELS = (
    "- **Hard limit:**",
    "- **Not formatted:**",
    "- **Runs, compiles, exempt:**",
    "- **Compared output and copied blocks:**",
)
# Where every port lists its copy, so a digest change reaches all of them.
PORTS = "PORTS in libtmux/docs scripts/check_shared_examples.py"


def fence_tag(info: str) -> str:
    """Return a fence's language, reading past a MyST ``{directive}``.

    >>> fence_tag("rust,no_run")
    'rust'
    >>> fence_tag("{code-block} python")
    'python'
    >>> fence_tag("{note}")
    'text'
    >>> fence_tag("")
    ''
    """
    words = info.strip().lower().split()
    if words and words[0].startswith("{"):
        if words[0].strip("{}") not in CODE_DIRECTIVES:
            return "text"
        words = words[1:]
    return words[0].split(",")[0] if words else ""


@dataclasses.dataclass(frozen=True)
class Finding:
    """One line wider than the configured width."""

    path: str
    number: int
    columns: int
    width: int

    def __str__(self) -> str:
        """Render as ``path:line: width > limit``.

        >>> print(Finding("README.md", 3, 90, 80))
        README.md:3: 90 columns > 80
        """
        return f"{self.path}:{self.number}: {self.columns} columns > {self.width}"


def columns(text: str) -> int:
    """Return the columns a line occupies; wide characters take two.

    >>> columns("abc")
    3
    >>> columns("日本")
    4
    """
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)


def is_url(text: str) -> bool:
    """Return whether a line is one URL, which cannot be broken.

    >>> is_url("    https://example.com/" + "x" * 90)
    True
    >>> is_url("// <https://example.com/a>")
    True
    >>> is_url('let body=reqwest::get("https://example.com/").await?;')
    False
    >>> is_url("server.sessions().stream().filter(s->s.isAttached()).toList()")
    False
    """
    return bool(URL.match(text.strip()))


def open_quote(line: str, quote: str | None) -> str | None:
    r"""Return the shell quote still open at the end of a line, if any.

    >>> open_quote("$ julia -e 'using Pkg", None)
    "'"
    >>> open_quote("Pkg.add(1)'", "'") is None
    True
    >>> open_quote('$ echo "a b"', None) is None
    True
    """
    for char in line:
        if quote is None and char in "'\"":
            quote = char
        elif char == quote:
            quote = None
    return quote


LIST_ITEM = re.compile(r"^\s*([-*+]|\d+[.)])\s")


def indent_code(line: str) -> bool:
    """Return whether a Markdown line is indented far enough to be code."""
    return line.startswith(("    ", "\t"))


def markdown_lines(text: str, indented: bool = True) -> list[tuple[int, str]]:
    r"""Return the code lines of the fences a reader runs or copies.

    Output fences are skipped, and so are the lines a ``console`` block
    prints after its ``$`` commands. An untagged fence counts as code.

    >>> doc = "\n".join([
    ...     "```rust", "let a = 1;", "```",
    ...     "```text", "output", "```",
    ...     "```", "untagged();", "```",
    ...     "```console", "$ cargo test \\", "    --doc", "ok", "```",
    ... ])
    >>> [line for _, line in markdown_lines(doc)]
    ['let a = 1;', 'untagged();', '$ cargo test \\', '    --doc']
    >>> rust = "```rust\n# let hidden = 1;\nlet shown = 2;\n```"
    >>> [line for _, line in markdown_lines(rust)]
    ['let shown = 2;']
    >>> myst = "```{code-block} text\nplain output\n```"
    >>> markdown_lines(myst)
    []
    >>> ps = "```console\nPS> Get-Item `\n    -Path x\nok\n```"
    >>> [line for _, line in markdown_lines(ps)]
    ['PS> Get-Item `', '    -Path x']
    >>> quoted = "```console\n$ julia -e '\n    using Pkg'\nok\n```"
    >>> [line for _, line in markdown_lines(quoted)]
    ["$ julia -e '", "    using Pkg'"]

    A ``text`` fence that opens with a prompt is a console session, and an
    indented code block or a ``<pre>`` block outside a list is code:

    >>> prompted = "```text\n$ ls -l\ntotal 0\n```"
    >>> [line for _, line in markdown_lines(prompted)]
    ['$ ls -l']
    >>> page = "Before:\n\n    new Server()\n\n- item\n\n    more of the item"
    >>> [line for _, line in markdown_lines(page)]
    ['    new Server()']
    >>> [line for _, line in markdown_lines("<pre><code>run()\n</code></pre>")]
    ['<pre><code>run()', '</code></pre>']
    """
    found: list[tuple[int, str]] = []
    fence: tuple[str, str] | None = None
    first = False
    continued = False
    quote: str | None = None
    blank, in_list, in_block, in_pre = True, False, False, False
    for number, line in enumerate(text.splitlines(), 1):
        match = FENCE.match(line)
        if fence is None and match:
            fence = (match["mark"], fence_tag(match["info"]))
            first, continued, in_block = True, False, False
            continue
        if fence is None:
            if not indented:
                continue
            stripped = line.strip()
            if in_pre or stripped.startswith("<pre"):
                found.append((number, line))
                in_pre = "</pre>" not in line
            elif not stripped:
                blank = True
                continue
            elif LIST_ITEM.match(line):
                in_list, in_block = True, False
            elif indent_code(line) and not in_list and (blank or in_block):
                found.append((number, line))
                in_block = True
            else:
                in_list = in_list and line.startswith((" ", "\t"))
                in_block = False
            blank = False
            continue
        if match and match["mark"].startswith(fence[0]) and not match["info"].strip():
            fence = None
            continue
        if first and line.strip():
            first = False
            if fence[1] in OUTPUT_TAGS and line.lstrip().startswith(("$ ", "PS> ")):
                fence = (fence[0], "console")
        tag = fence[1]
        if tag in OUTPUT_TAGS:
            continue
        if tag in RUSTDOC_TAGS and (
            line.strip() == "#" or line.lstrip().startswith("# ")
        ):
            continue
        if tag in {"console", "shell-session", "pycon"}:
            prompt = line.lstrip().startswith(("$ ", "PS> ", ">>> ", "... "))
            if not (prompt or continued):
                continue
            quote = open_quote(line, quote if continued else None)
            continued = quote is not None or line.rstrip().endswith(("\\", "`"))
        found.append((number, line))
    return found


def rest_block_lines(text: str) -> list[tuple[int, str]]:
    r"""Return the lines of reST literal and code-directive blocks.

    A block is every line indented past the line that opens it, up to the
    next non-blank line at or left of that indent.

    >>> doc = "Use it::\n\n    pane.run(1)\n\nProse.\n.. code-block:: sh\n\n   ls\n"
    >>> [line for _, line in rest_block_lines(doc)]
    ['    pane.run(1)', '   ls']
    >>> rest_block_lines(".. toctree::\n\n   capture\n")
    []
    """
    found: list[tuple[int, str]] = []
    opener: int | None = None
    for number, line in enumerate(text.splitlines(), 1):
        indent = len(line) - len(line.lstrip())
        if opener is not None and line.strip():
            if indent > opener:
                found.append((number, line))
                continue
            opener = None
        if REST_BLOCK.search(line) and not line.lstrip().startswith((">>>", "...")):
            opener = indent
    return found


def doc_comment_lines(text: str, suffix: str) -> list[tuple[int, str]]:
    r"""Return code inside doc comments: fences and ``{@code}``/``<code>``.

    Python docstrings contribute their doctest lines and reST literal
    blocks, Go doc comments their tab-indented code blocks, and Julia
    docstrings their fences. A fence
    tagged as output is skipped, and a plain ``//`` comment is not a doc
    comment.

    >>> src = "\n".join([
    ...     "/// ```", "/// let wide = 1;", "/// # hidden();", "/// ```",
    ...     "/// ```text", "/// output", "/// ```",
    ...     "// ```", "// not a doc comment", "// ```",
    ...     "/// prose is not code", "fn f() {}",
    ... ])
    >>> [line for _, line in doc_comment_lines(src, ".rs")]
    ['/// let wide = 1;']
    >>> cs = "/// <code>\n/// var x = 1;\n/// </code>\n/// prose"
    >>> [line for _, line in doc_comment_lines(cs, ".cs")]
    ['/// var x = 1;']
    >>> py = '    >>> pane.send_keys("x")\n    plain prose'
    >>> [line for _, line in doc_comment_lines(py, ".py")]
    ['    >>> pane.send_keys("x")']
    >>> literal = '    Example::\n\n        server.cmd("x")\n    Prose.'
    >>> [line for _, line in doc_comment_lines(literal, ".py")]
    ['        server.cmd("x")']
    >>> go = "// Run starts a pane:\n//\tpane.Run(ctx)\nfunc Run() {}"
    >>> [line for _, line in doc_comment_lines(go, ".go")]
    ['//\tpane.Run(ctx)']
    """
    if suffix == ".jl":
        return markdown_lines(text, indented=False)
    if suffix == ".py":
        doctests = [
            (number, line)
            for number, line in enumerate(text.splitlines(), 1)
            if line.lstrip().startswith((">>> ", "... "))
        ]
        return sorted(set(doctests + rest_block_lines(text)))
    found: list[tuple[int, str]] = []
    inside = False
    output = False
    for number, line in enumerate(text.splitlines(), 1):
        if suffix == ".go":
            if line.lstrip().startswith("//\t"):
                found.append((number, line))
            continue
        if BLOCK_OPEN.search(line):
            inside, output = not BLOCK_CLOSE.search(line), False
            continue
        prefix = DOC_LINE.match(line)
        if prefix is None:
            inside = False
            continue
        body = line[prefix.end() :]
        fence = FENCE.match(body)
        if fence:
            inside = not inside
            output = inside and fence_tag(fence["info"]) in OUTPUT_TAGS
            continue
        if inside and BLOCK_CLOSE.search(body):
            inside = False
            continue
        hidden = suffix == ".rs" and (body == "#" or body.startswith("# "))
        if inside and not output and not hidden:
            found.append((number, line))
    return found


def glob_regex(pattern: str) -> re.Pattern[str]:
    """Translate a glob: ``*`` stays within a directory, ``**`` spans them.

    >>> bool(glob_regex("docs/*.md").fullmatch("docs/plans/a.md"))
    False
    >>> bool(glob_regex("docs/**/*.md").fullmatch("docs/a.md"))
    True
    """
    out = []
    i = 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile("".join(out))


def matches(path: str, patterns: list[str]) -> bool:
    """Return whether a repository-relative path matches any glob.

    >>> matches("README.md", ["**/README.md"])
    True
    >>> matches("docs/a/b.md", ["docs/**/*.md"])
    True
    >>> matches("src/a.rs", ["docs/**/*.md"])
    False
    """
    return any(glob_regex(pattern).fullmatch(path) for pattern in patterns)


def config_problems(config: dict[str, t.Any], files: list[str]) -> list[str]:
    """Return configuration mistakes that would silently weaken the check.

    >>> config = {"widht": 80, "markdown": ["nope/*.md"], "allow_ceiling": 0}
    >>> config_problems(config, ["README.md"])
    ['unknown key: widht', 'markdown glob matches no tracked file: nope/*.md']
    >>> config = {"allow": [{"path": "a", "line": "b"}], "allow_ceiling": 1}
    >>> config_problems(config, ["a"])
    ["allow entry for a has no reason: 'b'"]
    >>> for problem in config_problems({"width": 100, "exclude": ["a"]}, ["a"]):
    ...     print(problem)
    width is 100; the shared rule is 80
    exclude entry has no reason: 'a'
    allow_ceiling is missing; set it to 0, the number of allow entries
    >>> excluded = {"glob": "notes/*.md", "reason": "drafts"}
    >>> config = {"markdown": ["*.md"], "exclude": [excluded], "allow_ceiling": 0}
    >>> config_problems(config, ["a.md", "notes/b.md"])
    ['exclude glob matches no checked file: notes/*.md']
    >>> config = {"sources": ["examples/*.go"], "allow_ceiling": 0}
    >>> files = ["examples/a.go", "examples/go.mod"]
    >>> config_problems(config, files)[0].split(";")[0]
    'examples/go.mod is under examples/ but neither checked nor excluded'
    >>> mod = {"glob": "examples/go.mod", "reason": "module file"}
    >>> config_problems(dict(config, exclude=[mod]), files)
    []
    """
    problems = [f"unknown key: {key}" for key in sorted(set(config) - KEYS)]
    if config.get("width", 80) != 80:
        problems.append(f"width is {config['width']}; the shared rule is 80")
    globs = [(key, pattern) for key in GLOB_KEYS for pattern in config.get(key, [])]
    problems.extend(
        f"{key} glob matches no tracked file: {pattern}"
        for key, pattern in globs
        if not any(glob_regex(pattern).fullmatch(path) for path in files)
    )
    checked = [path for path in files if matches(path, [p for _, p in globs])]
    examples = [path for path in files if EXAMPLE_DIR.search(path)]
    excluded: list[str] = []
    for entry in config.get("exclude", []):
        if not isinstance(entry, dict) or not str(entry.get("reason", "")).strip():
            problems.append(f"exclude entry has no reason: {entry!r}")
            continue
        excluded.append(entry.get("glob", ""))
        pattern = glob_regex(entry.get("glob", ""))
        if not any(pattern.fullmatch(path) for path in checked + examples):
            problems.append(f"exclude glob matches no checked file: {entry['glob']}")
    problems.extend(
        f"{path} is under examples/ but neither checked nor excluded; add it to "
        "sources, or to [[exclude]] with a reason"
        for path in examples
        if path not in checked and not matches(path, excluded)
    )
    count = len(config.get("allow", []))
    ceiling = config.get("allow_ceiling")
    if ceiling is None:
        problems.append(
            f"allow_ceiling is missing; set it to {count}, the number of allow entries"
        )
    elif count > int(ceiling):
        problems.append(
            f"{count} allow entries exceed allow_ceiling {ceiling}; shorten the "
            "new line, or raise the ceiling in a change that gives the reason"
        )
    elif count < int(ceiling):
        problems.append(
            f"allow_ceiling {ceiling} is above the {count} allow entries; lower it"
        )
    problems.extend(
        f"allow entry for {entry.get('path')} has no reason: {entry.get('line')!r}"
        for entry in config.get("allow", [])
        if not str(entry.get("reason", "")).strip()
    )
    return problems


def copy_problems(root: pathlib.Path, config: dict[str, t.Any]) -> list[str]:
    """Return formatter copies that drifted from their root file.

    A copy may differ from its root only on lines naming the width key.
    """
    problems = []
    for pair in config.get("formatter_copies", []):

        def kept(path: str, key: str = pair["key"]) -> list[str]:
            lines = (root / path).read_text(encoding="utf-8").splitlines()
            return [line for line in lines if key not in line]

        if kept(pair["copy"]) != kept(pair["root"]):
            problems.append(
                f"{pair['copy']} differs from {pair['root']} beyond {pair['key']}"
            )
    return problems


def check(
    root: pathlib.Path, config: dict[str, t.Any], files: list[str]
) -> tuple[list[Finding], list[dict[str, str]]]:
    """Return lines over the width, and allow entries that matched nothing."""
    width = int(config.get("width", 80))
    tab_width = int(config.get("tab_width", 4))
    exclude = [entry["glob"] for entry in config.get("exclude", [])]
    allow = config.get("allow", [])
    allowed = {(entry["path"], entry["line"]) for entry in allow}
    used: set[tuple[str, str]] = set()
    findings: list[Finding] = []
    for path in files:
        if matches(path, exclude):
            continue
        suffix = pathlib.PurePosixPath(path).suffix
        if matches(path, config.get("markdown", [])):
            kind = "markdown"
        elif matches(path, config.get("sources", [])):
            kind = "source"
        elif matches(path, config.get("doc_comments", [])):
            kind = "doc"
        else:
            continue
        try:
            text = (root / path).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if kind == "markdown" and suffix == ".rst":
            lines = rest_block_lines(text)
        elif kind == "markdown":
            lines = markdown_lines(text)
        elif kind == "doc":
            lines = doc_comment_lines(text, suffix)
        else:
            lines = list(enumerate(text.splitlines(), 1))
        for number, line in lines:
            shown = line.expandtabs(tab_width).rstrip()
            wide = columns(shown)
            if wide <= width or is_url(shown) or HIDDEN.match(shown):
                continue
            key = (path, line.rstrip())
            if key in allowed:
                used.add(key)
                continue
            findings.append(Finding(path, number, wide, width))
    stale = [entry for entry in allow if (entry["path"], entry["line"]) not in used]
    return findings, stale


def tracked_files(root: pathlib.Path) -> list[str]:
    """Return the files git tracks, as POSIX paths relative to the root."""
    output = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [path for path in output.split("\0") if path]


def writing_path(root: pathlib.Path) -> pathlib.Path | None:
    """Return the WRITING.md that carries the shared section, if any."""
    for name in (".github/WRITING.md", "WRITING.md"):
        path = root / name
        if path.is_file() and SHARED.search(path.read_text(encoding="utf-8")):
            return path
    return None


def slug(heading: str) -> str:
    """Return the anchor GitHub gives a Markdown heading.

    >>> slug("Documented examples that run")
    'documented-examples-that-run'
    >>> slug("Reaching 80")
    'reaching-80'
    """
    text = re.sub(r"[^\w\- ]", "", heading.strip().lower())
    return text.replace(" ", "-")


def routing_problems(root: pathlib.Path) -> list[str]:
    """Return a problem unless AGENTS.md links the shared section's heading.

    The heading is the last one of level one or two above the shared
    markers: the section an agent routed from AGENTS.md should land in.
    """
    writing = writing_path(root)
    if writing is None:
        return []
    text = writing.read_text(encoding="utf-8")
    above = text[: text.index("<!-- shared:examples -->")]
    headings = [m[2] for m in HEADING.finditer(above) if len(m[1]) <= 2]
    if not headings:
        return [f"{writing.name}: no heading above the shared section"]
    anchor = f"WRITING.md#{slug(headings[-1])}"
    agents = root / "AGENTS.md"
    if agents.is_file() and anchor in agents.read_text(encoding="utf-8"):
        return []
    return [f"AGENTS.md does not link {anchor}, the section with the example rules"]


def port_block_problems(text: str) -> list[str]:
    r"""Return how a WRITING.md's ``### In this repository`` block strays.

    >>> labels = "\n".join(label + " x" for label in PORT_LABELS)
    >>> block = f"### In this repository\n\n{labels}\n\nBad, over 80:\n\nGood, named:\n"
    >>> port_block_problems(block)
    []
    >>> port_block_problems(block.replace("- **Not formatted:**", "- **Other:**"))
    ['In this repository: no "- **Not formatted:**" bullet in its place']
    >>> port_block_problems("## Examples\n")
    ['no "### In this repository" block']
    """
    match = PORT_BLOCK.search(text)
    if match is None:
        return ['no "### In this repository" block']
    lines = match["body"].splitlines()
    problems = []
    at = 0
    for label in PORT_LABELS:
        found = next((i for i, line in enumerate(lines) if line.startswith(label)), -1)
        if found < at:
            problems.append(f'In this repository: no "{label}" bullet in its place')
        else:
            at = found
    for example in ("Bad, over 80", "Good"):
        count = sum(line.startswith(example) for line in lines[at:])
        if count != 1:
            problems.append(f'In this repository: {count} "{example}" examples, want 1')
    return problems


def digests(root: pathlib.Path) -> list[str]:
    """Return ``checker <sha256>`` and ``shared <sha256>`` lines.

    The shared digest covers the text between the markers in WRITING.md;
    ``shared missing`` means no WRITING.md carries them.
    """
    checker = hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()
    shared = "missing"
    writing = writing_path(root)
    if writing is not None:
        match = SHARED.search(writing.read_text(encoding="utf-8"))
        if match:
            shared = hashlib.sha256(match["body"].encode()).hexdigest()
    return [f"checker {checker}", f"shared {shared}"]


def digest_problems(root: pathlib.Path, config: dict[str, t.Any]) -> list[str]:
    """Return digests that differ from the ones the configuration records.

    Both files are the same in every port, so the message sends the reader to
    all of them rather than to this repository's digest.
    """
    actual = dict(line.split(" ", 1) for line in digests(root))
    names = {"checker": "this checker", "shared": "WRITING.md's shared section"}
    here, top = pathlib.Path(__file__).resolve(), root.resolve()
    script = here.relative_to(top) if here.is_relative_to(top) else here.name
    return [
        f"{names[name]} has digest {actual[name][:12]}, but {name}_digest records "
        f"{config[name + '_digest'][:12]}. Every libtmux port carries the same "
        f"file: change it in each repository listed in {PORTS}, then run "
        f"`python3 {script} --digest` in each and record both lines in its config"
        for name in ("checker", "shared")
        if name + "_digest" in config and actual[name] != config[name + "_digest"]
    ]


def self_test() -> int:
    """Run the doctests above, plus planted failures and clean controls."""
    import doctest
    import tempfile

    failures, _ = doctest.testmod(sys.modules[__name__])

    def expect(condition: bool, message: str) -> None:
        nonlocal failures
        if not condition:
            print(f"self-test: {message}", file=sys.stderr)
            failures += 1

    with tempfile.TemporaryDirectory() as scratch:
        root = pathlib.Path(scratch)
        wide = "let total = " + " + ".join(["value"] * 12) + ";"
        (root / "README.md").write_text(f"```rust\n{wide}\n```\n")
        config: dict[str, t.Any] = {"width": 60, "markdown": ["README.md"]}
        planted, _ = check(root, config, ["README.md"])
        expect(len(planted) == 1, "a planted wide line was not reported")
        config["allow"] = [{"path": "README.md", "line": wide, "reason": "test"}]
        clean, stale = check(root, config, ["README.md"])
        expect(not clean and not stale, "an allowed line was reported")
        config["allow"].append({"path": "README.md", "line": "gone", "reason": "x"})
        _, stale = check(root, config, ["README.md"])
        expect(len(stale) == 1, "a stale allow entry was not reported")
        tabbed = "\t" + wide
        (root / "main.go").write_text(tabbed + "\n")
        config = {"width": 60, "sources": ["*.go"]}
        config["allow"] = [{"path": "main.go", "line": tabbed, "reason": "test"}]
        clean, stale = check(root, config, ["main.go"])
        expect(not clean and not stale, "a raw tabbed allow entry did not match")
        (root / "fmt.toml").write_text("edition = 1\nmax_width = 100\n")
        (root / "copy.toml").write_text("edition = 1\nmax_width = 80\n")
        pair = {"copy": "copy.toml", "root": "fmt.toml", "key": "max_width"}
        copies = {"formatter_copies": [pair]}
        expect(not copy_problems(root, copies), "a width-only copy was reported")
        (root / "copy.toml").write_text("edition = 2\nmax_width = 80\n")
        expect(bool(copy_problems(root, copies)), "a drifted copy was not reported")
        expect(digests(root)[1] == "shared missing", "a missing section was digested")
        shared = "<!-- shared:examples -->\nrule\n<!-- /shared:examples -->\n"
        (root / "WRITING.md").write_text(shared)
        expect(digests(root)[1] != "shared missing", "a shared section was missed")
        recorded = {"shared_digest": "0" * 64}
        expect(bool(digest_problems(root, recorded)), "a digest change was missed")
        shared_now = digests(root)[1].split(" ", 1)[1]
        recorded = {"shared_digest": shared_now}
        expect(not digest_problems(root, recorded), "a matching digest was reported")
        (root / "WRITING.md").write_text("## Examples\n\n" + shared)
        expect(bool(routing_problems(root)), "a missing AGENTS.md link passed")
        (root / "AGENTS.md").write_text("Code examples: WRITING.md#examples\n")
        expect(not routing_problems(root), "a linked section was reported")
        entry = {"path": "a", "line": "b", "reason": "c"}
        ceiling: dict[str, t.Any] = {"allow": [entry, entry], "allow_ceiling": 1}
        expect(bool(config_problems(ceiling, ["a"])), "a grown allow list passed")
        ceiling = {"allow": [entry], "allow_ceiling": 2}
        expect(bool(config_problems(ceiling, ["a"])), "a shrunk list kept its ceiling")
        ceiling = {"allow": [entry], "allow_ceiling": 1}
        expect(not config_problems(ceiling, ["a"]), "an exact ceiling was reported")
    print("self-test:", "failed" if failures else "ok")
    return 1 if failures else 0


def main(argv: list[str] | None = None) -> int:
    """Check the repository, or run the self-test."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--self-test", action="store_true", help="prove the checker can fail"
    )
    parser.add_argument(
        "--digest",
        action="store_true",
        help="print digests of this checker and the shared WRITING.md section",
    )
    parser.add_argument(
        "--root", type=pathlib.Path, help="repository root (default: git toplevel)"
    )
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    root = args.root or pathlib.Path(
        subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    )
    if args.digest:
        for line in digests(root):
            print(line)
        return 0
    config = tomllib.loads((root / CONFIG).read_text(encoding="utf-8"))
    files = tracked_files(root)
    writing = writing_path(root)
    problems = (
        config_problems(config, files)
        + copy_problems(root, config)
        + digest_problems(root, config)
        + routing_problems(root)
        + (port_block_problems(writing.read_text(encoding="utf-8")) if writing else [])
    )
    findings, stale = check(root, config, files)
    annotate = os.environ.get("GITHUB_ACTIONS") == "true"
    for problem in problems:
        print(f"{CONFIG}: {problem}")
    for finding in findings:
        print(finding)
        if annotate:
            print(
                f"::error file={finding.path},line={finding.number}::"
                f"{finding.columns} columns > {finding.width}"
            )
    for entry in stale:
        print(f"{entry['path']}: allow entry matches no line: {entry['line']!r}")
    if problems or findings or stale:
        rules = writing.relative_to(root).as_posix() if writing else "WRITING.md"
        print(
            f"{len(problems)} config problems, {len(findings)} wide lines, "
            f"{len(stale)} stale allow entries."
        )
        if findings:
            print(
                "Fix a wide line by changing the code, not the line breaks: "
                f"{rules}#reaching-80"
            )
        if stale:
            print("Delete each stale allow entry and lower allow_ceiling to match.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
