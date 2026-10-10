---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Resolve-TmuxSession.md
Locale: en-US
Module Name: LibTmux
ms.date: 10/10/2026
PlatyPS schema version: 2024-05-01
title: Resolve-TmuxSession
---

# Resolve-TmuxSession

## SYNOPSIS

Find an exact session name or create and own that session.

## SYNTAX

### __AllParameterSets

```text
Resolve-TmuxSession [-Server] <Server> [-Name] <string> [-Request <NewSessionRequest>] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Match the literal session name in full. A result contains Value, Created and nullable Owner. Existing sessions remain borrowed. A newly created session carries cleanup responsibility. Request supplies native creation options; a conflicting name or ReplaceExisting request fails. If another client wins the same session name, the cmdlet returns the matching session as borrowed.

## EXAMPLES

### Example 1

Resolve a unique name on the normal endpoint, close its result and inspect whether it was created.

```powershell
Import-Module LibTmux
$name = 'resolve-' + [Guid]::NewGuid().ToString('N')
$result = New-TmuxServer | Resolve-TmuxSession -Name $name
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

### -Name

Literal name to match in full. Window names may be duplicated by other clients; ambiguity fails.

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

### -Request

Native creation options used when no match exists. Reused resources retain their current settings.

```yaml
Type: LibTmux.NewSessionRequest
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

### LibTmux.FoundOrCreated`1[[LibTmux.Session, LibTmux, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null]]

The result described above.

## NOTES

Library find-or-create calls serialize within this process for the captured socket path spelling. Other clients can change resources; window names and pane identities require application coordination across processes. Reused results grant no destruction responsibility.

Owned cleanup uses a separate five-second core deadline. Acquisition and cleanup preserve the accepted endpoint, object ID and daemon token. The reserved server option @libtmux_owner_generation contains 32 hexadecimal characters; callers must not shadow or change it. A failed cleanup keeps its owner available for another Close-TmuxScope attempt.

## RELATED LINKS

[Ownership and cleanup](../../lifecycle.md)
