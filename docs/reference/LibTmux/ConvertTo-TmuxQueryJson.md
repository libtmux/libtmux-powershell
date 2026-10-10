---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/ConvertTo-TmuxQueryJson.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: ConvertTo-TmuxQueryJson
---

# ConvertTo-TmuxQueryJson

## SYNOPSIS

Serialize a native query document.

## SYNTAX

### __AllParameterSets

```text
ConvertTo-TmuxQueryJson [-Query] <QueryDocument>
```

## ALIASES

None.

## DESCRIPTION

Serialize a native query document through LibTmux.Query.Json. The returned
string uses the shared schema 2 contract. Serialization performs no tmux I/O.
Restore the document with New-TmuxQuery -Json.

## EXAMPLES

### Example 1

Serialize a pane-width filter for storage or another native consumer.

```powershell
LibTmux\New-TmuxQuery -Target Pane -Criteria @{ Width = @{ Ge = 80 } } |
    LibTmux\ConvertTo-TmuxQueryJson
```

## PARAMETERS

### -Query

The native document to serialize.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Query.QueryDocument

Native query documents.

## OUTPUTS

### System.String

One JSON string per document.

## NOTES

Tmux.QueryJsonFailed terminates invalid serialization.

## RELATED LINKS

[New-TmuxQuery](New-TmuxQuery.md)
