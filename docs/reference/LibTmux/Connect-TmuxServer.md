---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Connect-TmuxServer.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Connect-TmuxServer
---

# Connect-TmuxServer

## SYNOPSIS

Discover the server at an explicit endpoint.

## SYNTAX

### __AllParameterSets

```text
Connect-TmuxServer [-Server] <Server>
```

## ALIASES

None.

## DESCRIPTION

Accept a native LibTmux.Server handle and discover its live server generation. An unmaterialized handle produces a connected replacement. An already connected handle is returned unchanged. Use Get-TmuxSnapshot to acquire the hierarchy.

## EXAMPLES

### Example 1

Connect to the existing server identified by $SocketPath.

```powershell
LibTmux\New-TmuxServer -SocketPath $SocketPath | LibTmux\Connect-TmuxServer
```

## PARAMETERS

### -Server

The endpoint handle to connect.

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

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Server

Native pipeline type for this command.

## OUTPUTS

### LibTmux.Server

Native pipeline type for this command.

## NOTES

This command borrows the daemon. Errors preserve the core exception; -ErrorAction Stop terminates the pipeline.

## RELATED LINKS

[Task guide](../../read.md)
