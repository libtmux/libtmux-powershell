# Send input to a pane

Select a pane with `Get-TmuxPane` on the endpoint you intend to change. Input
commands use that pane's endpoint and daemon generation. Pipeline input must be
a `LibTmux.Pane`; an object with similar property names does not bind.

| Command | Input | Enter behavior |
| --- | --- | --- |
| [Send-TmuxText](reference/LibTmux/Send-TmuxText.md) | Literal text, including spaces, dashes and tmux format markers | Appends one Enter only with `-Enter` |
| [Send-TmuxKey](reference/LibTmux/Send-TmuxKey.md) | An ordered string array of tmux key tokens | Send `Enter` explicitly as a token |

The [literal text example](reference/LibTmux/Send-TmuxText.md#example-1) types
the characters in a key name. The
[key sequence example](reference/LibTmux/Send-TmuxKey.md#example-1) sends the
corresponding control keys.

- **`Send-TmuxText`:** accepts empty text and rejects NUL before dispatch.
  Newlines and other control characters are delivered, and a newline in the text
  can run a command even without `-Enter`. It does not quote text for the
  receiving shell or application.
- **`Send-TmuxKey`:** copies its input array and sends the tokens in order. It
  rejects null, empty and NUL-containing tokens. tmux interprets names such as
  `C-a`; unrecognized names send their characters. A string is not split on
  whitespace.
- **Preview:** both commands support `-WhatIf` and `-Confirm`. A preview
  acquires and sends nothing. Confirmation names the endpoint and pane, not the
  content.
- **Output:** success emits no objects, and an empty owner pipeline does no work.

A successful send means tmux accepted the input, not that a command finished or
exited. To know that, use
[Invoke-TmuxPaneCommand](reference/LibTmux/Invoke-TmuxPaneCommand.md) for a
shell command's exit status, or wait for a signal from the receiving
application before [capturing its output](capture.md).
[Wait-TmuxChannel](reference/LibTmux/Wait-TmuxChannel.md) waits for a
cooperative `tmux wait-for -S` signal. Give each operation a unique channel with
one waiter; timeout and cancellation withdraw the registration so it cannot
consume a later signal.

Failures:

- Errors keep the original core exception, dispatch information and target pane.
- `-ErrorAction Continue` lets later owners run; `-ErrorAction Stop` stops at the
  first failure.
- Cancellation stops pending work but cannot undo input already delivered. A
  failed key sequence can leave earlier keys applied. If literal text went out
  but the following Enter failed, the core reports unknown partial dispatch.
- Nothing retries automatically, and a retry can repeat effects.

## Run a command to completion

`Invoke-TmuxPaneCommand` runs a shell command in a writable POSIX shell pane
and returns a `LibTmux.PaneRunResult` with an authenticated exit status.

- **tmux 3.4 or newer:** it stages a temporary buffer that older releases cannot
  delete safely, so an older daemon is refused before any buffer exists.
- **Status:** a nonzero status is still a result. A timeout returns
  `TimedOut = True` and a null status, because the command may still be running.
- **Subshell:** the command runs in one, so `cd` and `export` do not change the
  pane's shell.
- **Completion:** it waits on a cooperative tmux `wait-for` channel. It also
  checks run status and pane liveness, from 250 ms backing off to five seconds,
  to detect a pane that exits without signalling.

With an endpoint in `$server`, create a shell pane and read the status instead
of guessing from a prompt or screen capture. The example removes only its
session:

<!-- example: input.run -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    $name = 'pane-run-' + [Guid]::NewGuid().ToString('N')
    $session = $server | New-TmuxSession -Name $name -Command 'exec /bin/sh'
    try {
        $pane = $session | Get-TmuxPane
        $pane |
            Invoke-TmuxPaneCommand -Command 'exit 7' -Timeout 5 -Confirm:$false
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
```

The result's `ExitStatus` is 7 and [`TimedOut`][panerunresult-timedout] is
False.

- `Output` holds bounded rendered output, which can mix stdout and stderr. It is
  not a byte-exact stream, and the default view omits it. Check
  [`LinesMissed`][panerunresult-linesmissed],
  [`AnchorLost`][panerunresult-anchorlost] and the omission counts when you need
  all of it.
- `Get-TmuxPaneContent` reads the current screen separately.
- After a timeout or a cancellation that followed dispatch, inspect the pane
  before retrying.

The [cmdlet reference](reference/LibTmux/Invoke-TmuxPaneCommand.md) covers
history suppression, validation and confirmation.

## Wait for an application's readiness line

Use [Wait-TmuxPaneText](reference/LibTmux/Wait-TmuxPaneText.md) when an
application reports readiness in its terminal output. It returns a
`LibTmux.PaneWaitResult` and needs no cooperative channel.

- **tmux 3.7 or newer:** it reads rendered text through a temporary control
  client, checks text already visible at entry, then wakes on output or layout
  changes.
- **Earlier releases:** it polls and attaches no control client.

With Python 3 on `PATH` and the selected endpoint in `$server`, this starts a
local HTTP server on a free loopback port, waits for its readiness line, then
requests a page. The `finally` block removes the session and stops the server:

<!-- example: input.http-ready -->
```powershell
Import-Module -Name LibTmux -ErrorAction Stop
& {
    $ErrorActionPreference = 'Stop'
    $session = $server | New-TmuxSession `
        -Name ('http-' + [Guid]::NewGuid().ToString('N')) `
        -Command 'exec python3 -u -m http.server 0 --bind 127.0.0.1'
    try {
        $pane = $session | Get-TmuxPane
        $ready = $pane | Wait-TmuxPaneText `
            -Pattern '^Serving HTTP on 127\.0\.0\.1 port [0-9]+' `
            -CaseSensitive -Timeout 10 -TailLines 4 -Confirm:$false
        if ($ready.Outcome -notin 'PresentAtEntry', 'Matched') {
            throw "HTTP readiness ended with $($ready.Outcome)."
        }
        $tail = $ready.Tail -join "`n"
        $port = [regex]::Match($tail, 'port ([0-9]+)').Groups[1].Value
        $uri = "http://127.0.0.1:$port/"
        $response = Invoke-WebRequest -Uri $uri -TimeoutSec 5 -NoProxy
        $ready
        $response.StatusCode
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
```

The outcome is `PresentAtEntry` or `Matched`, then HTTP status 200. The wait
closes any control client it creates and leaves the pane and daemon running; the
example removes its own session.

Matching:

- Patterns are bounded .NET regular expressions and ignore case by default.
  `-SimpleMatch` matches literal text, `-CaseSensitive` matches case, and
  `-StopPattern` names a terminal failure line that wins over a wanted pattern.
- Without `-Pattern`, the wait returns on new output.
- A pattern matches a line that wraps across rows as one line.

Outcomes and errors:

- [`TimedOut`][panewaitoutcome-timedout] and
  [`PaneExited`][panewaitoutcome-paneexited] are outcomes. Transport failures and
  invalid patterns are errors.
- A wait whose server is killed ends as `PaneExited` with the output read so
  far, and no error.
- Ctrl+C cancels the observation, not the application.
- On tmux 3.7 or newer, `-AllowPollingFallback` permits polling if control
  observation fails. Earlier releases always poll. `PollingFallback` and
  `EventsDropped` disclose degradation.

Rendered text can include echoed input and can vanish on repaint or scrollback
eviction. A match shows the text condition, not an exit status or lasting health;
the HTTP request above checks the service. Check
[`LinesMissed`][panewaitresult-linesmissed],
[`AnchorLost`][panewaitresult-anchorlost], `OmittedTailLines` and
`OmittedTailBytes` before treating the bounded tail as complete. For an exit
status see [command completion](#run-a-command-to-completion), and for
individual notifications see [event streams](watch.md).

## Send a command and wait for its output

With an endpoint in `$server` ([endpoint selection](read.md)), send literal
text to a shell and use `-Enter` to submit it. The shell signals a unique
channel after printing, so the capture waits for finished output. The signal uses
the endpoint's tmux executable and socket, quoted for the shell.

<!-- example: readme.input -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    $ready = 'libtmux-demo-' + [Guid]::NewGuid().ToString('N')
    $binary = $server.ConnectionOptions.TmuxBinaryPath
    $tmux = (Get-Command $binary -CommandType Application |
        Select-Object -First 1).Source
    $selector = if ($server.ConnectionOptions.SocketPath) {
        "-S '{0}'" -f $server.ConnectionOptions.SocketPath.Replace("'", "'\''")
    } elseif ($server.ConnectionOptions.SocketName) {
        "-L '{0}'" -f $server.ConnectionOptions.SocketName.Replace("'", "'\''")
    } else { '' }
    $quoted = $tmux.Replace("'", "'\''")
    $signal = "'{0}' {1} wait-for -S '{2}'" -f $quoted, $selector, $ready
    $session = $server |
        New-TmuxSession -Name 'input-demo' -Command 'exec /bin/sh'
    try {
        $pane = $session | Get-TmuxPane
        $text = 'printf "\nhello from PowerShell\n"; ' + $signal
        $pane | Send-TmuxText -Text $text -Enter
        $null = $server | Wait-TmuxChannel -Channel $ready -Timeout 10
        $pane | Get-TmuxPaneContent
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
```

The captured screen includes `hello from PowerShell`.

- `Wait-TmuxChannel` accepts a signal that arrived before the wait, reports a
  timeout if none arrives, and withdraws its waiter on timeout or Ctrl+C. Use one
  waiter per channel: withdrawal also wakes other waiters on it.
- `Send-TmuxKey` sends key tokens such as `C-c` or `Enter`; `Send-TmuxText`
  sends those characters literally.

More: [capturing output](capture.md).

[panerunresult-timedout]: https://libtmux.org/en/csharp/latest/reference/libtmux-panerunresult-timedout/
[panerunresult-linesmissed]: https://libtmux.org/en/csharp/latest/reference/libtmux-panerunresult-linesmissed/
[panerunresult-anchorlost]: https://libtmux.org/en/csharp/latest/reference/libtmux-panerunresult-anchorlost/
[panewaitoutcome-timedout]: https://libtmux.org/en/csharp/latest/reference/libtmux-panewaitoutcome-timedout/
[panewaitoutcome-paneexited]: https://libtmux.org/en/csharp/latest/reference/libtmux-panewaitoutcome-paneexited/
[panewaitresult-linesmissed]: https://libtmux.org/en/csharp/latest/reference/libtmux-panewaitresult-linesmissed/
[panewaitresult-anchorlost]: https://libtmux.org/en/csharp/latest/reference/libtmux-panewaitresult-anchorlost/
