---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxQueryPlan.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxQueryPlan
---

# Get-TmuxQueryPlan

## SYNOPSIS

Inspect how a query will run against a known tmux version.

## SYNTAX

### __AllParameterSets

```text
Get-TmuxQueryPlan [-Query] <QueryDocument> -DaemonVersion <TmuxVersion> [-Pushdown <QueryPushdown>]
```

## ALIASES

None.

## DESCRIPTION

Prepare a native query plan without contacting tmux. The plan exposes pushed
and residual predicates, required fields, snapshot depth and fallback reasons.
Displaying the plan or reading its properties performs no I/O. Pass it to
Invoke-TmuxQuery with an explicit server to execute it.

Auto evaluates supported conditions inside tmux and the remainder locally.
Never evaluates the complete predicate locally. Require rejects predicates
that need local evaluation. All modes retain the complete acquired graph;
source evaluation does not reduce the captured rows.

## EXAMPLES

### Example 1

Prepare an exact pane-ID query for tmux 3.2a without opening a connection.
Use the observed daemon version when preparing a plan for execution.

```powershell
LibTmux\New-TmuxQuery -Target Pane -Criteria @{ Id = '%0' } | LibTmux\Get-TmuxQueryPlan -DaemonVersion ([LibTmux.TmuxVersion]::Parse('3.2a')) -Pushdown Require
```

## PARAMETERS

### -Query

A native Session, Window or Pane document.

```yaml
Type: LibTmux.Query.QueryDocument
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

### -DaemonVersion

The known daemon version. Execution verifies it against the selected endpoint.

```yaml
Type: LibTmux.TmuxVersion
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
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

Where predicates may be evaluated. Require concerns predicate evaluation; parsing and object construction still occur locally.

```yaml
Type: LibTmux.Query.QueryPushdown
DefaultValue: 'Auto'
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
AcceptedValues: [Auto, Never, Require]
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Query.QueryDocument

A query document.

## OUTPUTS

### LibTmux.Query.QueryPlan\<T\>

One native plan targeting Session, Window or Pane.

## NOTES

Invalid or unsupported planning terminates with Tmux.QueryPlanFailed. Planning does not discover the installed client or daemon version.

## RELATED LINKS

[New-TmuxQuery](New-TmuxQuery.md)

[Invoke-TmuxQuery](Invoke-TmuxQuery.md)
