---
document type: cmdlet
external help file: LibTmux.Workspace.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux.Workspace/Get-TmuxWorkspace.md
Locale: en-US
Module Name: LibTmux.Workspace
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxWorkspace
---

# Get-TmuxWorkspace

## SYNOPSIS

Find workspace declaration files without loading sessions.

## SYNTAX

### Discover (Default)

```text
Get-TmuxWorkspace [-ConfigurationDirectory <String>] [-AllLocations]
```

### Name

```text
Get-TmuxWorkspace [-Name] <String> [-ConfigurationDirectory <String>] [-AllLocations]
```

### Directory

```text
Get-TmuxWorkspace -Directory <String>
```

### LiteralPath

```text
Get-TmuxWorkspace -LiteralPath <String>
```

### Search

```text
Get-TmuxWorkspace -Search <String> [-SearchIn <String[]>] [-CaseSensitive] [-ConfigurationDirectory <String>] [-AllLocations]
```

## ALIASES

None.

## DESCRIPTION

Return native FileInfo objects for readable, seekable declaration files.
Discovery does not contact tmux, run scripts, resolve declaration variables or
create configuration directories. Pipe a selected file to Import-TmuxWorkspace
for parsing, or Resolve-TmuxWorkspace for explicit file-relative resolution.

With no arguments, list .tmuxp.yaml, .tmuxp.yml and .tmuxp.json in the current
filesystem directory, then each ancestor through HOME when it is an ancestor,
otherwise through the filesystem root. Each directory uses that extension
order. Append files from the first existing global configuration directory:
ConfigurationDirectory, TMUXP_CONFIGDIR, XDG_CONFIG_HOME/tmuxp (or
HOME/.config/tmuxp), then HOME/.tmuxp. HOME falls back to the platform user
profile directory when unset. Missing default locations are skipped; an
explicit missing ConfigurationDirectory is an error. AllLocations includes
all existing global candidates in that order, preserving shadowed files.
Global filenames sort ordinally within each location. Repeated full paths
are emitted once.

Directory checks only the three local .tmuxp filenames in that exact directory.
LiteralPath selects one exact filesystem file and bypasses discovery; it has
no extension restriction. File symlinks retain their literal paths when the
shared opener accepts the target. Directory entries are not files and are
never recursively descended, including directory symlinks.

Name searches only the selected global locations. It is a literal basename,
with an optional .yaml, .yml or .json suffix. Without a supported suffix, those
three suffixes are tried in order. Multiple matches in one location are an
ambiguity error naming the candidates; use LiteralPath to choose. A missing
name emits no objects. Path separators are rejected; wildcard characters are
literal. Filename suffixes are lowercase and literal; path/name identity
follows the filesystem, independently of search case behavior.

Search uses literal ordinal-ignore-case substring matching on filenames by
default. CaseSensitive selects ordinal matching. SearchIn selects FileName,
Session, Window, Command or Directory fields. Any content field
parses every candidate with the shared strict UTF-8 reader, accepting a UTF-8
BOM and at most 1048576 characters. Command includes before_script and all
pane commands and shell_command_before entries; none are executed. Directory
searches declared strings without expansion. Multiple fields combine by OR.
Malformed candidate data fails content search even if its filename matches.

Traversal stops with an error after 1024 examined entries: existing local
marker probes and global directory entries count, including unselected suffixes
and directories. Ancestor traversal also has a 1024-directory ceiling. Narrow
the request with Directory, Name or LiteralPath. Results are published only
after successful discovery/search, so failures do not emit truncated lists.
Filesystem contents can change between discovery and later import; FileInfo
output is not a locked or atomic filesystem snapshot.

## EXAMPLES

### Example 1

Select the existing declaration named by $WorkspacePath, retaining a native
FileInfo that can feed Import-TmuxWorkspace or Resolve-TmuxWorkspace.

```powershell
LibTmux.Workspace\Get-TmuxWorkspace -LiteralPath $WorkspacePath
```

## PARAMETERS

### -LiteralPath

One literal FileSystem path. Other providers and directories are rejected.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: LiteralPath
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Name

A literal global declaration basename, optionally ending in .yaml, .yml or .json.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Name
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Directory

One existing directory whose local .tmuxp declaration filenames are checked.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Directory
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ConfigurationDirectory

The first global directory candidate. An explicitly supplied missing directory is an error.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Discover
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Name
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Search
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -AllLocations

Include every existing global location in precedence order instead of only the first.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: 'False'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Discover
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Name
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Search
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Search

Literal substring text, from 1 through 4096 characters. No regex or wildcard interpretation.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Search
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SearchIn

Fields to search. Any declaration field explicitly opts into bounded parsing of all candidates.

```yaml
Type: System.String[]
DefaultValue: 'FileName'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Search
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: [FileName, Session, Window, Command, Directory]
HelpMessage: ''
```

### -CaseSensitive

Use ordinal case-sensitive substring matching. This does not change path or name identity.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: 'False'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Search
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

### None

No pipeline input.

## OUTPUTS

### System.IO.FileInfo

Declaration files in documented precedence order.

## NOTES

Failures write Tmux.WorkspaceDiscoveryFailed with the request as TargetObject.
File read/parse errors retain the original exception and identify the failing
path in Exception.Data['WorkspacePath']. Use ErrorAction Stop to terminate.
Cancellation is checked between traversal, read and search operations and
before publication. Stopping discovery does not delete files or stop a daemon.

## RELATED LINKS

[Import-TmuxWorkspace](Import-TmuxWorkspace.md)

[Resolve-TmuxWorkspace](Resolve-TmuxWorkspace.md)
