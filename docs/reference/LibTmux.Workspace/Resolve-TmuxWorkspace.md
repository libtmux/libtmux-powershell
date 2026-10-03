---
document type: cmdlet
external help file: LibTmux.Workspace.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux.Workspace/Resolve-TmuxWorkspace.md
Locale: en-US
Module Name: LibTmux.Workspace
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Resolve-TmuxWorkspace
---

# Resolve-TmuxWorkspace

## SYNOPSIS

Resolve inherited workspace paths against an explicit document base.

## SYNTAX

### Workspace (Default)

```text
Resolve-TmuxWorkspace [-Workspace] <WorkspaceFile> -BaseDirectory <String> [-Variables <IDictionary>]
```

### Path

```text
Resolve-TmuxWorkspace -LiteralPath <String> [-Variables <IDictionary>]
```

### File

```text
Resolve-TmuxWorkspace -File <FileInfo> [-Variables <IDictionary>]
```

## ALIASES

None.

## DESCRIPTION

Return a replacement native declaration with resolved inherited directories
and option values.
A parsed WorkspaceFile requires an explicit BaseDirectory. LiteralPath and
File read a bounded, seekable UTF-8 YAML/JSON file and use its absolute parent
as the base. Paths use the FileSystem provider without wildcard expansion.
Malformed declarations and invalid UTF-8 retain their native exceptions as
InvalidData errors.

Expansion uses only the supplied case-sensitive string map. Supply HOME for
home-directory expansion in paths; no process environment is copied implicitly.
Dollar pairs represent a literal dollar sign in declaration paths and option
values. Session, window and pane option values expand supplied variables;
unknown variables in option values remain literal. Unresolved path variables
are errors. Option names, command text, the host script, session and window
names, and environment values remain literal. Resolution does not execute
scripts, inspect tmux or require the resulting directories to exist. The input
declaration remains unchanged.

## EXAMPLES

### Example 1

Resolve a parsed declaration against the current filesystem directory. Pass a
different explicit BaseDirectory when the declaration came from elsewhere.

```powershell
LibTmux.Workspace\Import-TmuxWorkspace -Yaml '{session_name: development, start_directory: "${PROJECT}", windows: [{panes: [null]}]}' | LibTmux.Workspace\Resolve-TmuxWorkspace -BaseDirectory (Get-Location).Path -Variables @{ PROJECT = 'src' }
```

## PARAMETERS

### -Workspace

The parsed declaration to resolve without reading a file.

```yaml
Type: LibTmux.Workspace.WorkspaceFile
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Workspace
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -BaseDirectory

The explicit filesystem base for a parsed declaration. Relative bases resolve against the current PowerShell location.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Workspace
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -LiteralPath

The literal declaration path. The file parent becomes its document base.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Path
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -File

A FileInfo whose parent becomes the document base.

```yaml
Type: System.IO.FileInfo
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: File
  Position: Named
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Variables

Allowed string expansion variables. Values requiring conversion are rejected.

```yaml
Type: System.Collections.IDictionary
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

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Workspace.WorkspaceFile

A declaration used with BaseDirectory.

### System.IO.FileInfo

A declaration file to read and resolve.

## OUTPUTS

### LibTmux.Workspace.WorkspaceFile

The replacement declaration with document-directory provenance.

## NOTES

Invalid variable maps terminate with Tmux.InvalidWorkspaceVariables before
processing input. File and resolution failures retain their native exception
under Tmux.WorkspaceResolutionFailed; ErrorAction Continue permits later input.

## RELATED LINKS

[Import-TmuxWorkspace](Import-TmuxWorkspace.md)

[Test-TmuxWorkspace](Test-TmuxWorkspace.md)

[Get-TmuxWorkspacePlan](Get-TmuxWorkspacePlan.md)
