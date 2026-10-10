---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Invoke-TmuxScope.md
Locale: en-US
Module Name: LibTmux
ms.date: 10/10/2026
PlatyPS schema version: 2024-05-01
title: Invoke-TmuxScope
---

# Invoke-TmuxScope

## SYNOPSIS

Run a script block and clean up its owned tmux resource.

## SYNTAX

### __AllParameterSets

```text
Invoke-TmuxScope [-Body] <scriptblock> -InputObject <Object>
```

## ALIASES

None.

## DESCRIPTION

Pass an owner from an Owned creation, ConvertTo-TmuxOwnedResource or a Resolve-Tmux command. The Body receives its borrowed Value as the first argument. The cmdlet disposes the owner after normal return, a terminating body error or a stopped pipeline. It buffers success output until cleanup succeeds. Nonterminating PowerShell errors retain normal ErrorAction behavior; use ErrorAction Stop when they should stop the body.

## EXAMPLES

### Example 1

Create a session with normal tmux defaults, return its captured initial window, and destroy the session before emitting that window.

```powershell
Import-Module LibTmux
$name = 'example-' + [Guid]::NewGuid().ToString('N')
New-TmuxServer | New-TmuxSession -Name $name -Owned |
    Invoke-TmuxScope {
        param($session)
        $session | Get-TmuxWindow
    }
```

## PARAMETERS

### -Body

The script block to run in a local scope. Declare param($resource) to receive the borrowed Value. Cleanup runs after body cancellation with its own core deadline.

```yaml
Type: System.Management.Automation.ScriptBlock
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
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
  Position: Named
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

### System.Object

The native pipeline input.

## OUTPUTS

### System.Object

The result described above.

## NOTES

Owned cleanup uses a separate five-second core deadline. Acquisition and cleanup preserve the accepted endpoint, object ID and daemon token. The reserved server option @libtmux_owner_generation contains 32 hexadecimal characters; callers must not shadow or change it. A failed cleanup keeps its owner available for another Close-TmuxScope attempt.

If body and cleanup both fail, the original PowerShell body exception retains the cleanup exception. Inspect [LibTmux.OwnedScope]::CleanupFailure($error) and $error.Data['LibTmux.PowerShell.Owner']; PowerShell may wrap the exception, so inspect InnerException as needed. A stopped pipeline can replace it; retain the owner and read Get-TmuxScopeFailure for BodyFailure, CleanupFailure and retry authority. Failed cleanup emits no buffered success output. Abrupt process death requires an outer process supervisor.

## RELATED LINKS

[Ownership and cleanup](../../lifecycle.md)
