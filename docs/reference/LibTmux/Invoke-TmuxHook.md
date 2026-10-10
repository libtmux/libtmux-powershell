---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Invoke-TmuxHook.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Invoke-TmuxHook
---

# Invoke-TmuxHook

## SYNOPSIS

Run a configured tmux hook now.

## SYNTAX

### Server (Default)

```text
Invoke-TmuxHook [-Server] <Server> -Name <String> [-Scope <OptionScope>] [-Global] [-WhatIf] [-Confirm]
```

### Session

```text
Invoke-TmuxHook [-Session] <Session> -Name <String> [-Scope <OptionScope>] [-Global] [-WhatIf] [-Confirm]
```

### Window

```text
Invoke-TmuxHook [-Window] <Window> -Name <String> [-Scope <OptionScope>] [-Global] [-WhatIf] [-Confirm]
```

### Pane

```text
Invoke-TmuxHook [-Pane] <Pane> -Name <String> [-Scope <OptionScope>] [-Global] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Ask tmux to run the selected hook without waiting for its event. The command emits
no success output. Completion confirms tmux accepted the request; asynchronous
work launched by a hook may still be running. Use an explicit producer signal
and Wait-TmuxChannel when application completion matters. WhatIf performs no I/O.

## EXAMPLES

### Example 1

Run a previously configured hook on a native $session.

```powershell
$session | LibTmux\Invoke-TmuxHook -Name 'alert-bell'
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

### -Name

The tmux hook name, optionally indexed for a specific entry. tmux expands formats in names.

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

### None

No success output.

## NOTES

Server hooks are the global hook table; tmux has no separate server hook table.
Choose a hook supported by the selected scope. Scope and Global pass through to
tmux without remapping the owner. Empty pipelines do no I/O. Errors retain the
native owner and core exception; Continue permits later owners and Stop terminates.
Cancellation cannot undo commands already dispatched. Multiple mutations are
sequential, not an atomic replacement.

## RELATED LINKS

[Hooks](../../hooks.md)
