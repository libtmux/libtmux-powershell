---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/New-TmuxWindow.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: New-TmuxWindow
---

# New-TmuxWindow

## SYNOPSIS

Create a window in an explicit session.

## SYNTAX

### __AllParameterSets

```text
New-TmuxWindow [-Session] <Session> [-Name <string>] [-Index <int>] [-StartDirectory <string>]
 [-Command <string>] [-Environment <IDictionary>] [-Activate] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Create a window and its initial pane, then return the captured native
LibTmux.Window. Supply a native Session directly or through the pipeline. The
new window remains unselected unless Activate is present. The existing session
object is not refreshed in place.

## EXAMPLES

### Example 1

Create a named window at an unused index in the first session on the server
identified by $SocketPath. This example requires /bin/sh and leaves the new
window running for later work.

```powershell
LibTmux\New-TmuxServer -SocketPath $SocketPath |
    LibTmux\Get-TmuxSession | Select-Object -First 1 |
    LibTmux\New-TmuxWindow -Name 'help-window' -Index 5 -Command 'exec /bin/sh'
```

## PARAMETERS

### -Activate

Select the new window in its session. By default the current selection is
preserved. This switch does not attach the PowerShell process to a tmux
terminal.

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

### -Command

One shell-command string for the new pane. tmux interprets shell syntax in this
string; it is not an argument array. Omit it to use the configured default
command or shell.

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

### -Environment

A dictionary with string names and string values. Names must be nonempty and
contain neither '=' nor NUL (U+0000). Values may be empty but must not contain
NUL. Null or non-string entries are rejected before confirmation or dispatch.
Entries are copied for this invocation and do not change the PowerShell host
environment.

```yaml
Type: System.Collections.IDictionary
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

### -Index

Unused session-relative window index, at least 0. Omit it to let tmux choose an
available index. An occupied index remains an error.

```yaml
Type: System.Nullable`1[System.Int32]
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

Window name. Omit it to retain tmux's default naming behavior. tmux's format
expansion rules apply.

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

### -Session

Native session that owns the new window. This is the only pipeline-bound
parameter; binding by an object's Session property is not supported.

```yaml
Type: LibTmux.Session
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

### -StartDirectory

Working directory for the new pane. Use an absolute filesystem path for
predictable behavior. The core expands ~ and ~/; this cmdlet does not resolve
PowerShell provider paths or change the host's current directory.

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

### LibTmux.Session

Native pipeline type for this command.

## OUTPUTS

### LibTmux.Window

Captured native object for the created resource.

## NOTES

WhatIf performs no core discovery or dispatch and returns no created object.
Confirmation precedes the core operation. The caller remains responsible for
created resources. Cancellation does not prove that creation was rolled back; no
mutation is retried. Per-owner errors use Tmux.WindowCreateFailed and retain the
core exception and failed session. ErrorAction Continue allows later owners to
run.

## RELATED LINKS

[Task guide](../../create.md)
