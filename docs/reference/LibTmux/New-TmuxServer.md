---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/New-TmuxServer.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: New-TmuxServer
---

# New-TmuxServer

## SYNOPSIS

Construct a tmux endpoint handle without contacting it.

## SYNTAX

### Name (Default)

```text
New-TmuxServer [-SocketName <string>] [-TmuxBinaryPath <string>] [-ConfigurationFile <string>]
```

### Path

```text
New-TmuxServer -SocketPath <string> [-TmuxBinaryPath <string>] [-ConfigurationFile <string>]
```

## ALIASES

None.

## DESCRIPTION

Choose a socket name or absolute socket path. Construction performs no tmux I/O and does not start or own a daemon. A later command explicitly acquires data or changes tmux. Omitting both socket selectors uses the core default endpoint.

## EXAMPLES

### Example 1

Construct a handle for the existing socket identified by $SocketPath.

```powershell
LibTmux\New-TmuxServer -SocketPath $SocketPath
```

## PARAMETERS

### -ConfigurationFile

The configuration used if a later operation starts tmux.

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

### -SocketName

The tmux socket name.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Name
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SocketPath

The absolute socket path.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Path
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TmuxBinaryPath

The tmux executable used by subsequent operations.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### LibTmux.Server

Native pipeline type for this command.

## NOTES

The returned LibTmux.Server is unmaterialized. TmuxBinaryPath and ConfigurationFile affect subsequent operations; construction does not execute them.

## RELATED LINKS

[Task guide](../../read.md)
