---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Remove-TmuxSession.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Remove-TmuxSession
---

# Remove-TmuxSession

## SYNOPSIS

Remove an explicit native session without emitting an object.

## SYNTAX

### __AllParameterSets

```text
Remove-TmuxSession [-Session] <Session> [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Remove the supplied native LibTmux.Session. The endpoint and daemon generation
come from that handle. Windows linked into another session survive; windows
owned only by the removed session and their panes are destroyed. Removing the
last session can stop the daemon when its configuration requires that.

This high-impact operation requests confirmation by default. WhatIf performs
no acquisition or mutation. Cancellation does not restore removed resources.

## EXAMPLES

### Example 1

Remove the previously selected native $session from an endpoint you own.
This example explicitly suppresses confirmation; omitting Confirm uses the
normal high-impact confirmation behavior.

```powershell
$session | LibTmux\Remove-TmuxSession -Confirm:$false
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

### -Session

The native session to remove. Select it explicitly using Get-TmuxSession
on the endpoint you intend to change.

```yaml
Type: LibTmux.Session
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

### LibTmux.Session

A native LibTmux.Session selected from an explicit endpoint.

## OUTPUTS

### None

No success objects are emitted. An empty input pipeline performs no work.

## NOTES

Failures use Tmux.SessionRemoveFailed and retain the original core exception,
its dispatch information and the failed owner. ErrorAction Continue permits
later owners to be processed; ErrorAction Stop stops on the first failure.
A missing target remains an error. No mutation is retried. Previously captured
handles retain their old data after removal and are not refreshed in place.

## RELATED LINKS

[Remove sessions, windows and panes](../../remove.md)

[Choose endpoints and owners](../../read.md)
