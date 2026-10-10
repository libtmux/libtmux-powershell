---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Enter-TmuxSession.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Enter-TmuxSession
---

# Enter-TmuxSession

## SYNOPSIS

Attach your foreground terminal to a selected session.

## SYNTAX

### __AllParameterSets

```text
Enter-TmuxSession [-Session] <Session> [-ReadOnly] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Attach a foreground tmux client using the endpoint and daemon generation of
the supplied native Session. The command waits until you detach, then returns
one refreshed Session. It does not detach other clients or choose a session
from ambient tmux variables.

Run it in a foreground terminal outside tmux. Redirected stdin and a nonempty
TMUX environment variable are rejected. These checks do not establish whether
an arbitrary PowerShell host or in-process background runspace owns the terminal.
Background jobs, remoting and custom hosts are not a supported attachment workflow.

ReadOnly prevents the client from sending pane input. Detach normally with your
tmux detach key binding. Stopping the PowerShell pipeline cancels its owned
attachment client; the borrowed session, daemon and other clients remain.
Cancellation does not undo a workspace already applied.

The session's connection CommandTimeout bounds the entire attachment. Its
initial acknowledgement has a five-second ceiling, shortened by CommandTimeout;
a null CommandTimeout permits an indefinite interactive lifetime afterward.
A successful detach can still report a native readback failure if the session
or daemon disappears before the refreshed handle is captured.

WhatIf emits no success object and performs no attachment, refresh or host
application notification. Each actual input session is entered sequentially;
prefer selecting exactly one session before invoking the command.

## EXAMPLES

### Example 1

Preview attachment to a previously selected native session. No terminal is
required for the preview.

```powershell
$session | LibTmux\Enter-TmuxSession -WhatIf
```

### Example 2

Observe the selected session from your foreground terminal without sending pane
input. Detach to receive the refreshed Session.

```powershell
$session | LibTmux\Enter-TmuxSession -ReadOnly
```

## PARAMETERS

### -Session

The native session to enter. Its endpoint and generation are retained.

```yaml
Type: LibTmux.Session
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

### -ReadOnly

Attach without permitting pane input.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
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

### -WhatIf

Describe the attachment without executing it.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: [wi]
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

### -Confirm

Prompt before attaching the terminal.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: [cf]
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

### LibTmux.Session

A native session selected from an explicit endpoint.

## OUTPUTS

### LibTmux.Session

One refreshed native session after successful detach. Empty input emits nothing.

## NOTES

Requires PowerShell 7.4 or later on Linux or macOS with native tmux and a foreground terminal.
Tmux.SessionAttachFailed retains the native exception and input session. When
attachment and host restoration both fail, both causes are retained together.

## RELATED LINKS

[Get-TmuxSession](Get-TmuxSession.md)
[Invoke-TmuxWorkspace](../LibTmux.Workspace/Invoke-TmuxWorkspace.md)
