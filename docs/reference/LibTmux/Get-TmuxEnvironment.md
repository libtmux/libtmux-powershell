---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxEnvironment.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxEnvironment
---

# Get-TmuxEnvironment

## SYNOPSIS

Read native tmux environment entries.

## SYNTAX

### Server (Default)

```text
Get-TmuxEnvironment [-Server] <Server> [-Name <String>]
```

### Session

```text
Get-TmuxEnvironment [-Session] <Session> [-Name <String>]
```

## ALIASES

None.

## DESCRIPTION

Emit native TmuxEnvironmentEntry objects with Name, Value and IsRemoved. An empty
value is present. A removal marker has IsRemoved true and Value null; an absent or
hidden variable emits no object. Hidden variables remain available to tmux formats
and are excluded from new child process environments. Omit Name to list the table.

## EXAMPLES

### Example 1

Read a previously stored variable from a native $session.

```powershell
$session | LibTmux\Get-TmuxEnvironment -Name 'APP_MODE'
```

## PARAMETERS

### -Name

The environment variable name. Omit Name on Get to list this table. Whitespace-only names and NUL are rejected.

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

The native server whose table is used.

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

The native session whose table is used.

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

A native server owner.

### LibTmux.Session

A native session owner.

## OUTPUTS

### LibTmux.TmuxEnvironmentEntry

One native entry per visible variable or removal marker.

## NOTES

A Server selects the global environment; a Session selects its local environment.
Reads do not merge those tables. Changes affect newly created processes and do not
rewrite the environment of an existing pane process. Empty owner pipelines do no
I/O. Errors retain the original exception and owner; Continue permits later owners
and Stop terminates. Cancellation cannot undo a dispatched mutation.

## RELATED LINKS

[Environment](../../environment.md)
