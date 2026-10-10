---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Close-TmuxScope.md
Locale: en-US
Module Name: LibTmux
ms.date: 10/10/2026
PlatyPS schema version: 2024-05-01
title: Close-TmuxScope
---

# Close-TmuxScope

## SYNOPSIS

Dispose an owned tmux resource or a created-versus-reused result.

## SYNTAX

### __AllParameterSets

```text
Close-TmuxScope [-InputObject] <Object> [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

A successful repeated close has no effect. Failed cleanup remains retryable on the same owner. A reused Resolve-Tmux result has no owner, so closing it preserves the borrowed object. Borrowed Server, Session, Window and Pane handles are rejected; use ConvertTo-TmuxOwnedResource to accept destruction responsibility.

## EXAMPLES

### Example 1

Create and own one session, then close its owner twice. Both calls succeed and produce no output.

```powershell
Import-Module LibTmux
$name = 'close-' + [Guid]::NewGuid().ToString('N')
$owner = New-TmuxServer | New-TmuxSession -Name $name -Owned
$owner | Close-TmuxScope
$owner | Close-TmuxScope
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

### -InputObject

The native owned resource or created-versus-reused result. Pipeline binding uses the object itself, not a property.

```yaml
Type: System.Object
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

### System.Object

The native pipeline input.

## OUTPUTS

### System.Void

No success output.

## NOTES

Owned cleanup uses a separate five-second core deadline. Acquisition and cleanup preserve the accepted endpoint, object ID and daemon token. The reserved server option @libtmux_owner_generation contains 32 hexadecimal characters; callers must not shadow or change it. A failed cleanup keeps its owner available for another Close-TmuxScope attempt. The Owner from a Get-TmuxScopeFailure record also supports retry after acquisition failed before returning a normal scope. The cmdlet accepts only that registered recovery owner; an arbitrary disposable object carries no tmux cleanup authority.

## RELATED LINKS

[Ownership and cleanup](../../lifecycle.md)
