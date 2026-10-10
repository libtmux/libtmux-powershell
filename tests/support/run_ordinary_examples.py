"""Verify copied PowerShell examples with the shared Linux example supervisor."""
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', required=True, type=Path)
    parser.add_argument('--pwsh', required=True)
    parser.add_argument('--module-root', required=True, type=Path)
    parser.add_argument('--tmux', required=True, action='append')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--checks', choices=('all', 'examples', 'api', 'faults'), default='all')
    parser.add_argument('--document', type=Path)
    parser.add_argument('--example-source', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    args.output.mkdir(parents=True, exist_ok=False)
    runner = args.runner.resolve(strict=True)
    modules = args.module_root.resolve(strict=True)
    wrapper = args.output.resolve() / 'tmux'
    wrapper.write_text('#!' + sys.executable + '\n' + (repo / 'tests/support/ordinary_tmux.py').read_text())
    wrapper.chmod(0o700)
    original_environment = dict(os.environ)
    records = []
    active = []

    def start(label, binary, state, selector, mode='success', script=None, timeout=25):
        target = args.output.resolve() / label
        target.mkdir()
        fault = target / 'fault'
        fault.write_text('')
        env = dict(os.environ, LIBTMUX_ORDINARY_TMUX=str(Path(binary).resolve()),
                   LIBTMUX_ORDINARY_FAULT=str(fault), LIBTMUX_ORDINARY_TRACE=str(target / 'calls.jsonl'),
                   PSModulePath=str(modules))
        child = [args.pwsh, '-NoLogo', '-NoProfile', '-File',
                 str(repo / (script or 'tests/support/QuickStartChild.ps1')),
                 '-ModuleRoot', str(modules), '-InitialState', state, '-OutputPath', str(target / 'body.json')]
        if not script:
            child += ['-Mode', mode]
            if args.document:
                child += ['-Document', str(args.document.resolve())]
            if args.example_source:
                child += ['-ExampleSource', str(args.example_source.resolve())]
        command = [sys.executable, str(runner), '--output-dir', str(target / 'supervisor'), '--cwd', str(repo),
                   '--server-state', state, '--socket-mode', selector, '--timeout', str(timeout),
                   '--tmux', str(wrapper), '--', *child]
        log = (target / 'controller.log').open('wb')
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        entry = dict(label=label, target=target, process=process, log=log, command=command,
                     state=state, selector=selector, mode=mode, start=time.monotonic())
        active.append(entry)
        return entry

    def wait_file(path, process, seconds=10):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if path.exists():
                try:
                    return json.loads(path.read_text())
                except json.JSONDecodeError:
                    pass
            if process.poll() is not None:
                break
            select.select([], [], [], 0.01)
        raise AssertionError('Expected worker observation did not arrive: ' + str(path))

    def finish(entry, success=True, error_type=None):
        code = entry['process'].wait(timeout=35)
        entry['log'].close()
        result_path = entry['target'] / 'supervisor/result.json'
        deadline = time.monotonic() + 10
        while True:
            try:
                result = json.loads(result_path.read_text())
                if result.get('state') == 'complete':
                    break
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            if time.monotonic() >= deadline:
                raise AssertionError('Supervisor did not produce a terminal receipt: ' + str(result_path))
            select.select([], [], [], 0.01)
        record = dict(label=entry['label'], argv=entry['command'], exitCode=code,
                      seconds=time.monotonic() - entry['start'], result=str(result_path), expectedSuccess=success)
        if not any(saved['label'] == entry['label'] for saved in records):
            records.append(record)
        (args.output / 'commands.json').write_text(json.dumps(records, indent=2) + '\n')
        assert result['rootRemoved'] and not Path(result['root']).exists(), result
        assert result['processes'] and all(p['exitObserved'] for p in result['processes']), result
        assert not [error for error in result['errors'] if error['phase'] == 'cleanup'], result
        assert result['serverState'] == entry['state'], result
        assert result['socketExistsBeforeExample'] == (entry['state'] == 'running'), result
        if success:
            assert code == 0 and result['passed'], result
            body = json.loads((entry['target'] / 'body.json').read_text())
            assert body['Passed'], body
        else:
            assert not result['passed'], result
            if error_type:
                assert any(error['type'] == error_type for error in result['errors']), result
        if entry['mode'] == 'body':
            body = json.loads((entry['target'] / 'body.json').read_text())
            assert not body['Passed'] and 'injected ordinary example body failure' in body['Failure'], body
            assert body['PartialWorkspaceObserved'], body
        active.remove(entry)
        print(json.dumps(record), flush=True)
        return result

    try:
        if args.checks in ('all', 'examples'):
            for index, binary in enumerate(args.tmux):
                for state in ('absent', 'running'):
                    for selector in ('path', 'name'):
                        finish(start(f'example-{index}-{state}-{selector}', binary, state, selector))
        if args.checks in ('all', 'api'):
            for index, binary in enumerate(dict.fromkeys((args.tmux[0], args.tmux[-1]))):
                for state in ('absent', 'running'):
                    for selector in ('path', 'name'):
                        finish(start(f'api-{index}-{state}-{selector}', binary, state, selector,
                                     script='tests/StartServer.Tests.ps1'))
        if args.checks in ('all', 'faults'):
            binary = args.tmux[-1]
            for state in ('absent', 'running'):
                for selector in ('path', 'name'):
                    finish(start(f'body-{state}-{selector}', binary, state, selector, mode='body'),
                           success=False, error_type='RuntimeError')
            entry = start('timeout-absent-path', binary, 'absent', 'path', mode='hold', timeout=8)
            wait_file(entry['target'] / 'body.json', entry['process'])
            finish(entry, success=False, error_type='TimeoutError')
            for number, state, selector in ((signal.SIGINT, 'running', 'path'), (signal.SIGKILL, 'absent', 'name')):
                entry = start('controller-' + number.name, binary, state, selector, mode='hold')
                wait_file(entry['target'] / 'body.json', entry['process'])
                entry['process'].send_signal(number)
                finish(entry, success=False, error_type='InterruptedError')
            first = start('parallel-first', binary, 'absent', 'path', mode='hold')
            second = start('parallel-second', binary, 'absent', 'name', mode='hold')
            one = wait_file(first['target'] / 'body.json', first['process'])
            two = wait_file(second['target'] / 'body.json', second['process'])
            assert one['DaemonPid'] != two['DaemonPid']
            first['process'].send_signal(signal.SIGINT)
            finish(first, success=False, error_type='InterruptedError')
            live = json.loads((second['target'] / 'supervisor/result.json').read_text())
            child_env = dict(os.environ)
            for key in ('TMUX', 'TMUX_PANE'):
                child_env.pop(key, None)
            reply = subprocess.run([binary, '-N', '-S', live['socket'], 'has-session', '-t', '=libtmux-demo'],
                                   env=child_env, capture_output=True, timeout=2)
            assert reply.returncode == 0, reply.stderr
            subprocess.run([binary, '-N', '-S', live['socket'], 'wait-for', '-S', 'ordinary-example-release'],
                           env=child_env, check=True, timeout=2)
            finish(second)
        assert dict(os.environ) == original_environment
        (args.output / 'summary.json').write_text(json.dumps({
            'passed': True, 'invocations': len(records), 'parentEnvironmentUnchanged': True,
            'runner': str(runner), 'runnerSha256': hashlib.sha256(runner.read_bytes()).hexdigest(),
            'exampleSha256': hashlib.sha256((repo / 'examples/QuickStart.ps1').read_bytes()).hexdigest(),
            'tmuxVersions': [subprocess.check_output([binary, '-V'], text=True).strip() for binary in args.tmux],
        }, indent=2) + '\n')
    finally:
        for entry in list(active):
            if entry['process'].poll() is None:
                entry['process'].send_signal(signal.SIGINT)
            # The independent supervisor must finish, even if this assertion driver fails.
            try:
                finish(entry, success=False)
            except BaseException as failure:
                print('Retained failed invocation: ' + str(failure), file=sys.stderr)


if __name__ == '__main__':
    main()
