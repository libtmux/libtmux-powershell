"""Restrict example clients to the external runner's endpoint and omit personal config."""
import json
import os
from pathlib import Path
import sys

arguments = sys.argv[1:]
root = Path(os.environ['TMUX_TMPDIR']).resolve()
endpoint = (Path(os.environ['LIBTMUX_SOCKET_PATH']) if os.environ.get('LIBTMUX_SOCKET_PATH')
            else root / ('tmux-' + str(os.getuid())) / os.environ['LIBTMUX_SOCKET_NAME'])
if '-V' not in arguments:
    if '-S' not in arguments or Path(arguments[arguments.index('-S') + 1]) != endpoint:
        raise SystemExit('Ordinary example harness refused an endpoint outside its run.')
    if root not in endpoint.parents:
        raise SystemExit('Ordinary example endpoint is outside its owned root.')
fault_path = os.environ.get('LIBTMUX_ORDINARY_FAULT')
fault = Path(fault_path).read_text().strip() if fault_path else ''
trace = os.environ.get('LIBTMUX_ORDINARY_TRACE')
if trace:
    with Path(trace).open('a') as stream:
        stream.write(json.dumps({'arguments': arguments, 'fault': fault}) + '\n')
if fault == 'body' and 'new-window' in arguments:
    raise SystemExit('injected ordinary example body failure')
if fault == 'cleanup' and 'kill-server' in arguments:
    raise SystemExit('injected ordinary startup cleanup failure')
if '-f' not in arguments and '-V' not in arguments:
    arguments = ['-f', '/dev/null', *arguments]
binary = os.environ['LIBTMUX_ORDINARY_TMUX']
os.execv(binary, [binary, *arguments])
