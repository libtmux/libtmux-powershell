---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/New-TmuxServer.md
Locale: en-US
Module Name: LibTmux
ms.date: 10/09/2026
PlatyPS schema version: 2024-05-01
title: New-TmuxServer
---

# New-TmuxServer

## SYNOPSIS

Construct a tmux endpoint handle without contacting it.

## SYNTAX

### Name (Default)

```text
New-TmuxServer [-SocketName <string>] [-TmuxBinaryPath <string>] [-ConfigurationFile <string>] [-ChildEnvironment <IDictionary>] [-Owned] [-WhatIf] [-Confirm]
```

### Path

```text
New-TmuxServer -SocketPath <string> [-TmuxBinaryPath <string>] [-ConfigurationFile <string>] [-ChildEnvironment <IDictionary>] [-Owned] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

With Owned, return OwnedServerScope and accept destruction responsibility for the new server. Invoke-TmuxScope and Close-TmuxScope run cleanup through the captured identity. Without Owned, the existing behavior below applies.

Construct a borrowed handle without starting or owning a daemon. A later command reads data or changes tmux. The constructor captures the endpoint, effective child environment and executable lookup for later commands and cleanup.

Select an endpoint with this precedence: an explicit SocketPath or SocketName, nonempty LIBTMUX_SOCKET_PATH, nonempty LIBTMUX_SOCKET_NAME, nonempty TMUX, then tmux's named default. ChildEnvironment overrides the host values for this selection. Empty selector variables count as absent. An invalid selected value raises an argument error; ignored lower-precedence values do not affect the choice.

Use an absolute SocketPath or a nonempty leaf SocketName. Names cannot contain path separators or be '.' or '..'. A selected TMUX value must contain an absolute socket path, positive decimal PID and nonnegative decimal session ID (with an optional '$') or '-1', separated by its last two commas. Commas in the path remain part of the path.

Named endpoints use the captured TMUX_TMPDIR or /tmp and the current user's tmux directory. The root must exist and be absolute. Commands create the per-user directory with mode 0700 when needed; they reject missing roots and unsafe existing directories without falling back to another socket. Explicit socket paths require an existing parent directory.

Later host-environment changes cannot redirect the handle. Launched clients omit TMUX and TMUX_PANE. Creating or looking up a handle grants no responsibility for destroying remote resources.

## EXAMPLES

### Example 1

Construct a handle for the existing socket identified by $SocketPath.

```powershell
LibTmux\New-TmuxServer -SocketPath $SocketPath
```

## PARAMETERS

### -Owned

Return the native owner of the created server. Close it with Close-TmuxScope or run its body with Invoke-TmuxScope. Server creation fails if a daemon already owns the endpoint; use a disposable endpoint for whole-server ownership.

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

### -ChildEnvironment

A copied dictionary of child-process environment overrides. Names and non-null values must be strings; null removes an inherited variable. The handle snapshots the effective environment at construction, including PATH for executable lookup. These overrides leave the PowerShell host and tmux server/session environment tables unchanged. Use Set-TmuxEnvironment to change a tmux environment table.

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

### -ConfigurationFile

The configuration used if a later operation starts tmux.

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

### -SocketName

The tmux socket leaf name. An explicit name takes precedence over environment selectors. Supply either SocketName or SocketPath.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Name
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SocketPath

The absolute socket path. Preserve spaces and commas as part of the path. An explicit path takes precedence over environment selectors. Supply either SocketPath or SocketName.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Path
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TmuxBinaryPath

The tmux executable used by subsequent operations.

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

Describe the operation without discovery, ownership acquisition or remote mutation.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### LibTmux.OwnedServerScope

Returned with Owned; disposal destroys the created resource.

### LibTmux.Server

Native pipeline type for this command.

## NOTES

The returned LibTmux.Server is unmaterialized. TmuxBinaryPath and ConfigurationFile affect subsequent operations; construction does not execute them.

## RELATED LINKS

[Task guide](../../read.md)
