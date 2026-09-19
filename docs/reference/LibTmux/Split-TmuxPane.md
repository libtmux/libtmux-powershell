---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Split-TmuxPane.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Split-TmuxPane
---

# Split-TmuxPane

## SYNOPSIS

Split an explicit pane and return the newly created pane.

## SYNTAX

### Cells (Default)

```text
Split-TmuxPane [-Pane] <Pane> [-Horizontal] [-Before] [-Size <int>] [-StartDirectory <string>]
 [-Command <string>] [-Environment <IDictionary>] [-Activate] [-FullWindow] [-Zoom] [-WhatIf]
 [-Confirm]
```

### Percentage

```text
Split-TmuxPane [-Pane] <Pane> -Percentage <int> [-Horizontal] [-Before] [-StartDirectory <string>]
 [-Command <string>] [-Environment <IDictionary>] [-Activate] [-FullWindow] [-Zoom] [-WhatIf]
 [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Split a native Pane directly or through the pipeline. By default the new pane is
below its target and remains unselected. Horizontal chooses a left/right split;
Before places the new pane above or left of the target. Success returns the
captured native LibTmux.Pane for the new pane and does not refresh the original
handle in place.

## EXAMPLES

### Example 1

Place a new twenty-column pane to the left of the first pane on the server
identified by $SocketPath. The window must have enough room. The current pane
selection is preserved; the new /bin/sh process remains running until you remove
its pane.

```powershell
LibTmux\New-TmuxServer -SocketPath $SocketPath |
    LibTmux\Get-TmuxPane | Select-Object -First 1 |
    LibTmux\Split-TmuxPane -Horizontal -Before -Size 20 -Command 'exec /bin/sh'
```

## PARAMETERS

### -Activate

Make the new pane active. By default the previously active pane remains active;
this switch does not attach a terminal.

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

### -Before

Place the new pane above the target, or on its left when Horizontal is present.

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

### -Command

One shell-command string for the new pane. tmux interprets shell syntax in this
string; it is not an argument array. Omit it to use the configured default
command or shell.

```yaml
Type: System.String
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

### -Environment

A dictionary with string names and string values. Names must be nonempty and
contain neither '=' nor NUL (U+0000). Values may be empty but must not contain
NUL. Null or non-string entries are rejected before confirmation or dispatch.
Entries are copied for this invocation and do not change the PowerShell host
environment.

```yaml
Type: System.Collections.IDictionary
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

### -FullWindow

Split across the whole window instead of only the target pane.

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

### -Horizontal

Split left to right instead of top to bottom. Without Before the new pane is on
the right.

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

### -Pane

Native pane to split. This is the only pipeline-bound parameter; binding by an
object's Pane property is not supported.

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

### -Percentage

New pane size as a percentage from 1 through 100. Percentage and Size cannot be
combined. The requested geometry must still fit the window.

```yaml
Type: System.Nullable`1[System.Int32]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Percentage
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Size

New pane size in cells, at least 1: columns for a horizontal split or rows
otherwise. Size and Percentage cannot be combined. Omit both to use tmux's
default split size.

```yaml
Type: System.Nullable`1[System.Int32]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Cells
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -StartDirectory

Working directory for the new pane. Use an absolute filesystem path for
predictable behavior. The core expands ~ and ~/; this cmdlet does not resolve
PowerShell provider paths or change the host's current directory.

```yaml
Type: System.String
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

### -Zoom

Ask tmux to zoom the new pane.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Pane

Native pipeline type for this command.

## OUTPUTS

### LibTmux.Pane

Captured native object for the created resource.

## NOTES

WhatIf performs no core discovery or dispatch and emits no pane. Confirmation
precedes the core operation. The caller remains responsible for the created pane
and its process. Cancellation is not rollback and no mutation is retried.
Per-owner errors use Tmux.PaneSplitFailed and retain the core exception and
failed pane. ErrorAction Continue allows later owners to run. The core and tmux
enforce geometry and version capabilities.

## RELATED LINKS

[Task guide](../../create.md)
