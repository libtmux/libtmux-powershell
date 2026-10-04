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

function Get-PhysicalDirectory([string] $Path) {
    $before = [IO.Directory]::GetCurrentDirectory()
    try {
        [IO.Directory]::SetCurrentDirectory($Path)
        [IO.Directory]::GetCurrentDirectory()
    } finally { [IO.Directory]::SetCurrentDirectory($before) }
}

$declaration = @'
session_name: ''
start_directory: '${ROOT}/work $$ #{}'
before_script: 'printf %s "$HOME"'
options: { '@empty': '', '@null': 'null', '@tilde': '~' }
environment: { EMPTY: '', 'NULL': 'null', BOOL: 'true' }
shell_command_before: ['', { cmd: 'first', enter: false }, 'second']
windows:
  - window_name: null
    window_index: 5
    start_directory: null
    layout: even-horizontal
    focus: false
    options: { '@boolean': 'false' }
    environment: { LOCAL: 'window' }
    shell_command_before: [{ cmd: 'window before', enter: true }]
    panes:
      - shell_command: ['', 'null', '~', 'true', '01', "line one\nline two", '#{pane_id}', { cmd: 'hold', enter: false }, { cmd: 'resume', enter: true }, 'after resume']
        enter: false
        start_directory: null
        focus: true
        options: { '@pane': '' }
        environment: { LOCAL: 'pane', EMPTY: '' }
        shell_command_before: ['', { cmd: 'pane before', enter: false }]
      - null
      - ''
  - window_name: ''
    layout: null
    start_directory: child
    focus: true
    panes: []
'@
$original = [LibTmux.Workspace.WorkspaceFile]::Parse($declaration)
Assert-WorkspaceText ($original.Windows[0].WindowIndex -eq 5 -and
    $null -eq $original.Windows[1].WindowIndex) 'declared and implicit window indices were not distinguished'
Assert-WorkspaceText ($original.BeforeCommands[1].Enter -eq $false -and
    $null -eq $original.BeforeCommands[2].Enter -and
    $original.Windows[0].BeforeCommands[0].Enter -eq $true -and
    $original.Windows[0].Panes[0].Enter -eq $false -and
    $original.Windows[0].Panes[0].BeforeCommands[1].Enter -eq $false -and
    $original.Windows[0].Panes[0].Commands[7].Enter -eq $false -and
    $original.Windows[0].Panes[0].Commands[8].Enter -eq $true -and
    $null -eq $original.Windows[0].Panes[0].Commands[9].Enter) 'pane defaults, command overrides and inheritance were not distinguished'
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
        Assert-WorkspaceText ($restored.Windows[0].WindowIndex -eq 5 -and
            $null -eq $restored.Windows[1].WindowIndex) 'window index did not survive text conversion'
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

# Outer integration: freeze uses an owned captured graph after daemon shutdown.
. "$PSScriptRoot/support/OwnedTmux.ps1"
Invoke-WithOwnedTmux {
    param($fixture)
    $physicalParent = Join-Path $fixture.DirectoryPath 'physical'
    $aliasParent = Join-Path $fixture.DirectoryPath 'alias'
    $null = [IO.Directory]::CreateDirectory($physicalParent)
    $null = [IO.Directory]::CreateSymbolicLink($aliasParent, $physicalParent)
    $path = Join-Path $aliasParent '$cash ${literal} #{session_name} space'
    $null = [IO.Directory]::CreateDirectory($path)
    $physicalPath = Get-PhysicalDirectory $path
    Assert-WorkspaceText ($physicalPath -cne $path) 'fixture did not create a path alias'
    $null = Invoke-OwnedTmux $fixture -Arguments @('respawn-pane', '-k', '-t', '%0', '-c', $path.Replace('#', '#{a:35}'), 'exec /bin/cat')
    $null = Invoke-OwnedTmux $fixture -Arguments @('rename-window', '-t', '@0', 'editor')
    $null = Invoke-OwnedTmux $fixture -Arguments @('split-window', '-d', '-h', '-t', '%0', '-c', $fixture.DirectoryPath, 'exec /bin/cat')
    $null = Invoke-OwnedTmux $fixture -Arguments @('link-window', '-s', '@0', '-t', 'fixture:7')
    $null = Invoke-OwnedTmux $fixture -Arguments @('select-pane', '-t', '%1')
    $null = Invoke-OwnedTmux $fixture -Arguments @('select-window', '-t', 'fixture:7')
    Register-OwnedTmuxPane $fixture
    $trace = Join-Path $fixture.DirectoryPath 'freeze-calls'
    $blocked = Join-Path $fixture.DirectoryPath 'freeze-blocked'
    $wrapper = Join-Path $fixture.DirectoryPath 'freeze-tmux'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' call >> '$trace'
if [ -f '$blocked' ]; then exit 91; fi
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper
    $snapshot = $server | LibTmux\Get-TmuxSnapshot -Depth Panes
    $shallow = $server | LibTmux\Get-TmuxSnapshot -Depth Sessions
    $captured = $snapshot.Sessions[0]
    Assert-WorkspaceText ($captured.Windows.Count -eq 2) 'freeze fixture did not capture its native linked graph'
    Assert-WorkspaceText ($captured.Windows[0].Panes[0].CurrentPath -ceq $physicalPath) 'freeze fixture did not capture the physical literal path'
    [IO.File]::WriteAllText($blocked, '')
    $before = [IO.File]::ReadAllText($trace)
    $exited = $fixture.ServerProcess.WaitForExitAsync()
    $null = Invoke-OwnedTmux $fixture -Arguments @('kill-server')
    $null = $exited.WaitAsync([TimeSpan]::FromSeconds(1)).GetAwaiter().GetResult()

    $warnings = @()
    $outputs = @(@($captured, $captured) | LibTmux.Workspace\ConvertTo-TmuxWorkspace -WarningAction SilentlyContinue -WarningVariable warnings)
    Assert-WorkspaceText ($outputs.Count -eq 2 -and $outputs[0] -is [LibTmux.Workspace.WorkspaceFile] -and
        $outputs[1] -is [LibTmux.Workspace.WorkspaceFile] -and $warnings.Count -eq 2) 'freeze lost native per-record output or explicit loss warnings'
    Assert-WorkspaceText ($warnings[0].Message -match 'pane indices' -and
        $warnings[0].Message -notmatch 'window indices') 'freeze warning misstated which indices are omitted'
    $frozen = $outputs[0]
    Assert-WorkspaceText ($null -eq $frozen.DocumentDirectory -and $frozen.Windows.Count -eq 2 -and
        $frozen.Windows[0].WindowIndex -eq 0 -and $frozen.Windows[1].WindowIndex -eq 7 -and
        !$frozen.Windows[0].Focus -and $frozen.Windows[1].Focus -and
        $frozen.Windows[0].WindowName -ceq 'editor' -and $frozen.Windows[1].WindowName -ceq 'editor' -and
        !$frozen.Windows[0].Panes[0].Focus -and $frozen.Windows[0].Panes[1].Focus -and
        !$frozen.Windows[1].Panes[0].Focus -and $frozen.Windows[1].Panes[1].Focus -and
        $frozen.Windows[0].Layout -ceq $captured.Windows[0].Layout -and
        $frozen.Windows[1].Layout -ceq $captured.Windows[1].Layout) 'freeze lost contextual order, focus, layout or unresolved provenance'
    Assert-WorkspaceText ($frozen.Windows[0].Panes[0].StartDirectory -ceq $physicalPath.Replace('$', '$$') -and
        @($frozen.Windows | ForEach-Object { $_.Panes } | ForEach-Object { $_.ShellCommands }).Count -eq 0 -and
        @($frozen.Windows | ForEach-Object { $_.Panes } | Where-Object { $null -ne $_.Enter }).Count -eq 0) 'freeze rewrote literal paths or invented startup commands or Enter intent'
    foreach ($format in @('Yaml', 'Json')) {
        $text = $frozen | & "LibTmux.Workspace\ConvertTo-TmuxWorkspace$format"
        $restored = LibTmux.Workspace\Import-TmuxWorkspace -Yaml $text |
            LibTmux.Workspace\Resolve-TmuxWorkspace -BaseDirectory $fixture.DirectoryPath
        Assert-WorkspaceText ($restored.Windows[0].Panes[0].StartDirectory -ceq $physicalPath -and
            $restored.Windows[1].Panes[0].StartDirectory -ceq $physicalPath -and
            $restored.Windows[0].WindowIndex -eq 0 -and $restored.Windows[1].WindowIndex -eq 7) 'freeze/text/import/resolve changed a literal captured directory or window index'
    }
    $errors = @()
    $continued = @(@($shallow.Sessions[0], $captured) | LibTmux.Workspace\ConvertTo-TmuxWorkspace -ErrorAction Continue -ErrorVariable errors -WarningAction SilentlyContinue 2>$null)
    Assert-WorkspaceText ($continued.Count -eq 1 -and $errors.Count -eq 1 -and
        $errors[0].Exception -is [LibTmux.IncompleteSnapshotException] -and
        $errors[0].CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::InvalidData -and
        $errors[0].FullyQualifiedErrorId -like 'Tmux.WorkspaceFreezeFailed,*' -and
        [object]::ReferenceEquals($errors[0].TargetObject, $shallow.Sessions[0])) 'incomplete freeze lost native error identity, target or Continue behavior'
    Assert-WorkspaceText ([IO.File]::ReadAllText($trace) -ceq $before) 'pure freeze or subsequent text conversion contacted tmux'
}
'PASS workspace freeze: native projection, linked focus, offline conversion and strict capture errors'
