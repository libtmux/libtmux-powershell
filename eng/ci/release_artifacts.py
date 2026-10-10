#!/usr/bin/env python3
"""Bind the release to the tested archives from a successful trunk CI run."""

import argparse
import json
import os
from pathlib import Path
import re
from urllib.request import Request, urlopen


REPOSITORY = "libtmux/libtmux-powershell"
WORKFLOW = ".github/workflows/ci.yml"
JOBS = {
    "build and pack PowerShell modules",
    "PowerShell 7.4.20 / tmux 3.2a",
    "PowerShell 7.4.20 / tmux 3.7c",
    "PowerShell 7.6.6 / tmux 3.2a",
    "PowerShell 7.6.6 / tmux 3.7c",
    "powershell gate",
}


def positive_integer(value):
    return type(value) is int and value > 0


def validate(run, jobs, artifacts, source_commit, run_id):
    repository = run.get("repository", {})
    head_repository = run.get("head_repository", {})
    attempt = run.get("run_attempt")
    if (
        not re.fullmatch(r"[0-9a-f]{40}", source_commit)
        or not positive_integer(run_id)
        or run.get("id") != run_id
        or repository.get("full_name") != REPOSITORY
        or head_repository.get("full_name") != REPOSITORY
        or not positive_integer(repository.get("id"))
        or repository.get("id") != head_repository.get("id")
        or run.get("path") != WORKFLOW
        or run.get("event") != "push"
        or run.get("head_branch") != "master"
        or run.get("head_sha") != source_commit
        or run.get("status") != "completed"
        or run.get("conclusion") != "success"
        or not positive_integer(attempt)
    ):
        raise ValueError("CI run must be a successful same-repository master push at the release commit")

    rows = jobs.get("jobs", [])
    if (
        jobs.get("total_count") != len(rows)
        or len(rows) != len(JOBS)
        or {job.get("name") for job in rows} != JOBS
        or any(
            not positive_integer(job.get("id"))
            or job.get("run_id") != run_id
            or job.get("run_attempt") != attempt
            or job.get("head_sha") != source_commit
            or job.get("status") != "completed"
            or job.get("conclusion") != "success"
            for job in rows
        )
    ):
        raise ValueError("Linux jobs must include the successful build, four endpoint cells and gate from this CI attempt")

    all_artifacts = artifacts.get("artifacts", [])
    matches = [item for item in all_artifacts if item.get("name") == "port-package"]
    if artifacts.get("total_count") != len(all_artifacts) or len(matches) != 1:
        raise ValueError("CI package artifact must be uniquely identified in the complete artifact list")
    artifact = matches[0]
    origin = artifact.get("workflow_run", {})
    if (
        not positive_integer(artifact.get("id"))
        or artifact.get("expired") is not False
        or not re.fullmatch(r"sha256:[0-9a-f]{64}", artifact.get("digest") or "")
        or origin.get("id") != run_id
        or origin.get("head_sha") != source_commit
        or origin.get("head_branch") != "master"
        or origin.get("repository_id") != repository["id"]
        or origin.get("head_repository_id") != repository["id"]
    ):
        raise ValueError("CI package artifact must be unexpired and belong to the verified source and run")
    return {
        "schemaVersion": 1,
        "repository": REPOSITORY,
        "sourceCommit": source_commit,
        "workflowPath": WORKFLOW,
        "runId": run_id,
        "runAttempt": attempt,
        "runUrl": f"https://github.com/{REPOSITORY}/actions/runs/{run_id}",
        "artifactId": artifact["id"],
        "artifactName": artifact["name"],
        "artifactDigest": artifact["digest"],
        "jobs": [{"id": job["id"], "name": job["name"]} for job in rows],
    }


def read_api(path):
    token = os.environ.get("GH_TOKEN")
    if not token:
        raise ValueError("GH_TOKEN is required to inspect the trusted CI artifacts")
    request = Request(
        f"https://api.github.com/repos/{REPOSITORY}/{path}",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", type=int, required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--github-output", type=Path, required=True)
    args = parser.parse_args()
    if not positive_integer(args.run_id) or not re.fullmatch(r"[0-9a-f]{40}", args.source_commit):
        parser.error("run ID must be positive and source commit must be a full lowercase SHA")
    run = read_api(f"actions/runs/{args.run_id}")
    attempt = run.get("run_attempt")
    if not positive_integer(attempt):
        raise ValueError("CI run has no valid attempt")
    jobs = read_api(f"actions/runs/{args.run_id}/attempts/{attempt}/jobs?per_page=100")
    artifacts = read_api(f"actions/runs/{args.run_id}/artifacts?per_page=100")
    receipt = validate(run, jobs, artifacts, args.source_commit, args.run_id)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, indent=2) + "\n")
    with args.github_output.open("a") as output:
        output.write(f"artifact_id={receipt['artifactId']}\n")
    print("PASS CI source, Linux gates and package artifact provenance")


if __name__ == "__main__":
    main()
