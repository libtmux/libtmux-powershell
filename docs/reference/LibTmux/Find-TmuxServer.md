---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Find-TmuxServer.md
Locale: en-US
Module Name: LibTmux
ms.date: 10/10/2026
PlatyPS schema version: 2024-05-01
title: Find-TmuxServer
---

# Find-TmuxServer

## SYNOPSIS

Discover responsive tmux sockets within explicit roots and bounds.

## SYNTAX

### __AllParameterSets

```text
Find-TmuxServer [[-Root] <string[]>] [-NoConfiguredRoots] [-Connection <ServerConnectionOptions>] [-MaximumRoots <int>] [-MaximumEntries <int>] [-MaximumProbes <int>] [-TimeoutMilliseconds <int>] [-ProbeTimeoutMilliseconds <int>]
```

## ALIASES

None.

## DESCRIPTION

Inspect immediate children of the supplied roots and, unless NoConfiguredRoots is present, the current user's captured configured socket directories. The core skips symlink roots and entries, probes sockets owned by the current user, and uses no-start probes. Read Servers, Diagnostics, Truncated, EntriesVisited and ProbesAttempted on the single result. Discovery is a bounded search, not a complete machine inventory. Filesystem calls may outlast the deadline; later work stops at the next boundary.

## EXAMPLES

### Example 1

Search the configured roots with at most 32 socket probes and a two-second total deadline. Read the result's diagnostics and truncation flag as well as its servers.

```powershell
Import-Module LibTmux
Find-TmuxServer -MaximumProbes 32 -TimeoutMilliseconds 2000
```

## PARAMETERS

### -Connection

Native ServerConnectionOptions for probe executable and copied child environment. Defaults use the ordinary captured endpoint rules.

```yaml
Type: LibTmux.ServerConnectionOptions
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

### -MaximumEntries

Maximum directory entries visited across roots. The default is 256.

```yaml
Type: System.Int32
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

### -MaximumProbes

Maximum socket probes. The default is 64.

```yaml
Type: System.Int32
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

### -MaximumRoots

Maximum root inputs, including duplicates. The default is 16.

```yaml
Type: System.Int32
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

### -NoConfiguredRoots

Search only Root entries; omit the configured and selected socket directories.

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

### -ProbeTimeoutMilliseconds

Deadline for one socket probe in milliseconds. The default is 250.

```yaml
Type: System.Int32
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

### -Root

Additional absolute directories whose immediate children are socket candidates. Omit for configured roots. Discovery does not recurse.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TimeoutMilliseconds

Total discovery deadline in milliseconds. The default is 5000.

```yaml
Type: System.Int32
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

### CommonParameters

This cmdlet supports the standard PowerShell common parameters, including ErrorAction and ErrorVariable.

## INPUTS

### None

Supply the named discovery settings.

## OUTPUTS

### LibTmux.ServerDiscoveryResult

The result described above.

## NOTES

## RELATED LINKS

[Ownership and cleanup](../../lifecycle.md)
