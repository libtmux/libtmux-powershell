---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Invoke-TmuxCommand.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Invoke-TmuxCommand
---

# Invoke-TmuxCommand

## SYNOPSIS

Execute literal tmux arguments against an explicit server.

## SYNTAX

### __AllParameterSets

```text
Invoke-TmuxCommand [-Server] <Server> [-Arguments] <string[]> [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Pass the tmux command name and arguments as a string array. The adapter invokes the core directly without a shell. It returns a native TmuxCommandResult only on success; a nonzero exit writes an error retaining the result, target and dispatch metadata.

## EXAMPLES

### Example 1

Read the version of the existing server identified by $SocketPath.

```powershell
$arguments = @('display-message', '-p', '#{version}')
LibTmux\New-TmuxServer -SocketPath $SocketPath |
    LibTmux\Invoke-TmuxCommand -Arguments $arguments
```

## PARAMETERS

### -Arguments

Literal arguments beginning with a tmux command name or alias. Global options such as -S, -L and -f cannot replace the command name; configure the endpoint on Server. Invalid command names terminate before confirmation or dispatch.

```yaml
Type: System.String[]
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

### -Server

The endpoint that receives the command.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Server

Native pipeline type for this command.

## OUTPUTS

### LibTmux.TmuxCommandResult

Native pipeline type for this command.

## NOTES

Arguments can mutate tmux or run application commands. WhatIf performs no dispatch. Confirmation shows the command name without exposing the full argument content. Cancellation does not prove a dispatched mutation was rolled back; do not retry uncertain mutations automatically.

## RELATED LINKS

[Task guide](../../capture.md)
