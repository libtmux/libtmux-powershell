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

Sending input confirms acceptance by tmux. Use an explicit signal from the
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
    $tmux = (Get-Command $server.ConnectionOptions.TmuxBinaryPath -CommandType Application |
        Select-Object -First 1).Source
    $selector = if ($server.ConnectionOptions.SocketPath) {
        "-S '{0}'" -f $server.ConnectionOptions.SocketPath.Replace("'", "'\''")
    } elseif ($server.ConnectionOptions.SocketName) {
        "-L '{0}'" -f $server.ConnectionOptions.SocketName.Replace("'", "'\''")
    } else { '' }
    $signal = "'{0}' {1} wait-for -S '{2}'" -f $tmux.Replace("'", "'\''"), $selector, $ready
    $session = $server | New-TmuxSession -Name 'input-demo' -Command 'exec /bin/sh'
    try {
        $pane = $session | Get-TmuxPane
        $pane | Send-TmuxText -Text ('printf "\nhello from PowerShell\n"; ' + $signal) -Enter
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
