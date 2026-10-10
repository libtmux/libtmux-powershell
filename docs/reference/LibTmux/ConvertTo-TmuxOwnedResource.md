---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/ConvertTo-TmuxOwnedResource.md
Locale: en-US
Module Name: LibTmux
ms.date: 10/10/2026
PlatyPS schema version: 2024-05-01
title: ConvertTo-TmuxOwnedResource
---

# ConvertTo-TmuxOwnedResource

## SYNOPSIS

Accept destruction responsibility for an existing tmux object.

## SYNTAX

### __AllParameterSets

```text
ConvertTo-TmuxOwnedResource [-InputObject] <Object> [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Supply a native Server, Session, Window or Pane. The returned owner captures the endpoint, daemon generation, reserved ownership token and object ID. Dispose it with Close-TmuxScope or Invoke-TmuxScope. Session cleanup destroys its windows and panes. Window cleanup destroys all links to that window and its panes. Pane cleanup follows its ID after a move. Server cleanup destroys the accepted daemon and waits for its process to exit. Give whole-server adoption a disposable endpoint.

## EXAMPLES

### Example 1

Create a session on the normal endpoint, accept ownership, then destroy it. The returned owner retains its captured session handle after disposal.

```powershell
Import-Module LibTmux
$name = 'adopt-' + [Guid]::NewGuid().ToString('N')
$session = New-TmuxServer | New-TmuxSession -Name $name
$owner = $session | ConvertTo-TmuxOwnedResource
$owner | Close-TmuxScope
$owner
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

Borrowed native Server, Session, Window or Pane whose destruction responsibility you accept. An existing lookup alone grants no ownership.

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

### LibTmux.OwnedServerScope

The result described above.

### LibTmux.OwnedSessionScope

The result described above.

### LibTmux.OwnedWindowScope

The result described above.

### LibTmux.OwnedPaneScope

The result described above.

## NOTES

Owned cleanup uses a separate five-second core deadline. Acquisition and cleanup preserve the accepted endpoint, object ID and daemon token. The reserved server option @libtmux_owner_generation contains 32 hexadecimal characters; callers must not shadow or change it. A failed cleanup keeps its owner available for another Close-TmuxScope attempt.

## RELATED LINKS

[Ownership and cleanup](../../lifecycle.md)
