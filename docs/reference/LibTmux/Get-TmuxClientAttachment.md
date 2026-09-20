---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxClientAttachment.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxClientAttachment
---

# Get-TmuxClientAttachment

## SYNOPSIS

Resolve the session, window and pane a client currently views.

## SYNTAX

### __AllParameterSets

```text
Get-TmuxClientAttachment [-Client] <Client>
```

## ALIASES

None.

## DESCRIPTION

Resolve current attachment data through the native core. Return a
ClientAttachment containing native Session, Window and Pane handles. A detached
client or missing session produces no output. Window or Pane can be null when
unavailable. This explicit live read leaves the original Client unchanged.

## EXAMPLES

### Example 1

Resolve the current attachment of a previously selected native $client.

```powershell
$client | LibTmux\Get-TmuxClientAttachment
```

## PARAMETERS

### -Client

The native client whose current state is read.

```yaml
Type: LibTmux.Client
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

This cmdlet supports the common parameters: -Debug, -ErrorAction,
-ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable,
-PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more
information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Client

Native pipeline owner.

## OUTPUTS

### LibTmux.ClientAttachment

Native observed result.

## NOTES

The observation uses several tmux reads and is not a transaction. Server or
transport failures write an error rather than becoming an empty result.

## RELATED LINKS

[Task guide](../../clients.md)
