#!/usr/bin/env python3
"""Plan the Linux CI matrix from eng/ci/matrix.json and the event.

Every push and pull request ran the whole table (nine tmux versions on two
PowerShell versions, and four refusal lanes), although the oldest and newest
release bracket what the rest do. This script decides what a run covers, so
the workflow lists no version and the manifest is the one table.

Scopes:

- `edges`: the oldest and newest supported release, on every PowerShell
  version. The default for a push, a pull request and a dispatch.
- `full`: the whole table, tmux master, and the refusal lanes. A dispatch that
  asks, and the run a Gallery release is bound to.
- `custom`: only the tmux versions, tags, branches or commits a dispatch names.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
import typing as t

MANIFEST = pathlib.Path(__file__).with_name("matrix.json")

SCOPES = ("edges", "full", "custom")
TMATE_MODES = ("off", "before-tests", "on-failure")
EVENTS = ("push", "pull_request", "workflow_dispatch")

# Every item of `tmux-ref` is checked against this before it reaches a shell
# or a git command.
REF_PATTERN = re.compile(r"^[A-Za-z0-9._/-]{1,64}$")
ABBREVIATED_SHA = re.compile(r"^[0-9a-f]{7,39}$")

# A mistyped list should fail rather than fan out into a huge matrix.
MAX_REFS = 8

# The plan, the package build and the gate, which every run has.
FIXED_JOBS = 3

# Jobs named in the workflow that no matrix produces.
PLAN_JOB = "plan"
PACKAGE_JOB = "build and pack PowerShell modules"
GATE_JOB = "powershell gate"


class PlanError(ValueError):
    """The inputs name a run that cannot or must not happen."""


def load_manifest(path: pathlib.Path = MANIFEST) -> dict[str, t.Any]:
    """Read the table the plan is measured against."""
    with path.open(encoding="utf-8") as handle:
        return t.cast(dict[str, t.Any], json.load(handle))


def split_list(value: str) -> list[str]:
    """Split a comma-separated input, dropping blanks and repeats."""
    items: list[str] = []
    for each in value.split(","):
        item = each.strip()
        if item and item not in items:
            items.append(item)
    return items


def resolve_scope(event: str, scope: str) -> str:
    """Decide how much of the table a run covers."""
    if scope:
        if scope not in SCOPES:
            raise PlanError(f"scope must be one of {', '.join(SCOPES)}, not {scope!r}")
        return scope
    if event in EVENTS:
        return "edges"
    raise PlanError(f"no scope is defined for the {event!r} event")


def edge_versions(supported: list[str]) -> list[str]:
    """Pick the oldest and the newest supported release."""
    return list(dict.fromkeys([*supported[:1], *supported[-1:]]))


def check_scope_inputs(scope: str, tmux_ref: str) -> None:
    """Refuse a list of refs that the scope would silently ignore."""
    if tmux_ref and scope != "custom":
        raise PlanError("tmux-ref is only used with scope custom")


def require_cells(cells: list[dict[str, str]]) -> None:
    """Refuse a plan with no test leg, which GitHub would reject anyway."""
    if not cells:
        raise PlanError("the plan has no test leg")


def select_powershell(manifest: dict[str, t.Any], requested: str) -> list[dict[str, str]]:
    """Narrow the PowerShell versions, or keep every one when none is asked for."""
    available = {each["version"]: each for each in manifest["powershell"]}
    chosen = split_list(requested)
    for version in chosen:
        if version not in available:
            raise PlanError(
                f"pwsh must name versions from {', '.join(available)}, not {version!r}"
            )
    return [available[version] for version in chosen] or list(manifest["powershell"])


def check_ref(item: str) -> str:
    """Refuse a tmux ref that is malformed or could be read as an option."""
    if not REF_PATTERN.fullmatch(item):
        raise PlanError(f"tmux-ref item {item!r} must match {REF_PATTERN.pattern}")
    if item.startswith("-") or ".." in item or item.endswith((".lock", "/")):
        raise PlanError(f"tmux-ref item {item!r} is not a usable git ref")
    if ABBREVIATED_SHA.fullmatch(item):
        raise PlanError(
            f"tmux-ref item {item!r} looks like an abbreviated commit; "
            "give the full 40-hex SHA"
        )
    return item


def custom_refs(tmux_ref: str) -> list[str]:
    """Validate the refs a custom run was asked to build."""
    items = split_list(tmux_ref)
    if not items:
        raise PlanError("scope custom needs tmux-ref, a comma-separated list of tmux refs")
    if len(items) > MAX_REFS:
        raise PlanError(f"tmux-ref names {len(items)} refs; at most {MAX_REFS} fit one run")
    return [check_ref(item) for item in items]


def tmux_entries(manifest: dict[str, t.Any], scope: str, tmux_ref: str) -> list[dict[str, str]]:
    """Choose the tmux builds a run covers.

    A name in the table keeps its pinned commit and its build path. Any other
    ref is resolved to a commit and built from source when the job runs.
    """
    table = {each["tmux"]: each for each in [*manifest["supported"], *manifest["development"]]}
    supported = [each["tmux"] for each in manifest["supported"]]
    if scope == "full":
        return list(table.values())
    if scope == "edges":
        return [table[name] for name in edge_versions(supported)]
    return [
        table.get(item, {"tmux": item, "commit": "", "build": "ref"})
        for item in custom_refs(tmux_ref)
    ]


def cell(powershell: dict[str, str], tmux: dict[str, str]) -> dict[str, str]:
    """Describe one test leg."""
    return {
        "powershell": powershell["version"],
        "powershell_sha256": powershell["sha256"],
        "tmux": tmux["tmux"],
        "tmux_commit": tmux["commit"],
        "build": tmux["build"],
        # Artifact names cannot hold a slash, which a branch name can.
        "slug": tmux["tmux"].replace("/", "-"),
        "mcp": "false",
        "tmate": "off",
    }


def mark_mcp(manifest: dict[str, t.Any], cells: list[dict[str, str]]) -> None:
    """Run the MCP discovery check on the edge releases, on the first PowerShell.

    The check does not depend on the tmux version, so it follows the edges
    instead of a middle release, and it runs once per edge.
    """
    first = manifest["powershell"][0]["version"]
    edges = edge_versions([each["tmux"] for each in manifest["supported"]])
    for each in cells:
        each["mcp"] = "true" if each["powershell"] == first and each["tmux"] in edges else "false"


def select_lanes(manifest: dict[str, t.Any], scope: str) -> dict[str, list[dict[str, str]]]:
    """Pick the refusal lanes, which run on the first PowerShell version."""
    if scope != "full":
        return {"reject": [], "old_daemon": []}
    base = manifest["powershell"][0]
    client = manifest["supported"][0]
    shared = {"powershell": base["version"], "powershell_sha256": base["sha256"]}
    return {
        "reject": [
            {**shared, "tmux": each["tmux"], "tmux_commit": each["commit"]}
            for each in manifest["rejected"]
        ],
        "old_daemon": [
            {
                **shared,
                "tmux": each["tmux"],
                "tmux_commit": each["commit"],
                "client_tmux": client["tmux"],
                "client_commit": client["commit"],
            }
            for each in manifest["oldDaemon"]
        ],
    }


def assign_tmate(
    event: str,
    mode: str,
    cells: list[dict[str, str]],
    lanes: dict[str, list[dict[str, str]]],
) -> None:
    """Give exactly one leg the debug session, or fail."""
    if mode not in TMATE_MODES:
        raise PlanError(f"tmate must be one of {', '.join(TMATE_MODES)}, not {mode!r}")
    if mode == "off":
        return
    if event != "workflow_dispatch":
        raise PlanError("tmate is only available on a workflow_dispatch run")
    legs = len(cells) + sum(len(each) for each in lanes.values())
    if legs != 1:
        raise PlanError(
            f"tmate needs exactly one leg and this run has {legs}; "
            "use scope custom with one tmux-ref and one pwsh version"
        )
    cells[0]["tmate"] = mode


def plan(
    manifest: dict[str, t.Any],
    *,
    event: str,
    scope: str = "",
    tmux_ref: str = "",
    pwsh: str = "",
    tmate: str = "",
) -> dict[str, t.Any]:
    """Return the matrix, the lanes and the job count for one run."""
    chosen = resolve_scope(event, scope)
    check_scope_inputs(chosen, tmux_ref)

    cells = [
        cell(powershell, tmux)
        for tmux in tmux_entries(manifest, chosen, tmux_ref)
        for powershell in select_powershell(manifest, pwsh)
    ]
    require_cells(cells)
    mark_mcp(manifest, cells)
    lanes = select_lanes(manifest, chosen)
    assign_tmate(event, tmate or "off", cells, lanes)

    return {
        "scope": chosen,
        "matrix": {"include": cells},
        "reject": lanes["reject"],
        "old_daemon": lanes["old_daemon"],
        "expected_jobs": FIXED_JOBS + len(cells) + len(lanes["reject"]) + len(lanes["old_daemon"]),
    }


def job_names(result: dict[str, t.Any]) -> set[str]:
    """Name the jobs a plan produces, as the workflow names them."""
    names = {PLAN_JOB, PACKAGE_JOB, GATE_JOB}
    names |= {
        f"PowerShell {each['powershell']} / tmux {each['tmux']}"
        for each in result["matrix"]["include"]
    }
    names |= {
        f"PowerShell {each['powershell']} / tmux {each['tmux']} rejected"
        for each in result["reject"]
    }
    names |= {
        f"PowerShell {each['powershell']} / tmux {each['tmux']} "
        f"daemon behind a {each['client_tmux']} client"
        for each in result["old_daemon"]
    }
    return names


def full_job_names(manifest: dict[str, t.Any]) -> set[str]:
    """Name every job of a full-scope run, which is what a release is bound to."""
    return job_names(plan(manifest, event="workflow_dispatch", scope="full"))


def check_needs(needs: dict[str, t.Any]) -> list[str]:
    """Find the jobs that stop the gate from passing.

    The matrix and the package build must succeed. A refusal lane must succeed
    when the plan scheduled it and be skipped when the plan left it out, so a
    skipped lane that was planned cannot pass.
    """
    problems = []
    for job in (PLAN_JOB, "port", "matrix"):
        result = needs.get(job, {}).get("result")
        if result != "success":
            problems.append(f"{job} finished {result or 'missing'}, not success")
    outputs = needs.get(PLAN_JOB, {}).get("outputs", {})
    for job, output in (("reject", "run_reject"), ("reject-old-daemon", "run_old_daemon")):
        wanted = "success" if outputs.get(output) == "true" else "skipped"
        result = needs.get(job, {}).get("result")
        if result != wanted:
            problems.append(f"{job} finished {result or 'missing'}, not {wanted}")
    return problems


def summary(result: dict[str, t.Any]) -> str:
    """Describe a plan for the job summary."""
    lines = [
        f"### tmux plan: {result['scope']}",
        "",
        f"Expected jobs in this workflow: {result['expected_jobs']}",
        "",
    ]
    lines += [
        f"- PowerShell {each['powershell']} with tmux {each['tmux']} ({each['build']})"
        for each in result["matrix"]["include"]
    ]
    lines += [f"- tmux {each['tmux']} is refused" for each in result["reject"]]
    lines += [f"- tmux {each['tmux']} daemon is refused" for each in result["old_daemon"]]
    return "\n".join(lines) + "\n"


def outputs(result: dict[str, t.Any]) -> dict[str, str]:
    """Flatten a plan into single-line workflow outputs."""
    compact = {"separators": (",", ":")}
    return {
        "scope": result["scope"],
        "matrix": json.dumps(result["matrix"], **compact),
        "reject": json.dumps({"include": result["reject"]}, **compact),
        "run_reject": "true" if result["reject"] else "false",
        "old_daemon": json.dumps({"include": result["old_daemon"]}, **compact),
        "run_old_daemon": "true" if result["old_daemon"] else "false",
        "expected_jobs": str(result["expected_jobs"]),
    }


def main(argv: list[str] | None = None) -> int:
    """Print the plan for a workflow, or check the jobs that finished."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)

    planner = commands.add_parser("plan", help="plan the matrix for one event")
    planner.add_argument("--manifest", type=pathlib.Path, default=MANIFEST)
    planner.add_argument("--event", required=True, help="github.event_name")
    planner.add_argument("--scope", default="", help="edges, full or custom")
    planner.add_argument("--tmux-ref", default="", help="comma-separated tmux refs")
    planner.add_argument("--pwsh", default="", help="comma-separated PowerShell versions")
    planner.add_argument("--tmate", default="", help="off, before-tests or on-failure")
    planner.add_argument("--github-output", type=pathlib.Path, help="the GITHUB_OUTPUT file")
    planner.add_argument("--summary", type=pathlib.Path, help="the GITHUB_STEP_SUMMARY file")

    commands.add_parser("gate", help="check the NEEDS environment variable")
    arguments = parser.parse_args(argv)

    if arguments.command == "gate":
        problems = check_needs(json.loads(os.environ.get("NEEDS", "{}")))
        for problem in problems:
            print(f"gate: {problem}", file=sys.stderr)
        return 1 if problems else 0

    try:
        result = plan(
            load_manifest(arguments.manifest),
            event=arguments.event,
            scope=arguments.scope,
            tmux_ref=arguments.tmux_ref,
            pwsh=arguments.pwsh,
            tmate=arguments.tmate,
        )
    except PlanError as error:
        print(f"plan: {error}", file=sys.stderr)
        return 1

    print(json.dumps(result, indent=2))
    if arguments.github_output:
        with arguments.github_output.open("a", encoding="utf-8") as handle:
            for key, value in outputs(result).items():
                handle.write(f"{key}={value}\n")
    if arguments.summary:
        with arguments.summary.open("a", encoding="utf-8") as handle:
            handle.write(summary(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
