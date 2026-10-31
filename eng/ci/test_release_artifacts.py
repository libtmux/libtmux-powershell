import copy
import unittest

import plan_matrix
import release_artifacts


REPOSITORY = "libtmux/libtmux-powershell"
SOURCE = "a" * 40
RUN_ID = 123
BARE_NAMES = (
    "plan",
    "build and pack PowerShell modules",
    "PowerShell 7.4.20 / tmux 3.3a",
    "PowerShell 7.4.20 / tmux 3.4",
    "PowerShell 7.4.20 / tmux 3.5",
    "PowerShell 7.4.20 / tmux 3.6",
    "PowerShell 7.4.20 / tmux 3.7a",
    "PowerShell 7.4.20 / tmux 3.7b",
    "PowerShell 7.4.20 / tmux 3.7c",
    "PowerShell 7.4.20 / tmux 3.8",
    "PowerShell 7.4.20 / tmux master",
    "PowerShell 7.6.6 / tmux 3.3a",
    "PowerShell 7.6.6 / tmux 3.4",
    "PowerShell 7.6.6 / tmux 3.5",
    "PowerShell 7.6.6 / tmux 3.6",
    "PowerShell 7.6.6 / tmux 3.7a",
    "PowerShell 7.6.6 / tmux 3.7b",
    "PowerShell 7.6.6 / tmux 3.7c",
    "PowerShell 7.6.6 / tmux 3.8",
    "PowerShell 7.6.6 / tmux master",
    "PowerShell 7.4.20 / tmux 3.2a rejected",
    "PowerShell 7.4.20 / tmux 3.3 rejected",
    "PowerShell 7.4.20 / tmux 3.0a daemon behind a 3.3a client",
    "PowerShell 7.4.20 / tmux 3.1c daemon behind a 3.3a client",
    "powershell gate",
)
# The release workflow calls ci.yml from a job named ci, and GitHub lists the
# called jobs as "<calling job> / <called job>".
NAMES = tuple(f"ci / {name}" for name in BARE_NAMES)
RELEASE_JOB = "gallery"


def job(index, name, status="completed", conclusion="success"):
    return {
        "id": index + 1,
        "run_id": RUN_ID,
        "run_attempt": 1,
        "head_sha": SOURCE,
        "name": name,
        "status": status,
        "conclusion": conclusion,
    }


def jobs_for(names):
    """List the called jobs, then the release job that is running this check."""
    rows = [job(index, name) for index, name in enumerate(names)]
    rows.append(job(len(rows), RELEASE_JOB, "in_progress", None))
    return {"total_count": len(rows), "jobs": rows}


class ReleaseArtifactsTests(unittest.TestCase):
    def setUp(self):
        repository = {"id": 456, "full_name": REPOSITORY}
        self.run = {
            "id": RUN_ID,
            "repository": repository,
            "head_repository": repository.copy(),
            "path": ".github/workflows/release.yml",
            "event": "workflow_dispatch",
            "head_branch": "master",
            "head_sha": SOURCE,
            "status": "in_progress",
            "conclusion": None,
            "run_attempt": 1,
        }
        self.jobs = jobs_for(NAMES)
        self.artifacts = {"total_count": 1, "artifacts": [{
            "id": 789,
            "name": "port-package",
            "expired": False,
            "digest": "sha256:" + "b" * 64,
            "workflow_run": {
                "id": RUN_ID,
                "head_sha": SOURCE,
                "head_branch": "master",
                "repository_id": 456,
                "head_repository_id": 456,
            },
        }]}

    def validate(self):
        return release_artifacts.validate(
            self.run, self.jobs, self.artifacts, SOURCE, RUN_ID,
        )

    def test_trusted_run_preserves_artifact_and_source_identity(self):
        receipt = self.validate()
        self.assertEqual(receipt["sourceCommit"], SOURCE)
        self.assertEqual(receipt["repository"], REPOSITORY)
        self.assertEqual(receipt["runId"], RUN_ID)
        self.assertEqual(receipt["artifactId"], 789)
        self.assertEqual(receipt["artifactDigest"], "sha256:" + "b" * 64)
        self.assertEqual({job["name"] for job in receipt["jobs"]}, set(NAMES))
        self.assertEqual(receipt["workflowPath"], ".github/workflows/ci.yml")
        self.assertEqual(
            receipt["runUrl"], f"https://github.com/{REPOSITORY}/actions/runs/{RUN_ID}"
        )

    def test_rejects_stale_pr_fork_wrong_workflow_or_incomplete_run(self):
        changes = (
            {"head_sha": "c" * 40},
            {"event": "pull_request"},
            {"event": "push"},
            {"event": "schedule"},
            {"head_branch": "feature"},
            {"repository": {"id": 456, "full_name": "other/repository"}},
            {"head_repository": {"id": 999, "full_name": "fork/repository"}},
            {"path": ".github/workflows/other.yml"},
            {"path": ".github/workflows/ci.yml"},
            {"status": "completed", "conclusion": "success"},
            {"status": "queued"},
            {"conclusion": "failure"},
            {"id": 999},
        )
        original = copy.deepcopy(self.run)
        for change in changes:
            with self.subTest(change=change):
                self.run = original | change
                with self.assertRaisesRegex(ValueError, "Release run"):
                    self.validate()

    def test_rejects_missing_failed_duplicate_or_foreign_linux_jobs(self):
        original = copy.deepcopy(self.jobs)
        for kind in ("missing", "failed", "duplicate", "foreign", "attempt", "truncated"):
            with self.subTest(kind=kind):
                self.jobs = copy.deepcopy(original)
                if kind == "missing":
                    self.jobs["jobs"].pop(1)
                    self.jobs["total_count"] -= 1
                elif kind == "failed":
                    self.jobs["jobs"][1]["conclusion"] = "failure"
                elif kind == "duplicate":
                    self.jobs["jobs"][1]["name"] = NAMES[0]
                elif kind == "foreign":
                    self.jobs["jobs"][1]["head_sha"] = "c" * 40
                elif kind == "attempt":
                    self.jobs["jobs"][1]["run_attempt"] = 2
                else:
                    self.jobs["total_count"] += 1
                with self.assertRaisesRegex(ValueError, "Linux jobs"):
                    self.validate()

    def test_rejects_unrelated_expired_ambiguous_or_unverified_artifact(self):
        original = copy.deepcopy(self.artifacts)
        for kind in ("missing", "expired", "duplicate", "foreign", "source", "digest", "truncated"):
            with self.subTest(kind=kind):
                self.artifacts = copy.deepcopy(original)
                artifact = self.artifacts["artifacts"][0]
                if kind == "missing":
                    artifact["name"] = "evidence-other"
                elif kind == "expired":
                    artifact["expired"] = True
                elif kind == "duplicate":
                    self.artifacts["artifacts"].append(copy.deepcopy(artifact))
                    self.artifacts["total_count"] += 1
                elif kind == "foreign":
                    artifact["workflow_run"]["id"] = 999
                elif kind == "source":
                    artifact["workflow_run"]["head_sha"] = "c" * 40
                elif kind == "digest":
                    artifact["digest"] = None
                else:
                    self.artifacts["total_count"] += 1
                with self.assertRaisesRegex(ValueError, "package artifact"):
                    self.validate()

    def test_the_required_jobs_are_the_whole_table_the_plan_derives(self):
        self.assertEqual(release_artifacts.JOBS, set(NAMES))
        derived = plan_matrix.job_names(
            plan_matrix.plan(
                plan_matrix.load_manifest(), event="workflow_dispatch", scope="full"
            )
        )
        self.assertEqual(release_artifacts.JOBS, {f"ci / {name}" for name in derived})

    def test_rejects_a_call_that_only_covered_the_edges(self):
        edges = plan_matrix.job_names(
            plan_matrix.plan(plan_matrix.load_manifest(), event="push")
        )
        self.assertLess(len(edges), len(BARE_NAMES))
        self.jobs = jobs_for(sorted(f"ci / {name}" for name in edges))
        with self.assertRaisesRegex(ValueError, "only the full-scope CI"):
            self.validate()

    def test_rejects_a_full_call_with_the_master_cells_missing(self):
        self.jobs = jobs_for([name for name in NAMES if not name.endswith("tmux master")])
        with self.assertRaisesRegex(ValueError, "Linux jobs"):
            self.validate()

    def test_rejects_jobs_that_are_not_named_for_the_calling_job(self):
        self.jobs = jobs_for(BARE_NAMES)
        with self.assertRaisesRegex(ValueError, "Linux jobs"):
            self.validate()

    def test_needs_the_one_release_job_beside_the_called_jobs(self):
        original = copy.deepcopy(self.jobs)
        cases = {
            "absent": lambda rows: rows.pop(),
            "twice": lambda rows: rows.append(job(99, RELEASE_JOB, "in_progress", None)),
            "stranger": lambda rows: rows.append(job(99, "publish elsewhere")),
            "finished": lambda rows: rows[-1].update(status="completed", conclusion="success"),
            "foreign": lambda rows: rows[-1].update(head_sha="c" * 40),
            "attempt": lambda rows: rows[-1].update(run_attempt=2),
        }
        for kind, change in cases.items():
            with self.subTest(kind=kind):
                self.jobs = copy.deepcopy(original)
                change(self.jobs["jobs"])
                self.jobs["total_count"] = len(self.jobs["jobs"])
                with self.assertRaisesRegex(ValueError, "Linux jobs"):
                    self.validate()

    def test_a_called_job_that_has_not_finished_is_refused(self):
        self.jobs["jobs"][0].update(status="in_progress", conclusion=None)
        with self.assertRaisesRegex(ValueError, "Linux jobs"):
            self.validate()

    def test_the_receipt_names_the_called_jobs_and_not_the_release_job(self):
        names = [each["name"] for each in self.validate()["jobs"]]
        self.assertNotIn(RELEASE_JOB, names)
        self.assertEqual(set(names), set(NAMES))


if __name__ == "__main__":
    unittest.main()
