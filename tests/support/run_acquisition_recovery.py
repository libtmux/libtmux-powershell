"""Run native recovery checks under the shared documentation supervisor."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', required=True, type=Path)
    parser.add_argument('--pwsh', required=True)
    parser.add_argument('--module-root', required=True, type=Path)
    parser.add_argument('--tmux', required=True, action='append')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--case', action='append', choices=(
        'startup', 'session', 'window', 'pane', 'unknown', 'cancel', 'replacement',
        'plain', 'aggregate', 'action', 'stopped'))
    parser.add_argument('--socket-mode', action='append', choices=('path', 'name'))
    args = parser.parse_args()
    for binary in args.tmux:
        Path(binary).resolve(strict=True)
    repo = Path(__file__).resolve().parents[2]
    args.output.mkdir(parents=True, exist_ok=False)
    wrapper = args.output.resolve() / 'tmux'
    wrapper.write_text('#!' + sys.executable + '\n' + (repo / 'tests/support/recovery_tmux.py').read_text())
    wrapper.chmod(0o700)
    records = []
    for index, binary in enumerate(args.tmux):
        for selector in args.socket_mode or ('path', 'name'):
            for case in args.case or ('startup', 'session', 'window', 'pane', 'unknown', 'cancel', 'replacement',
                                      'plain', 'aggregate', 'action', 'stopped'):
                target = args.output.resolve() / f'{index}-{selector}-{case}'
                target.mkdir()
                fault = target / 'fault'
                fault.write_text('')
                env = dict(os.environ, LIBTMUX_ORDINARY_TMUX=str(Path(binary).resolve()),
                           LIBTMUX_ORDINARY_FAULT=str(fault), LIBTMUX_ORDINARY_TRACE=str(target / 'calls.jsonl'),
                           PSModulePath=str(args.module_root.resolve()))
                script = ('RecoveryWrappers.Tests.ps1' if case in ('plain', 'aggregate', 'action', 'stopped')
                          else 'AcquisitionRecovery.Tests.ps1')
                command = [sys.executable, str(args.runner.resolve()), '--output-dir', str(target / 'supervisor'),
                           '--cwd', str(repo), '--server-state', 'absent', '--socket-mode', selector,
                           '--timeout', '25', '--tmux', str(wrapper), '--', args.pwsh, '-NoLogo', '-NoProfile',
                           '-File', str(repo / 'tests' / script),
                           '-ModuleRoot', str(args.module_root.resolve()), '-Case', case,
                           '-OutputPath', str(target / 'body.json')]
                started = time.monotonic()
                with (target / 'controller.log').open('w') as log:
                    result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
                receipt = json.loads((target / 'supervisor/result.json').read_text())
                row = {'case': case, 'selector': selector, 'argv': command, 'exit': result.returncode,
                       'seconds': time.monotonic() - started, 'receipt': str(target / 'supervisor/result.json')}
                records.append(row)
                (args.output / 'commands.json').write_text(json.dumps(records, indent=2) + '\n')
                assert receipt['rootRemoved'] and not Path(receipt['root']).exists(), receipt
                assert receipt['processes'] and all(p['exitObserved'] for p in receipt['processes']), receipt
                assert not [e for e in receipt['errors'] if e['phase'] == 'cleanup'], receipt
                if result.returncode or not receipt['passed']:
                    raise AssertionError('Recovery case failed; inspect ' + str(target))
                assert json.loads((target / 'body.json').read_text())['Passed']
                print(json.dumps(row), flush=True)
    (args.output / 'summary.json').write_text(json.dumps({
        'passed': True, 'cases': len(records),
        'runnerSha256': hashlib.sha256(args.runner.read_bytes()).hexdigest(),
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
