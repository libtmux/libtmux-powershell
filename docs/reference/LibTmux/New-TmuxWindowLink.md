---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/New-TmuxWindowLink.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/27/2026
PlatyPS schema version: 2024-05-01
title: New-TmuxWindowLink
---

# New-TmuxWindowLink

## SYNOPSIS

Link a window into another session.

## SYNTAX

### __AllParameterSets

```text
New-TmuxWindowLink [-Window] <Window> -Session <Session> [-Index <int>]
 [-Direction <WindowDirection>] [-ReplaceExisting] [-NoSelect] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Link a captured window placement into a native destination Session. The
source handle must name a current session-relative link. The destination
must belong to the same endpoint and daemon generation. An existing link at
the requested index is an error unless ReplaceExisting is present.

This command does not emit a new placement. Read the destination session's
windows to work with its new link. The original Window handle stays a capture
of the source placement. Confirmation is requested by default because
ReplaceExisting can remove a destination window. WhatIf performs no tmux I/O.

## EXAMPLES

### Example 1

Link the previously selected $window into $guest at index 5 without selecting
it. Both handles must come from the same tmux server generation.

```powershell
$window | LibTmux\New-TmuxWindowLink -Session $guest -Index 5 -NoSelect -Confirm:$false
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

### -Direction

Insert Before or After the destination. Without Index, tmux places the link
relative to the destination session's current window.

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

An index in the destination session, at least 0. Omit it to let tmux choose
the placement.

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

Leave the new link unselected in its destination session.

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

Replace a link already at the requested index. This may destroy the displaced
window if it had no other links.

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

### -Session

The native destination session. Its endpoint and generation must match the
source Window.

```yaml
Type: LibTmux.Session
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
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

The native source placement, supplied directly or through the pipeline. A
physical window linked into multiple sessions has a distinct Window handle
for each placement.

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

### None

No success objects are emitted.

## NOTES

A stale source placement or missing destination writes a per-input
Tmux.WindowLinkFailed error. ErrorAction Continue processes later windows;
ErrorAction Stop stops on the first failure. The core checks source placement
and server generation in tmux's native queue before mutating. Do not retry an
already dispatched mutation without observing current topology.

## RELATED LINKS

[Move a window placement](Move-TmuxWindow.md)

[Remove one window link](Remove-TmuxWindowLink.md)

[Remove a physical window](Remove-TmuxWindow.md)
