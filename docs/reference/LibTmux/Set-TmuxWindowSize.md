---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Set-TmuxWindowSize.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Set-TmuxWindowSize
---

# Set-TmuxWindowSize

## SYNOPSIS

Resize a window in cells or against its attached clients.

## SYNTAX

### Size (Default)

```text
Set-TmuxWindowSize [-Window] <Window> [-Width <Int32>] [-Height <Int32>] [-PassThru] [-WhatIf] [-Confirm]
```

### Direction

```text
Set-TmuxWindowSize [-Window] <Window> -Direction <ResizeDirection> -Adjustment <Int32> [-PassThru] [-WhatIf] [-Confirm]
```

### Mode

```text
Set-TmuxWindowSize [-Window] <Window> -Mode <WindowResizeMode> [-PassThru] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Specify at least one positive cell dimension, an edge Direction with positive
Adjustment, or a client-size Mode. These forms cannot be combined. Resize
delegates to the native core and switches window-size to manual. PassThru
returns the observed replacement Window; the original capture remains unchanged.

## EXAMPLES

### Example 1

Set a previously selected native $window to 120 columns and 40 rows.

```powershell
$window | LibTmux\Set-TmuxWindowSize -Width 120 -Height 40 -PassThru
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

Positive height in cells.

```yaml
Type: System.Nullable[System.Int32]
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

### -Mode

Expand to the largest client or Shrink to the smallest client.

```yaml
Type: LibTmux.WindowResizeMode
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

### -Width

Positive width in cells. At least one of Width or Height is required in the Size
parameter set.

```yaml
Type: System.Nullable[System.Int32]
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

A disappeared target or stale generation writes a per-target error. Use
-ErrorAction Stop to terminate. Cancellation cannot undo an already dispatched
change.

## RELATED LINKS

[Task guide](../../layout.md)
