---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxHook.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxHook
---

# Get-TmuxHook

## SYNOPSIS

Read native grouped hooks from an owner table.

## SYNTAX

### Server (Default)

```text
Get-TmuxHook [-Server] <Server> [-Name <String>] [-Scope <OptionScope>] [-Global]
```

### Session

```text
Get-TmuxHook [-Session] <Session> [-Name <String>] [-Scope <OptionScope>] [-Global]
```

### Window

```text
Get-TmuxHook [-Window] <Window> [-Name <String>] [-Scope <OptionScope>] [-Global]
```

### Pane

```text
Get-TmuxHook [-Pane] <Pane> [-Name <String>] [-Scope <OptionScope>] [-Global]
```

## ALIASES

None.

## DESCRIPTION

Emit native TmuxHook objects with a base Name and indexed Values entries. Get by
base name only; indexed names are rejected with a clear error rather than silently
returning no matches. Missing local hooks emit no objects and are not filled from
the global table. Omit Name to list the selected scope.

## EXAMPLES

### Example 1

Inspect a previously configured hook on a native $session.

```powershell
$session | LibTmux\Get-TmuxHook -Name 'alert-bell'
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

### -Name

The base hook name. Indexed reads are rejected before I/O; inspect Values for indexed entries. Omit Name to list the selected table.

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

### LibTmux.TmuxHook

One native grouped hook per result, with indexed TmuxHookEntry values.

## NOTES

Server hooks are the global hook table; tmux has no separate server hook table.
Choose a hook supported by the selected scope. Scope and Global pass through to
tmux without remapping the owner. Empty pipelines do no I/O. Errors retain the
native owner and core exception; Continue permits later owners and Stop terminates.
Cancellation cannot undo commands already dispatched. Multiple mutations are
sequential, not an atomic replacement.

## RELATED LINKS

[Hooks](../../hooks.md)
