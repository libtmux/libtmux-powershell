---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Update-TmuxClient.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Update-TmuxClient
---

# Update-TmuxClient

## SYNOPSIS

Refresh a client into a replacement captured object.

## SYNTAX

### __AllParameterSets

```text
Update-TmuxClient [-Client] <Client>
```

## ALIASES

None.

## DESCRIPTION

Read the client again by its native name and return a replacement Client. Leave
the original captured fields unchanged. This is an explicit read, not a redraw
or mutation of the terminal.

## EXAMPLES

### Example 1

Refresh a previously selected native $client.

```powershell
$client | LibTmux\Update-TmuxClient
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

### LibTmux.Client

Native observed result.

## NOTES

A client that has detached writes the native TmuxObjectNotFoundException as a
per-target error. Use -ErrorAction Stop to terminate.

## RELATED LINKS

[Task guide](../../clients.md)
