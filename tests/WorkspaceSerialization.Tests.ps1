param([Parameter(Mandatory)] [string] $ModuleRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1')

function Assert-WorkspaceText([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Workspace serialization: $Message" }
}

function Assert-WorkspaceEquivalent($Expected, $Actual) {
    $before = Microsoft.PowerShell.Utility\ConvertTo-Json -InputObject $Expected -Depth 20 -Compress
    $after = Microsoft.PowerShell.Utility\ConvertTo-Json -InputObject $Actual -Depth 20 -Compress
    Assert-WorkspaceText ($before -ceq $after) 'native declaration properties did not round trip'
}

$declaration = @'
session_name: ''
start_directory: '${ROOT}/work $$ #{}'
before_script: 'printf %s "$HOME"'
options: { '@empty': '', '@null': 'null', '@tilde': '~' }
environment: { EMPTY: '', 'NULL': 'null', BOOL: 'true' }
shell_command_before: ['', 'first', 'second']
windows:
  - window_name: null
    start_directory: null
    layout: even-horizontal
    focus: false
    options: { '@boolean': 'false' }
    environment: { LOCAL: 'window' }
    shell_command_before: ['window before']
    panes:
      - shell_command: ['', 'null', '~', 'true', '01', "line one\nline two", '#{pane_id}']
        start_directory: null
        focus: true
        options: { '@pane': '' }
        environment: { LOCAL: 'pane', EMPTY: '' }
        shell_command_before: ['', 'pane before']
      - null
      - ''
  - window_name: ''
    layout: null
    start_directory: child
    focus: true
    panes: []
'@
$original = [LibTmux.Workspace.WorkspaceFile]::Parse($declaration)
$empty = [LibTmux.Workspace.WorkspaceFile]::new()
$directory = [IO.Directory]::CreateTempSubdirectory('libtmux-workspace-text-')
$oldPath = $env:PATH
try {
    $env:PATH = $directory.FullName
    foreach ($format in @('Yaml', 'Json')) {
        $command = "LibTmux.Workspace\ConvertTo-TmuxWorkspace$format"
        $outputs = @(@($original, $empty) | & $command)
        Assert-WorkspaceText ($outputs.Count -eq 2 -and $outputs[0] -is [string] -and $outputs[1] -is [string]) 'conversion did not emit one string per native declaration'
        $restored = [LibTmux.Workspace.WorkspaceFile]::Parse($outputs[0])
        Assert-WorkspaceEquivalent $original $restored
        Assert-WorkspaceEquivalent $empty ([LibTmux.Workspace.WorkspaceFile]::Parse($outputs[1]))
        Assert-WorkspaceText ($outputs[0] -notmatch 'DocumentDirectory|DirectoriesAreResolved|!!') 'output exposed CLR metadata or type tags'
        Assert-WorkspaceText ($restored.StartDirectory -ceq '${ROOT}/work $$ #{}') 'unresolved path expressions were rewritten'

        $resolved = $original | LibTmux.Workspace\Resolve-TmuxWorkspace -BaseDirectory $directory.FullName -Variables @{ ROOT = $directory.FullName }
        $text = $resolved | & $command
        $imported = LibTmux.Workspace\Import-TmuxWorkspace -Yaml $text
        Assert-WorkspaceText ($null -eq $imported.DocumentDirectory) 'resolution provenance was serialized as declaration data'
        $again = $imported | LibTmux.Workspace\Resolve-TmuxWorkspace -BaseDirectory $directory.FullName
        Assert-WorkspaceEquivalent $resolved $again
        Assert-WorkspaceText ($again.Windows[0].Panes[0].StartDirectory.EndsWith('work $ #{}', [StringComparison]::Ordinal)) 'resolved literal dollar, space or tmux format path changed'
        Assert-WorkspaceText ($again.BeforeScript -ceq $original.BeforeScript) 'host command text was expanded or rewritten'
    }
    Assert-WorkspaceText ($directory.GetFileSystemInfos().Count -eq 0) 'pure conversion wrote a file or executed a host command'
} finally {
    $env:PATH = $oldPath
    $directory.Delete($true)
}
'PASS workspace serialization: native values, defaults, order, nulls and resolved-path semantics'
