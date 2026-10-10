import json
import hashlib
from pathlib import Path
import tempfile
import unittest

import review_dependencies


BASE = "0.0.0-alpha.17.ps.4"
LONG_BASE = "0.0.0-alpha.20.ci.1791578156704.1.ci.1791578845576.1.ci.1791630419701.1"
CI = "0.0.0-ci.123.1"


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

    def test_long_original_pin_is_preserved_without_extending_the_review_version(self):
        for relative in review_dependencies.BASELINE_INPUTS:
            path = self.root / relative
            path.write_text(path.read_text().replace(BASE, LONG_BASE))
        props = (self.root / "Directory.Packages.props").read_bytes()
        self.assertEqual(review_dependencies.review_version(self.root, 123, 1), CI)
        review_dependencies.prepare(self.root, CI, self.baseline)
        self.apply_ci_locks()
        review_dependencies.verify(self.root, CI, self.baseline)
        self.assertEqual((self.baseline / "Directory.Packages.props").read_bytes(), props)
        saved = json.loads((self.baseline / "baseline.json").read_text())
        self.assertEqual(saved["original_version"], LONG_BASE)
        self.assertEqual(saved["review_version"], CI)

    def test_version_bound_and_distinct_run_attempts(self):
        largest = review_dependencies.review_version(self.root, 2**63 - 1, 2**31 - 1)
        self.assertEqual(largest, "0.0.0-ci.9223372036854775807.2147483647")
        self.assertLessEqual(len(largest), 39)
        review_dependencies.validate_review_version(largest)
        versions = {review_dependencies.review_version(self.root, run, attempt)
                    for run in (1, 2**63 - 1) for attempt in (1, 2**31 - 1)}
        self.assertEqual(len(versions), 4)
        for run, attempt in ((0, 1), (-1, 1), (2**63, 1), (1, 0),
                             (1, -1), (1, 2**31)):
            with self.subTest(run=run, attempt=attempt):
                with self.assertRaisesRegex(ValueError, "positive Int64"):
                    review_dependencies.review_version(self.root, run, attempt)

    def test_prepare_rejects_unbounded_version_without_mutating_inputs(self):
        props = self.root / "Directory.Packages.props"
        original = props.read_bytes()
        for version in (LONG_BASE + ".ci.123.1", "0.0.0-ci.9223372036854775808.1",
                        "0.0.0-ci.1.2147483648", "0.0.0-ci.01.1", "0.0.0-ci.1.0"):
            with self.subTest(version=version):
                with self.assertRaisesRegex(ValueError, "bounded"):
                    review_dependencies.prepare(self.root, version, self.baseline)
                self.assertFalse(self.baseline.exists())
                self.assertEqual(props.read_bytes(), original)

    def test_existing_baseline_prevents_pin_mutation(self):
        props = self.root / "Directory.Packages.props"
        original = props.read_bytes()
        self.baseline.mkdir()
        with self.assertRaisesRegex(ValueError, "baseline already exists"):
            review_dependencies.prepare(self.root, CI, self.baseline)
        self.assertEqual(props.read_bytes(), original)

    def test_verify_rejects_changed_original_baseline_files(self):
        review_dependencies.prepare(self.root, CI, self.baseline)
        self.apply_ci_locks()
        for relative in review_dependencies.BASELINE_INPUTS:
            path = self.baseline / relative
            original = path.read_bytes()
            with self.subTest(file=relative):
                path.write_bytes(original + b"\n")
                with self.assertRaisesRegex(ValueError, "original dependency baseline changed"):
                    review_dependencies.verify(self.root, CI, self.baseline)
                path.write_bytes(original)

    def test_verify_rejects_baseline_for_a_different_version(self):
        review_dependencies.prepare(self.root, CI, self.baseline)
        self.apply_ci_locks()
        path = self.baseline / "baseline.json"
        original = path.read_text()
        for field in ("original_version", "review_version"):
            with self.subTest(field=field):
                saved = json.loads(original)
                saved[field] = "0.0.0-ci.999.1"
                path.write_text(json.dumps(saved))
                with self.assertRaisesRegex(ValueError, "original pin or built review version"):
                    review_dependencies.verify(self.root, CI, self.baseline)

    def test_verify_does_not_normalize_unrelated_matching_version(self):
        for relative in review_dependencies.LOCKS:
            path = self.root / relative
            lock = json.loads(path.read_text())
            lock["dependencies"]["net8.0"]["ThirdParty"]["resolved"] = BASE
            path.write_text(json.dumps(lock))
        review_dependencies.prepare(self.root, CI, self.baseline)
        self.apply_ci_locks()
        path = self.root / review_dependencies.LOCKS[0]
        lock = json.loads(path.read_text())
        lock["dependencies"]["net8.0"]["ThirdParty"]["resolved"] = CI
        path.write_text(json.dumps(lock))
        with self.assertRaisesRegex(ValueError, "unexpected dependency graph change"):
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


class RepeatedReviewTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.case = 0

    def prepare_review(self, original, version, requested="[{0}, {0}]", edge="{0}"):
        self.case += 1
        root = self.root / str(self.case)
        root.mkdir()
        (root / "Directory.Packages.props").write_text(
            '<Project><ItemGroup>' + ''.join(
                f'<PackageVersion Include="{name}" Version="[{original}]" />'
                for name in review_dependencies.SHARED
            ) + '</ItemGroup></Project>\n'
        )

        def lock(pin):
            packages = {
                name: {
                    "type": "Direct", "requested": requested.format(pin),
                    "resolved": pin, "contentHash": name + "-bytes-" + pin,
                }
                for name in review_dependencies.SHARED
            }
            packages["LibTmux.Query.Json"]["dependencies"] = {
                "LibTmux": edge.format(pin), "ThirdParty": original,
            }
            packages["LibTmux.Workspace"]["dependencies"] = {
                "LibTmux": f"[{pin}, )", "LibTmux.Query.Json": f"(, {pin}]",
            }
            packages["ThirdParty"] = {
                "resolved": original, "contentHash": "unchanged",
                "dependencies": {"LibTmux": f"[{pin}]"},
            }
            return {"version": 1, "dependencies": {"net8.0": packages}}

        for relative in review_dependencies.LOCKS:
            path = root / relative
            path.parent.mkdir(parents=True)
            path.write_text(json.dumps(lock(original)) + "\n")
        baseline = root / "baseline"
        review_dependencies.prepare(root, version, baseline)
        for relative in review_dependencies.LOCKS:
            (root / relative).write_text(json.dumps(lock(version)) + "\n")
        return root, baseline

    def test_shorter_review_prefix_preserves_the_saved_pin(self):
        original = "0.0.0-ci.123.10"
        version = "0.0.0-ci.123.1"
        root, baseline = self.prepare_review(original, version)
        saved = {path: path.read_bytes() for path in baseline.rglob("*") if path.is_file()}
        review_dependencies.verify(root, version, baseline)
        self.assertEqual(saved, {path: path.read_bytes() for path in saved})
        identities = json.loads((baseline / "baseline.json").read_text())
        self.assertEqual(identities["original_version"], original)
        self.assertEqual(identities["review_version"], version)

    def test_longer_review_prefix_is_a_valid_update(self):
        version = "0.0.0-ci.123.10"
        root, baseline = self.prepare_review("0.0.0-ci.123.1", version)
        review_dependencies.verify(root, version, baseline)

    def test_range_tokens_preserve_prefix_related_other_bounds(self):
        version = "0.0.0-ci.123.1"
        for edge in ("{0}", "[{0}]", "[{0}, )", "(, {0}]",
                     "[{0}, 0.0.0-ci.123.100)", "(0.0.0-ci.12, {0}]"):
            with self.subTest(edge=edge):
                root, baseline = self.prepare_review("0.0.0-ci.123.10", version, edge=edge)
                review_dependencies.verify(root, version, baseline)

    def test_unchanged_other_bound_can_equal_the_new_review_version(self):
        version = "0.0.0-ci.123.10"
        root, baseline = self.prepare_review(
            "0.0.0-ci.123.1", version, edge="[{0}, 0.0.0-ci.123.10]",
        )
        review_dependencies.verify(root, version, baseline)

    def test_changed_other_requested_bound_is_not_a_review_version(self):
        version = "0.0.0-ci.123.10"
        root, baseline = self.prepare_review(
            "0.0.0-ci.123.1", version, requested="[{0}, {0}0]",
        )
        with self.assertRaisesRegex(ValueError, "unexpected dependency graph change"):
            review_dependencies.verify(root, version, baseline)

    def test_changed_other_edge_bound_is_not_a_review_version(self):
        version = "0.0.0-ci.123.10"
        root, baseline = self.prepare_review(
            "0.0.0-ci.123.1", version, edge="[{0}, {0}0]",
        )
        with self.assertRaisesRegex(ValueError, "unexpected dependency graph change"):
            review_dependencies.verify(root, version, baseline)

    def test_resolved_review_prefix_is_not_the_review_version(self):
        version = "0.0.0-ci.123.1"
        root, baseline = self.prepare_review("0.0.0-ci.123.10", version)
        path = root / review_dependencies.LOCKS[0]
        data = json.loads(path.read_text())
        data["dependencies"]["net8.0"]["LibTmux"]["resolved"] = version + "0"
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "does not resolve CI review version"):
            review_dependencies.verify(root, version, baseline)


class ReviewFeedTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.feed = Path(self.temporary.name)
        self.revision = "a" * 40
        records = []
        for name in (*review_dependencies.SHARED, "LibTmux.Mcp"):
            filename = f"{name}.{CI}.nupkg"
            data = name.encode()
            (self.feed / filename).write_bytes(data)
            records.append({"file": filename, "sha256": hashlib.sha256(data).hexdigest()})
        inventory = b'{"packages": []}\n'
        (self.feed / "api-inventory.json").write_bytes(inventory)
        self.provenance = {
            "version": CI, "revision": self.revision, "inspection": "passed",
            "packages": records, "inventory_sha256": hashlib.sha256(inventory).hexdigest(),
        }
        self.save_provenance()

    def save_provenance(self):
        (self.feed / "provenance.json").write_text(json.dumps(self.provenance))

    def check_feed(self):
        review_dependencies.verify_feed(self.feed, CI, self.revision)

    def test_verified_archive_identity(self):
        self.check_feed()

    def test_different_revision_or_uninspected_feed(self):
        for key, value in (("version", "0.0.0-other.1"), ("revision", "b" * 40),
                           ("inspection", "failed")):
            with self.subTest(field=key):
                old = self.provenance[key]
                self.provenance[key] = value
                self.save_provenance()
                with self.assertRaisesRegex(ValueError, "inspected version and revision"):
                    self.check_feed()
                self.provenance[key] = old

    def test_archive_corruption(self):
        (self.feed / self.provenance["packages"][0]["file"]).write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "differs from inspected bytes"):
            self.check_feed()

    def test_missing_mcp_archive(self):
        record = self.provenance["packages"].pop()
        (self.feed / record["file"]).unlink()
        self.save_provenance()
        with self.assertRaisesRegex(ValueError, "lacks a shared dependency or MCP"):
            self.check_feed()

    def test_duplicate_or_outside_archive_name(self):
        records = self.provenance["packages"][:]
        for name in (records[0]["file"], "../outside.nupkg", "..\\outside.nupkg"):
            with self.subTest(name=name):
                self.provenance["packages"] = records + [{"file": name, "sha256": "unused"}]
                self.save_provenance()
                with self.assertRaisesRegex(ValueError, "invalid or duplicate"):
                    self.check_feed()

    def test_archive_link_is_not_consumed(self):
        archive = self.feed / self.provenance["packages"][0]["file"]
        content = archive.read_bytes()
        archive.unlink()
        target = self.feed / "other-bytes"
        target.write_bytes(content)
        archive.symlink_to(target)
        with self.assertRaisesRegex(ValueError, "differs from inspected bytes"):
            self.check_feed()

    def test_unrecorded_archive(self):
        (self.feed / "unexpected.nupkg").write_bytes(b"unreviewed")
        with self.assertRaisesRegex(ValueError, "unrecorded package"):
            self.check_feed()

    def test_inventory_corruption(self):
        (self.feed / "api-inventory.json").write_bytes(b"{}")
        with self.assertRaisesRegex(ValueError, "API inventory differs"):
            self.check_feed()


if __name__ == "__main__":
    unittest.main()
