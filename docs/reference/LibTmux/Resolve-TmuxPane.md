---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Resolve-TmuxPane.md
Locale: en-US
Module Name: LibTmux
ms.date: 10/10/2026
PlatyPS schema version: 2024-05-01
title: Resolve-TmuxPane
---

# Resolve-TmuxPane

## SYNOPSIS

Find an application pane identity or split and own a pane.

## SYNTAX

### __AllParameterSets

```text
Resolve-TmuxPane [-Window] <Window> [-Identity] <string> [-Request <SplitPaneRequest>] [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Match the exact local pane option @libtmux-identity within the supplied Window. Titles and commands do not determine identity. Multiple matches raise TmuxAmbiguousMatchException. If no match exists, split the active pane, set the identity and return its owner. Request may configure the split but cannot supply a different target or parent window. Closing a created result destroys its pane; closing a reused result leaves it alive.

## EXAMPLES

### Example 1

Create a scoped session and resolve an editor pane by application identity. Closing the created result removes that pane, and scope exit removes the session.

```powershell
Import-Module LibTmux
$name = 'panes-' + [Guid]::NewGuid().ToString('N')
New-TmuxServer | New-TmuxSession -Name $name -Owned |
    Invoke-TmuxScope {
        param($session)
        $window = $session | Get-TmuxWindow | Select-Object -First 1
        $result = $window | Resolve-TmuxPane -Identity 'editor'
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

### -Identity

Nonempty application identity to compare against the local pane option @libtmux-identity.

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
Type: LibTmux.SplitPaneRequest
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

### -Window

The native parent window to search. The cmdlet accepts it through the pipeline.

```yaml
Type: LibTmux.Window
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

### CommonParameters

This cmdlet supports the standard PowerShell common parameters, including ErrorAction and ErrorVariable.

## INPUTS

### LibTmux.Window

The native pipeline input.

## OUTPUTS

### LibTmux.FoundOrCreated`1[[LibTmux.Pane, LibTmux, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null]]

The result described above.

## NOTES

Library find-or-create calls serialize within this process for the captured socket path spelling. Other clients can change resources; window names and pane identities require application coordination across processes. Reused results grant no destruction responsibility.

Owned cleanup uses a separate five-second core deadline. Acquisition and cleanup preserve the accepted endpoint, object ID and daemon token. The reserved server option @libtmux_owner_generation contains 32 hexadecimal characters; callers must not shadow or change it. A failed cleanup keeps its owner available for another Close-TmuxScope attempt.

## RELATED LINKS

[Ownership and cleanup](../../lifecycle.md)
