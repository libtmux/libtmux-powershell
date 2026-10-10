---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxPane.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxPane
---

# Get-TmuxPane

## SYNOPSIS

Read panes from a server, session or window.

## SYNTAX

### Server (Default)

```text
Get-TmuxPane [-Server] <Server> [-Id <string>]
```

### Session

```text
Get-TmuxPane [-Session] <Session> [-Id <string>]
```

### Window

```text
Get-TmuxPane [-Window] <Window> [-Id <string>]
```

## ALIASES

None.

## DESCRIPTION

Acquire panes from the native owning object. Id is an ordinal literal selector. Linked windows can expose multiple contextual placements of one physical pane. Use native Where-Object over the returned captured properties for local selection.

## EXAMPLES

### Example 1

List panes on the existing server identified by $SocketPath.

```powershell
LibTmux\New-TmuxServer -SocketPath $SocketPath | LibTmux\Get-TmuxPane
```

## PARAMETERS

### -Id

An ordinal, literal pane identifier selector.

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

The server whose panes are read.

```yaml
Type: LibTmux.Server
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Server
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Session

The session whose panes are read.

```yaml
Type: LibTmux.Session
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Session
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Window

The window whose panes are read.

```yaml
Type: LibTmux.Window
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Window
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

### LibTmux.Session

Native pipeline type for this command.

### LibTmux.Window

Native pipeline type for this command.

## OUTPUTS

### LibTmux.Pane

Native pipeline type for this command.

## NOTES

CurrentCommand and CurrentPath read captured data without I/O. Zero results emit nothing; one emits one object; many emit separate objects. Use @() for a stable array.

## RELATED LINKS

[Task guide](../../read.md)
