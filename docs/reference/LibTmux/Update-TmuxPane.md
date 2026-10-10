---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Update-TmuxPane.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Update-TmuxPane
---

# Update-TmuxPane

## SYNOPSIS

Refresh a pane into a replacement captured object.

## SYNTAX

### __AllParameterSets

```text
Update-TmuxPane [-Pane] <Pane>
```

## ALIASES

None.

## DESCRIPTION

Acquire current pane data through the native core handle. Return a new Pane and leave the original capture unchanged. This is an explicit read operation, so it does not require mutation confirmation.

## EXAMPLES

### Example 1

Refresh the first pane on the existing server identified by $SocketPath.

```powershell
LibTmux\New-TmuxServer -SocketPath $SocketPath |
    LibTmux\Get-TmuxPane |
    Select-Object -First 1 |
    LibTmux\Update-TmuxPane
```

## PARAMETERS

### -Pane

The pane whose current state is read.

```yaml
Type: LibTmux.Pane
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

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Pane

Native pipeline type for this command.

## OUTPUTS

### LibTmux.Pane

Native pipeline type for this command.

## NOTES

The owning endpoint and server generation remain part of the handle. A disappeared pane or stale generation writes a per-target error; use -ErrorAction Stop to terminate.

## RELATED LINKS

[Task guide](../../capture.md)
