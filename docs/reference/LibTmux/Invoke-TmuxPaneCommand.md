---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Invoke-TmuxPaneCommand.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/27/2026
PlatyPS schema version: 2024-05-01
title: Invoke-TmuxPaneCommand
---

# Invoke-TmuxPaneCommand

## SYNOPSIS

Run a shell command in a native pane and report its exit status.

## SYNTAX

### __AllParameterSets

```text
Invoke-TmuxPaneCommand [-Pane] <Pane> [-Command] <String> [-Timeout <Double>] [-SuppressHistory <Boolean>] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Run Command in a subshell in the selected pane and return a native
`LibTmux.PaneRunResult`. The result records the pane ID, authenticated shell
exit status, whether the wait timed out, elapsed time and effective timeout. A
nonzero exit status is a result, not a cmdlet error. The command does not change
the parent shell's working directory or environment.

A timeout returns `TimedOut = True` and a null `ExitStatus`; the command may
still be running. Cancellation after dispatch can leave it running too. Inspect
the pane before retrying either case. `Output` contains bounded rendered command
output, which may include stdout and stderr together. It is not a byte-exact
process stream. Inspect `LinesMissed`, `AnchorLost` and omission counts before
treating it as complete. `Started = False` means no start marker was confirmed;
it does not prove the command never ran. The default view omits output text.
[Get-TmuxPaneContent](Get-TmuxPaneContent.md) reads the current screen separately.

The pane must be a live, writable POSIX-compatible shell. `-WhatIf` performs
no tmux I/O or input operation. Confirmation identifies the endpoint and pane
without displaying Command. A leading space is added to shell input by default;
shells configured to ignore space-prefixed history entries may omit it from
history. This is best effort.

## EXAMPLES

### Example 1

Given a native `$pane` running `/bin/sh` on an endpoint you own, inspect a
nonzero status without treating it as an operation failure:

```powershell
$pane |
    LibTmux\Invoke-TmuxPaneCommand -Command 'exit 7' -Timeout 5 -Confirm:$false
```

The result has `ExitStatus = 7` and `TimedOut = False`.

## PARAMETERS

### -Command

The shell command to run in a subshell. Empty, whitespace-only and NUL-containing
commands are rejected. The core accepts at most 64 KiB of UTF-8 input.

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

### -Confirm

Prompt before sending the command. The prompt does not show Command.

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

### -Pane

The native pane from the endpoint you intend to change.

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

### -SuppressHistory

Add a leading space to the shell input. Defaults to True. Set to False to
omit the prefix; shell history behavior still depends on the shell and its
configuration.

```yaml
Type: System.Boolean
DefaultValue: 'True'
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

### -Timeout

The completion wait in seconds. Fractions are accepted. The default is 30;
the valid range is 0.0000001 through 86400. NaN and infinity are rejected.
Cleanup after an observed result may take additional time.

```yaml
Type: System.Double
DefaultValue: '30'
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

Describe the intended command without sending it or acquiring fresh tmux state.

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

The native pane selected from an explicit endpoint.

## OUTPUTS

### LibTmux.PaneRunResult

One result per pane with exit status or a timeout indication.

## NOTES

Tmux.PaneCommandFailed retains the pane as its target. The core reserves one
active command per pane in this process. A timed-out run keeps its reservation
until completion or an authenticated pane/server end; a second run is refused
while that command may still be active. A borrowed server is never removed.

## RELATED LINKS

[Send input to a pane](../../input.md)
