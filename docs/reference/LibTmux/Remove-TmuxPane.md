---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Remove-TmuxPane.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Remove-TmuxPane
---

# Remove-TmuxPane

## SYNOPSIS

Remove an explicit native pane without emitting an object.

## SYNTAX

### __AllParameterSets

```text
Remove-TmuxPane [-Pane] <Pane> [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Remove the supplied native LibTmux.Pane. The endpoint and daemon generation
come from that handle. Removing the last pane destroys its window; sessions
left without windows can also disappear. A shared window is affected in all
sessions that link it.

This high-impact operation requests confirmation by default. WhatIf performs
no acquisition or mutation. Cancellation does not restore removed resources.

## EXAMPLES

### Example 1

Remove the previously selected native $pane from an endpoint you own.
This example explicitly suppresses confirmation; omitting Confirm uses the
normal high-impact confirmation behavior.

```powershell
$pane | LibTmux\Remove-TmuxPane -Confirm:$false
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

### -Pane

The native pane to remove. Select it explicitly using Get-TmuxPane on
the endpoint you intend to change.

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

### LibTmux.Pane

A native LibTmux.Pane selected from an explicit endpoint.

## OUTPUTS

### None

No success objects are emitted. An empty input pipeline performs no work.

## NOTES

Failures use Tmux.PaneRemoveFailed and retain the original core exception,
its dispatch information and the failed owner. ErrorAction Continue permits
later owners to be processed; ErrorAction Stop stops on the first failure.
A missing target remains an error. No mutation is retried. Previously captured
handles retain their old data after removal and are not refreshed in place.

## RELATED LINKS

[Remove sessions, windows and panes](../../remove.md)

[Choose endpoints and owners](../../read.md)
