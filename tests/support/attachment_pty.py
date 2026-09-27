"""Installed-module outer gate. PowerShell owns the borrowed daemon and panes."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pty
import selectors
import signal
import struct
import subprocess
import sys
import termios
import threading
import time
import uuid


def receive(fd, expected, seconds=5):
    data = bytearray()
    deadline = time.monotonic() + seconds
    with selectors.DefaultSelector() as selector:
        selector.register(fd, selectors.EVENT_READ)
        while expected not in data:
            if not selector.select(max(0, deadline - time.monotonic())):
                raise AssertionError(f"Missing terminal event {expected!r}; received {bytes(data)!r}")
            block = os.read(fd, 8192)
            if not block:
                raise AssertionError(f"EOF before {expected!r}")
            data.extend(block)
            if len(data) > 65536:
                raise AssertionError("Terminal event output exceeded 64 KiB")
    return bytes(data)


def stop_group(process):
    # Every long-lived child starts a fresh process group owned by this harness.
    # A reaped leader no longer pins its PID against reuse by another group.
    if process.returncode is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=1)


def wait_unreaped(process, timeout):
    completed = threading.Event()
    outcome = []

    def observe():
        try:
            outcome.append(os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOWAIT))
        except BaseException as failure:
            outcome.append(failure)
        finally:
            completed.set()

    observer = threading.Thread(target=observe)
    observer.start()
    try:
        if not completed.wait(timeout):
            raise subprocess.TimeoutExpired(process.args, timeout)
        result = outcome[0]
        if isinstance(result, BaseException):
            raise result
        return result.si_status if result.si_code == os.CLD_EXITED else -result.si_status
    except BaseException:
        stop_group(process)
        raise
    finally:
        observer.join(timeout=1)
        if observer.is_alive():
            raise AssertionError("Owned exit observer did not finish after process cleanup")


def run(args):
    started = time.monotonic()
    environment = {key: value for key, value in os.environ.items() if key not in ("TMUX", "TMUX_PANE")}
    environment.update(TERM="xterm-256color", SHELL="/bin/sh")
    prefix = [args.binary, "-S", args.socket, "-f", "/dev/null"]
    cases, cleanup_errors, owned = [], [], []
    report = {"status": "RUNNING", "cases": cases, "cleanupErrors": cleanup_errors,
              "tmuxSha256": hashlib.sha256(Path(args.binary).read_bytes()).hexdigest()}

    def command(*arguments):
        return subprocess.run(prefix + list(arguments), env=environment, capture_output=True,
                              timeout=5, check=True)

    def clients():
        rows = command("list-clients", "-F", "#{client_pid}|#{client_tty}|#{session_id}|#{client_readonly}").stdout.decode()
        return [row.split("|") for row in rows.splitlines()]

    def cleanup(label, action):
        try:
            action()
        except BaseException as failure:
            cleanup_errors.append(f"{label}: {failure!r}")

    sentinel = None
    try:
        report["tmuxVersion"] = command("display-message", "-p", "#{version}").stdout.decode().strip()
        generation = command("display-message", "-p", "#{pid}:#{start_time}").stdout.decode().strip()
        sentinel = subprocess.Popen(prefix + ["-C", "attach-session", "-t", args.sentinel_session],
                                    env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, start_new_session=True)
        owned.append(sentinel)
        receive(sentinel.stdout.fileno(), b"%end ")

        for mode in args.modes:
            case_started = time.monotonic()
            cancel = "libtmux-powershell-attach-" + uuid.uuid4().hex
            result_path = Path(args.output).with_name(mode + ".json")
            master = slave = None
            child = None
            try:
                master, slave = pty.openpty()
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
                original = termios.tcgetattr(slave)

                def terminal():
                    os.setsid()
                    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

                child = subprocess.Popen([args.pwsh, "-NoLogo", "-NoProfile", "-File",
                    str(Path(__file__).with_name("AttachmentChild.ps1")), "-ModuleRoot", args.module_root,
                    "-Binary", args.binary, "-Socket", args.socket, "-SessionId", args.session,
                    "-Mode", mode, "-CancelChannel", cancel, "-ResultPath", str(result_path)],
                    stdin=slave, stdout=slave, stderr=slave, env=environment, preexec_fn=terminal)
                owned.append(child)
                if mode in ("Detach", "ReadOnly", "Cancel"):
                    # The pane's output persists in the PTY even if attach finishes first.
                    receive(master, b"LIBTMUX_ATTACHMENT_READY")
                    rows = clients()
                    selected = [row for row in rows if row[2] == args.session]
                    assert len(selected) == 1, rows
                    assert selected[0][3] == ("1" if mode == "ReadOnly" else "0"), selected
                    marker = ("PS_ATTACH_INPUT_" + uuid.uuid4().hex).encode()
                    os.write(master, marker + b"\r")
                    if mode == "ReadOnly":
                        command("detach-client", "-t", selected[0][1])
                    else:
                        receive(master, marker)
                        assert marker in command("capture-pane", "-p", "-t", args.session + ":").stdout
                        if mode == "Cancel":
                            command("wait-for", "-S", cancel)
                        else:
                            command("detach-client", "-t", selected[0][1])
                # Keep the exited leader as a zombie until group cleanup below.
                child_exit = wait_unreaped(child, timeout=5)
                if mode == "ReadOnly":
                    assert marker not in command("capture-pane", "-p", "-t", args.session + ":").stdout
                result = json.loads(result_path.read_text())
                expected = {"Cancel": "Stopped", "Nested": "NestedRejected", "WhatIf": "Previewed"}.get(mode, "Returned")
                assert child_exit == 0 and result["outcome"] == expected, result
                rows = clients()
                assert len(rows) == 1 and rows[0][0] == str(sentinel.pid), rows
                assert command("display-message", "-p", "#{pid}:#{start_time}").stdout.decode().strip() == generation
                command("has-session", "-t", args.session)
                command("has-session", "-t", args.sentinel_session)
                restored = termios.tcgetattr(slave) == original
                assert restored, "Terminal attributes were not restored"
                cases.append({"mode": mode, "status": "PASS", "seconds": time.monotonic() - case_started,
                              "result": result, "terminalRestored": restored,
                              "borrowedDaemonSessionsClientPreserved": True})
            finally:
                if child is not None:
                    cleanup(f"{mode} pwsh process group", lambda: stop_group(child))
                if master is not None:
                    cleanup(f"{mode} PTY master", lambda: os.close(master))
                if slave is not None:
                    cleanup(f"{mode} PTY slave", lambda: os.close(slave))
        report["status"] = "PASS"
    except BaseException as failure:
        report["status"] = "FAIL"
        report["failure"] = repr(failure)
    finally:
        # A failed child cleanup must never suppress sentinel cleanup or the receipt.
        if sentinel is not None:
            cleanup("sentinel process group", lambda: stop_group(sentinel))
            for name in ("stdin", "stdout", "stderr"):
                stream = getattr(sentinel, name)
                if stream is not None:
                    cleanup("sentinel " + name, stream.close)
        report["ownedClientsExited"] = all(process.poll() is not None for process in owned)
        if cleanup_errors or not report["ownedClientsExited"]:
            report["status"] = "FAIL"
        report["seconds"] = time.monotonic() - started
        Path(args.output).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--module-root", required=True)
    parser.add_argument("--pwsh", required=True)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--socket", required=True)
    parser.add_argument("--session", required=True)
    parser.add_argument("--sentinel-session", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--modes", nargs="+", choices=("Detach", "ReadOnly", "Cancel", "Nested", "WhatIf"), required=True)
    sys.exit(run(parser.parse_args()))
