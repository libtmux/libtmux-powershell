---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxOption.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxOption
---

# Get-TmuxOption

## SYNOPSIS

Read a native tmux option table or named option.

## SYNTAX

### Server (Default)

```text
Get-TmuxOption [-Server] <Server> [-Name <String>] [-Scope <OptionScope>] [-Global] [-IncludeInherited] [-IncludeHooks] [-Quiet]
```

### Session

```text
Get-TmuxOption [-Session] <Session> [-Name <String>] [-Scope <OptionScope>] [-Global] [-IncludeInherited] [-IncludeHooks] [-Quiet]
```

### Window

```text
Get-TmuxOption [-Window] <Window> [-Name <String>] [-Scope <OptionScope>] [-Global] [-IncludeInherited] [-IncludeHooks] [-Quiet]
```

### Pane

```text
Get-TmuxOption [-Pane] <Pane> [-Name <String>] [-Scope <OptionScope>] [-Global] [-IncludeInherited] [-IncludeHooks] [-Quiet]
```

## ALIASES

None.

## DESCRIPTION

The native owner selects its option table. Scope overrides that choice, and Global
selects global defaults. A named read emits each native TmuxOption row, preserving
sparse array indices, inherited markers and TmuxOptionValue fields. Omit Name to
list the table. IncludeInherited requests inherited values explicitly.

Global values and local overrides remain separate. Names follow tmux syntax,
including array indices and tmux format expansion. Use Where-Object on returned
rows for local PowerShell filtering.

## EXAMPLES

### Example 1

Read the effective key mode from a previously selected native $session.

```powershell
$session | LibTmux\Get-TmuxOption -Name 'status-keys' -IncludeInherited
```

## PARAMETERS

### -Global

Use the global table for the selected scope. For global session defaults from a Server, specify Scope Session and Global.

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

### -IncludeHooks

Include hooks alongside options.

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

### -IncludeInherited

Include values inherited from a parent scope.

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

The tmux option name, optionally indexed. tmux expands formats in option names; this is not a literal wildcard selector. Whitespace-only names and NUL are rejected.

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

### -Pane

The native pane whose table is used.

```yaml
Type: LibTmux.Pane
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Pane
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Quiet

Pass tmux its quiet flag. Missing reads emit no objects; suppressed writes may return an absent value with PassThru.

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

### -Scope

Override the owner scope with Server, Session, Window or Pane. Omission uses the native owner scope.

```yaml
Type: LibTmux.OptionScope
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

### -Window

The native window whose table is used.

```yaml
Type: LibTmux.Window
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Window
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

### LibTmux.Window

A native window owner.

### LibTmux.Pane

A native pane owner.

## OUTPUTS

### LibTmux.TmuxOption

One object per option or array entry, in tmux order.

## NOTES

Reads contact tmux explicitly. Empty owner pipelines perform no I/O. Errors retain
the original core exception and native owner as their target. ErrorAction Continue
permits later owners; Stop terminates the pipeline. Cancellation stops the
operation but cannot undo a dispatched mutation. Set readback is an observation,
not a transaction with other clients.

## RELATED LINKS

[Options](../../options.md)
