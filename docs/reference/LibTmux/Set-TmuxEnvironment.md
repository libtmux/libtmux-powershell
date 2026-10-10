---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Set-TmuxEnvironment.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Set-TmuxEnvironment
---

# Set-TmuxEnvironment

## SYNOPSIS

Set a tmux environment variable for future processes or formats.

## SYNTAX

### Server (Default)

```text
Set-TmuxEnvironment [-Server] <Server> -Name <String> -Value <String> [-ExpandFormats] [-Hidden] [-PassThru] [-WhatIf] [-Confirm]
```

### Session

```text
Set-TmuxEnvironment [-Session] <Session> -Name <String> -Value <String> [-ExpandFormats] [-Hidden] [-PassThru] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

An empty string sets a present, empty value. ExpandFormats expands tmux formats
before storage. Hidden keeps the variable for tmux formats and excludes it from
new child process environments and ordinary reads. With Hidden and PassThru, the
native readback entry has Value null and IsRemoved false; this does not mean an
empty or removed variable. Without PassThru, emit no success output. WhatIf does
not contact tmux.

## EXAMPLES

### Example 1

Set a value for future processes in a native $session and inspect its readback.

```powershell
$session |
    LibTmux\Set-TmuxEnvironment -Name 'APP_MODE' -Value 'development' -PassThru
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

### -ExpandFormats

Expand tmux formats in the value before storage.

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

### -Hidden

Keep the variable for tmux formats, excluding it from child environments and ordinary reads.

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

### -PassThru

Emit the native value read back after the mutation. Without this switch, emit no success output. Readback still occurs.

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

### -Value

The value to store. Empty strings are allowed; NUL is rejected.

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

### LibTmux.TmuxEnvironmentEntry

The native readback entry, only with PassThru.

## NOTES

A Server selects the global environment; a Session selects its local environment.
Reads do not merge those tables. Changes affect newly created processes and do not
rewrite the environment of an existing pane process. Empty owner pipelines do no
I/O. Errors retain the original exception and owner; Continue permits later owners
and Stop terminates. Cancellation cannot undo a dispatched mutation.

## RELATED LINKS

[Environment](../../environment.md)
