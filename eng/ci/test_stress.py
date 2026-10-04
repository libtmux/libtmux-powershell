import json
from pathlib import Path
import tempfile
import unittest

import stress


def receipt(directory: Path, suite: str, *commands: dict) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"test-{suite}.json").write_text(json.dumps(
        {"suite": suite, "status": "FAIL", "seconds": 1, "commands": list(commands)}))


def command(script: str, exit_code, arguments=(), seconds=1.0, timed_out=False) -> dict:
    return {"script": script, "arguments": list(arguments), "exit": exit_code,
            "timedOut": timed_out, "seconds": seconds}


class StressReportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_names_the_failing_test_and_leaves_a_clean_control_at_zero(self):
        for iteration, exit_code in (("1", 0), ("2", 1), ("3", 0)):
            receipt(self.root / iteration, "Remove",
                    command("tests/Remove.Tests.ps1", exit_code, ["-ModuleRoot", "/tmp/a" + iteration]))
            receipt(self.root / iteration, "Read", command("tests/Read.Tests.ps1", 0))
        iterations, rows = stress.collect(self.root)
        self.assertEqual(iterations, 3)
        self.assertEqual((rows["Remove"]["runs"], rows["Remove"]["failures"]), (3, 1))
        self.assertEqual((rows["Read"]["runs"], rows["Read"]["failures"]), (3, 0))

    def test_timeouts_and_argument_variants_are_separate_rows(self):
        receipt(self.root / "1", "Examples",
                command("tests/Help.Tests.ps1", 1, ["-ModuleRoot", "/x", "-RunExamples", "-ExampleGroup", "Terminal"],
                        timed_out=True),
                command("tests/Help.Tests.ps1", 0, ["-ModuleRoot", "/x", "-RunExamples", "-ExampleGroup", "Workspace"]))
        _, rows = stress.collect(self.root)
        self.assertEqual(rows["Help -RunExamples -ExampleGroup Terminal"]["timeouts"], 1)
        self.assertEqual(rows["Help -RunExamples -ExampleGroup Workspace"]["failures"], 0)

    def test_suite_list_follows_the_validate_set_and_skips_aggregates(self):
        names = stress.suite_names(stress.ROOT / "eng/Test.ps1")
        self.assertIn("Attachment", names)
        for aggregate in ("All", "Product", "Documentation", "Mcp"):
            self.assertNotIn(aggregate, names)


if __name__ == "__main__":
    unittest.main()
