---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Disconnect-TmuxControl.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Disconnect-TmuxControl
---

# Disconnect-TmuxControl

## SYNOPSIS

Dispose an explicitly supplied tmux control client.

## SYNTAX

### __AllParameterSets

```text
Disconnect-TmuxControl [-Connection] <IControlModeSession> [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Dispose the native control client and await its cleanup. The tmux daemon,
sessions and panes remain running. This is an explicit ownership action:
other callers using the same connection lose that client.

The operation emits no success object. An empty pipeline performs no work.
WhatIf leaves the connection usable.

## EXAMPLES

### Example 1

Close the $control client owned by the surrounding scope; use this in finally.

```powershell
$control | LibTmux\Disconnect-TmuxControl -Confirm:$false
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

### -Connection

The native control client. This operation borrows the supplied client.

```yaml
Type: LibTmux.IControlModeSession
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

### LibTmux.IControlModeSession

The client the caller explicitly chooses to close.

## OUTPUTS

### None

No success output.

## NOTES

Tmux.ControlDisconnectFailed retains the native failure and connection
target. The native disposal API has no cancellation token; cleanup is awaited
rather than abandoned when a pipeline stops.

## RELATED LINKS

[Commands and control clients](../../commands.md)
