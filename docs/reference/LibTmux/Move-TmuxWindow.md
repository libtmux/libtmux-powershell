---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Move-TmuxWindow.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/27/2026
PlatyPS schema version: 2024-05-01
title: Move-TmuxWindow
---

# Move-TmuxWindow

## SYNOPSIS

Move one session placement of a window.

## SYNTAX

### __AllParameterSets

```text
Move-TmuxWindow [-Window] <Window> [-DestinationSession <Session>] [-Index <int>]
 [-Direction <WindowDirection>] [-NoSelect] [-ReplaceExisting] [-PassThru] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Move only the placement captured in the source Window handle. Other links to
the same physical window remain in their sessions. Omit DestinationSession to
move within the source session. Omit Index to let tmux use the next free
index in the destination. A supplied destination Session must belong to the
same endpoint and daemon generation as the Window.

With PassThru, return a new Window handle containing the observed destination
placement. The original handle remains unchanged and is stale after a move.
Without PassThru, emit no success object. Confirmation is requested by
default because ReplaceExisting can remove a destination window. WhatIf
performs no tmux I/O.

## EXAMPLES

### Example 1

Move the previously selected $window to index 5 in its own session and emit
the replacement handle. Assign the output for subsequent operations.

```powershell
$window | LibTmux\Move-TmuxWindow -Index 5 -PassThru -Confirm:$false
```

## PARAMETERS

### -Confirm

Prompts you for confirmation before running the cmdlet.

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

### -DestinationSession

Move into this native session. Omit it to use the source Window's captured
session. A different endpoint or daemon generation is rejected before tmux
dispatch.

```yaml
Type: LibTmux.Session
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

### -Direction

Insert Before or After the destination. Without Index, tmux places the
window relative to the destination session's current window.

```yaml
Type: System.Nullable`1[LibTmux.WindowDirection]
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

### -Index

The destination session's window index, at least 0. Omit it to use the next
free index.

```yaml
Type: System.Nullable`1[System.Int32]
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

### -NoSelect

Leave the moved window unselected in the destination session.

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

### -PassThru

Emit a new Window handle with the destination placement read back after tmux
accepts the move. A failed readback does not mean the move was rolled back.

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

### -ReplaceExisting

Replace a link already at the requested destination index. This may destroy
the displaced window if it had no other links.

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

Runs the command in a mode that only reports what would happen without performing the actions.

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

### -Window

The native source placement, supplied directly or through the pipeline.

```yaml
Type: LibTmux.Window
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Window

One native source placement per pipeline input.

## OUTPUTS

### LibTmux.Window

One replacement Window per successful input when PassThru is present;
otherwise no success output.

## NOTES

The core checks captured source placement and server generation before the
move. A stale placement, tmux rejection or failed readback writes a per-input
Tmux.WindowMoveFailed error. Readback failure after dispatch has unknown final
state; inspect topology before deciding whether to retry. ErrorAction
Continue permits later inputs; ErrorAction Stop stops at the first failure.

## RELATED LINKS

[Link a window into another session](New-TmuxWindowLink.md)

[Remove one window link](Remove-TmuxWindowLink.md)
