import json
from pathlib import Path
import tempfile
import unittest

import review_dependencies


BASE = "0.0.0-alpha.16.ps.2"
CI = BASE + ".ci.123.1"


class ReviewDependenciesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "src/LibTmux.PowerShell").mkdir(parents=True)
        (self.root / "src/LibTmux.Workspace.PowerShell").mkdir(parents=True)
        (self.root / "Directory.Packages.props").write_text(
            '<Project><ItemGroup>'
            f'<PackageVersion Include="LibTmux" Version="[{BASE}]" />'
            f'<PackageVersion Include="LibTmux.Query.Json" Version="[{BASE}]" />'
            f'<PackageVersion Include="LibTmux.Workspace" Version="[{BASE}]" />'
            '</ItemGroup></Project>\n'
        )
        self.lock = {
            "version": 1,
            "dependencies": {
                "net8.0": {
                    "LibTmux": {"resolved": BASE, "contentHash": "original-core"},
                    "LibTmux.Query.Json": {
                        "resolved": BASE,
                        "contentHash": "original-query",
                        "dependencies": {"LibTmux": BASE},
                    },
                    "ThirdParty": {"resolved": "1.0.0", "contentHash": "original-third-party"},
                }
            },
        }
        for project in ("LibTmux.PowerShell", "LibTmux.Workspace.PowerShell"):
            (self.root / f"src/{project}/packages.lock.json").write_text(
                json.dumps(self.lock) + "\n"
            )
        self.baseline = self.root / "baseline"

    def apply_ci_locks(self):
        for project in ("LibTmux.PowerShell", "LibTmux.Workspace.PowerShell"):
            path = self.root / f"src/{project}/packages.lock.json"
            lock = json.loads(path.read_text())
            lock["dependencies"]["net8.0"]["LibTmux"]["resolved"] = CI
            lock["dependencies"]["net8.0"]["LibTmux"]["contentHash"] = "new-core"
            query = lock["dependencies"]["net8.0"]["LibTmux.Query.Json"]
            query["resolved"] = CI
            query["contentHash"] = "new-query"
            query["dependencies"]["LibTmux"] = CI
            path.write_text(json.dumps(lock) + "\n")

    def test_prepare_and_verify_only_new_review_hashes(self):
        self.assertEqual(review_dependencies.review_version(self.root, 123, 1), CI)
        review_dependencies.prepare(self.root, CI, self.baseline)
        self.apply_ci_locks()
        review_dependencies.verify(self.root, CI, self.baseline)

    def test_verify_rejects_transitive_package_drift(self):
        review_dependencies.prepare(self.root, CI, self.baseline)
        self.apply_ci_locks()
        path = self.root / "src/LibTmux.PowerShell/packages.lock.json"
        lock = json.loads(path.read_text())
        lock["dependencies"]["net8.0"]["ThirdParty"]["contentHash"] = "changed"
        path.write_text(json.dumps(lock) + "\n")
        with self.assertRaisesRegex(ValueError, "unexpected dependency graph change"):
            review_dependencies.verify(self.root, CI, self.baseline)

    def test_verify_requires_the_ci_review_version_in_resolved_locks(self):
        review_dependencies.prepare(self.root, CI, self.baseline)
        with self.assertRaisesRegex(ValueError, "does not resolve CI review version"):
            review_dependencies.verify(self.root, CI, self.baseline)

    def test_prepare_rejects_mismatched_shared_pins(self):
        props = self.root / "Directory.Packages.props"
        props.write_text(props.read_text().replace(
            f'Include="LibTmux.Workspace" Version="[{BASE}]"',
            'Include="LibTmux.Workspace" Version="[0.0.0-other.1]"',
        ))
        with self.assertRaisesRegex(ValueError, "matching exact versions"):
            review_dependencies.prepare(self.root, CI, self.baseline)


if __name__ == "__main__":
    unittest.main()
