---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Send-TmuxText.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Send-TmuxText
---

# Send-TmuxText

## SYNOPSIS

Send literal text and optional Enter to a native pane.

## SYNTAX

### __AllParameterSets

```text
Send-TmuxText [-Pane] <Pane> [-Text] <String> [-Enter] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Text is literal: key names, leading dashes, semicolons and tmux format markers
remain text. Enter is sent only when requested. Newlines already present in
Text are delivered regardless of the Enter switch; they can execute commands
in the receiving shell or application. NUL characters are rejected before I/O.

An empty string is accepted, including with Enter to send just that key.

The endpoint and daemon generation come from the supplied native pane.
WhatIf performs no acquisition or sending. Confirmation names the endpoint
and pane without displaying the supplied text or keys. Successful sending
confirms tmux accepted input; use an explicit application readiness signal
before checking that a command has finished.

## EXAMPLES

### Example 1

Use a previously selected native $pane on an endpoint you own.

```powershell
$pane | LibTmux\Send-TmuxText -Text 'Enter' -Confirm:$false
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

### -Enter

Send one Enter key after the literal text. Omitted by default.

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

### -Text

Literal text to send. Empty text is valid; NUL is unsupported. Newlines and
control characters can affect the receiving application.

```yaml
Type: System.String
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

Failures use Tmux.TextSendFailed and retain the original core exception,
its dispatch information and the failed pane. ErrorAction Continue permits
later owners to be processed; ErrorAction Stop stops on the first failure.
NUL and invalid key-token content use Tmux.InvalidInput before dispatch;
PowerShell handles parameter binding errors. Cancellation stops pending work
but cannot undo delivered input. Nothing is retried.
If text was sent but the following Enter fails, the core reports unknown
partial dispatch. Retrying the whole operation can duplicate effects.

## RELATED LINKS

[Choose endpoints and owners](../../read.md)

[Capture pane output](../../capture.md)
