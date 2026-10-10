---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Remove-TmuxWindowLink.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/27/2026
PlatyPS schema version: 2024-05-01
title: Remove-TmuxWindowLink
---

# Remove-TmuxWindowLink

## SYNOPSIS

Remove one session placement of a window.

## SYNTAX

### __AllParameterSets

```text
Remove-TmuxWindowLink [-Window] <Window> [-KillIfLast] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Remove only the session-relative link captured by the native Window handle.
Other links to the same physical window remain. Without KillIfLast, tmux
refuses to remove the final link. With it, removing the final link also
destroys the window and its panes. Confirmation is requested by default.
WhatIf performs no tmux I/O.

## EXAMPLES

### Example 1

Remove the selected $window placement from its session while retaining the
physical window through another link.

```powershell
$window | LibTmux\Remove-TmuxWindowLink -Confirm:$false
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

### -KillIfLast

Allow tmux to destroy the physical window and its panes when this was its
last link. Without this switch, the last-link operation fails.

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

The native placement to remove. It must identify the session and index that
still contain the captured window.

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

One native window placement per pipeline input.

## OUTPUTS

### None

No success objects are emitted.

## NOTES

This command differs from Remove-TmuxWindow, which kills the physical window
and all its links. The core verifies source placement and server generation in
tmux's native queue before unlinking. Stale or missing placements write a
per-input Tmux.WindowUnlinkFailed error. ErrorAction Continue permits later
inputs; ErrorAction Stop stops at the first failure.

## RELATED LINKS

[Remove a physical window](Remove-TmuxWindow.md)

[Link a window into another session](New-TmuxWindowLink.md)
