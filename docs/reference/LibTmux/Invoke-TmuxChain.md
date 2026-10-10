---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Invoke-TmuxChain.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Invoke-TmuxChain
---

# Invoke-TmuxChain

## SYNOPSIS

Execute an ordered command chain against one server.

## SYNTAX

### __AllParameterSets

```text
Invoke-TmuxChain [-Server] <Server> [-Command] <TmuxCommand[]> [-MaxCommands <Int32>] [-MaxInputBytes <Int64>] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Execute an explicit array of native commands in order and return one merged
TmuxCommandResult. Native generation and window-placement guards are retained.
An empty server pipeline performs no work. Admission validates the complete
array before confirmation or dispatch.

A failed command stops the remaining chain; earlier mutations remain. The
result is merged stdout/stderr, not one receipt per command. Chains are not
transactions. Cancellation cannot undo a command already sent to tmux.

## EXAMPLES

### Example 1

Print two values in order on a previously selected $server.

```powershell
$commands = 'first', 'second' | ForEach-Object {
    LibTmux\New-TmuxCommand -Name 'display-message' -Arguments @('-p', $_)
}
$server | LibTmux\Invoke-TmuxChain -Command $commands
```

## PARAMETERS

### -Command

A nonempty array of native commands in dispatch order.

```yaml
Type: LibTmux.TmuxCommand[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Confirm

Ask for confirmation before the operation.

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

### -MaxCommands

Positive admitted command count. Default: 1024.

```yaml
Type: System.Int32
DefaultValue: '1024'
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

### -MaxInputBytes

Positive UTF-8 budget for command names and argument text, including one NUL terminator per item. Default: 1048576. This is an argv-text budget, not a process-memory or response budget. Native transport and operating-system limits still apply.

```yaml
Type: System.Int64
DefaultValue: '1048576'
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

The explicit endpoint that receives the operation.

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

### -WhatIf

Show the operation without contacting tmux.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Server

The native server to execute against.

## OUTPUTS

### LibTmux.TmuxCommandResult

One native merged result after success.

## NOTES

Tmux.InvalidChain terminates invalid admission. Tmux.ChainFailed retains the
native failure and server target. ErrorAction Continue permits later servers
to run; Stop terminates. WhatIf dispatches nothing. Do not automatically retry
an uncertain mutation.

## RELATED LINKS

[Commands and control clients](../../commands.md)
