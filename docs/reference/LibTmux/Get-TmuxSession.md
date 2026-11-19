---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxSession.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxSession
---

# Get-TmuxSession

## SYNOPSIS

Read sessions with optional exact selectors.

## SYNTAX

### __AllParameterSets

```text
Get-TmuxSession [-Server] <Server> [-Id <string>] [-Name <string>]
```

## ALIASES

None.

## DESCRIPTION

Acquire sessions from a native Server. Id and Name are ordinal, case-sensitive literal selectors; combining them requires both to match. Wildcards are not expanded. An unmatched selector emits nothing; a failed acquisition writes an error.

**What is on here.** A session is the native LibTmux.Session that
Get-TmuxSession returns. The cmdlets below return one, take one directly or from
the pipeline, or query for one. They fall into a few groups:

**Finding sessions.** Get-TmuxSession lists every session on a server, or the
ones that match an exact id or name. Get-TmuxSnapshot captures sessions with
their windows and panes, and Get-TmuxClientAttachment resolves the session a
client is viewing.

Get-TmuxSession, Get-TmuxSnapshot and Get-TmuxClientAttachment

**Filtering and querying sessions.** Select-TmuxSession filters sessions you
already captured without contacting tmux, and can require exactly one match.
New-TmuxQuery builds criteria for the Session target and Get-TmuxQueryField
lists the fields they accept. Invoke-TmuxQuery acquires fresh sessions instead.

Select-TmuxSession, New-TmuxQuery, Get-TmuxQueryField and Invoke-TmuxQuery

**Creating a session.** New-TmuxSession creates a detached session with its
first window and pane, and returns it. It can start a daemon that is not
running yet, and an existing name is an error.

New-TmuxSession

**Renaming or removing a session.** Rename-TmuxSession names the session by id
and, with PassThru, returns a replacement that carries the new name.
Remove-TmuxSession deletes it, and destroys the windows that only it owns.
Windows linked into another session survive.

Rename-TmuxSession and Remove-TmuxSession

**Working inside a session.** New-TmuxWindow adds a window, and
New-TmuxWindowLink links an existing one into the session. Move-TmuxWindow
moves a window placement to it. Get-TmuxWindow and Get-TmuxPane list what it
holds.

New-TmuxWindow, New-TmuxWindowLink, Move-TmuxWindow, Get-TmuxWindow and
Get-TmuxPane

**Attaching a terminal.** Enter-TmuxSession attaches your foreground terminal
to the session and returns when you detach. Run it outside tmux; it rejects
redirected input.

Enter-TmuxSession

**Options, hooks and environment.** Get-TmuxOption, Set-TmuxOption and
Remove-TmuxOption read, write and unset the options of one session.
Get-TmuxHook, Set-TmuxHook and Remove-TmuxHook do the same for its hooks, and
Invoke-TmuxHook runs one now. Get-TmuxEnvironment, Set-TmuxEnvironment and
Remove-TmuxEnvironment manage its environment table.

Get-TmuxOption, Set-TmuxOption, Remove-TmuxOption, Get-TmuxHook, Set-TmuxHook,
Remove-TmuxHook, Invoke-TmuxHook, Get-TmuxEnvironment, Set-TmuxEnvironment and
Remove-TmuxEnvironment

**Saving a session as a workspace.** `ConvertTo-TmuxWorkspace` turns a captured
session into a workspace declaration without contacting tmux. Capture the
session with Get-TmuxSnapshot first, at the Panes depth, so its windows and
panes come with it.

`ConvertTo-TmuxWorkspace` and Get-TmuxSnapshot

## EXAMPLES

### Example 1

List sessions on the existing server identified by $SocketPath.

```powershell
LibTmux\New-TmuxServer -SocketPath $SocketPath | LibTmux\Get-TmuxSession
```

## PARAMETERS

### -Id

An ordinal, literal session identifier selector.

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

An ordinal, literal session name selector.

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

The server whose sessions are read.

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

### LibTmux.Session

Native pipeline type for this command.

## NOTES

Wrap results in @() when a stable array is needed. A missing daemon is an error, not a successful empty list. Session-only capture does not acquire windows.

## RELATED LINKS

[Task guide](../../read.md)
