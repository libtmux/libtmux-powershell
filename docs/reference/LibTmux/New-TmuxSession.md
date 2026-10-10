---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/New-TmuxSession.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: New-TmuxSession
---

# New-TmuxSession

## SYNOPSIS

Create a detached session on an explicit server.

## SYNTAX

### __AllParameterSets

```text
New-TmuxSession [-Server] <Server> [-Name <string>] [-WindowName <string>]
 [-StartDirectory <string>] [-Command <string>] [-Width <int>] [-Height <int>]
 [-Environment <IDictionary>] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Create a session and its initial window and pane, then return the captured
native LibTmux.Session. The Server parameter accepts a native endpoint handle
directly or through the pipeline. The core can start the daemon when that
endpoint has no server. Existing session names remain errors; the command does
not replace or attach to an existing session.

## EXAMPLES

### Example 1

Create a detached session on the server identified by the absolute $SocketPath.
Choose an endpoint you control; the created session remains running until you
remove it.

```powershell
$options = @{
    Name = 'help-session'
    WindowName = 'work'
    Command = 'exec /bin/sh'
}
LibTmux\New-TmuxServer -SocketPath $SocketPath |
    LibTmux\New-TmuxSession @options
```

## PARAMETERS

### -Command

One shell-command string for the new pane. tmux interprets shell syntax in this
string; it is not an argument array. Omit it to use the configured default
command or shell.

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

### -Confirm

Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- cf
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

### -Environment

A dictionary with string names and string values. Names must be nonempty and
contain neither '=' nor NUL (U+0000). Values may be empty but must not contain
NUL. Null or non-string entries are rejected before confirmation or dispatch.
Entries are copied for this invocation and do not change the PowerShell host
environment.

```yaml
Type: System.Collections.IDictionary
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

### -Height

Initial height in terminal cells, at least 1. Omit it to use tmux's default
dimensions.

```yaml
Type: System.Nullable`1[System.Int32]
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

Session name. Omit it to let tmux choose. An existing name remains an error;
tmux's name and format rules apply.

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

Native server endpoint in which to create the session. This is the only
pipeline-bound parameter; binding by an object's Server property is not
supported.

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

### -StartDirectory

Working directory for the new pane. Use an absolute filesystem path for
predictable behavior. The core expands ~ and ~/; this cmdlet does not resolve
PowerShell provider paths or change the host's current directory.

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

### -WhatIf

Runs the command in a mode that only reports what would happen without performing the actions.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- wi
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

### -Width

Initial width in terminal cells, at least 1. Omit it to use tmux's default
dimensions.

```yaml
Type: System.Nullable`1[System.Int32]
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

### -WindowName

Name of the initial window. Omit it to retain tmux's default naming behavior.

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

### LibTmux.Server

Native pipeline type for this command.

## OUTPUTS

### LibTmux.Session

Captured native object for the created resource.

## NOTES

WhatIf reports the intended endpoint without discovery, daemon startup or
dispatch, and returns no created object. Confirmation precedes the core
operation. Success does not transfer ownership of the daemon to the module or
arrange automatic cleanup. Cancellation can occur after a session was created;
it is not rollback and the module does not retry. Per-owner errors use
Tmux.SessionCreateFailed and retain the core exception and failed server.
ErrorAction Continue allows later owners to run.

## RELATED LINKS

[Task guide](../../create.md)
