---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Send-TmuxKey.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Send-TmuxKey
---

# Send-TmuxKey

## SYNOPSIS

Send an ordered sequence of tmux key tokens to a native pane.

## SYNTAX

### __AllParameterSets

```text
Send-TmuxKey [-Pane] <Pane> [-Key] <String[]> [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Each array element is interpreted by tmux as a key token, such as C-a or
Enter. Unrecognized key names follow tmux's character-sending behavior. No
additional Enter is appended. Null, empty and NUL-containing tokens are
rejected before I/O. The command owns a snapshot of the supplied array.

Keys run in input order through one core command chain. A failure can leave
earlier keys delivered and prevent later keys from running.

The endpoint and daemon generation come from the supplied native pane.
WhatIf performs no acquisition or sending. Confirmation names the endpoint
and pane without displaying the supplied text or keys. Successful sending
confirms tmux accepted input; use an explicit application readiness signal
before checking that a command has finished.

## EXAMPLES

### Example 1

Use a previously selected native $pane on an endpoint you own.

```powershell
$pane | LibTmux\Send-TmuxKey -Key @('C-a', 'Enter') -Confirm:$false
```

## PARAMETERS

### -Confirm

Prompts for confirmation before sending input.

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

### -Key

Key tokens in sending order. Use an array for a sequence and quote tokens
such as 'C-a'. This command does not split one string on whitespace.

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

### -Pane

The native pane selected from the endpoint you intend to change.

```yaml
Type: LibTmux.Pane
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

Describe the intended input operation without acquiring or sending anything.

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

### LibTmux.Pane

A native pane selected from an explicit endpoint.

## OUTPUTS

### None

No success objects are emitted. An empty owner pipeline performs no work.

## NOTES

Failures use Tmux.KeySendFailed and retain the original core exception,
its dispatch information and the failed pane. ErrorAction Continue permits
later owners to be processed; ErrorAction Stop stops on the first failure.
NUL and invalid key-token content use Tmux.InvalidInput before dispatch;
PowerShell handles parameter binding errors. Cancellation stops pending work
but cannot undo delivered input. Nothing is retried.

## RELATED LINKS

[Choose endpoints and owners](../../read.md)

[Capture pane output](../../capture.md)
