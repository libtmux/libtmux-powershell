---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Set-TmuxPaneSize.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Set-TmuxPaneSize
---

# Set-TmuxPaneSize

## SYNOPSIS

Resize a pane or toggle its zoom.

## SYNTAX

### Size (Default)

```text
Set-TmuxPaneSize [-Pane] <Pane> [-Width <String>] [-Height <String>] [-PassThru] [-WhatIf] [-Confirm]
```

### Direction

```text
Set-TmuxPaneSize [-Pane] <Pane> -Direction <ResizeDirection> -Adjustment <Int32> [-PassThru] [-WhatIf] [-Confirm]
```

### Zoom

```text
Set-TmuxPaneSize [-Pane] <Pane> -Zoom [-PassThru] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Specify at least one positive cell or percentage dimension, an edge Direction
with positive Adjustment, or Zoom. These forms cannot be combined. Zoom toggles
the current state; repeating it turns zoom off. tmux clamps sizes that do not
fit. PassThru returns the observed replacement Pane, which may differ from the
requested dimensions.

## EXAMPLES

### Example 1

Give a previously selected native $pane 40 columns in a window with a horizontal
split.

```powershell
$pane | LibTmux\Set-TmuxPaneSize -Width 40 -PassThru
```

## PARAMETERS

### -Adjustment

Positive number of cells to move the selected edge.

```yaml
Type: System.Int32
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Direction
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

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

### -Direction

Move the Up, Down, Left or Right edge.

```yaml
Type: LibTmux.ResizeDirection
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Direction
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Height

Positive height in cells or as a percentage.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Size
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Pane

The native pane to change.

```yaml
Type: LibTmux.Pane
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

### -Width

Positive width in cells or as a percentage such as 50%. At least one of Width or
Height is required in the Size parameter set.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Size
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Zoom

Toggle pane zoom; this does not mean set zoom to true.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Zoom
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
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

### LibTmux.Pane

Native pipeline owner.

## OUTPUTS

### LibTmux.Pane

Emitted only with PassThru.

## NOTES

A disappeared target or stale generation writes a per-target error. Use
-ErrorAction Stop to terminate. Cancellation cannot undo an already dispatched
change.

## RELATED LINKS

[Task guide](../../layout.md)
