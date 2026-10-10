#!/usr/bin/env python3
"""Repeat the real-tmux suites and report each test's failure count."""

import argparse
import csv
import json
from pathlib import Path
import re
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
# Mcp needs a separately installed tool; the aggregate suites repeat their parts.
NOT_REPEATED = {"All", "Product", "Documentation", "Mcp"}
PATH_VALUED = {"-ModuleRoot", "-PackageRoot", "-PSResourceGetVersion"}


def suite_names(test_script: Path) -> list[str]:
    text = test_script.read_text()
    match = re.search(r"\[ValidateSet\(([^)]*)\)\]\s*\[string\]\s*\$Suite", text)
    if not match:
        raise ValueError(f"{test_script} does not declare its suites")
    names = re.findall(r"'([^']+)'", match.group(1))
    return [name for name in names if name not in NOT_REPEATED]


def test_key(record: dict) -> str:
    arguments = record.get("arguments") or []
    kept, skip = [], False
    for argument in arguments:
        if skip:
            skip = False
        elif argument in PATH_VALUED:
            skip = True
        else:
            kept.append(argument)
    name = Path(record["script"]).name.removesuffix(".Tests.ps1")
    return " ".join([name] + kept)


def collect(directory: Path) -> tuple[int, dict[str, dict]]:
    """Each iteration is a numbered subdirectory of test-<suite>.json receipts."""
    iterations = sorted(path for path in directory.iterdir() if path.is_dir())
    rows: dict[str, dict] = {}
    for iteration in iterations:
        for receipt in sorted(iteration.glob("test-*.json")):
            data = json.loads(receipt.read_text())
            for record in data["commands"]:
                row = rows.setdefault(test_key(record), {"runs": 0, "failures": 0,
                                                         "timeouts": 0, "seconds": []})
                row["runs"] += 1
                row["failures"] += 1 if record["exit"] != 0 else 0
                row["timeouts"] += 1 if record["timedOut"] else 0
                row["seconds"].append(record["seconds"])
    return len(iterations), rows


def table(iterations: int, rows: dict[str, dict]) -> list[list[str]]:
    result = [["test", "iterations", "runs", "failures", "timeouts", "median_seconds", "max_seconds"]]
    ordered = sorted(rows.items(), key=lambda item: (-item[1]["failures"], item[0]))
    for name, row in ordered:
        result.append([name, str(iterations), str(row["runs"]), str(row["failures"]),
                       str(row["timeouts"]), f"{statistics.median(row['seconds']):.1f}",
                       f"{max(row['seconds']):.1f}"])
    return result


def markdown(label: str, rows_table: list[list[str]]) -> str:
    lines = [f"### {label}", "", "| " + " | ".join(rows_table[0]) + " |",
             "| " + " | ".join("---" for _ in rows_table[0]) + " |"]
    lines += ["| " + " | ".join(row) + " |" for row in rows_table[1:]]
    failed = sum(int(row[3]) for row in rows_table[1:])
    lines += ["", f"Failures across all tests: {failed}", ""]
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("suites", help="print the suite names to repeat")
    report = commands.add_parser("report", help="aggregate receipts into a table and a CSV")
    report.add_argument("--receipts", type=Path, required=True)
    report.add_argument("--label", required=True)
    report.add_argument("--csv", type=Path, required=True)
    report.add_argument("--summary", type=Path)
    arguments = parser.parse_args(argv)
    if arguments.command == "suites":
        print("\n".join(suite_names(ROOT / "eng/Test.ps1")))
        return 0
    iterations, rows = collect(arguments.receipts)
    if not iterations:
        print("no iteration receipts found", file=sys.stderr)
        return 1
    rows_table = table(iterations, rows)
    with arguments.csv.open("w", newline="") as handle:
        csv.writer(handle).writerows(rows_table)
    text = markdown(arguments.label, rows_table)
    if arguments.summary:
        with arguments.summary.open("a") as handle:
            handle.write(text)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
