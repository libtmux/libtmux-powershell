---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxScopeFailure.md
Locale: en-US
Module Name: LibTmux
ms.date: 10/10/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxScopeFailure
---

# Get-TmuxScopeFailure

## SYNOPSIS

Inspect the latest failed cleanup retained on an owned scope.

## SYNTAX

### Owner (Default)

```text
Get-TmuxScopeFailure [-InputObject] <Object>
```

### Pending

```text
Get-TmuxScopeFailure -Pending
```

## ALIASES

None.

## DESCRIPTION

Return the latest TmuxScopeFailure from a failed cmdlet cleanup on the supplied owner. Use -Pending to list unresolved cleanup failures across runspaces in this PowerShell process, including core acquisition rollback failures and failed output handoffs that did not reach a caller variable. The record contains BodyFailure, CleanupFailure and the same Owner for retry. It remains available after a successful retry. No result means that these cmdlets have not recorded a cleanup failure on this owner. This diagnostic survives PowerShell replacing its pipeline cancellation exception.

## EXAMPLES

### Example 1

Create and close a session, then inspect the owner. A successful close has no failure record, so this example produces no output.

```powershell
Import-Module LibTmux
$name = 'inspect-' + [Guid]::NewGuid().ToString('N')
$owner = New-TmuxServer | New-TmuxSession -Name $name -Owned
$owner | Close-TmuxScope
$owner | Get-TmuxScopeFailure
```

## PARAMETERS

### -InputObject

The native owned resource or created-versus-reused result. Pipeline binding uses the object itself, not a property.

```yaml
Type: System.Object
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Owner
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Pending

List unresolved cmdlet cleanup failures across runspaces in this process. A successful cmdlet cleanup removes its pending entry. Each entry retains its owner so a canceled handoff cannot discard retry authority.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Pending
  Position: Named
  IsRequired: true
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

### LibTmux.PowerShell.TmuxScopeFailure

The original body error, cleanup error and retry owner from the latest failed cmdlet cleanup.

## NOTES

Pending records keep their owners reachable until a cmdlet cleanup succeeds. The per-owner history uses a weak table and remains readable after that retry while the caller retains the owner. Calling the core DisposeAsync method outside these cmdlets does not populate or retire PowerShell records. Use Close-TmuxScope to retry, ErrorAction and ErrorVariable for normal pipeline errors, and -Pending to recover an owner lost during canceled output handoff. Process termination loses these in-memory records; an external harness must own cleanup after a worker crash. Acquisition can fail before a cmdlet receives an owner. If the core accepted cleanup authority and rollback fails, the cmdlet registers each owner from OwnedScope.CleanupOwners before PowerShell replaces the error. Close-TmuxScope accepts those registered owners, including raw creation receipts that expose only IAsyncDisposable. Unknown creation effects without accepted authority have no pending owner.

## RELATED LINKS

[Ownership and cleanup](../../lifecycle.md)
