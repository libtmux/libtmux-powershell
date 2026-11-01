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

Choose a socket name or absolute socket path. Construction performs no tmux I/O
and does not start or own a daemon. A later command explicitly acquires data or
changes tmux.

Omitting both socket parameters passes tmux no socket, so tmux picks the
server: the one the TMUX variable names inside a tmux pane, otherwise its
default socket. Two variables choose a socket for such a handle.
LIBTMUX_SOCKET_PATH becomes -S and LIBTMUX_SOCKET becomes -L; when both are set
the path wins, and a blank value counts as unset. A parameter beats both
variables. The handle reads the variables when it is made.
LIBTMUX_SOCKET_NAME, which earlier versions read, selects nothing.

**What is on here.** Most cmdlets in the module start from the handle this one
returns. They take it directly, or take a session, window, pane or client that
was read through it. The cmdlets fall into a few groups:

**Connecting.** New-TmuxServer builds the handle. Connect-TmuxServer discovers
the live server behind it and returns a connected replacement, and
Get-TmuxServer reads the daemon's identity and version without starting one.
Connect-TmuxControl opens a control client and Disconnect-TmuxControl closes it.

New-TmuxServer, Connect-TmuxServer, Get-TmuxServer, Connect-TmuxControl and
Disconnect-TmuxControl

**Finding one thing.** Get-TmuxSession and Get-TmuxWindow select by id or name,
Get-TmuxPane by id, and Get-TmuxClient by name. A selector that matches nothing
emits nothing. Get-TmuxClientAttachment resolves the session, window and pane a
client is viewing.

Get-TmuxSession, Get-TmuxWindow, Get-TmuxPane, Get-TmuxClient and
Get-TmuxClientAttachment

**Listing everything.** Get-TmuxSession, Get-TmuxWindow, Get-TmuxPane and
Get-TmuxClient list everything on the server when given no selector. A missing
daemon writes an error instead of returning an empty list. Get-TmuxSnapshot
captures the hierarchy to a depth you choose and returns a replacement server.
Update-TmuxPane and Update-TmuxClient read one object again into a new capture.

Get-TmuxSession, Get-TmuxWindow, Get-TmuxPane, Get-TmuxClient, Get-TmuxSnapshot,
Update-TmuxPane and Update-TmuxClient

**Querying things and getting around.** New-TmuxQuery builds reusable criteria.
Select-TmuxSession, Select-TmuxWindow and Select-TmuxPane filter objects you
already captured without contacting tmux, and can require exactly one match.
Invoke-TmuxQuery acquires fresh objects instead. Get-TmuxQueryField lists the
fields and operators, Get-TmuxQueryPlan shows how a query will run, and
`ConvertTo-TmuxQueryJson` serializes one. To move down the hierarchy, pass a
session to Get-TmuxWindow or Get-TmuxPane, or a window to Get-TmuxPane.

New-TmuxQuery, Select-TmuxSession, Select-TmuxWindow, Select-TmuxPane,
Invoke-TmuxQuery, Get-TmuxQueryField, Get-TmuxQueryPlan,
`ConvertTo-TmuxQueryJson`, Get-TmuxWindow and Get-TmuxPane

**Changing things.** New-TmuxSession, New-TmuxWindow, Split-TmuxPane and
New-TmuxWindowLink create, and New-TmuxSession can start a daemon that is not
running yet. Move-TmuxWindow, Set-TmuxLayout, Set-TmuxPaneSize and
Set-TmuxWindowSize rearrange. Remove-TmuxSession, Remove-TmuxWindow,
Remove-TmuxWindowLink and Remove-TmuxPane delete.

New-TmuxSession, New-TmuxWindow, Split-TmuxPane, New-TmuxWindowLink,
Move-TmuxWindow, Set-TmuxLayout, Set-TmuxPaneSize, Set-TmuxWindowSize,
Remove-TmuxSession, Remove-TmuxWindow, Remove-TmuxWindowLink and Remove-TmuxPane

**Options and hooks.** Get-TmuxOption, Set-TmuxOption and Remove-TmuxOption
read, write and unset options on a server, session, window or pane.
Get-TmuxHook, Set-TmuxHook and Remove-TmuxHook do the same for hooks, and
Invoke-TmuxHook runs one now. Get-TmuxEnvironment, Set-TmuxEnvironment and
Remove-TmuxEnvironment manage the environment table of a server or session.

Get-TmuxOption, Set-TmuxOption, Remove-TmuxOption, Get-TmuxHook, Set-TmuxHook,
Remove-TmuxHook, Invoke-TmuxHook, Get-TmuxEnvironment, Set-TmuxEnvironment and
Remove-TmuxEnvironment

**Everything else tmux keeps.** Send-TmuxText and Send-TmuxKey type into a pane,
Get-TmuxPaneContent reads what it shows, and Wait-TmuxPaneText waits for text to
appear. Invoke-TmuxPaneCommand runs a shell command in a pane and reports its
exit status. Wait-TmuxChannel waits for a channel signal, and Watch-TmuxEvent
streams events from a control client.

Send-TmuxText, Send-TmuxKey, Get-TmuxPaneContent, Wait-TmuxPaneText,
Invoke-TmuxPaneCommand, Wait-TmuxChannel and Watch-TmuxEvent

**Things that need a terminal.** Enter-TmuxSession attaches your foreground
terminal to a session and returns when you detach. Run it outside tmux; it
rejects redirected input.

Enter-TmuxSession

**Running a command.** Anything tmux can do that is not here is reachable
through Invoke-TmuxCommand, which runs literal tmux arguments and returns the
result. Invoke-TmuxChain runs several commands in order, New-TmuxCommand builds
one without running it, and Invoke-TmuxControlCommand sends one over a control
client.

Invoke-TmuxCommand, Invoke-TmuxChain, New-TmuxCommand and
Invoke-TmuxControlCommand

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

The tmux socket name, passed as -L. It beats LIBTMUX_SOCKET and
LIBTMUX_SOCKET_PATH.

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

The absolute socket path, passed as -S. It beats LIBTMUX_SOCKET and
LIBTMUX_SOCKET_PATH.

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
