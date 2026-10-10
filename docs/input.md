# Send input to a pane

Select a native pane using `Get-TmuxPane` on the endpoint you intend to
change. Input commands use that pane's endpoint and daemon generation.
An arbitrary object's `Id` or `Pane` property does not bind as an owner.

| Command | Input | Enter behavior |
| --- | --- | --- |
| [Send-TmuxText](reference/LibTmux/Send-TmuxText.md) | Literal text, including spaces, dashes and tmux format markers | Appends one Enter only with `-Enter` |
| [Send-TmuxKey](reference/LibTmux/Send-TmuxKey.md) | An ordered string array of tmux key tokens | Send `Enter` explicitly as a token |

The [literal text example](reference/LibTmux/Send-TmuxText.md#example-1)
types the characters in a key name. The
[key sequence example](reference/LibTmux/Send-TmuxKey.md#example-1) sends
the corresponding control keys. Both examples run against an owned byte
receiver in the installed-help suite.

`Send-TmuxText` accepts empty text. NUL is rejected before dispatch; newlines
and other control characters are delivered. Newlines already in the text
can execute commands even when `-Enter` is omitted. Literal sending does
not quote text for the receiving shell or application.

`Send-TmuxKey` owns a snapshot of its input array and sends tokens in order.
It rejects null, empty and NUL-containing tokens. tmux interprets recognized
names such as `C-a`; unrecognized names follow tmux's character-sending
behavior. One string is not split into multiple tokens on whitespace.

Both commands support `-WhatIf` and `-Confirm`. A preview performs no
acquisition or input operation. Confirmation identifies the endpoint and
pane without displaying the supplied content. Successful commands emit no
objects; an empty owner pipeline performs no work.

Sending input confirms acceptance by tmux. Use
[Invoke-TmuxPaneCommand](reference/LibTmux/Invoke-TmuxPaneCommand.md) when a
shell command needs a verified exit status, or an explicit signal from the
receiving application before asserting completion or
[capturing its output](capture.md). Use
[Wait-TmuxChannel](reference/LibTmux/Wait-TmuxChannel.md) for a cooperative
`tmux wait-for -S` signal. Give each operation a unique channel with one waiter;
its timeout and cancellation cleanup withdraw the registration so it cannot
consume a later signal. A successful send is not a command result
or shell exit status.

Failures retain the original core exception, dispatch information and target
pane. `-ErrorAction Continue` permits later owners to run;
`-ErrorAction Stop` stops on the first failure. Cancellation stops pending
work but cannot undo input already delivered. A failed key sequence can leave
earlier keys applied. If literal text was sent but the following Enter fails,
the core reports unknown partial dispatch. Retrying can repeat effects;
the commands never retry automatically.

## Run a command to completion

`Invoke-TmuxPaneCommand` runs a shell command in a writable POSIX shell pane.
It returns a native `LibTmux.PaneRunResult` with an authenticated exit
status. A nonzero status remains a result; a timeout returns `TimedOut = True`
and a null status because the command may still be running. The command runs
in a subshell, so `cd` and `export` do not change the pane's parent shell.

Completion uses a cooperative tmux `wait-for` channel. While waiting, the
runner also checks authenticated run status and pane liveness, starting after
250 ms and backing off to five seconds. These checks detect a pane that exits
without signalling; they are separate from event-backed pane text waits.

With an endpoint in `$server`, create a shell pane and check the status rather
than guessing from a prompt or screen capture. The example removes only its
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

The result's `ExitStatus` is 7 and `TimedOut` is False. `Output` contains
bounded rendered command output, which can include both stdout and stderr.
It is not a byte-exact stream. The default view omits output text; inspect
`Output`, `LinesMissed`, `AnchorLost` and omission counts when needed.
`Get-TmuxPaneContent` reads the current pane screen separately. On timeout or cancellation after dispatch, inspect the pane
before retrying. The [cmdlet reference](reference/LibTmux/Invoke-TmuxPaneCommand.md)
describes history suppression, validation and confirmation.

## Wait for an application's readiness line

Use [Wait-TmuxPaneText](reference/LibTmux/Wait-TmuxPaneText.md) when an
application reports readiness in its terminal output. It observes rendered
text through a temporary control client, checks text already visible at entry,
then wakes on output or layout changes. It returns a native
`LibTmux.PaneWaitResult`; it does not require a cooperative tmux channel.

With Python 3 on `PATH` and the selected endpoint in `$server`, start a local
HTTP server on an available loopback port. Wait for its readiness line, then
make an HTTP request to verify that the server responds. The `finally` block
removes the session and stops the server process:

<!-- example: input.http-ready -->
```powershell
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

The observation is `PresentAtEntry` or `Matched`, followed by HTTP status 200.
The wait owns and closes its control client; it leaves the pane and daemon
running. The example separately owns its session and removes it.

Patterns use bounded .NET regular expressions and ignore case by default.
Use `-SimpleMatch` for literal text, `-CaseSensitive` for case-sensitive
matching, and `-StopPattern` for a terminal failure line. Stop patterns take
priority over wanted patterns. Without `-Pattern`, the wait returns on new
output. `TimedOut` and `PaneExited` are result outcomes; transport failures
and invalid patterns are errors. Ctrl+C cancels observation, not the
application. `-AllowPollingFallback` explicitly permits polling if control
observation fails; `PollingFallback` and `EventsDropped` disclose degradation.

Rendered text can include echoed input and can disappear on repaint or
scrollback eviction. A match proves the text condition, not an exit status
or continuing service health. The HTTP request above checks service behavior
separately. Inspect `LinesMissed`, `AnchorLost`, `OmittedTailLines` and
`OmittedTailBytes` before treating the bounded tail as complete output.
Use [command completion](#run-a-command-to-completion) for an authenticated
exit status and [event streams](watch.md) for individual notifications.

## Send a command and wait for its output

With an endpoint in `$server`, send literal text to a shell and use `-Enter`
to submit it. See [endpoint selection](read.md) for setup. The shell signals
a unique channel after printing, so capture waits for completed output. The
signal uses the endpoint's tmux executable and socket, with paths quoted for
the shell. A successful send alone means tmux accepted the input; it does not
establish that the receiving program finished.

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

The captured screen includes `hello from PowerShell`. `Wait-TmuxChannel`
accepts a signal that arrived before the wait, reports a timeout if no signal
arrives, and withdraws its waiter on timeout or Ctrl+C. Use one waiter per
unique channel: tmux withdrawal also wakes other waiters on that channel.
The example removes its `input-demo` session in `finally`.
`Send-TmuxKey` sends key tokens such as `C-c` or `Enter`; `Send-TmuxText`
sends those characters literally. Mutation commands also support `-WhatIf`
and `-Confirm`. See [capturing output](capture.md).
