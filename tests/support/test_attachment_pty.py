"""Process-group cleanup contracts for the owned attachment PTY."""

import errno
import fcntl
import os
from pathlib import Path
import pty
import signal
import subprocess
import sys
import termios
import time
from types import SimpleNamespace
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent))
import attachment_pty


def wait_unreaped(pid):
    deadline = time.monotonic() + 0.5
    while time.monotonic() < deadline:
        result = os.waitid(os.P_PID, pid, os.WEXITED | os.WNOWAIT | os.WNOHANG)
        if result is not None:
            return result
        os.sched_yield()
    raise AssertionError("Owned test child did not exit")


class ProcessGroupCleanupTests(unittest.TestCase):
    def test_terminal_output_is_drained_while_waiting_for_child_exit(self):
        master, slave = pty.openpty()
        process = None
        try:
            process = subprocess.Popen([sys.executable, "-c",
                "import os; os.write(1, b'READY'); data = memoryview(b'x' * 262144); "
                "\nwhile data: data = data[os.write(1, data):]"],
                stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
            attachment_pty.receive(master, b"READY", seconds=0.5)
            self.assertEqual(attachment_pty.wait_unreaped_draining_pty(
                process, master, timeout=0.5), 0)
        finally:
            if process is not None and process.returncode is None:
                attachment_pty.stop_group(process)
            os.close(master)
            os.close(slave)

    def test_timeout_diagnostics_precede_cleanup_and_keep_wait_error(self):
        process = SimpleNamespace(args=["owned-child"])
        timeout = subprocess.TimeoutExpired(process.args, 0.02)
        events = []

        def diagnose():
            events.append("diagnose")
            raise RuntimeError("diagnostic unavailable")

        def cleanup(_process, _failure):
            events.append("cleanup")

        with mock.patch.object(attachment_pty.sys, "platform", "darwin"), \
             mock.patch.object(attachment_pty, "wait_unreaped_darwin", side_effect=timeout), \
             mock.patch.object(attachment_pty, "stop_group_preserving_error", side_effect=cleanup):
            with self.assertRaises(subprocess.TimeoutExpired) as raised:
                attachment_pty.wait_unreaped(process, timeout=0.02, on_timeout=diagnose)
        self.assertIs(raised.exception, timeout)
        self.assertEqual(events, ["diagnose", "cleanup"])
        self.assertIn("diagnostic unavailable", " ".join(timeout.__notes__))

    def test_darwin_cleanup_failure_keeps_original_wait_error(self):
        process = SimpleNamespace(args=["owned-child"])
        timeout = subprocess.TimeoutExpired(process.args, 0.02)
        cleanup = PermissionError(errno.EPERM, "Operation not permitted")
        with mock.patch.object(attachment_pty.sys, "platform", "darwin"), \
             mock.patch.object(attachment_pty, "wait_unreaped_darwin", side_effect=timeout), \
             mock.patch.object(attachment_pty, "stop_group", side_effect=cleanup):
            with self.assertRaises(subprocess.TimeoutExpired) as raised:
                attachment_pty.wait_unreaped(process, timeout=0.02)
        self.assertIn("cleanup", " ".join(raised.exception.__notes__).lower())

    def test_zombie_only_eperm_reaps_owned_leader(self):
        process = subprocess.Popen(["/bin/sh", "-c", "exit 7"], start_new_session=True)
        try:
            wait_unreaped(process.pid)
            with mock.patch.object(attachment_pty.os, "killpg",
                                   side_effect=PermissionError(errno.EPERM, "Operation not permitted")):
                attachment_pty.stop_group(process)
            self.assertEqual(process.returncode, 7)
        finally:
            process.wait(timeout=1)

    def test_darwin_timeout_never_blocks_in_exit_observer(self):
        process = subprocess.Popen(["/bin/sleep", "10"], start_new_session=True)

        class EmptyQueue:
            def control(self, changes, count, timeout):
                return []

            def close(self):
                pass

        events = SimpleNamespace(kqueue=EmptyQueue, kevent=lambda *a, **kw: object(),
            KQ_FILTER_PROC=0, KQ_EV_ADD=1, KQ_NOTE_EXIT=1)
        real_waitid = os.waitid

        def nonblocking_waitid(kind, pid, flags):
            if not flags & os.WNOHANG:
                raise AssertionError("Blocking exit observer cannot be cancelled")
            return real_waitid(kind, pid, flags)

        try:
            with mock.patch.object(attachment_pty.sys, "platform", "darwin"), \
                 mock.patch.object(attachment_pty, "select", events, create=True), \
                 mock.patch.object(attachment_pty.os, "waitid", side_effect=nonblocking_waitid):
                with self.assertRaises(subprocess.TimeoutExpired):
                    attachment_pty.wait_unreaped(process, timeout=0.02)
            self.assertEqual(process.returncode, -signal.SIGKILL)
        finally:
            if process.returncode is None:
                attachment_pty.stop_group(process)

    def test_darwin_exit_event_keeps_leader_unreaped_for_group_cleanup(self):
        process = subprocess.Popen(["/bin/sleep", "10"], start_new_session=True)

        class ExitQueue:
            def control(self, changes, count, timeout):
                if changes is not None:
                    return []
                os.kill(process.pid, signal.SIGTERM)
                wait_unreaped(process.pid)
                return [SimpleNamespace(ident=process.pid, flags=0, fflags=1)]

            def close(self):
                pass

        events = SimpleNamespace(kqueue=ExitQueue, kevent=lambda *a, **kw: object(),
            KQ_FILTER_PROC=0, KQ_EV_ADD=1, KQ_EV_ERROR=2, KQ_NOTE_EXIT=1)
        try:
            with mock.patch.object(attachment_pty.sys, "platform", "darwin"), \
                 mock.patch.object(attachment_pty, "select", events):
                self.assertEqual(attachment_pty.wait_unreaped(process, timeout=0.5),
                                 -signal.SIGTERM)
            self.assertIsNone(process.returncode)
            attachment_pty.stop_group(process)
            self.assertEqual(process.returncode, -signal.SIGTERM)
        finally:
            if process.returncode is None:
                attachment_pty.stop_group(process)

    def test_eperm_with_live_owned_group_member_is_an_error(self):
        process = subprocess.Popen([sys.executable, "-c",
            "import os,subprocess; subprocess.Popen(['/bin/sleep','10']); os._exit(0)"],
            start_new_session=True)
        try:
            wait_unreaped(process.pid)
            with mock.patch.object(attachment_pty.os, "killpg",
                                   side_effect=PermissionError(errno.EPERM, "Operation not permitted")):
                with self.assertRaises(PermissionError):
                    attachment_pty.stop_group(process)
        finally:
            try:
                os.killpg(process.pid, 9)
            except ProcessLookupError:
                pass
            process.wait(timeout=1)


class TerminalAttributeTests(unittest.TestCase):
    def test_attributes_come_from_the_master_after_the_slave_is_revoked(self):
        master, slave = pty.openpty()
        real = termios.tcgetattr
        try:
            expected = real(master)

            def revoked_slave(fd):
                if fd == slave:
                    raise termios.error(errno.ENOTTY, "Inappropriate ioctl for device")
                return real(fd)

            with mock.patch.object(attachment_pty.termios, "tcgetattr", side_effect=revoked_slave):
                self.assertEqual(attachment_pty.terminal_attributes(master), expected)
        finally:
            os.close(master)
            os.close(slave)

    def test_attributes_survive_session_leader_exit(self):
        master, slave = pty.openpty()
        try:
            before = attachment_pty.terminal_attributes(master)

            def terminal():
                os.setsid()
                fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

            process = subprocess.Popen([sys.executable, "-c", "pass"], stdin=slave, stdout=slave,
                                       stderr=slave, preexec_fn=terminal)
            self.assertEqual(attachment_pty.wait_unreaped_draining_pty(process, master, timeout=5), 0)
            process.wait(timeout=1)
            self.assertEqual(attachment_pty.terminal_attributes(master), before)
        finally:
            os.close(master)
            os.close(slave)


if __name__ == "__main__":
    unittest.main()
