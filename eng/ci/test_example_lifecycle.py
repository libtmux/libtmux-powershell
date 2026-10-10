"""Guard against a green gate with missing execution or cleanup evidence."""
import json
from pathlib import Path
import tempfile
import time
import unittest

import check_example_lifecycle as gate


class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.directory = self.root / 'ordinary/case'
        (self.directory / 'supervisor').mkdir(parents=True)
        self.script = self.root / 'QuickStartChild.ps1'
        self.modules = self.root / 'modules'
        self.receipt = {
            'state': 'complete', 'passed': True, 'errors': [], 'runId': 'unique',
            'serverState': 'absent', 'socketMode': 'name', 'socketExistsBeforeExample': False,
            'rootRemoved': True, 'root': str(self.root / 'removed'), 'rootRemovedAt': 20,
            'processes': [{'exitObserved': True, 'bindingError': None, 'identityBinding': 'pidfd',
                           'startTicks': 1, 'exitObservedAt': 19}],
            'command': ['pwsh', '-File', str(self.script), '-ModuleRoot', str(self.modules),
                        '-OutputPath', str(self.directory / 'body.json')],
        }
        self.body = {'Passed': True, 'SourceSha256': 'abcd', 'InitialState': 'absent',
                     'Mode': 'success', 'SessionId': '$0', 'PaneIds': ['%0']}

    def tearDown(self):
        self.temporary.cleanup()

    def validate(self):
        (self.directory / 'supervisor/result.json').write_text(json.dumps(self.receipt))
        (self.directory / 'body.json').write_text(json.dumps(self.body))
        return gate.validate_case(self.directory, 'absent', 'name', self.script, None,
                                  self.modules, 'abcd')

    def test_complete_native_receipt(self):
        self.assertTrue(self.validate()['passed'])

    def test_prestarted_case_cannot_replace_absent_case(self):
        self.receipt['socketExistsBeforeExample'] = True
        with self.assertRaisesRegex(ValueError, 'Wrong initial state'):
            self.validate()

    def test_path_case_cannot_replace_name_case(self):
        self.receipt['socketMode'] = 'path'
        with self.assertRaisesRegex(ValueError, 'default selector'):
            self.validate()

    def test_empty_process_inventory_fails(self):
        self.receipt['processes'] = []
        with self.assertRaisesRegex(ValueError, 'Unconfirmed process exit'):
            self.validate()

    def test_exit_after_root_removal_fails(self):
        self.receipt['processes'][0]['exitObservedAt'] = 21
        with self.assertRaisesRegex(ValueError, 'before root removal'):
            self.validate()

    def test_unknown_process_identity_fails(self):
        self.receipt['processes'][0]['bindingError'] = 'identity unavailable'
        with self.assertRaisesRegex(ValueError, 'Unconfirmed process exit'):
            self.validate()

    def test_remaining_root_fails(self):
        Path(self.receipt['root']).mkdir()
        with self.assertRaisesRegex(ValueError, 'Test root remains'):
            self.validate()

    def test_other_module_fails(self):
        self.receipt['command'][4] = '/other/modules'
        with self.assertRaisesRegex(ValueError, 'Wrong installed test command'):
            self.validate()

    def test_changed_example_fails(self):
        self.body['SourceSha256'] = 'changed'
        with self.assertRaisesRegex(ValueError, 'Ordinary program did not execute'):
            self.validate()

    def test_empty_body_fails(self):
        self.body = {'Passed': True}
        with self.assertRaisesRegex(ValueError, 'Ordinary program did not execute'):
            self.validate()

    def test_zero_native_assertions_fail(self):
        self.script = self.root / 'StartServer.Tests.ps1'
        self.receipt['command'][2] = str(self.script)
        self.body = {'Passed': True, 'Assertions': 0, 'InitialState': 'absent'}
        with self.assertRaisesRegex(ValueError, 'Native assertions did not execute'):
            self.validate()

    def test_empty_success_summary_fails(self):
        (self.root / 'ordinary/summary.json').write_text(json.dumps({
            'passed': True, 'invocations': 0, 'runnerSha256': gate.SUPERVISOR_SHA256}))
        (self.root / 'ordinary/commands.json').write_text('[]')
        with self.assertRaisesRegex(ValueError, 'ordinary did not execute all 4'):
            gate.validate_results(self.root, self.root, self.modules)

    def test_missing_execution_summary_fails(self):
        with self.assertRaises(FileNotFoundError):
            gate.validate_results(self.root, self.root, self.modules)

    def test_failed_cleanup_cannot_drain_as_success(self):
        self.validate()
        (self.directory / 'supervisor/invocation.json').write_text('{}')
        self.receipt['errors'] = [{'phase': 'cleanup'}]
        (self.directory / 'supervisor/result.json').write_text(json.dumps(self.receipt))
        with self.assertRaisesRegex(ValueError, 'cleanup failure'):
            gate.drain_receipts(self.root, time.monotonic() + 1)


if __name__ == '__main__':
    unittest.main()
