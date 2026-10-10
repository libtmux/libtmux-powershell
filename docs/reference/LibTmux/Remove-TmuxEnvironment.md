---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Remove-TmuxEnvironment.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Remove-TmuxEnvironment
---

# Remove-TmuxEnvironment

## SYNOPSIS

Unset an environment entry or keep an explicit removal marker.

## SYNTAX

### Server (Default)

```text
Remove-TmuxEnvironment [-Server] <Server> -Name <String> [-MarkRemoved] [-WhatIf] [-Confirm]
```

### Session

```text
Remove-TmuxEnvironment [-Session] <Session> -Name <String> [-MarkRemoved] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

By default, forget the entry using tmux set-environment -u. Unsetting a session
entry allows a global value to apply to future panes again. MarkRemoved instead
uses -r: tmux retains a removal marker to suppress the variable in future pane
processes. Neither operation is equivalent to setting an empty string. WhatIf
performs no tmux I/O.

## EXAMPLES

### Example 1

Prevent future processes in a native $session from inheriting APP_MODE.

```powershell
$session | LibTmux\Remove-TmuxEnvironment -Name 'APP_MODE' -MarkRemoved
```

## PARAMETERS

### -Confirm

Ask for confirmation before changing the selected table.

```yaml
Type: System.Management.Automation.SwitchParameter
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

### -MarkRemoved

Keep a removal marker to suppress inherited values in new child processes instead of forgetting the entry.

```yaml
Type: System.Management.Automation.SwitchParameter
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

The environment variable name. Omit Name on Get to list this table. Whitespace-only names and NUL are rejected.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
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

### -WhatIf

Show the selected owner, scope and operation without contacting tmux.

```yaml
Type: System.Management.Automation.SwitchParameter
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

A native server owner.

### LibTmux.Session

A native session owner.

## OUTPUTS

### None

No success output.

## NOTES

A Server selects the global environment; a Session selects its local environment.
Reads do not merge those tables. Changes affect newly created processes and do not
rewrite the environment of an existing pane process. Empty owner pipelines do no
I/O. Errors retain the original exception and owner; Continue permits later owners
and Stop terminates. Cancellation cannot undo a dispatched mutation.

## RELATED LINKS

[Environment](../../environment.md)
