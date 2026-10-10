---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Start-TmuxServer.md
Locale: en-US
Module Name: LibTmux
ms.date: 10/10/2026
PlatyPS schema version: 2024-05-01
title: Start-TmuxServer
---

# Start-TmuxServer

## SYNOPSIS

Start a missing daemon or return the existing server.

## SYNTAX

### __AllParameterSets

```text
Start-TmuxServer [[-Server] <Server>] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Return an ordinary LibTmux.Server at the selected endpoint. With no Server argument, capture the same environment defaults as New-TmuxServer. Pipe a New-TmuxServer handle to select explicit socket, configuration or child-environment options.

Reusing a daemon preserves its sessions, windows, panes and configuration. Starting a daemon reads the selected tmux configuration, creates a temporary session, sets exit-empty to off, then removes the temporary session. The returned daemon stays available without a bootstrap session. Any resources created by your tmux configuration remain.

A successful call leaves the daemon running without requiring a cleanup owner. After the shared core returns its acquisition result, the cmdlet retains it until output handoff completes. If cancellation or a downstream pipeline error prevents handoff, the cmdlet attempts to destroy only a daemon started by this call. A reused daemon remains alive. Failed handoff cleanup retains a retry owner through Get-TmuxScopeFailure.

The current core has a recovery gap before it returns an acquisition result. If startup and its rollback both fail, the exception retains both errors but exposes no retry owner. The daemon can remain alive. The external test supervisor handles final cleanup for this case; the public API needs a shared-core repair.

## EXAMPLES

### Example 1

Return a usable server at the normal endpoint. The same code works with or without a running daemon.

```powershell
Import-Module LibTmux
Start-TmuxServer
```

## PARAMETERS

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

### -Server

The captured endpoint to make available. Omit this parameter for normal environment defaults, or pipe a native Server constructed with New-TmuxServer.

```yaml
Type: LibTmux.Server
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: true
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

### CommonParameters

This cmdlet supports the standard PowerShell common parameters, including ErrorAction and ErrorVariable.

## INPUTS

### LibTmux.Server

The native pipeline input.

## OUTPUTS

### LibTmux.Server

The result described above.

## NOTES

Calls serialize within this process for the captured socket path spelling. Other clients can change resources after selection. New-TmuxServer still constructs a handle without contacting tmux; Connect-TmuxServer still requires an existing daemon. Resolve-TmuxServer returns the separate created-or-reused ownership result.

Endpoint precedence is explicit arguments captured by New-TmuxServer, nonempty LIBTMUX_SOCKET_PATH, nonempty LIBTMUX_SOCKET_NAME, selected TMUX context, then tmux's named default. TMUX_TMPDIR controls the named socket root. Later host environment changes do not redirect a captured handle.

## RELATED LINKS

[Ownership and cleanup](../../lifecycle.md)
