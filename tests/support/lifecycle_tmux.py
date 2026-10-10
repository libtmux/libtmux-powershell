"""Forward only the harness-owned endpoint; inject failures outside the example."""

import json
import os
from pathlib import Path
import subprocess
import sys

arguments = sys.argv[1:]
socket = os.environ["LIBTMUX_LIFECYCLE_SOCKET"]
binary = os.environ["LIBTMUX_LIFECYCLE_BINARY"]
mode = os.environ["LIBTMUX_LIFECYCLE_MODE"]
trace = Path(os.environ["LIBTMUX_LIFECYCLE_TRACE"])
if "-V" not in arguments:
    if "-S" not in arguments or arguments[arguments.index("-S") + 1] != socket:
        sys.exit("Harness refused a tmux command outside its owned endpoint.")
if "TMUX" in os.environ or "TMUX_PANE" in os.environ:
    sys.exit("Harness observed an inherited tmux context in a launched client.")

record = {
    "arguments": arguments,
    "value": os.environ.get("LIBTMUX_LIFECYCLE_VALUE"),
    "removed": os.environ.get("LIBTMUX_LIFECYCLE_REMOVED"),
    "inherited": os.environ.get("LIBTMUX_LIFECYCLE_INHERITED"),
    "later": os.environ.get("LIBTMUX_LIFECYCLE_LATER"),
}
if "kill-session" in arguments:
    target = arguments[arguments.index("-t") + 1]
    prefix = [binary, "-S", socket, "-N"]
    record["target"] = target
    record["windows"] = subprocess.check_output(
        prefix + ["list-windows", "-t", target, "-F", "#{window_name}:#{window_panes}"],
        text=True,
    ).splitlines()
    record["panes"] = subprocess.check_output(
        prefix + ["list-panes", "-s", "-t", target, "-F", "#{pane_id}"], text=True
    ).splitlines()
    if mode == "Rename":
        subprocess.run(prefix + ["rename-session", "-t", target, "renamed"], check=True)
        record["renamed"] = True
with trace.open("a", encoding="utf-8") as output:
    output.write(json.dumps(record) + "\n")

if "split-window" in arguments and mode in ("Body", "Both"):
    sys.exit("injected example body failure")
if "kill-session" in arguments and mode in ("Cleanup", "Both"):
    sys.exit("injected example cleanup failure")
if "kill-session" in arguments and mode == "NoCleanup":
    # Keep the core generation guard's reply while deliberately omitting deletion.
    arguments = arguments[: arguments.index("kill-session")] + ["display-message", "-p", ""]
os.execv(binary, [binary, *arguments])
