---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Wait-TmuxChannel.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Wait-TmuxChannel
---

# Wait-TmuxChannel

## SYNOPSIS

Wait for a tmux channel signal with a timeout and owned withdrawal.

## SYNTAX

### __AllParameterSets

```text
Wait-TmuxChannel [-Server] <Server> [-Channel] <String> [-Timeout <Double>]
```

## ALIASES

None.

## DESCRIPTION

Wait on the supplied native server and emit True after observing a channel
signal. A pending signal from before the call also completes the wait. An
empty owner pipeline performs no work and emits no output.

Use one open waiter per channel and give each operation a unique channel.
tmux has no individual waiter deregistration: withdrawing signals the channel
and wakes every waiter registered there. This command owns and disposes its
wait, including on timeout or pipeline cancellation, so an abandoned client
cannot consume a later signal. The borrowed server remains running.

The timeout bounds the wait attempt. Withdrawal is awaited before returning;
cleanup time is additional. A signal racing withdrawal can leave the channel
pending for a later caller. Do not infer that no signal arrived from a timeout,
and do not reuse a channel to identify a different operation.

## EXAMPLES

### Example 1

Use a previously selected native $server and reserve build-finished for one
waiter. Have the producer run tmux wait-for -S build-finished on that server
after its work completes. The producer may signal before this command starts.

```powershell
$server | LibTmux\Wait-TmuxChannel -Channel 'build-finished' -Timeout 10
```

## PARAMETERS

### -Channel

The nonempty, non-whitespace channel reserved for this operation. NUL is rejected.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Server

The native server endpoint that owns the channel.

```yaml
Type: LibTmux.Server
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Timeout

The wait budget in seconds. Fractions are accepted. The default is 10; the
valid range is 0.0000001 through 86400. NaN and infinity are rejected.

```yaml
Type: System.Double
DefaultValue: '10'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Server

The native server to wait on.

## OUTPUTS

### System.Boolean

True after observing a signal. Timeout emits an error, not False.

## NOTES

Tmux.ChannelWaitFailed retains the native server as its target. Timeout uses
TimeoutException with the OperationTimeout category and emits no success
object. ErrorAction Continue permits later owners to run; ErrorAction Stop
terminates on failure. Ctrl+C cancels the attempt and withdraws the waiter
before the pipeline stops. Cancellation cannot undo work in the producer.
Invalid channels and timeouts fail before contacting tmux.

## RELATED LINKS

[Send input and wait for completion](../../input.md)
