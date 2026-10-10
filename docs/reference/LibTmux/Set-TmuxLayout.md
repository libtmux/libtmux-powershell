---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Set-TmuxLayout.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Set-TmuxLayout
---

# Set-TmuxLayout

## SYNOPSIS

Arrange the panes of a window.

## SYNTAX

### Layout (Default)

```text
Set-TmuxLayout [-Window] <Window> -Layout <String> [-PassThru] [-WhatIf] [-Confirm]
```

### Mode

```text
Set-TmuxLayout [-Window] <Window> -Mode <SelectLayoutMode> [-PassThru] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Apply a named preset or a captured window Layout string. Mode accepts Spread,
Next or Previous. The native core rejects unknown or ambiguous preset names
before dispatch. Without PassThru, emit no success output; with it, return a
replacement Window and leave the original capture unchanged.

## EXAMPLES

### Example 1

Tile the panes in a previously selected native $window.

```powershell
$window | LibTmux\Set-TmuxLayout -Layout tiled -PassThru
```

## PARAMETERS

### -Confirm

Ask for confirmation before changing tmux.

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

### -Layout

A preset name, unambiguous preset prefix, or captured layout string.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Layout
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Mode

Spread panes or select the Next or Previous layout.

```yaml
Type: LibTmux.SelectLayoutMode
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Mode
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Emit the native replacement handle carrying observed state.

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

Preview the change without contacting tmux.

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

### -Window

The native window to change.

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

This cmdlet supports the common parameters: -Debug, -ErrorAction,
-ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable,
-PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more
information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Window

Native pipeline owner.

## OUTPUTS

### LibTmux.Window

Emitted only with PassThru.

## NOTES

Restoring a classic layout restores pane sizes but can rotate pane placement on
tmux 3.7 and earlier. It does not guarantee the same pane IDs occupy the same
positions. A disappeared target or stale generation writes a per-target error.
Use -ErrorAction Stop to terminate. Cancellation cannot undo an already
dispatched change.

## RELATED LINKS

[Task guide](../../layout.md)
