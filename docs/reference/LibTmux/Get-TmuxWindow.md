---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxWindow.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxWindow
---

# Get-TmuxWindow

## SYNOPSIS

Read contextual windows from a server or session.

## SYNTAX

### Server (Default)

```text
Get-TmuxWindow [-Server] <Server> [-Id <string>] [-Name <string>]
```

### Session

```text
Get-TmuxWindow [-Session] <Session> [-Id <string>] [-Name <string>]
```

## ALIASES

None.

## DESCRIPTION

Accept a native Server or Session as the owner. Each result retains its session placement. A linked window can therefore appear more than once. Id and Name are ordinal literal selectors; they do not expand wildcards.

**What is on here.** A window is the native LibTmux.Window that Get-TmuxWindow
returns. It carries its session placement, so a window linked into two sessions
appears twice. The cmdlets below return one, take one directly or from the
pipeline, or query for one. They fall into a few groups:

**Finding windows.** Get-TmuxWindow lists the windows of a server or a session,
or the ones that match an exact id or name. Get-TmuxPane lists the panes of one
window. Get-TmuxSnapshot captures windows with their panes, and
Get-TmuxClientAttachment resolves the window a client is viewing.

Get-TmuxWindow, Get-TmuxPane, Get-TmuxSnapshot and Get-TmuxClientAttachment

**Filtering and querying windows.** Select-TmuxWindow filters windows you
already captured without contacting tmux, and can require exactly one match.
New-TmuxQuery builds criteria for the Window target and Get-TmuxQueryField
lists the fields they accept. Invoke-TmuxQuery acquires fresh windows instead.

Select-TmuxWindow, New-TmuxQuery, Get-TmuxQueryField and Invoke-TmuxQuery

**Creating, renaming and removing a window.** New-TmuxWindow creates a window
and its first pane in a session, and returns it. Rename-TmuxWindow names the
window by id and, with PassThru, returns a replacement that carries the new
name. Remove-TmuxWindow destroys the physical window and its panes in every
session that links it.

New-TmuxWindow, Rename-TmuxWindow and Remove-TmuxWindow

**Linking and moving a window.** New-TmuxWindowLink links a window into
another session. Move-TmuxWindow moves one placement, within its session or to
another. Remove-TmuxWindowLink removes one placement and leaves the other links
alone; tmux refuses to remove the last one unless you pass KillIfLast.

New-TmuxWindowLink, Move-TmuxWindow and Remove-TmuxWindowLink

**Arranging and resizing a window.** Set-TmuxLayout applies a named preset or a
layout string you captured, and arranges the panes. Set-TmuxWindowSize resizes
the window in cells or against its attached clients.

Set-TmuxLayout and Set-TmuxWindowSize

**Options and hooks.** Get-TmuxOption, Set-TmuxOption and Remove-TmuxOption
read, write and unset the options of one window. Get-TmuxHook, Set-TmuxHook and
Remove-TmuxHook do the same for its hooks, and Invoke-TmuxHook runs one now.

Get-TmuxOption, Set-TmuxOption, Remove-TmuxOption, Get-TmuxHook, Set-TmuxHook,
Remove-TmuxHook and Invoke-TmuxHook

## EXAMPLES

### Example 1

List window placements on the existing server identified by $SocketPath.

```powershell
LibTmux\New-TmuxServer -SocketPath $SocketPath | LibTmux\Get-TmuxWindow
```

## PARAMETERS

### -Id

An ordinal, literal window identifier selector.

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

### -Name

An ordinal, literal window name selector.

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

The server whose windows are read.

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

The session whose windows are read.

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

## OUTPUTS

### LibTmux.Window

Native pipeline type for this command.

## NOTES

Global window identity differs from session-relative placement. Do not silently deduplicate results when placement index matters.

## RELATED LINKS

[Task guide](../../read.md)
