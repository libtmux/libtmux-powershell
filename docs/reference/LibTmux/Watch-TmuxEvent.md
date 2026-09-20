---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Watch-TmuxEvent.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Watch-TmuxEvent
---

# Watch-TmuxEvent

## SYNOPSIS

Stream native tmux events with bounded delivery and explicit ownership.

## SYNTAX

### Connection (Default)

```text
Watch-TmuxEvent [-Connection] <IControlModeSession> [-MaxEventBytes <Int32>] [-MaxEvents <Int64>] [-MaxOutputBytes <Int64>] [-WhatIf] [-Confirm]
```

### Server

```text
Watch-TmuxEvent [-Server] <Server> [-Target] <String> [-MaxEventBytes <Int32>] [-MaxEvents <Int64>] [-MaxOutputBytes <Int64>] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Emit native TmuxEvent values in stream order. A supplied Connection is borrowed
and remains usable after cancellation or early pipeline exit. With Server and
Target, the command owns a new control client and closes it before returning.
Both forms borrow the daemon and its sessions. Output count and byte budgets
reset for each input connection or server; piping N owners can emit N times
MaxEvents.

There is one acknowledged handoff slot. The reader does not fetch the next
event until downstream processing returns. PowerShell output runs only on the
active pipeline callback; native command replies continue independently, so
downstream code may send through the same connection.

Only one Watch-TmuxEvent consumer may read a connection at a time. Direct
native Events readers remain the caller's responsibility: the stream is not
broadcast. Event output is decoded text fragments, not rendered pane contents,
lines, byte-exact output or a durable log. Loss and exit events are forwarded.

## EXAMPLES

### Example 1

Observe the first notification on fixture using a previously selected $server.
The command closes its new control client when the count limit is reached.

```powershell
$server | LibTmux\Watch-TmuxEvent -Target 'fixture' -MaxEvents 1 -MaxOutputBytes 1048576
```

## PARAMETERS

### -Confirm

Ask before attaching or consuming the event stream.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- cf
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

### -Connection

The borrowed native client. No other consumer may read its Events stream while this watch is active.

```yaml
Type: LibTmux.IControlModeSession
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Connection
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MaxEventBytes

Positive maximum UTF-8 text bytes in the one-event handoff. Default: 1048576. An oversized event fails before output.

```yaml
Type: System.Int32
DefaultValue: '1048576'
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

### -MaxEvents

Positive maximum emitted event count. Default: Int64.MaxValue. Reaching the limit ends the watch normally.

```yaml
Type: System.Int64
DefaultValue: '9223372036854775807'
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

### -MaxOutputBytes

Positive maximum cumulative emitted UTF-8 text bytes. Default: Int64.MaxValue. Reaching it exactly ends normally; an event too large for the remaining budget emits an error before that event.

```yaml
Type: System.Int64
DefaultValue: '9223372036854775807'
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

### -Server

The borrowed endpoint on which this command creates and owns one control client.

```yaml
Type: LibTmux.Server
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Server
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Target

The explicit raw tmux target to attach to. It has no captured session identity guard.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Server
  Position: 1
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WhatIf

Show the operation without attaching a client or consuming events.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- wi
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

### LibTmux.IControlModeSession

A borrowed native control client.

### LibTmux.Server

An endpoint on which to create an owned control client.

## OUTPUTS

### LibTmux.TmuxEvent

Native output, notification, loss, pane-gone or exit events.

## NOTES

Tmux.WatchFailed preserves the native exception and supplied owner. Buffered
events precede a terminal stream error. A byte-budget failure preserves earlier
output and reports that the consumed oversized event was not emitted.

Byte accounting includes decoded UTF-8 text in pane IDs, output data,
notification names and arguments, and exit reasons. Numeric loss counts add
no text bytes. This bounds text payload, not object overhead or serialized
PowerShell Job data. Set BOTH MaxEvents and MaxOutputBytes for unattended jobs.
The bundled alpha.15 core has a count-bounded upstream notification queue; this
handoff limit does not add an aggregate byte limit to that upstream queue.

Ctrl+C, pipeline early exit and module removal stop the reader and await its
disposal. Module removal cancels active watches only in the importing runspace;
it does not dispose supplied clients. Cancellation may consume an event that
has not reached the pipeline. Resnapshot after loss when current state matters.
The foreground pipeline remains occupied while watching; use a bounded
ThreadJob to make the prompt available.

## RELATED LINKS

[Watch events and use runspaces](../../watch.md)
[Commands and control clients](../../commands.md)
