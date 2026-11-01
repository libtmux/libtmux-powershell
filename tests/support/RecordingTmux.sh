#!/bin/sh
# Stands in for tmux where a test checks what a tmux client is handed. Each call
# appends its argument list and the names of the selector variables it inherited
# to $LIBTMUX_TEST_RECORD, never a value, and fails as a tmux with no server does.
record=${LIBTMUX_TEST_RECORD:?LIBTMUX_TEST_RECORD must name the file to append to}
{
    printf 'call\n'
    for argument in "$@"; do printf 'arg\t%s\n' "$argument"; done
    [ -n "${TMUX+set}" ] && printf 'set\tTMUX\n'
    [ -n "${TMUX_PANE+set}" ] && printf 'set\tTMUX_PANE\n'
    # Every variable with the prefix, by name: sed keeps the name and drops the value.
    for name in $(env | sed -n 's/^\(LIBTMUX_SOCKET[A-Za-z0-9_]*\)=.*/\1/p'); do printf 'set\t%s\n' "$name"; done
    if [ -z "${TMUX_TMPDIR+set}" ]; then printf 'tmpdir\tunset\n'
    elif [ "$TMUX_TMPDIR" = "${LIBTMUX_TEST_SANDBOX-}" ]; then printf 'tmpdir\tsandbox\n'
    else printf 'tmpdir\tother\n'; fi
} >>"$record"
if [ "${1-}" = '-V' ]; then printf 'tmux 3.8\n'; exit 0; fi
printf 'recording tmux: no server running\n' >&2
exit 1
