"""Inject acquisition failures only at the shared supervisor's private endpoint."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

arguments = sys.argv[1:]
root = Path(os.environ['TMUX_TMPDIR']).resolve()
endpoint = (Path(os.environ['LIBTMUX_SOCKET_PATH']) if os.environ.get('LIBTMUX_SOCKET_PATH')
            else root / ('tmux-' + str(os.getuid())) / os.environ['LIBTMUX_SOCKET_NAME'])
if '-V' not in arguments:
    if '-S' not in arguments or Path(arguments[arguments.index('-S') + 1]) != endpoint:
        raise SystemExit('Recovery harness refused an endpoint outside its run.')
    if root not in endpoint.parents:
        raise SystemExit('Recovery endpoint is outside its owned root.')
fault_path = Path(os.environ['LIBTMUX_ORDINARY_FAULT'])
fault = fault_path.read_text().strip()
created = fault_path.with_suffix('.created')
with Path(os.environ['LIBTMUX_ORDINARY_TRACE']).open('a') as stream:
    stream.write(json.dumps({'arguments': arguments, 'fault': fault}) + '\n')
if '-f' not in arguments and '-V' not in arguments:
    arguments = ['-f', '/dev/null', *arguments]
binary = os.environ['LIBTMUX_ORDINARY_TMUX']
kind = fault.split('-')[-1]
if fault == 'startup' and 'set-option' in arguments and 'exit-empty' in arguments:
    raise SystemExit('injected acquisition startup failure')
if fault and ('kill-' + ('server' if fault == 'startup' else kind)) in arguments:
    raise SystemExit('injected acquisition rollback failure')
creation = {'session': 'new-session', 'window': 'new-window', 'pane': 'split-window'}.get(kind)
readback = ('list-' + kind + 's') in arguments or any('#{' + kind + '_id}' in value for value in arguments)
if created.exists() and readback and creation not in arguments:
    if fault.startswith('cancel-'):
        fault_path.with_suffix('.entered').write_text('readback reached')
        signal.pause()
    if fault.startswith('readback-'):
        raise SystemExit('injected acquisition readback failure')
if creation is not None and creation in arguments:
    result = subprocess.run([binary, *arguments], capture_output=True)
    if result.returncode == 0:
        created.write_text('creation receipt returned')
    if fault == 'unknown-session':
        print('unusable creation receipt')
        raise SystemExit('injected unknown creation receipt')
    sys.stdout.buffer.write(result.stdout)
    sys.stderr.buffer.write(result.stderr)
    raise SystemExit(result.returncode)
os.execv(binary, [binary, *arguments])
