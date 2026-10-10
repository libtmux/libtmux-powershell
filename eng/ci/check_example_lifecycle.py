"""Run the installed ordinary-example and recovery gate without tmux fixtures."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import time


SUPERVISOR_SHA256 = 'c59c70a07d2e5dca40e32c12bd2fc442f71409ae1d0f7916bbfc4905f69ad111'
RECOVERY_CASES = ('startup', 'session', 'cancel', 'aggregate', 'action')
EXECUTION_SECONDS = 50
CLEANUP_SECONDS = 8


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text())


def cases():
    for group, prefix, script in (
            ('ordinary', 'example', 'tests/support/QuickStartChild.ps1'),
            ('startup', 'api', 'tests/StartServer.Tests.ps1')):
        for state in ('absent', 'running'):
            for selector in ('path', 'name'):
                yield group, f'{prefix}-0-{state}-{selector}', state, selector, script, None
    for selector in ('path', 'name'):
        for case in RECOVERY_CASES:
            script = ('tests/RecoveryWrappers.Tests.ps1' if case in ('aggregate', 'action')
                      else 'tests/AcquisitionRecovery.Tests.ps1')
            yield 'recovery', f'0-{selector}-{case}', 'absent', selector, script, case


def validate_case(directory, state, selector, script, case, modules, example_hash):
    receipt = read_json(directory / 'supervisor/result.json')
    require(receipt.get('state') == 'complete' and receipt.get('passed') is True
            and receipt.get('errors') == [], f'Incomplete or failed supervisor: {directory}')
    require(receipt.get('serverState') == state and receipt.get('socketMode') == selector
            and receipt.get('socketExistsBeforeExample') is (state == 'running'),
            f'Wrong initial state or default selector: {directory}')
    require(receipt.get('rootRemoved') is True and not Path(receipt['root']).exists(),
            f'Test root remains: {directory}')
    processes = receipt.get('processes', [])
    require(processes and all(
        p.get('exitObserved') is True and p.get('bindingError') is None
        and p.get('identityBinding') in ('pidfd', 'unreaped-child')
        and isinstance(p.get('startTicks'), int) and p['startTicks'] > 0
        and p.get('exitObservedAt', float('inf')) <= receipt['rootRemovedAt']
        for p in processes), f'Unconfirmed process exit before root removal: {directory}')
    command = receipt['command']
    require(command[command.index('-File') + 1] == str(script)
            and command[command.index('-ModuleRoot') + 1] == str(modules)
            and command[command.index('-OutputPath') + 1] == str(directory / 'body.json'),
            f'Wrong installed test command: {directory}')
    body = read_json(directory / 'body.json')
    require(body.get('Passed') is True, f'Native test failed: {directory}')
    if script.name == 'QuickStartChild.ps1':
        require(body.get('SourceSha256', '').lower() == example_hash
                and body.get('InitialState') == state and body.get('Mode') == 'success'
                and body.get('SessionId') and body.get('PaneIds'),
                f'Ordinary program did not execute: {directory}')
    else:
        require(isinstance(body.get('Assertions'), int) and body['Assertions'] > 0,
                f'Native assertions did not execute: {directory}')
        require(body.get('Case') == case if case else body.get('InitialState') == state,
                f'Wrong native test case: {directory}')
    return {'receipt': str(directory / 'supervisor/result.json'),
            'runId': receipt['runId'], 'processes': len(processes),
            'assertions': body.get('Assertions'), 'passed': True}


def validate_results(repo, output, modules):
    expected = list(cases())
    for group, count in (('ordinary', 4), ('startup', 4), ('recovery', 10)):
        summary = read_json(output / group / 'summary.json')
        records = read_json(output / group / 'commands.json')
        field = 'cases' if group == 'recovery' else 'invocations'
        require(summary.get('passed') is True and summary.get(field) == count
                and len(records) == count and summary.get('runnerSha256') == SUPERVISOR_SHA256,
                f'{group} did not execute all {count} required invocations')
    verified = [validate_case(output / group / label, state, selector, repo / script, case,
                              modules, digest(repo / 'examples/QuickStart.ps1'))
                for group, label, state, selector, script, case in expected]
    require(len({row['runId'] for row in verified}) == len(expected),
            'The gate reused a supervisor receipt')
    return verified


def snapshot(root):
    return {str(path.relative_to(root)): digest(path)
            for path in sorted(root.rglob('*')) if path.is_file()}


def drain_receipts(output, deadline):
    invocations = sorted(output.glob('*/*/supervisor/invocation.json'))
    for invocation in invocations:
        path = invocation.with_name('result.json')
        while True:
            try:
                receipt = read_json(path)
                if receipt.get('state') == 'complete':
                    break
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            require(time.monotonic() < deadline, f'Supervisor cleanup did not finish: {path}')
            select.select([], [], [], 0.01)
        require(not any(error['phase'] == 'cleanup' for error in receipt['errors']),
                f'Supervisor reported a cleanup failure: {path}')
        if 'root' in receipt:
            require(receipt.get('rootRemoved') is True and not Path(receipt['root']).exists()
                    and all(p['exitObserved'] and p['exitObservedAt'] <= receipt['rootRemovedAt']
                            for p in receipt['processes']), f'Cleanup remains unconfirmed: {path}')
    return len(invocations)


def run(args):
    repo = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    started = time.monotonic()
    record = {'schema': 1, 'passed': False, 'cleanupComplete': False,
              'commands': [], 'verified': [], 'errors': []}
    active = []
    interrupted = False

    def cancel(number, frame):
        nonlocal interrupted
        interrupted = True
        raise KeyboardInterrupt('Ordinary-example gate interrupted')

    previous_handlers = {number: signal.signal(number, cancel)
                         for number in (signal.SIGINT, signal.SIGTERM)}
    try:
        runner = args.runner.resolve(strict=True)
        modules = args.module_root.resolve(strict=True)
        tmux = args.tmux.resolve(strict=True)
        require(digest(runner) == SUPERVISOR_SHA256, 'The shared supervisor does not match its pinned digest')
        before = snapshot(modules)
        require('LibTmux/0.1.0/LibTmux.PowerShell.dll' in before, 'The extracted module is missing')
        record.update(runner=str(runner), runnerSha256=SUPERVISOR_SHA256,
                      modules=before, tmux=str(tmux), tmuxVersion=subprocess.check_output(
                          [str(tmux), '-V'], text=True, timeout=2).strip())
        inputs = {path: digest(repo / path) for path in sorted({
            'README.md', 'examples/QuickStart.ps1', 'eng/ci/check_example_lifecycle.py',
            'tests/support/run_ordinary_examples.py', 'tests/support/run_acquisition_recovery.py',
            'tests/support/ordinary_tmux.py', 'tests/support/recovery_tmux.py',
            'tests/support/RecoveryProbe.cs', 'tests/support/SocketCreatedSignal.cs',
            'tests/support/HelpExampleAssertions.ps1', *(item[4] for item in cases())})}
        record['inputs'] = inputs
        common = ['--runner', str(runner), '--pwsh', args.pwsh, '--module-root', str(modules),
                  '--tmux', str(tmux)]
        jobs = [('ordinary', 'run_ordinary_examples.py', ['--checks', 'examples']),
                ('startup', 'run_ordinary_examples.py', ['--checks', 'api']),
                ('recovery', 'run_acquisition_recovery.py',
                 [value for case in RECOVERY_CASES for value in ('--case', case)])]
        for group, script, options in jobs:
            command = [sys.executable, str(repo / 'tests/support' / script), *common, *options,
                       '--output', str(output / group)]
            log = (output / f'{group}.log').open('wb')
            try:
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                           start_new_session=True)
            except BaseException:
                log.close()
                raise
            row = {'group': group, 'argv': command, 'exit': None}
            record['commands'].append(row)
            active.append((process, log, row))
        for process, log, row in active:
            remaining = EXECUTION_SECONDS - (time.monotonic() - started)
            row['exit'] = process.wait(timeout=max(remaining, 0.001))
        require(all(row['exit'] == 0 for row in record['commands']),
                'A native runner failed; inspect the retained group logs')
        record['verified'] = validate_results(repo, output, modules)
        require(snapshot(modules) == before, 'Installed module bytes changed during the gate')
        require(all(digest(repo / path) == value for path, value in inputs.items()),
                'Example or test source changed during the gate')
        require(digest(runner) == SUPERVISOR_SHA256, 'Shared supervisor changed during the gate')
        record['passed'] = True
    except BaseException as error:
        record['errors'].append({'type': type(error).__name__, 'message': str(error)})
    finally:
        # Each driver owns its process group. Supervisors start separate sessions
        # and must survive cancellation until they observe their accepted exits.
        for process, log, row in active:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        deadline = time.monotonic() + CLEANUP_SECONDS
        for process, log, row in active:
            try:
                row['exit'] = process.wait(timeout=max(deadline - time.monotonic(), 0.001))
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                row['exit'] = process.wait(timeout=1)
                record['errors'].append({'type': 'TimeoutError', 'message': 'Runner did not stop: ' + row['group']})
            finally:
                log.close()
        try:
            record['supervisorReceipts'] = drain_receipts(output, deadline)
            record['cleanupComplete'] = True
        except BaseException as error:
            record['errors'].append({'type': type(error).__name__, 'message': str(error)})
        for number, handler in previous_handlers.items():
            signal.signal(number, handler)
        record['passed'] = record['passed'] and not record['errors'] and not interrupted
        record['seconds'] = time.monotonic() - started
        (output / 'summary.json').write_text(json.dumps(record, indent=2) + '\n')
        print(str(output / 'summary.json'), flush=True)
    return 0 if record['passed'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', required=True, type=Path)
    parser.add_argument('--pwsh', required=True)
    parser.add_argument('--module-root', required=True, type=Path)
    parser.add_argument('--tmux', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    return run(parser.parse_args())


if __name__ == '__main__':
    sys.exit(main())
