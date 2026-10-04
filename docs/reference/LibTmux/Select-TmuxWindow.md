---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Select-TmuxWindow.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Select-TmuxWindow
---

# Select-TmuxWindow

## SYNOPSIS

Filter captured native windows.

## SYNTAX

### Criteria (Default)

```text
Select-TmuxWindow [-InputObject] <Object[]> -Criteria <IDictionary> [-ExactlyOne]
```

### Query

```text
Select-TmuxWindow [-InputObject] <Object[]> -Query <QueryDocument> [-ExactlyOne]
```

## ALIASES

None.

## DESCRIPTION

Evaluate criteria against captured native objects using the shared .NET query
evaluator. Selection preserves input order, duplicates, object identity and the
complete graph behind each object. It does not contact tmux or refresh data.
Use Where-Object when an ordinary PowerShell predicate is sufficient.

Ordinary selection streams each match. ExactlyOne retains a match until finite
input completes, then emits it only if exactly one input matched. A second
match, invalid object, unavailable captured relation, evaluation failure or
pipeline stop terminates selection before that retained object is emitted.
ExactlyOne counts only the successful objects it receives. An upstream
nonterminating error is outside that guarantee. When completeness is required
before mutation, use -ErrorAction Stop on every upstream acquisition.

## EXAMPLES

### Example 1

Capture the existing endpoint selected by $SocketPath, then select active window placements.

```powershell
$snapshot = LibTmux\New-TmuxServer -SocketPath $SocketPath |
    LibTmux\Get-TmuxSnapshot
$snapshot.Windows |
    LibTmux\Select-TmuxWindow -Criteria @{ IsActive = $true }
```

## PARAMETERS

### -Criteria

The criteria map copied before input begins. An empty map accepts every valid native input.

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

### -ExactlyOne

Require exactly one match from successfully completed finite input.

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

### -InputObject

Native LibTmux.Window objects, individually or in an array. The callback validates each object and rejects nulls or lookalike objects.

```yaml
Type: System.Object[]
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

A native query document whose target is Window.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Window

Captured native windows; no property-name binding.

## OUTPUTS

### LibTmux.Window

The original matching objects.

## NOTES

Errors terminate even with -ErrorAction Continue. Tmux.NoMatch and
Tmux.MultipleMatches report cardinality failures. Tmux.InvalidQuery reports
invalid criteria or a mismatched target; Tmux.QuerySelectionFailed retains
the native evaluation exception and failing input. ExactlyOne cannot prove
cardinality on an input stream that never completes.

## RELATED LINKS

[New-TmuxQuery](New-TmuxQuery.md)

[Get-TmuxSnapshot](Get-TmuxSnapshot.md)

[Read captured objects](../../read.md)
