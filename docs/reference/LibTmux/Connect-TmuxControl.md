---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Connect-TmuxControl.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Connect-TmuxControl
---

# Connect-TmuxControl

## SYNOPSIS

Attach a native control client to an explicit tmux target.

## SYNTAX

### __AllParameterSets

```text
Connect-TmuxControl [-Server] <Server> [-Target] <String> [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Attach one control client and return its native IControlModeSession. The
caller owns the returned client and must dispose it or use
Disconnect-TmuxControl in finally. The server and its sessions are borrowed.

Target is raw tmux target syntax, resolved when connecting. A name, index or
ID does not carry a captured entity identity guard. No implicit current
session is selected. WhatIf does not attach a client. An empty server pipeline
performs no work.

## EXAMPLES

### Example 1

Attach to fixture on a previously selected $server. Retain the returned
client and close it in finally with Disconnect-TmuxControl; the task guide
shows a complete ownership scope.

```powershell
$server | LibTmux\Connect-TmuxControl -Target 'fixture'
```

## PARAMETERS

### -Confirm

Ask for confirmation before the operation.

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

### -Server

The explicit endpoint that receives the operation.

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

### -Target

Nonempty raw tmux target to attach to. NUL and whitespace-only values are rejected.

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

### -WhatIf

Show the operation without contacting tmux.

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

### LibTmux.Server

The native endpoint to attach to.

## OUTPUTS

### LibTmux.IControlModeSession

The newly attached client. Its ownership transfers to the caller.

## NOTES

Tmux.ControlConnectFailed retains the original failure and server target. If
pipeline output fails before the client transfers to the caller, the cmdlet
disposes it. Stop cancels attachment; it never kills the borrowed tmux server.

## RELATED LINKS

[Commands and control clients](../../commands.md)
