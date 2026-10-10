---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Resolve-TmuxWindow.md
Locale: en-US
Module Name: LibTmux
ms.date: 10/10/2026
PlatyPS schema version: 2024-05-01
title: Resolve-TmuxWindow
---

# Resolve-TmuxWindow

## SYNOPSIS

Find one exact window name in a session or create and own it.

## SYNTAX

### __AllParameterSets

```text
Resolve-TmuxWindow [-Session] <Session> [-Name] <string> [-Request <NewWindowRequest>] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Match a literal name within the supplied Session. Multiple matching windows raise TmuxAmbiguousMatchException. Return Value, Created and nullable Owner. Request supplies native creation options, but replacement and select-existing behavior are refused. Closing a created result destroys that window and its links; closing a reused result leaves it alive.

## EXAMPLES

### Example 1

Create a scoped session, resolve its editor window and close both created resources. The returned result contains the captured window.

```powershell
Import-Module LibTmux
$name = 'windows-' + [Guid]::NewGuid().ToString('N')
New-TmuxServer | New-TmuxSession -Name $name -Owned |
    Invoke-TmuxScope {
        param($session)
        $result = $session | Resolve-TmuxWindow -Name 'editor'
        $result | Close-TmuxScope
        $result
    }
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
Type: LibTmux.NewWindowRequest
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

The native parent session to search. The cmdlet accepts it through the pipeline.

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

### LibTmux.Session

The native pipeline input.

## OUTPUTS

### LibTmux.FoundOrCreated`1[[LibTmux.Window, LibTmux, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null]]

The result described above.

## NOTES

Library find-or-create calls serialize within this process for the captured socket path spelling. Other clients can change resources; window names and pane identities require application coordination across processes. Reused results grant no destruction responsibility.

Owned cleanup uses a separate five-second core deadline. Acquisition and cleanup preserve the accepted endpoint, object ID and daemon token. The reserved server option @libtmux_owner_generation contains 32 hexadecimal characters; callers must not shadow or change it. A failed cleanup keeps its owner available for another Close-TmuxScope attempt.

## RELATED LINKS

[Ownership and cleanup](../../lifecycle.md)
