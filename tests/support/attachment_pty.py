"""Installed-module outer gate. PowerShell owns the borrowed daemon and panes."""

import argparse
from contextlib import closing
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pty
import select
import selectors
import signal
import struct
import subprocess
import sys
import termios
import threading
import time
import uuid

# Bounds one step that waits on a process or a tmux event. It stops a hang and
# costs nothing otherwise, because every wait returns when its event happens.
HANG_GUARD = 30


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


def terminal_attributes(master):
    # Read through the master. When the session leader exits, XNU revokes the
    # controlling terminal and every descriptor still open on the slave side
    # answers ENOTTY, while the master keeps reporting the line discipline.
    return termios.tcgetattr(master)


def drain_until_eof(fd):
    # tmux stops reading a pane while every client attached to it is a control
    # client with unread output, so a control client must be read continuously.
    def drain():
        try:
            while os.read(fd, 8192):
                pass
        except OSError:
            pass

    reader = threading.Thread(target=drain, daemon=True)
    reader.start()
    return reader


def stop_group(process):
    # Every long-lived child starts a fresh process group owned by this harness.
    # A reaped leader no longer pins its PID against reuse by another group.
    if process.returncode is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    except PermissionError as failure:
        # Darwin's killpg excludes zombies and reports EPERM for a group
        # containing only exited members. Verify that no live member remains.
        if failure.errno != errno.EPERM or exit_status_unreaped(process) is None:
            raise
        rows = subprocess.run(["ps", "-A", "-o", "pid=", "-o", "pgid=", "-o", "stat="],
                              capture_output=True, text=True, check=True, timeout=1).stdout
        for line in rows.splitlines():
            _member_pid, pgid, state = line.split()
            if int(pgid) == process.pid and not state.startswith("Z"):
                raise failure
    process.wait(timeout=HANG_GUARD)


def exit_status_unreaped(process):
    result = os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOWAIT | os.WNOHANG)
    if result is None:
        return None
    if result.si_pid != process.pid:
        raise AssertionError("Owned child status has the wrong process ID")
    return result.si_status if result.si_code == os.CLD_EXITED else -result.si_status


def stop_group_preserving_error(process, failure):
    try:
        stop_group(process)
    except BaseException as cleanup_failure:
        failure.add_note(f"Owned process cleanup also failed: {cleanup_failure!r}")


def record_timeout_before_cleanup(failure, on_timeout):
    if isinstance(failure, subprocess.TimeoutExpired) and on_timeout is not None:
        try:
            on_timeout()
        except BaseException as diagnostic_failure:
            failure.add_note(f"Attachment timeout diagnostic failed: {diagnostic_failure!r}")


def wait_unreaped_darwin(process, timeout):
    status = exit_status_unreaped(process)
    if status is not None:
        return status
    with closing(select.kqueue()) as events:
        change = select.kevent(process.pid, filter=select.KQ_FILTER_PROC,
                               flags=select.KQ_EV_ADD, fflags=select.KQ_NOTE_EXIT)
        try:
            events.control([change], 0, 0)
        except ProcessLookupError:
            status = exit_status_unreaped(process)
            if status is None:
                raise
            return status
        status = exit_status_unreaped(process)
        if status is not None:
            return status
        notified = events.control(None, 1, timeout)
        if not notified:
            raise subprocess.TimeoutExpired(process.args, timeout)
        event = notified[0]
        if event.flags & select.KQ_EV_ERROR:
            raise OSError(event.data, os.strerror(event.data))
        if event.ident != process.pid or not event.fflags & select.KQ_NOTE_EXIT:
            raise AssertionError("Unexpected owned process event")
        status = exit_status_unreaped(process)
        if status is None:
            raise AssertionError("Owned exit event has no child status")
        return status


def wait_unreaped(process, timeout, on_timeout=None):
    if sys.platform == "darwin":
        # A blocking waitid observer can remain asleep after another thread
        # reaps the child during timeout cleanup; kqueue has a bounded wait.
        try:
            return wait_unreaped_darwin(process, timeout)
        except BaseException as failure:
            record_timeout_before_cleanup(failure, on_timeout)
            stop_group_preserving_error(process, failure)
            raise
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
    except BaseException as failure:
        record_timeout_before_cleanup(failure, on_timeout)
        stop_group_preserving_error(process, failure)
        raise
    finally:
        observer.join(timeout=1)
        if observer.is_alive():
            raise AssertionError("Owned exit observer did not finish after process cleanup")


def wait_unreaped_draining_pty(process, master, timeout, on_timeout=None):
    stop_read, stop_write = os.pipe()
    reader_errors = []
    output_bytes = 0

    def drain():
        nonlocal output_bytes
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(master, selectors.EVENT_READ)
                selector.register(stop_read, selectors.EVENT_READ)
                while True:
                    for key, _ in selector.select():
                        if key.fd == stop_read:
                            return
                        try:
                            block = os.read(master, 8192)
                        except OSError as failure:
                            if failure.errno == errno.EIO:
                                return
                            raise
                        if not block:
                            return
                        output_bytes += len(block)
        except BaseException as failure:
            reader_errors.append(failure)

    reader = threading.Thread(target=drain)
    reader.start()
    wait_error = None
    try:
        status = wait_unreaped(process, timeout, on_timeout=on_timeout)
    except BaseException as failure:
        wait_error = failure
        raise
    finally:
        try:
            os.write(stop_write, b"x")
            reader.join(timeout=0.5)
            if reader.is_alive():
                raise AssertionError("PTY output reader did not stop")
            if reader_errors:
                raise reader_errors[0]
        except BaseException as failure:
            if wait_error is None:
                raise
            wait_error.add_note(f"PTY output reader also failed: {failure!r}")
        finally:
            os.close(stop_read)
            os.close(stop_write)
    if output_bytes > 1024 * 1024:
        raise AssertionError("PTY output exceeded 1 MiB after attachment")
    return status


def attachment_timeout_diagnostics(process, result_path, prefix, environment):
    details = {}
    try:
        status = exit_status_unreaped(process)
        details["childExitStatus"] = status
        details["childExited"] = status is not None
    except BaseException as failure:
        details["childStatusError"] = repr(failure)

    try:
        if result_path.exists():
            with result_path.open("rb") as result_file:
                data = result_file.read(8193)
            truncated = len(data) > 8192
            content = data[:8192].decode("utf-8", errors="replace")
            if not truncated:
                try:
                    content = json.loads(content)
                except json.JSONDecodeError:
                    pass
            details["resultFile"] = {"present": True, "truncated": truncated, "content": content}
        else:
            details["resultFile"] = {"present": False}
    except BaseException as failure:
        details["resultFileError"] = repr(failure)

    try:
        result = subprocess.run(prefix + ["list-clients", "-F",
            "#{client_pid}|#{client_tty}|#{session_id}|#{client_readonly}"],
            env=environment, capture_output=True, timeout=0.4, check=False)
        details["clients"] = {"exitCode": result.returncode,
                              "rows": result.stdout.decode("utf-8", errors="replace").splitlines()[:16],
                              "stderr": result.stderr.decode("utf-8", errors="replace")[:256]}
    except BaseException as failure:
        details["clientsError"] = repr(failure)

    try:
        result = subprocess.run(["ps", "-A", "-o", "pid=", "-o", "pgid=", "-o", "stat="],
                                capture_output=True, text=True, timeout=0.4, check=False)
        members = []
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                pid, group, state = line.split()
                if int(group) == process.pid:
                    members.append({"pid": int(pid), "state": state})
        details["processGroup"] = {"exitCode": result.returncode, "members": members,
                                   "stderr": result.stderr[:256]}
    except BaseException as failure:
        details["processGroupError"] = repr(failure)
    return details


def run(args):
    started = time.monotonic()
    deadline = started + HANG_GUARD * len(args.modes)
    environment = {key: value for key, value in os.environ.items() if key not in ("TMUX", "TMUX_PANE")}
    environment.update(TERM="xterm-256color", SHELL="/bin/sh")
    prefix = [args.binary, "-S", args.socket, "-f", "/dev/null"]
    cases, cleanup_errors, owned = [], [], []
    report = {"status": "RUNNING", "cases": cases, "cleanupErrors": cleanup_errors,
              "tmuxSha256": hashlib.sha256(Path(args.binary).read_bytes()).hexdigest()}

    def remaining(limit=None):
        seconds = deadline - time.monotonic()
        if seconds <= 0:
            raise TimeoutError("Attachment PTY outer deadline expired")
        return seconds if limit is None else min(seconds, limit)

    def command(*arguments):
        return subprocess.run(prefix + list(arguments), env=environment, capture_output=True,
                              timeout=remaining(HANG_GUARD), check=True)

    def clients():
        rows = command("list-clients", "-F", "#{client_pid}|#{client_tty}|#{session_id}|#{client_readonly}").stdout.decode()
        return [row.split("|") for row in rows.splitlines()]

    def cleanup(label, action):
        try:
            action()
        except BaseException as failure:
            cleanup_errors.append(f"{label}: {failure!r}")

    sentinel = sentinel_reader = None
    try:
        report["tmuxVersion"] = command("display-message", "-p", "#{version}").stdout.decode().strip()
        generation = command("display-message", "-p", "#{pid}:#{start_time}").stdout.decode().strip()
        borrowed_windows = set(command("list-windows", "-t", args.session, "-F", "#{window_id}").stdout.decode().splitlines())
        sentinel = subprocess.Popen(prefix + ["-C", "attach-session", "-t", args.sentinel_session],
                                    env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, start_new_session=True)
        owned.append(sentinel)
        receive(sentinel.stdout.fileno(), b"%end ", seconds=remaining(HANG_GUARD))
        sentinel_reader = drain_until_eof(sentinel.stdout.fileno())

        for mode in args.modes:
            case_started = time.monotonic()
            cancel = "libtmux-powershell-attach-" + uuid.uuid4().hex
            result_path = Path(args.output).with_name(mode + ".json")
            master = slave = None
            ready_read = ready_write = None
            child = None
            preparation_seconds = attachment_seconds = None
            workspace_window = workspace_pane = None
            try:
                master, slave = pty.openpty()
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
                original = terminal_attributes(master)

                def terminal():
                    os.setsid()
                    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

                ready_read, ready_write = os.pipe()
                child = subprocess.Popen([args.pwsh, "-NoLogo", "-NoProfile", "-File",
                    str(Path(__file__).with_name("AttachmentChild.ps1")), "-ModuleRoot", args.module_root,
                    "-Binary", args.binary, "-Socket", args.socket, "-SessionId", args.session,
                    "-Mode", mode, "-CancelChannel", cancel, "-ResultPath", str(result_path),
                    "-ReadyHandle", str(ready_write)], stdin=slave, stdout=slave, stderr=slave,
                    env=environment, preexec_fn=terminal, pass_fds=(ready_write,))
                owned.append(child)
                os.close(ready_write)
                ready_write = None
                if mode in ("Detach", "ReadOnly", "Cancel"):
                    # Startup/import/help belong to the outer budget. Attachment
                    # gets its own hang guard after child preparation.
                    receive(ready_read, b"\x01", seconds=remaining())
                    preparation_seconds = time.monotonic() - case_started
                    attachment_started = time.monotonic()
                    # The pane's output persists in the PTY even if attach finishes first.
                    receive(master, b"LIBTMUX_ATTACHMENT_READY", seconds=remaining(HANG_GUARD))
                    attachment_seconds = time.monotonic() - attachment_started
                    rows = clients()
                    selected = [row for row in rows if row[2] == args.session]
                    assert len(selected) == 1, rows
                    assert selected[0][3] == ("1" if mode == "ReadOnly" else "0"), selected
                    if mode == "Detach":
                        active = command("display-message", "-p", "-t", args.session + ":",
                                         "#{window_name}|#{window_id}|#{pane_id}").stdout.decode().strip().split("|")
                        assert len(active) == 3 and active[0] == "workspace-attachment", active
                        workspace_window, workspace_pane = active[1:]
                    marker = ("PS_ATTACH_INPUT_" + uuid.uuid4().hex).encode()
                    os.write(master, marker + b"\r")
                    if mode == "ReadOnly":
                        command("detach-client", "-t", selected[0][1])
                    else:
                        receive(master, marker, seconds=remaining(HANG_GUARD))
                        assert marker in command("capture-pane", "-p", "-t", workspace_pane or args.session + ":").stdout
                        if mode == "Cancel":
                            command("wait-for", "-S", cancel)
                        else:
                            command("detach-client", "-t", selected[0][1])
                # Keep the exited leader as a zombie until group cleanup below.
                def on_child_timeout():
                    report["timeoutDiagnostics"] = {"mode": mode,
                        "preparationSeconds": preparation_seconds,
                        "attachmentSeconds": attachment_seconds,
                        **attachment_timeout_diagnostics(child, result_path, prefix, environment)}

                child_exit = wait_unreaped_draining_pty(child, master, timeout=remaining(HANG_GUARD),
                    on_timeout=on_child_timeout)
                if mode == "ReadOnly":
                    assert marker not in command("capture-pane", "-p", "-t", args.session + ":").stdout
                result = json.loads(result_path.read_text())
                expected = {"Cancel": "Stopped", "Nested": "NestedRejected", "WhatIf": "Previewed"}.get(mode, "Returned")
                assert child_exit == 0 and result["outcome"] == expected, result
                if mode == "Detach":
                    assert result["workspaceApplied"] is True, result
                    assert result["appliedSessionId"] == result["returnedId"] == args.session, result
                    assert result["workspaceWindowId"] == workspace_window, result
                    assert result["workspacePaneId"] == workspace_pane, result
                    assert command("show-window-options", "-v", "-t", workspace_window,
                                   "automatic-rename").stdout.strip() == b"off"
                    assert command("show-window-options", "-v", "-t", workspace_window,
                                   "@workspace-attachment").stdout.strip() == b"installed", "Applied workspace window option was not retained."
                    surviving_windows = set(command("list-windows", "-t", args.session,
                                                    "-F", "#{window_id}").stdout.decode().splitlines())
                    assert surviving_windows == borrowed_windows | {workspace_window}, surviving_windows
                rows = clients()
                assert len(rows) == 1 and rows[0][0] == str(sentinel.pid), rows
                assert command("display-message", "-p", "#{pid}:#{start_time}").stdout.decode().strip() == generation
                command("has-session", "-t", args.session)
                command("has-session", "-t", args.sentinel_session)
                restored = terminal_attributes(master) == original
                assert restored, "Terminal attributes were not restored"
                cases.append({"mode": mode, "status": "PASS", "seconds": time.monotonic() - case_started,
                              "preparationSeconds": preparation_seconds, "attachmentSeconds": attachment_seconds,
                              "result": result, "terminalRestored": restored,
                              "borrowedDaemonSessionsClientPreserved": True})
            finally:
                if child is not None:
                    cleanup(f"{mode} pwsh process group", lambda: stop_group(child))
                if ready_read is not None:
                    cleanup(f"{mode} readiness reader", lambda: os.close(ready_read))
                if ready_write is not None:
                    cleanup(f"{mode} readiness writer", lambda: os.close(ready_write))
                if master is not None:
                    cleanup(f"{mode} PTY master", lambda: os.close(master))
                if slave is not None:
                    cleanup(f"{mode} PTY slave", lambda: os.close(slave))
        report["status"] = "PASS"
    except BaseException as failure:
        report["status"] = "FAIL"
        report["failure"] = repr(failure)
        if getattr(failure, "__notes__", None):
            report["failureNotes"] = list(failure.__notes__)
    finally:
        # A failed child cleanup must never suppress sentinel cleanup or the receipt.
        if sentinel is not None:
            cleanup("sentinel process group", lambda: stop_group(sentinel))
            if sentinel_reader is not None:
                sentinel_reader.join(timeout=1)
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
