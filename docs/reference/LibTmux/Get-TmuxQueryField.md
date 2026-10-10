---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxQueryField.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxQueryField
---

# Get-TmuxQueryField

## SYNOPSIS

Discover query fields, operators and native bindings.

## SYNTAX

### __AllParameterSets

```text
Get-TmuxQueryField [-Target] <QueryTarget>
```

## ALIASES

None.

## DESCRIPTION

Return immutable descriptors from the shared LibTmux field catalog. Each
descriptor identifies the wire field, supported operations, capture depth and
native bindings. Discovery is local and requires no server or tmux executable.
Client descriptors are available for inspection; the PowerShell structured
selectors accept Session, Window and Pane targets. Operators use the native
wire vocabulary: greaterThanOrEqual corresponds to the PowerShell criteria
key Ge. See the [criteria keys](../../query.md#criteria-vocabulary) for the full mapping.

## EXAMPLES

### Example 1

Inspect the pane-width field and its supported operations.

```powershell
LibTmux\Get-TmuxQueryField -Target Pane | Where-Object WireName -EQ 'pane_width'
```

## PARAMETERS

### -Target

The entity whose catalog fields are returned.

```yaml
Type: LibTmux.Query.QueryTarget
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: [Session, Window, Pane, Client]
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

No pipeline input.

## OUTPUTS

### LibTmux.Query.QueryFieldDescriptor

Native descriptors in wire-name order.

## NOTES

Catalog discovery does not refresh captured objects.

## RELATED LINKS

[New-TmuxQuery](New-TmuxQuery.md)
