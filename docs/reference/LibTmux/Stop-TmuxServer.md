---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Stop-TmuxServer.md
Locale: en-US
Module Name: LibTmux
ms.date: 11/15/2026
PlatyPS schema version: 2024-05-01
title: Stop-TmuxServer
---

# Stop-TmuxServer

## SYNOPSIS

Stop a native tmux server without emitting an object.

## SYNTAX

### __AllParameterSets

```text
Stop-TmuxServer [-Server] <Server> [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Stop the tmux server that the supplied native LibTmux.Server handle names, with
the tmux kill-server command. Every session, window and pane on that server is
destroyed and its daemon exits. Use it to end a private server you started, such
as one named by New-TmuxServer on a socket of its own.

A server that is already gone is the requested outcome, so an absent daemon
succeeds and nothing is stopped. This high-impact operation requests
confirmation by default. WhatIf performs no tmux I/O. Cancellation does not
restore a stopped server.

## EXAMPLES

### Example 1

Stop the previously created $server, a private endpoint you own. This example
explicitly suppresses confirmation; omitting Confirm uses the normal
high-impact confirmation behavior.

```powershell
$server | LibTmux\Stop-TmuxServer -Confirm:$false
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

### -Server

The native server to stop. Create it with New-TmuxServer, or select it with
Get-TmuxServer, on the endpoint you intend to end.

```yaml
Type: LibTmux.Server
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

### LibTmux.Server

A native LibTmux.Server naming the endpoint to stop.

## OUTPUTS

### None

No success objects are emitted. An empty input pipeline performs no work.

## NOTES

Failures use Tmux.ServerStopFailed and retain the original core exception, its
dispatch information and the failed server. The stop is never retried. Session,
window and pane handles read from the stopped server no longer name anything.

## RELATED LINKS

[Remove sessions, windows and panes](../../remove.md)

[Choose endpoints and owners](../../read.md)
