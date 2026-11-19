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

**What is on here.** A pane is the native LibTmux.Pane that Get-TmuxPane
returns. The cmdlets below return one, take one directly or from the pipeline,
or query for one. They fall into a few groups:

**Finding panes.** Get-TmuxPane lists the panes of a server, a session or a
window, or the one that matches an exact id. Update-TmuxPane reads a pane again
into a new capture. Get-TmuxSnapshot captures panes with the windows and
sessions that hold them, and Get-TmuxClientAttachment resolves the pane a client
is viewing.

Get-TmuxPane, Update-TmuxPane, Get-TmuxSnapshot and Get-TmuxClientAttachment

**Filtering and querying panes.** Select-TmuxPane filters panes you already
captured without contacting tmux, and can require exactly one match.
New-TmuxQuery builds criteria for the Pane target and Get-TmuxQueryField lists
the fields they accept. Invoke-TmuxQuery acquires fresh panes instead.

Select-TmuxPane, New-TmuxQuery, Get-TmuxQueryField and Invoke-TmuxQuery

**Splitting, resizing and removing a pane.** Split-TmuxPane splits a pane and
returns the new one. Set-TmuxPaneSize resizes a pane in cells or percent, by
an edge, or toggles its zoom. Remove-TmuxPane deletes a pane; removing the
last pane of a window destroys the window.

Split-TmuxPane, Set-TmuxPaneSize and Remove-TmuxPane

**Sending input and running commands.** Send-TmuxText types literal text, and
adds Enter only when you ask. Send-TmuxKey sends tmux key tokens such as C-a
or Enter. Invoke-TmuxPaneCommand runs a shell command in the pane and returns
its exit status; a nonzero status is a result, not an error.

Send-TmuxText, Send-TmuxKey and Invoke-TmuxPaneCommand

**Reading what a pane shows.** Get-TmuxPaneContent captures the rendered text,
and its history when you ask. Wait-TmuxPaneText waits for text to appear. A
timeout or a pane that exits comes back as an outcome of the wait, not as an
error.

Get-TmuxPaneContent and Wait-TmuxPaneText

**Options and hooks.** Get-TmuxOption, Set-TmuxOption and Remove-TmuxOption
read, write and unset the options of one pane. Get-TmuxHook, Set-TmuxHook and
Remove-TmuxHook do the same for its hooks, and Invoke-TmuxHook runs one now.

Get-TmuxOption, Set-TmuxOption, Remove-TmuxOption, Get-TmuxHook, Set-TmuxHook,
Remove-TmuxHook and Invoke-TmuxHook

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
