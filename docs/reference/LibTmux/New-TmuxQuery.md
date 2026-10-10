---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/New-TmuxQuery.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: New-TmuxQuery
---

# New-TmuxQuery

## SYNOPSIS

Build reusable criteria for captured tmux objects.

## SYNTAX

### Criteria (Default)

```text
New-TmuxQuery -Target <QueryTarget> -Criteria <IDictionary>
```

### Json

```text
New-TmuxQuery -Json <String>
```

## ALIASES

None.

## DESCRIPTION

Construct a native LibTmux query document from a criteria map or serialized
schema 2 JSON. Construction copies and validates data without contacting tmux.
Use Where-Object for ordinary PowerShell predicates; structured criteria also
support serialization, field discovery and explicit source planning.

Map keys use native property names or catalog wire names. Bare values mean
equality; fields in a map are combined with And. Use operator maps such as
@{ Width = @{ Ge = 80 } }. Get-TmuxQueryField lists native catalog fields and operator names. The
[criteria reference](../../query.md#criteria-vocabulary) maps those names to accepted
PowerShell keys such as Ge, Some and Is.
Unknown fields, duplicate aliases, unsupported operators, ScriptBlocks, cycles
and oversized data are rejected before evaluation.

## EXAMPLES

### Example 1

Build a reusable filter for panes at least 80 columns wide.

```powershell
LibTmux\New-TmuxQuery -Target Pane -Criteria @{ Width = @{ Ge = 80 } }
```

## PARAMETERS

### -Criteria

A bounded data map. Values must have the native field type; strings and Boolean values are not converted to numbers.

```yaml
Type: System.Collections.IDictionary
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Criteria
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Json

A complete document serialized by ConvertTo-TmuxQueryJson. Only the current schema is accepted.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Json
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Target

The native entity described by Criteria.

```yaml
Type: LibTmux.Query.QueryTarget
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Criteria
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: [Session, Window, Pane]
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

### LibTmux.Query.QueryDocument

One validated native document.

## NOTES

Tmux.InvalidQuery terminates invalid construction. The packaged libtmux-query-v2.schema.json describes the JSON representation.

## RELATED LINKS

[Select-TmuxPane](Select-TmuxPane.md)

[Get-TmuxQueryField](Get-TmuxQueryField.md)

[ConvertTo-TmuxQueryJson](ConvertTo-TmuxQueryJson.md)
