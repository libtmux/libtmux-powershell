"""Prove the documents and the macOS trial still agree with the CI table."""

import pathlib
import re
import unittest

import plan_matrix

ROOT = pathlib.Path(__file__).resolve().parents[2]
MANIFEST = plan_matrix.load_manifest()
SUPPORTED = [each["tmux"] for each in MANIFEST["supported"]]
POWERSHELL = [each["version"] for each in MANIFEST["powershell"]]


def missing(text, versions):
    """Name the versions that a text does not mention as whole words."""
    return [
        version
        for version in versions
        if not re.search(rf"(?<![\w.]){re.escape(version)}(?![\w])", text)
    ]


def trial_pins(text):
    """Read each tmux release and source commit pair from the macOS trial."""
    return re.findall(r"tmux: '([^']+)'\s+tmux_commit: ([0-9a-f]{40})", text)


def trial_powershell(text):
    return set(re.findall(r"powershell: '([^']+)'", text))


class DocumentsAgreeWithTheTable(unittest.TestCase):
    def test_the_compatibility_guide_names_every_version_it_tests(self):
        text = (ROOT / "docs/compatibility.md").read_text(encoding="utf-8")
        row = next(line for line in text.splitlines() if line.startswith("| Linux x64"))
        self.assertEqual(missing(row, [*SUPPORTED, *POWERSHELL, "master"]), [])

    def test_the_readme_names_the_tested_range(self):
        text = (ROOT / "README.md").read_text(encoding="utf-8")
        line = next(each for each in text.splitlines() if each.startswith("- **tmux.** 3.3a or newer"))
        self.assertEqual(missing(line, [SUPPORTED[0], SUPPORTED[-1], "master"]), [])
        shells = next(each for each in text.splitlines() if each.startswith("- **PowerShell.**"))
        self.assertEqual(missing(shells, POWERSHELL), [])

    def test_the_floor_is_the_first_supported_release(self):
        text = (ROOT / "docs/compatibility.md").read_text(encoding="utf-8")
        self.assertIn(f"The minimum for ordinary operations is tmux {SUPPORTED[0]}", text)

    def test_the_macos_trial_uses_the_pins_of_the_table(self):
        text = (ROOT / ".github/workflows/macos-trial.yml").read_text(encoding="utf-8")
        pins = {each["tmux"]: each["commit"] for each in MANIFEST["supported"]}
        found = trial_pins(text)
        self.assertTrue(found)
        for version, commit in found:
            self.assertEqual(pins.get(version), commit, version)
        self.assertLessEqual(trial_powershell(text), set(POWERSHELL))

    def test_a_text_that_dropped_a_version_is_reported(self):
        row = "tmux " + ", ".join(SUPPORTED[:-1]) + " and master with PowerShell " + " and ".join(POWERSHELL)
        self.assertEqual(missing(row, [*SUPPORTED, *POWERSHELL, "master"]), [SUPPORTED[-1]])
        self.assertEqual(missing("3.7ab", ["3.7a"]), ["3.7a"])
        self.assertEqual(missing("tmux 3.10", ["3.1"]), ["3.1"])

    def test_a_trial_pin_that_drifted_is_reported(self):
        text = (ROOT / ".github/workflows/macos-trial.yml").read_text(encoding="utf-8")
        pins = {each["tmux"]: each["commit"] for each in MANIFEST["supported"]}
        version, commit = trial_pins(text)[0]
        drifted = text.replace(commit, "f" * 40)
        self.assertNotEqual(
            [pair for pair in trial_pins(drifted) if pins.get(pair[0]) != pair[1]], []
        )

    def test_every_pin_in_the_manifest_is_a_full_commit(self):
        for group in ("supported", "rejected", "oldDaemon"):
            for each in MANIFEST[group]:
                self.assertRegex(each["commit"], r"^[0-9a-f]{40}$", each["tmux"])
        for each in MANIFEST["powershell"]:
            self.assertRegex(each["sha256"], r"^[0-9a-f]{64}$", each["version"])
        for each in MANIFEST["development"]:
            self.assertEqual(each["commit"], "", "a development lane floats")


if __name__ == "__main__":
    unittest.main()
