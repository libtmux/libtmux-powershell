---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxClient.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxClient
---

# Get-TmuxClient

## SYNOPSIS

Read the clients attached to a tmux server.

## SYNTAX

### __AllParameterSets

```text
Get-TmuxClient [-Server] <Server> [-Name <String>]
```

## ALIASES

None.

## DESCRIPTION

Read current client rows through the native core. Name is an ordinal literal
selector, not a wildcard or tmux target expression. Return native Client
objects; an empty server or unmatched name produces no objects.
AttachedSessionId is captured state, so use Get-TmuxClientAttachment to resolve
the current attachment.

## EXAMPLES

### Example 1

Read clients from a previously selected native $server.

```powershell
$server | LibTmux\Get-TmuxClient
```

## PARAMETERS

### -Name

An exact, case-sensitive client name.

```yaml
Type: System.String
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

### -Server

The server whose attached clients are listed.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction,
-ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable,
-PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more
information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Server

Native pipeline owner.

## OUTPUTS

### LibTmux.Client

Native observed result.

## NOTES

This read does not attach, detach or own any client. Listing an unavailable
server writes an error.

## RELATED LINKS

[Task guide](../../clients.md)
