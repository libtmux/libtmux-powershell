"""Guard and fault-inject clients of the outer lifecycle fixture."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys

args = sys.argv[1:]
root = Path(os.environ['LIBTMUX_SCOPE_ROOT'])
real = os.environ['LIBTMUX_SCOPE_BINARY']
if args == ['-V']:
    os.execv(real, [real, *args])
if '-S' not in args:
    sys.exit('Scope fixture requires an explicit captured socket path.')
endpoint = Path(args[args.index('-S') + 1])
if endpoint.parent not in (root, root / ('tmux-' + str(os.getuid()))):
    sys.exit('Scope fixture refused an endpoint outside its exact root.')
if 'TMUX' in os.environ or 'TMUX_PANE' in os.environ:
    sys.exit('Scope fixture observed an inherited tmux context.')
markers = {key: value for key, value in os.environ.items() if key.startswith('LIBTMUX_START_')}
if ('new-session' in args and markers) or '--fixture-start' in args:
    request = {'socket': str(endpoint), 'markers': markers}
    with socket.socket(socket.AF_UNIX) as control:
        control.connect(os.environ['LIBTMUX_SCOPE_CONTROL'])
        control.sendall((json.dumps(request) + '\n').encode())
        answer = control.makefile('r').readline()
        reply = json.loads(answer)
        if not reply.get('ok'):
            sys.exit(reply.get('error', 'Fixture startup failed.'))
    if '--fixture-start' in args:
        sys.exit(0)
fault = Path(os.environ['LIBTMUX_SCOPE_FAULT']).read_text().strip()
with Path(os.environ['LIBTMUX_SCOPE_TRACE']).open('a') as stream:
    stream.write(json.dumps({'arguments': args, 'fault': fault}) + '\n')
is_cleanup = any('kill-session' in value or 'kill-window' in value or 'kill-pane' in value or 'kill-server' in value for value in args)
if 'list-windows' in args and fault in ('body', 'both', 'timeout', 'crash'):
    if fault in ('timeout', 'crash'):
        import signal
        (root / 'body-entered').write_text('accepted session reached its window query')
        signal.pause()
    print('injected scope body failure', file=sys.stderr)
    sys.exit(54)
if is_cleanup and fault in ('cleanup', 'both'):
    print('injected scope cleanup failure', file=sys.stderr)
    sys.exit(55)
if is_cleanup and fault == 'no-cleanup':
    # Preserve the identity reply so only the destructive command is omitted.
    args = [value.replace('kill-session', 'display-message').replace('kill-window', 'display-message').replace('kill-pane', 'display-message') for value in args]
if 'new-session' in args and fault in ('receipt', 'receipt-lost'):
    result = subprocess.run([real, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if fault == 'receipt-lost':
        import signal
        (root / 'receipt-lost').write_text('creation completed before its reply was lost')
        signal.pause()
    sys.stdout.buffer.write(result.stdout)
    sys.stderr.buffer.write(result.stderr)
    print('injected nonzero creation result', file=sys.stderr)
    sys.exit(77)
os.execv(real, [real, *args])
