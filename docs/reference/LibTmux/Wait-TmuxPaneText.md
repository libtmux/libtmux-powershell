---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Wait-TmuxPaneText.md
Locale: en-US
Module Name: LibTmux
ms.date: 10/03/2026
PlatyPS schema version: 2024-05-01
title: Wait-TmuxPaneText
---

# Wait-TmuxPaneText

## SYNOPSIS

Wait for rendered text in a native tmux pane.

## SYNTAX

### __AllParameterSets

```text
Wait-TmuxPaneText [-Pane] <Pane> [[-Pattern] <String[]>] [-StopPattern <String[]>] [-CaseSensitive] [-SimpleMatch] [-Timeout <Double>] [-AllowPollingFallback] [-TailLines <Int32>] [-MaxOutputBytes <Int32>] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Watch the selected pane until one pattern matches rendered text. A match
already visible when observation begins returns `PresentAtEntry`. With no
pattern, the command waits for any new rendered output and returns `AnyOutput`.
Stop patterns return `Stopped`; the deadline and a pane exit return `TimedOut`
and `PaneExited`. These are native `LibTmux.PaneWaitResult` outcomes, not cmdlet
errors. Inspect `Outcome` before treating a wait as readiness.

The observer attaches a temporary control client before its first capture.
Control events wake a grid-aware reader; matching uses captured rendered rows,
not individual output fragments. Results include a bounded final screen tail,
elapsed and effective timeout, dropped-event count, polling fallback, and
missed-line or lost-anchor indicators. The default view shows `Missed` and
omits the tail; inspect `Tail` explicitly if you need its text. A lost event
or anchor means the observer may have missed transient output.

Control observation is required by default. `-AllowPollingFallback` permits
bounded polling if control observation fails, and the result discloses whether
it ran. The wait borrows the pane and server; it disposes only its own observer
and client on completion or Ctrl+C. `-WhatIf` attaches no client and captures
no text. Confirmation identifies the endpoint and pane without displaying
patterns or pane content.

This command recognizes text; it does not authenticate command completion or
an exit status. Use [Invoke-TmuxPaneCommand](Invoke-TmuxPaneCommand.md) for a
shell command you start or [Wait-TmuxChannel](Wait-TmuxChannel.md) for a
cooperative application signal. Visible text can include input echoed by a
shell or application. `Get-TmuxPaneContent -History` reads retained rendered
scrollback, while `-Raw` joins rendered rows; neither is a byte-exact process
stream.

## EXAMPLES

### Example 1

Given a native `$pane` running a program that reads one line, prints `READY`,
then stays alive, send a trigger that cannot match the ready pattern. Output
may arrive before the wait begins; both `PresentAtEntry` and `Matched` mean the
line was observed:

```powershell
& {
    $pane | LibTmux\Send-TmuxText -Text go -Enter -Confirm:$false
    $pane | LibTmux\Wait-TmuxPaneText -Pattern '^READY$' -Timeout 5 -Confirm:$false
}
```

## PARAMETERS

### -AllowPollingFallback

Allow bounded capture polling if the control client cannot observe the pane.
The default is to report the control failure. `PollingFallback` discloses use.

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

### -CaseSensitive

Match letter case. Patterns are case-insensitive by default.

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

### -Confirm

Prompt before attaching an observer. The prompt omits pattern and pane text.

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

### -MaxOutputBytes

Maximum UTF-8 bytes retained in the result tail. The default is 65536; the
valid range is 1 through 1048576. This bounds returned text, not the producer.

```yaml
Type: System.Int32
DefaultValue: '65536'
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

### -Pane

The native pane to observe. An arbitrary object with an Id property is not a
pane owner.

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

### -Pattern

Regular expressions to wait for. Omit or pass an empty array to wait for any
new rendered output. Empty entries are rejected. The shared observer bounds
regex matching work and time over rendered rows. It uses .NET's nonbacktracking
regex mode; unsupported constructs such as lookarounds and backreferences are
rejected before attaching a client.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SimpleMatch

Treat each pattern and stop pattern as literal text instead of a regular
expression. `-CaseSensitive` still controls case matching.

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

### -StopPattern

Regular expressions that end the wait with `Outcome = Stopped`. Stop patterns
take precedence over wanted patterns, including text visible at entry. Across both
pattern lists, at most 32 entries, 999 UTF-8 bytes per entry and 16384 bytes
in total are accepted.

```yaml
Type: System.String[]
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

### -TailLines

Maximum rendered screen lines retained in the result tail. The default is 20;
the valid range is 1 through 1000. Truncation is reported separately.

```yaml
Type: System.Int32
DefaultValue: '20'
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

Wait budget in seconds. Fractions are accepted. The default is 10; the valid
range is 0.0000001 through 86400. A timed-out wait does not prove the program
stopped or the desired text was never printed.

```yaml
Type: System.Double
DefaultValue: '10'
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

Describe the intended observer without attaching a client or capturing text.

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

The pane selected from an explicit endpoint.

## OUTPUTS

### LibTmux.PaneWaitResult

One result per pane with outcome, matched pattern, bounded rendered tail and
observation metadata. No result is emitted for `-WhatIf` or an empty pipeline.

## NOTES

`Tmux.PaneTextWaitFailed` retains the native pane as its error target for
transport and capture failures. `Tmux.InvalidTimeout` and
`Tmux.InvalidPaneTextRequest` fail before attaching a client. `-ErrorAction
Continue` can advance to the next pane after an operation error;
`-ErrorAction Stop` stops the pipeline.

## RELATED LINKS

[Send input to a pane](../../input.md)

[Capture rendered pane text](../../capture.md)
