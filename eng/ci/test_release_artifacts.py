import copy
import unittest

import release_artifacts


REPOSITORY = "libtmux/libtmux-powershell"
SOURCE = "a" * 40
RUN_ID = 123
NAMES = (
    "build and pack PowerShell modules",
    "PowerShell 7.4.20 / tmux 3.2a",
    "PowerShell 7.4.20 / tmux 3.7c",
    "PowerShell 7.6.6 / tmux 3.2a",
    "PowerShell 7.6.6 / tmux 3.7c",
    "powershell gate",
)


class ReleaseArtifactsTests(unittest.TestCase):
    def setUp(self):
        repository = {"id": 456, "full_name": REPOSITORY}
        self.run = {
            "id": RUN_ID,
            "repository": repository,
            "head_repository": repository.copy(),
            "path": ".github/workflows/ci.yml",
            "event": "push",
            "head_branch": "master",
            "head_sha": SOURCE,
            "status": "completed",
            "conclusion": "success",
            "run_attempt": 1,
        }
        self.jobs = {"total_count": 6, "jobs": [
            {
                "id": index + 1,
                "run_id": RUN_ID,
                "run_attempt": 1,
                "head_sha": SOURCE,
                "name": name,
                "status": "completed",
                "conclusion": "success",
            }
            for index, name in enumerate(NAMES)
        ]}
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

    def test_rejects_stale_pr_fork_wrong_workflow_or_incomplete_run(self):
        changes = (
            {"head_sha": "c" * 40},
            {"event": "pull_request"},
            {"head_branch": "feature"},
            {"repository": {"id": 456, "full_name": "other/repository"}},
            {"head_repository": {"id": 999, "full_name": "fork/repository"}},
            {"path": ".github/workflows/other.yml"},
            {"status": "in_progress", "conclusion": None},
            {"conclusion": "failure"},
            {"id": 999},
        )
        original = copy.deepcopy(self.run)
        for change in changes:
            with self.subTest(change=change):
                self.run = original | change
                with self.assertRaisesRegex(ValueError, "CI run"):
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


if __name__ == "__main__":
    unittest.main()
