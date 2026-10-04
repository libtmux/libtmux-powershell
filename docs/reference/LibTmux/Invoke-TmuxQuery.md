---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Invoke-TmuxQuery.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Invoke-TmuxQuery
---

# Invoke-TmuxQuery

## SYNOPSIS

Acquire fresh tmux objects using an explicit query.

## SYNTAX

### Query (Default)

```text
Invoke-TmuxQuery [-Server] <Server> -Query <QueryDocument> [-Pushdown <QueryPushdown>] [-AsResult]
```

### Plan

```text
Invoke-TmuxQuery [-Server] <Server> -Plan <Object> [-AsResult]
```

### NativeFilter

```text
Invoke-TmuxQuery [-Server] <Server> -Target <QueryTarget> -NativeFilter <String>
```

## ALIASES

None.

## DESCRIPTION

Inspect the supplied endpoint, acquire a fresh snapshot and emit matching native
objects in captured order. A query document is planned against the observed
daemon version. A prepared plan must match that version. Execution never starts
an absent daemon.

Use AsResult to retain one native QueryResult, including its complete snapshot
when there are no matches. Filtering does not prune parent or child relations.
Acquisition spans tmux commands and does not promise an atomic observation.
Use Select-TmuxPane, Select-TmuxWindow or Select-TmuxSession for local filtering
of objects already acquired.

NativeFilter is a separate raw tmux-format escape hatch. It returns matching
rows without a complete structured-query snapshot. It cannot be combined with
Query, Plan, Pushdown or AsResult.

## EXAMPLES

### Example 1

Acquire panes at least 80 columns wide from an explicit socket.

```powershell
$query = LibTmux\New-TmuxQuery -Target Pane -Criteria @{ Width = @{ Ge = 80 } }
LibTmux\New-TmuxServer -SocketPath $SocketPath |
    LibTmux\Invoke-TmuxQuery -Query $query
```

### Example 2

Keep the query result and its captured graph, including an empty selection.

```powershell
$query = LibTmux\New-TmuxQuery -Target Pane -Criteria @{ Width = @{ Ge = 80 } }
LibTmux\New-TmuxServer -SocketPath $SocketPath |
    LibTmux\Invoke-TmuxQuery -Query $query -AsResult
```

## PARAMETERS

### -Server

The explicit endpoint to inspect and query.

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

### -Query

A native document planned using the observed daemon version.

```yaml
Type: LibTmux.Query.QueryDocument
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Query
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Plan

A native QueryPlan<Session>, QueryPlan<Window> or QueryPlan<Pane> prepared by Get-TmuxQueryPlan or the .NET API.

```yaml
Type: System.Object
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Plan
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Pushdown

Auto permits exact source evaluation and local residuals; Never evaluates locally; Require rejects residual predicates.

```yaml
Type: LibTmux.Query.QueryPushdown
DefaultValue: 'Auto'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Query
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: [Auto, Never, Require]
HelpMessage: ''
```

### -AsResult

Emit one native result with matches and its complete captured graph.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: 'False'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Query
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Plan
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Target

The native entity searched by NativeFilter.

```yaml
Type: LibTmux.Query.QueryTarget
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NativeFilter
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: [Session, Window, Pane]
HelpMessage: ''
```

### -NativeFilter

Uninterpreted tmux format text. The caller owns its semantics; it is not a structured portable query.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NativeFilter
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

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Server

An explicit server endpoint.

## OUTPUTS

### LibTmux.Session

Matching sessions.

### LibTmux.Window

Matching window placements.

### LibTmux.Pane

Matching panes in their captured placement context.

### LibTmux.Query.QueryResult\<T\>

One native result when AsResult is set.

## NOTES

Execution failures write Tmux.QueryExecutionFailed for the affected endpoint. Use ErrorAction Stop to terminate the pipeline. Cancellation stops the pending native operation. No matches are emitted from a failed acquisition.

## RELATED LINKS

[Get-TmuxQueryPlan](Get-TmuxQueryPlan.md)

[New-TmuxQuery](New-TmuxQuery.md)

[Select-TmuxPane](Select-TmuxPane.md)
