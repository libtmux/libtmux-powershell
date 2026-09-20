---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Invoke-TmuxControlCommand.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Invoke-TmuxControlCommand
---

# Invoke-TmuxControlCommand

## SYNOPSIS

Run a native command on a borrowed control client.

## SYNTAX

### __AllParameterSets

```text
Invoke-TmuxControlCommand [-Connection] <IControlModeSession> [-Command] <TmuxCommand> [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Send one native command and emit its reply lines as strings. Commands with
no reply emit no success object. Native commands retain their generation and
placement guards; raw commands use tmux target resolution.

Concurrent callers receive their correlated replies from the core. Cancelling
stops this caller waiting, not a command already sent, and does not dispose
the borrowed client. A later send remains usable after the cancelled command
finishes. WhatIf sends nothing; an empty connection pipeline performs no work.

## EXAMPLES

### Example 1

Print the attached session name using an existing $control owned by your surrounding try/finally scope.

```powershell
$control | LibTmux\Invoke-TmuxControlCommand -Command (LibTmux\New-TmuxCommand -Name 'display-message' -Arguments @('-p', '#{session_name}'))
```

## PARAMETERS

### -Command

The native command. Raw commands contain no captured entity identity guard.

```yaml
Type: LibTmux.TmuxCommand
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

### -Connection

The native control client. This operation borrows the supplied client.

```yaml
Type: LibTmux.IControlModeSession
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

### LibTmux.IControlModeSession

The borrowed client to send through.

## OUTPUTS

### System.String

Native reply lines, in reply order.

## NOTES

Tmux.InvalidCommand rejects a global option in the command-name position
before dispatch. Tmux.ControlCommandFailed retains native exceptions and the
connection target. ErrorAction Continue permits later clients to run. The
core bounds pending requests and replies; rejected admission does not retry.
Confirmation identifies the supplied connection without inventing endpoint
metadata absent from IControlModeSession.

## RELATED LINKS

[Commands and control clients](../../commands.md)
