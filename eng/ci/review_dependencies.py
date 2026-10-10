#!/usr/bin/env python3
"""Use one source-pinned CORE review build in an isolated CI checkout."""

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
SHARED = ("LibTmux", "LibTmux.Query.Json", "LibTmux.Workspace")
LOCKS = (
    Path("src/LibTmux.PowerShell/packages.lock.json"),
    Path("src/LibTmux.Workspace.PowerShell/packages.lock.json"),
)
BASELINE_INPUTS = (Path("Directory.Packages.props"), *LOCKS)


def package_versions(root: Path) -> tuple[ET.ElementTree, dict[str, ET.Element]]:
    tree = ET.parse(root / "Directory.Packages.props")
    found: dict[str, ET.Element] = {}
    for element in tree.iter("PackageVersion"):
        name = element.get("Include")
        if name in SHARED:
            if name in found:
                raise ValueError(f"duplicate shared dependency pin: {name}")
            found[name] = element
    if set(found) != set(SHARED):
        raise ValueError("all three shared dependency pins are required")
    values = {element.get("Version") for element in found.values()}
    if len(values) != 1 or not re.fullmatch(r"\[[^\[\]]+\]", next(iter(values)) or ""):
        raise ValueError("shared dependency pins must have matching exact versions")
    return tree, found


def review_version(root: Path, run_id: int, attempt: int) -> str:
    if not 1 <= run_id <= 2**63 - 1 or not 1 <= attempt <= 2**31 - 1:
        raise ValueError("run ID must fit a positive Int64 and attempt a positive Int32")
    _, found = package_versions(root)
    base = found[SHARED[0]].get("Version")[1:-1]
    if not re.fullmatch(r"\d+\.\d+\.\d+-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*", base):
        raise ValueError("original shared dependency pin must be a prerelease")
    # Repeated review builds must not grow the dependency pin beyond NuGet paths.
    return f"0.0.0-ci.{run_id}.{attempt}"


def validate_review_version(version: str) -> None:
    match = re.fullmatch(r"0\.0\.0-ci\.([1-9][0-9]{0,18})\.([1-9][0-9]{0,9})", version)
    if match is None or int(match[1]) > 2**63 - 1 or int(match[2]) > 2**31 - 1:
        raise ValueError("CI review version must use bounded 0.0.0-ci.<run-id>.<attempt>")


def prepare(root: Path, version: str, baseline: Path) -> None:
    tree, found = package_versions(root)
    base = found[SHARED[0]].get("Version")[1:-1]
    validate_review_version(version)
    if version == base:
        raise ValueError("CI review version must differ from the original dependency pin")
    if baseline.exists():
        raise ValueError("CI lock baseline already exists")
    for relative in LOCKS:
        if not (root / relative).is_file():
            raise ValueError(f"missing committed dependency lock: {relative}")
    baseline.mkdir(parents=True)
    records = {}
    for relative in BASELINE_INPUTS:
        target = baseline / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / relative, target)
        records[relative.as_posix()] = hashlib.sha256(target.read_bytes()).hexdigest()
    (baseline / "baseline.json").write_text(json.dumps({
        "original_version": base, "review_version": version, "files": records,
    }, indent=2) + "\n")
    for element in found.values():
        element.set("Version", f"[{version}]")
    ET.indent(tree, space="  ")
    props = root / "Directory.Packages.props"
    tree.write(props, encoding="unicode")
    with props.open("a") as output:
        output.write("\n")


def replace_version_tokens(requirement: str, source_version: str, target_version: str) -> str:
    parts = re.split(r"([\[\](),\s]+)", requirement)
    return "".join(target_version if part == source_version else part for part in parts)


def normalized_lock(data: dict, source_version: str, target_version: str) -> dict:
    result = copy.deepcopy(data)
    for packages in result.get("dependencies", {}).values():
        for name, record in packages.items():
            if name in SHARED:
                record.pop("contentHash", None)
                if record.get("resolved") == source_version:
                    record["resolved"] = target_version
                if "requested" in record:
                    record["requested"] = replace_version_tokens(
                        record["requested"], source_version, target_version,
                    )
            for dependency, requirement in record.get("dependencies", {}).items():
                if dependency in SHARED:
                    record["dependencies"][dependency] = replace_version_tokens(
                        requirement, source_version, target_version,
                    )
    return result


def verify(root: Path, version: str, baseline: Path) -> None:
    validate_review_version(version)
    _, found = package_versions(root)
    if found[SHARED[0]].get("Version") != f"[{version}]":
        raise ValueError("CI dependency pins differ from the built review version")
    saved = json.loads((baseline / "baseline.json").read_text())
    records = saved.get("files", {})
    if set(records) != {path.as_posix() for path in BASELINE_INPUTS}:
        raise ValueError("CI baseline does not record the original dependency inputs")
    for relative in BASELINE_INPUTS:
        path = baseline / relative
        if (path.is_symlink() or not path.is_file()
                or hashlib.sha256(path.read_bytes()).hexdigest() != records[relative.as_posix()]):
            raise ValueError(f"original dependency baseline changed: {relative}")
    _, original = package_versions(baseline)
    base = original[SHARED[0]].get("Version")[1:-1]
    if saved.get("review_version") != version or saved.get("original_version") != base:
        raise ValueError("CI baseline differs from the original pin or built review version")
    for relative in LOCKS:
        old = json.loads((baseline / relative).read_text())
        new = json.loads((root / relative).read_text())
        for framework, packages in old.get("dependencies", {}).items():
            updated = new.get("dependencies", {}).get(framework, {})
            for name in SHARED:
                if name in packages and updated.get(name, {}).get("resolved") != version:
                    raise ValueError(f"{relative} does not resolve CI review version for {name}")
        # Build the expected graph from whole original-version tokens.
        if normalized_lock(old, base, version) != normalized_lock(new, version, version):
            raise ValueError(f"unexpected dependency graph change: {relative}")


def verify_feed(feed: Path, version: str, revision: str) -> None:
    """Check the inspected source identity and archives before consuming them."""
    provenance = json.loads((feed / "provenance.json").read_text())
    if (provenance.get("version") != version
            or provenance.get("revision") != revision
            or provenance.get("inspection") != "passed"):
        raise ValueError("review feed does not match the inspected version and revision")
    records = provenance.get("packages")
    if not isinstance(records, list) or not records:
        raise ValueError("review feed has no inspected package records")
    names = set()
    for record in records:
        name = record.get("file", "")
        if (not isinstance(name, str) or "/" in name or "\\" in name
                or not name.endswith((".nupkg", ".snupkg")) or name in names):
            raise ValueError("review feed has an invalid or duplicate package filename")
        names.add(name)
        archive = feed / name
        if (archive.is_symlink() or not archive.is_file()
                or hashlib.sha256(archive.read_bytes()).hexdigest() != record.get("sha256")):
            raise ValueError(f"review package differs from inspected bytes: {name}")
    required = {f"{name}.{version}.nupkg" for name in (*SHARED, "LibTmux.Mcp")}
    if not required <= names:
        raise ValueError("review feed lacks a shared dependency or MCP archive")
    archives = {path.name for path in feed.iterdir()
                if path.name.endswith((".nupkg", ".snupkg"))}
    if archives != names:
        raise ValueError("review feed contains unrecorded package archives")
    inventory = feed / "api-inventory.json"
    if (inventory.is_symlink() or not inventory.is_file()
            or hashlib.sha256(inventory.read_bytes()).hexdigest()
            != provenance.get("inventory_sha256")):
        raise ValueError("review API inventory differs from inspected bytes")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    version = commands.add_parser("version")
    version.add_argument("--run-id", type=int, required=True,
                         help="Positive Int64 CI run ID or local timestamp in milliseconds.")
    version.add_argument("--attempt", type=int, required=True,
                         help="Positive Int32 CI attempt or local random identifier.")
    for name in ("prepare", "verify"):
        command = commands.add_parser(name)
        command.add_argument("--version", required=True)
        command.add_argument("--baseline", type=Path, required=True,
                             help="Saved original dependency pins, locks and their hashes.")
    feed = commands.add_parser("verify-feed")
    feed.add_argument("--feed", type=Path, required=True)
    feed.add_argument("--version", required=True)
    feed.add_argument("--revision", required=True)
    args = parser.parse_args()
    if args.command == "version":
        print(review_version(ROOT, args.run_id, args.attempt))
    elif args.command == "prepare":
        prepare(ROOT, args.version, args.baseline)
    elif args.command == "verify-feed":
        verify_feed(args.feed, args.version, args.revision)
        print("PASS review feed matches the inspected source and archive bytes")
    else:
        verify(ROOT, args.version, args.baseline)
        print("PASS CI dependency graph matches committed pins except reviewed package bytes")


if __name__ == "__main__":
    main()
