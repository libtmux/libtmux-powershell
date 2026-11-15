---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Rename-TmuxWindow.md
Locale: en-US
Module Name: LibTmux
ms.date: 11/15/2026
PlatyPS schema version: 2024-05-01
title: Rename-TmuxWindow
---

# Rename-TmuxWindow

## SYNOPSIS

Rename a native window and optionally emit its replacement.

## SYNTAX

### __AllParameterSets

```text
Rename-TmuxWindow [-Window] <Window> [-Name] <string> [-PassThru] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Rename the supplied native LibTmux.Window. The endpoint and daemon generation come
from that handle, so the window is named by its ID and not by its old name.
Only that window changes.

With PassThru, return a new Window handle that carries the new name. The original
handle keeps the name it captured and is stale after the rename. Without
PassThru, emit no success object. tmux expands the name as a format, so a
number sign in it does not survive verbatim. WhatIf performs no tmux I/O.

## EXAMPLES

### Example 1

Rename the previously selected $window and emit the replacement handle. Assign
the output for subsequent operations.

```powershell
$window | LibTmux\Rename-TmuxWindow -Name logs -PassThru
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

### -Name

The new window name. An empty name is rejected before tmux is called.

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

### -PassThru

Emit a new Window handle that carries the new name, read back after the rename.

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

The native window to rename. Select it with Get-TmuxWindow on the endpoint you intend to change.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Window

A native LibTmux.Window selected from an explicit endpoint.

## OUTPUTS

### LibTmux.Window

With PassThru, one replacement handle for each input. Otherwise no success
objects are emitted.

## NOTES

Failures use Tmux.WindowRenameFailed and retain the original core exception, its
dispatch information and the failed owner. ErrorAction Continue permits later
owners to be processed; ErrorAction Stop stops on the first failure. A missing
target remains an error. No mutation is retried.

## RELATED LINKS

[Create sessions, windows and panes](../../create.md)

[Choose endpoints and owners](../../read.md)
