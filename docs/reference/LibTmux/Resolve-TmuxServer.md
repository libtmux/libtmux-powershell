---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Resolve-TmuxServer.md
Locale: en-US
Module Name: LibTmux
ms.date: 10/10/2026
PlatyPS schema version: 2024-05-01
title: Resolve-TmuxServer
---

# Resolve-TmuxServer

## SYNOPSIS

Find a daemon at the captured endpoint or create and own one.

## SYNTAX

### __AllParameterSets

```text
Resolve-TmuxServer [-Server] <Server> [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Return FoundOrCreated<Server> with Value, Created and Owner. Existing daemons remain borrowed; a new daemon carries an owner that destroys it on close. The core proves startup using a per-call nonce before claiming ownership. Created daemons stay alive without sessions until their owner closes. This cmdlet preserves captured endpoint and child-environment defaults.

## EXAMPLES

### Example 1

Resolve the normal endpoint and close the result. A daemon already running remains alive. A daemon created by this call is destroyed; the result still describes which case occurred.

```powershell
Import-Module LibTmux
$result = New-TmuxServer | Resolve-TmuxServer
$result | Close-TmuxScope
$result
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

The captured server endpoint to search. The cmdlet accepts a native Server through the pipeline.

```yaml
Type: LibTmux.Server
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

### LibTmux.FoundOrCreated`1[[LibTmux.Server, LibTmux, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null]]

The result described above.

## NOTES

Library find-or-create calls serialize within this process for the captured socket path spelling. Other clients can change resources; window names and pane identities require application coordination across processes. Reused results grant no destruction responsibility.

Owned cleanup uses a separate five-second core deadline. Acquisition and cleanup preserve the accepted endpoint, object ID and daemon token. The reserved server option @libtmux_owner_generation contains 32 hexadecimal characters; callers must not shadow or change it. A failed cleanup keeps its owner available for another Close-TmuxScope attempt.

## RELATED LINKS

[Ownership and cleanup](../../lifecycle.md)
