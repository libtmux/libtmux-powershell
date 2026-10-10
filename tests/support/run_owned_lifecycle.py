"""Run PowerShell lifecycle cases with foreground daemon and descendant exit receipts."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import select
import selectors
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pwsh', required=True)
    parser.add_argument('--tmux', required=True)
    parser.add_argument('--module-root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--selector', choices=('path', 'name'), default='path')
    parser.add_argument('--script', type=Path)
    parser.add_argument('--timeout', type=float, default=25)
    parser.add_argument('--fault', default='')
    parser.add_argument('--document', type=Path)
    parser.add_argument('--expected-reason', choices=('completed', 'timeout', 'killed-after-marker'), default='completed')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    args.output.mkdir(parents=True, exist_ok=False)
    if ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0):
        raise OSError(ctypes.get_errno(), 'Cannot become fixture subreaper')
    root = Path(tempfile.mkdtemp(prefix='libtmux-powershell-', dir='/tmp'))
    root_identity = (root.stat().st_dev, root.stat().st_ino)
    socket_dir = root
    if args.selector == 'name':
        socket_dir = root / ('tmux-' + str(os.getuid()))
        socket_dir.mkdir(mode=0o700)
    endpoint = socket_dir / 'socket'
    (root / 'runner').mkdir()
    control = socket.socket(socket.AF_UNIX)
    control.bind(str(root / 'runner/control'))
    control.listen(8)
    control.setblocking(False)
    monitor = selectors.DefaultSelector()
    monitor.register(control, selectors.EVENT_READ)
    binary_dir = root / 'bin'
    binary_dir.mkdir()
    wrapper = binary_dir / 'tmux'
    wrapper.write_text('#!' + sys.executable + '\n' + (repo / 'tests/support/scope_tmux.py').read_text())
    wrapper.chmod(0o700)
    (root / 'fault').write_text(args.fault)
    environment = dict(os.environ)
    environment.pop('TMUX', None)
    environment.pop('TMUX_PANE', None)
    environment.update(PATH=str(binary_dir) + os.pathsep + environment.get('PATH', ''),
                       PSModulePath=str(args.module_root.resolve()),
                       LIBTMUX_SOCKET_PATH=str(endpoint) if args.selector == 'path' else '',
                       LIBTMUX_SOCKET_NAME='socket' if args.selector == 'name' else '../ignored',
                       TMUX_TMPDIR=str(root), LIBTMUX_SCOPE_ROOT=str(root),
                       LIBTMUX_SCOPE_SOCKET_DIRECTORY=str(socket_dir),
                       LIBTMUX_SCOPE_CONTROL=str(root / 'runner/control'),
                       LIBTMUX_SCOPE_BINARY=args.tmux, LIBTMUX_SCOPE_FAULT=str(root / 'fault'),
                       LIBTMUX_SCOPE_TRACE=str(root / 'trace'))
    if args.document:
        environment['LIBTMUX_SCOPE_DOCUMENT'] = str(args.document.resolve())
    environment['LIBTMUX_SCOPE_MODE'] = args.fault
    processes = []
    accepted = {}
    records = []
    daemons = {}
    files = []
    result = {'root': str(root), 'rootIdentity': list(root_identity), 'selector': args.selector, 'events': records}

    def process_state(pid):
        fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
        return fields[0], int(fields[1]), fields[19]

    def belongs(pid):
        seen = set()
        while pid != os.getpid():
            if pid in seen or pid <= 1:
                return False
            seen.add(pid)
            try:
                _, pid, _ = process_state(pid)
            except FileNotFoundError:
                return False
        return True

    def accept(pid, origin):
        before = process_state(pid)
        if pid in accepted:
            old = accepted[pid]
            if not select.select([old], [], [], 0)[0] or before[0] == 'Z':
                return
            records.append({'event': 'exit-observed-before-pid-reuse', 'pid': pid,
                            'observed': True, 'time': time.monotonic()})
            os.close(old)
            del accepted[pid]
        fd = os.pidfd_open(pid)
        try:
            if process_state(pid)[1:] != before[1:] or not belongs(pid):
                os.close(fd)
                return
        except OSError:
            os.close(fd)
            raise
        accepted[pid] = fd
        records.append({'event': 'accepted', 'pid': pid, 'origin': origin,
                        'startTicks': before[2], 'time': time.monotonic()})

    def descendants():
        pending = [os.getpid()]
        seen = set()
        while pending:
            parent = pending.pop()
            try:
                children = Path(f'/proc/{parent}/task/{parent}/children').read_text().split()
            except (FileNotFoundError, ProcessLookupError):
                # /proc may report ESRCH while an already accepted process exits.
                continue
            for child in children:
                pid = int(child)
                if pid in seen:
                    continue
                seen.add(pid)
                try:
                    # A live ancestry chain is the authority, never a remembered numeric PID.
                    accept(pid, 'descendant')
                    pending.append(pid)
                except (ProcessLookupError, FileNotFoundError):
                    pass
        return seen

    def observe_descendants():
        try:
            descendants()
        except OSError as failure:
            result.setdefault("inventoryErrors", []).append(str(failure))

    def native(path, *commands, env=None):
        return subprocess.run([args.tmux, '-S', str(path), '-N', *commands],
                              env=env or environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, timeout=1)

    def start_daemon(path, markers):
        path = Path(path)
        if path.parent not in (root, socket_dir):
            raise ValueError('Requested daemon lies outside the exact fixture root.')
        if path in daemons and daemons[path].poll() is None:
            return
        daemon_env = dict(environment, **markers)
        daemon_env['PATH'] = os.environ.get('PATH', '/usr/bin:/bin')
        log = (args.output / ('daemon-' + str(len(daemons)) + '.log')).open('ab')
        files.append(log)
        process = subprocess.Popen([args.tmux, '-f', '/dev/null', '-D', '-S', str(path)],
                                   env=daemon_env, stdout=log, stderr=subprocess.STDOUT)
        processes.append(process)
        accept(process.pid, 'foreground-daemon')
        daemons[path] = process
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError('Foreground daemon exited during startup.')
            if path.exists():
                reply = native(path, 'display-message', '-p', '#{pid}')
                if reply.returncode == 0 and reply.stdout.strip() == str(process.pid):
                    return
            select.select([accepted[process.pid]], [], [], 0.005)
        raise TimeoutError('Accepted foreground daemon never answered its PID probe.')

    worker = None
    try:
        start_daemon(endpoint, {})
        reply = native(endpoint, 'new-session', '-d', '-s', 'fixture', '-x', '120', '-y', '50', 'exec /bin/sh')
        if reply.returncode:
            raise RuntimeError(reply.stderr)
        script = args.script.resolve() if args.script else repo / 'tests/OwnedLifecycle.Tests.ps1'
        result['script'] = str(script)
        result['scriptSHA256'] = hashlib.sha256(script.read_bytes()).hexdigest()
        shutil.copyfile(script, args.output / 'executed-source.ps1')
        output = (args.output / 'worker.log').open('wb')
        files.append(output)
        worker = subprocess.Popen([args.pwsh, '-NoLogo', '-NoProfile', '-File', str(script),
                                   '-ModuleRoot', str(args.module_root.resolve())],
                                  cwd=repo, env=environment, stdout=output, stderr=subprocess.STDOUT)
        processes.append(worker)
        accept(worker.pid, 'worker')
        deadline = time.monotonic() + args.timeout
        reason = 'completed'
        while worker.poll() is None:
            for daemon in daemons.values():
                daemon.poll()
            observe_descendants()
            if time.monotonic() >= deadline:
                reason = 'timeout'
                signal.pidfd_send_signal(accepted[worker.pid], signal.SIGKILL)
                worker.wait(timeout=2)
                break
            if args.fault == 'crash' and (root / 'body-entered').exists():
                reason = 'killed-after-marker'
                signal.pidfd_send_signal(accepted[worker.pid], signal.SIGKILL)
                worker.wait(timeout=2)
                break
            for key, _ in monitor.select(0.005):
                channel, _ = key.fileobj.accept()
                with channel:
                    channel.settimeout(1)
                    try:
                        request = json.loads(channel.makefile('r').readline())
                        markers = request['markers']
                        if any(not key.startswith('LIBTMUX_START_') or not isinstance(value, str) for key, value in markers.items()):
                            raise ValueError('Invalid startup markers')
                        start_daemon(request['socket'], markers)
                        response = {'ok': True}
                    except Exception as failure:
                        response = {'ok': False, 'error': str(failure)}
                    channel.sendall((json.dumps(response) + '\n').encode())
        result.update(exitCode=worker.returncode, reason=reason, bodyEntered=(root / 'body-entered').exists())
        if hashlib.sha256(script.read_bytes()).hexdigest() != result['scriptSHA256']:
            raise RuntimeError('Executed script source changed during its run.')
    except Exception as failure:
        result['failure'] = str(failure)
    finally:
        observe_descendants()
        for pid, fd in list(accepted.items()):
            if not select.select([fd], [], [], 0)[0]:
                try:
                    signal.pidfd_send_signal(fd, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                except OSError as failure:
                    result.setdefault('cleanupErrors', []).append(str(failure))
        for process in processes:
            try:
                if process.poll() is None:
                    # Only this parent reaps these accepted direct Popen children.
                    process.kill()
                process.wait(timeout=2)
            except (OSError, subprocess.TimeoutExpired) as failure:
                result.setdefault('cleanupErrors', []).append(str(failure))
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            observe_descendants()
            while True:
                try:
                    pid, _ = os.waitpid(-1, os.WNOHANG)
                except ChildProcessError:
                    pid = 0
                if not pid:
                    break
            alive = [pid for pid, fd in accepted.items() if not select.select([fd], [], [], 0)[0]]
            if not alive:
                break
            for pid in alive:
                try:
                    signal.pidfd_send_signal(accepted[pid], signal.SIGKILL)
                except ProcessLookupError:
                    pass
                except OSError as failure:
                    result.setdefault('cleanupErrors', []).append(str(failure))
            select.select([accepted[pid] for pid in alive], [], [], 0.01)
        exited = {str(pid): bool(select.select([fd], [], [], 0)[0]) for pid, fd in accepted.items()}
        result['exitObserved'] = exited
        result['directChildrenExited'] = all(process.poll() is not None for process in processes)
        result['rootRemoved'] = False
        for pid, observed in exited.items():
            records.append({'event': 'exit-observed', 'pid': int(pid), 'observed': observed, 'time': time.monotonic()})
        if (root / 'trace').exists():
            shutil.copyfile(root / 'trace', args.output / 'calls.jsonl')
        for stream in files:
            stream.close()
        control.close()
        monitor.close()
        if (all(exited.values()) and result['directChildrenExited'] and not result.get('inventoryErrors')
                and (root.stat().st_dev, root.stat().st_ino) == root_identity):
            shutil.rmtree(root)
            result['rootRemoved'] = True
            records.append({'event': 'root-removed', 'time': time.monotonic()})
        for fd in accepted.values():
            os.close(fd)
        (args.output / 'receipt.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key not in ('events', 'exitObserved')}))
    expected = result.get('reason') == args.expected_reason
    if args.expected_reason == 'completed':
        expected = expected and result.get('exitCode') == 0
    else:
        expected = expected and result.get('bodyEntered') and result.get('exitCode') == -signal.SIGKILL
    return 0 if expected and result.get('rootRemoved') and 'failure' not in result else 1


if __name__ == '__main__':
    sys.exit(main())
