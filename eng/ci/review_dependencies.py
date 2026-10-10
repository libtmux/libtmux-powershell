#!/usr/bin/env python3
"""Use one source-pinned CORE review build in an isolated CI checkout."""

import argparse
import copy
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
    if run_id < 1 or attempt < 1:
        raise ValueError("run ID and attempt must be positive")
    _, found = package_versions(root)
    base = found[SHARED[0]].get("Version")[1:-1]
    if not re.fullmatch(r"\d+\.\d+\.\d+-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*", base):
        raise ValueError("base shared dependency pin must be a prerelease")
    return f"{base}.ci.{run_id}.{attempt}"


def prepare(root: Path, version: str, baseline: Path) -> None:
    tree, found = package_versions(root)
    base = found[SHARED[0]].get("Version")[1:-1]
    if not re.fullmatch(re.escape(base) + r"\.ci\.[1-9]\d*\.[1-9]\d*", version):
        raise ValueError("CI review version must extend the exact shared pin")
    if baseline.exists():
        raise ValueError("CI lock baseline already exists")
    for relative in LOCKS:
        if not (root / relative).is_file():
            raise ValueError(f"missing committed dependency lock: {relative}")
    baseline.mkdir(parents=True)
    for relative in LOCKS:
        target = baseline / relative
        target.parent.mkdir(parents=True)
        shutil.copyfile(root / relative, target)
    for element in found.values():
        element.set("Version", f"[{version}]")
    ET.indent(tree, space="  ")
    props = root / "Directory.Packages.props"
    tree.write(props, encoding="unicode")
    with props.open("a") as output:
        output.write("\n")


def normalized_lock(data: dict, version: str, base: str) -> dict:
    result = copy.deepcopy(data)

    def replace(value):
        if isinstance(value, str):
            return value.replace(version, base)
        if isinstance(value, list):
            return [replace(item) for item in value]
        if isinstance(value, dict):
            return {key: replace(item) for key, item in value.items()}
        return value

    result = replace(result)
    for packages in result.get("dependencies", {}).values():
        for name in SHARED:
            if name in packages:
                packages[name].pop("contentHash", None)
    return result


def verify(root: Path, version: str, baseline: Path) -> None:
    _, found = package_versions(root)
    if found[SHARED[0]].get("Version") != f"[{version}]":
        raise ValueError("CI dependency pins differ from the built review version")
    match = re.fullmatch(r"(.+)\.ci\.[1-9]\d*\.[1-9]\d*", version)
    if match is None:
        raise ValueError("invalid CI review version")
    base = match.group(1)
    for relative in LOCKS:
        old = json.loads((baseline / relative).read_text())
        new = json.loads((root / relative).read_text())
        for framework, packages in old.get("dependencies", {}).items():
            updated = new.get("dependencies", {}).get(framework, {})
            for name in SHARED:
                if name in packages and updated.get(name, {}).get("resolved") != version:
                    raise ValueError(f"{relative} does not resolve CI review version for {name}")
        if normalized_lock(old, version, base) != normalized_lock(new, version, base):
            raise ValueError(f"unexpected dependency graph change: {relative}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    version = commands.add_parser("version")
    version.add_argument("--run-id", type=int, required=True)
    version.add_argument("--attempt", type=int, required=True)
    for name in ("prepare", "verify"):
        command = commands.add_parser(name)
        command.add_argument("--version", required=True)
        command.add_argument("--baseline", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "version":
        print(review_version(ROOT, args.run_id, args.attempt))
    elif args.command == "prepare":
        prepare(ROOT, args.version, args.baseline)
    else:
        verify(ROOT, args.version, args.baseline)
        print("PASS CI dependency graph matches committed pins except reviewed package bytes")


if __name__ == "__main__":
    main()
