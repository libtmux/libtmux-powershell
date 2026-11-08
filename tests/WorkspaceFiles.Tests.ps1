param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [string] $CatalogFixtureRoot = (Join-Path $PSScriptRoot 'fixtures/workspace')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspaceModule = Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1'
Import-Module $workspaceModule

function Assert-WorkspaceFile([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Workspace files: $Message" }
}

$directory = [IO.Directory]::CreateTempSubdirectory('libtmux-powershell-files-')
$oldPath = $env:PATH
try {
    if ($IsLinux -or $IsMacOS) {
        $fifo = Join-Path $directory.FullName 'replaced.yaml'
        [IO.File]::WriteAllText($fifo, 'session_name: replaced')
        [IO.File]::Delete($fifo)
        $mkfifoStart = [Diagnostics.ProcessStartInfo]::new('/usr/bin/mkfifo')
        $mkfifoStart.ArgumentList.Add($fifo)
        $mkfifo = [Diagnostics.Process]::Start($mkfifoStart)
        try {
            Assert-WorkspaceFile ($mkfifo.WaitForExit(1000) -and $mkfifo.ExitCode -eq 0) 'owned FIFO creation failed'
        } finally { $mkfifo.Dispose() }

        $moduleLiteral = [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($workspaceModule)
        $fifoLiteral = [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($fifo)
        $childScript = @"
Import-Module '$moduleLiteral'
[Console]::Out.WriteLine('entered')
[Console]::Out.Flush()
try {
    `$null = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath '$fifoLiteral' -ErrorAction Stop
    exit 2
} catch {
    [Console]::Out.WriteLine(`$_.CategoryInfo.Category.ToString())
    exit 0
}
"@
        $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand',
            [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript)))) {
            $start.ArgumentList.Add($argument)
        }
        $child = [Diagnostics.Process]::Start($start)
        try {
            $stderr = $child.StandardError.ReadToEndAsync()
            $enteredTask = $child.StandardOutput.ReadLineAsync()
            $exitTask = $child.WaitForExitAsync()
            $null = [Threading.Tasks.Task]::WhenAny([Threading.Tasks.Task[]] @($enteredTask, $exitTask)).GetAwaiter().GetResult()
            $entered = $enteredTask.GetAwaiter().GetResult()
            Assert-WorkspaceFile ($entered -ceq 'entered') 'owned file-open probe did not reach admission'
            Assert-WorkspaceFile ($child.WaitForExit(1000)) 'opening a replaced FIFO blocked before cancellation could be observed'
            $category = $child.StandardOutput.ReadToEnd().Trim()
            Assert-WorkspaceFile ($child.ExitCode -eq 0 -and $category -ceq 'InvalidData') 'nonseekable input was admitted or miscategorized'
            Assert-WorkspaceFile ($stderr.GetAwaiter().GetResult().Length -eq 0) 'owned FIFO probe wrote unexpected errors'
        } finally {
            if (!$child.HasExited) { $child.Kill($true) }
            Assert-WorkspaceFile ($child.WaitForExit(1000)) 'owned FIFO probe did not exit during cleanup'
            $child.Dispose()
        }
    }
    $env:PATH = $directory.FullName
    $invalid = Join-Path $directory.FullName 'invalid.yaml'
    [IO.File]::WriteAllBytes($invalid, [Text.Encoding]::UTF8.GetBytes('session_name: invalid-') + [byte] 255)
    $failure = $null
    try { $null = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath $invalid } catch { $failure = $_ }
    Assert-WorkspaceFile ($null -ne $failure -and $failure.CategoryInfo.Category -eq 'InvalidData' -and
        $failure.Exception -is [Text.DecoderFallbackException]) 'invalid UTF-8 lost its strict decoder exception or data-error category'

    $failure = $null
    try { $null = LibTmux.Workspace\Import-TmuxWorkspace -Yaml 'windows: [' } catch { $failure = $_ }
    Assert-WorkspaceFile ($null -ne $failure -and $failure.CategoryInfo.Category -eq 'InvalidData' -and
        $failure.Exception -is [LibTmux.Workspace.WorkspaceFormatException]) 'malformed YAML lost its native exception or data-error category'

    $file = Join-Path $directory.FullName "[`u{89B3}`u{6E2C} native].yaml"
    $text = @'
session_name: files
start_directory: ${ROOT}
windows:
  - start_directory: src
    panes:
      - start_directory: ../literal-$$
'@
    [IO.File]::WriteAllText($file, $text, [Text.UTF8Encoding]::new($true, $true))
    $parsed = Get-Item -LiteralPath $file | LibTmux.Workspace\Import-TmuxWorkspace
    Assert-WorkspaceFile ($parsed -is [LibTmux.Workspace.WorkspaceFile] -and
        $parsed.StartDirectory -ceq '${ROOT}') 'FileInfo import expanded paths or failed literal brackets/BOM'

    $resolved = Get-Item -LiteralPath $file | LibTmux.Workspace\Resolve-TmuxWorkspace -Variables @{ ROOT = 'project' }
    $expected = Join-Path $directory.FullName 'project/literal-$'
    Assert-WorkspaceFile ($resolved.DocumentDirectory -ceq $directory.FullName -and
        $resolved.Windows[0].Panes[0].StartDirectory -ceq $expected -and
        $parsed.StartDirectory -ceq '${ROOT}') 'file-relative inheritance lost its base, literal dollar or immutable input'
    $local = $parsed | LibTmux.Workspace\Resolve-TmuxWorkspace -BaseDirectory $directory.FullName -Variables @{ ROOT = 'project' }
    Assert-WorkspaceFile ($local.Windows[0].Panes[0].StartDirectory -ceq $expected) 'explicit native resolution differs from file resolution'
    $failure = $null
    try { $null = LibTmux.Workspace\Resolve-TmuxWorkspace -LiteralPath $invalid } catch { $failure = $_ }
    Assert-WorkspaceFile ($null -ne $failure -and $failure.CategoryInfo.Category -eq 'InvalidData' -and
        $failure.Exception -is [Text.DecoderFallbackException]) 'resolution lost strict UTF-8 data-error semantics'
    $fromPath = LibTmux.Workspace\Resolve-TmuxWorkspace -LiteralPath $file -Variables @{ ROOT = 'project' }
    Assert-WorkspaceFile ($fromPath.Windows[0].Panes[0].StartDirectory -ceq $expected) 'literal path resolution differs from FileInfo resolution'

    $diagnostics = @()
    $results = @(@([IO.FileInfo]::new($invalid), [IO.FileInfo]::new($file)) |
        LibTmux.Workspace\Import-TmuxWorkspace -ErrorAction Continue -ErrorVariable diagnostics 2>$null)
    Assert-WorkspaceFile ($results.Count -eq 1 -and $results[0].SessionName -ceq 'files' -and
        $diagnostics.Count -eq 1 -and $diagnostics[0].FullyQualifiedErrorId -like 'Tmux.InvalidWorkspace,*') 'bad file prevented later input or lost its error'

    foreach ($variables in @(@{ ROOT = 1 }, @{ ROOT = $null }, @{ ROOT = { 'project' } })) {
        $failure = $null
        try { $null = $parsed | LibTmux.Workspace\Resolve-TmuxWorkspace -BaseDirectory $directory.FullName -Variables $variables } catch { $failure = $_ }
        Assert-WorkspaceFile ($null -ne $failure) 'variables accepted lossy conversion or executable data'
    }
    $failure = $null
    try { $null = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath 'Env:PATH' } catch { $failure = $_ }
    Assert-WorkspaceFile ($null -ne $failure) 'non-filesystem provider was accepted'

    [IO.File]::WriteAllText($invalid, 'session_name: unicode', [Text.Encoding]::Unicode)
    $failure = $null
    try { $null = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath $invalid } catch { $failure = $_ }
    Assert-WorkspaceFile ($null -ne $failure) 'non-UTF-8 file was accepted'
    [IO.File]::WriteAllText($invalid, ('#' + ('x' * 1048576)))
    $failure = $null
    try { $null = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath $invalid } catch { $failure = $_ }
    Assert-WorkspaceFile ($null -ne $failure) 'oversized file was admitted'
} finally {
    $env:PATH = $oldPath
    $directory.Delete($true)
}

# tmuxp example catalog: every example tmuxp ships loads through
# Import-TmuxWorkspace or fails with the error recorded here. A change in the
# loader fails the case until its entry is updated or removed.
$catalogLoaded = @(
    'tmuxp-v1.74.0-2-pane-synchronized.yaml'
    'tmuxp-v1.74.0-2-pane-vertical.yaml'
    'tmuxp-v1.74.0-3-pane.yaml'
    'tmuxp-v1.74.0-4-pane.yaml'
    'tmuxp-v1.74.0-blank-panes.yaml'
    'tmuxp-v1.74.0-env-variables.yaml'
    'tmuxp-v1.74.0-focus-window-and-panes.yaml'
    'tmuxp-v1.74.0-main-pane-height-percentage.yaml'
    'tmuxp-v1.74.0-main-pane-height.yaml'
    'tmuxp-v1.74.0-minimal.yaml'
    'tmuxp-v1.74.0-options.yaml'
    'tmuxp-v1.74.0-session-environment.yaml'
    'tmuxp-v1.74.0-shorthands.yaml'
    'tmuxp-v1.74.0-skip-send-pane-level.yaml'
    'tmuxp-v1.74.0-skip-send.yaml'
    'tmuxp-v1.74.0-start-directory.yaml'
    'tmuxp-v1.74.0-window-index.yaml'
)
$catalogRefused = [ordered] @{
    'tmuxp-v1.74.0-pane-shell.yaml' = 'Workspace path ''windows[0]'' contains unsupported key ''window_shell''. At line 4, column 5.'
    'tmuxp-v1.74.0-plugin-system.yaml' = 'Workspace path ''$'' contains unsupported key ''plugins''. At line 2, column 1.'
    'tmuxp-v1.74.0-sleep-pane-level.yaml' = 'Workspace path ''windows[0].panes[0]'' contains unsupported key ''sleep_before''. At line 5, column 9.'
    'tmuxp-v1.74.0-sleep-virtualenv.yaml' = 'Workspace path ''shell_command_before[0]'' contains unsupported key ''sleep_before''. At line 6, column 5.'
    'tmuxp-v1.74.0-sleep.yaml' = 'Workspace path ''windows[0].panes[0].shell_command[1]'' contains unsupported key ''sleep_before''. At line 9, column 13.'
    'tmuxp-v1.74.0-suppress-history.yaml' = 'Workspace path ''$'' contains unsupported key ''suppress_history''. At line 2, column 1.'
}
$catalogFound = @(Get-ChildItem -LiteralPath $CatalogFixtureRoot -Filter 'tmuxp-v1.74.0-*.yaml' |
    ForEach-Object Name)
$catalogNamed = @($catalogLoaded) + @($catalogRefused.Keys)
$catalogUnclassified = @($catalogFound | Where-Object { $_ -cnotin $catalogNamed -and
    $_ -cnotmatch '^tmuxp-v1\.74\.0-(two_windows|three_windows|first_pane_start_directory|environment_vars|window_options|window_index)\.yaml$' })
Assert-WorkspaceFile ($catalogUnclassified.Count -eq 0 -and $catalogNamed.Count -ge 20 -and
    @($catalogNamed | Where-Object { $_ -cnotin $catalogFound }).Count -eq 0) "tmuxp example catalog: files not classified: $($catalogUnclassified -join ', ')"
foreach ($name in $catalogLoaded) {
    $example = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath (Join-Path $CatalogFixtureRoot $name) -ErrorAction Stop
    Assert-WorkspaceFile ($example -is [LibTmux.Workspace.WorkspaceFile]) "tmuxp example catalog: $name did not load"
}
foreach ($name in $catalogRefused.Keys) {
    $failure = $null
    try { $null = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath (Join-Path $CatalogFixtureRoot $name) -ErrorAction Stop } catch { $failure = $_ }
    Assert-WorkspaceFile ($null -ne $failure -and
        $failure.Exception -is [LibTmux.Workspace.WorkspaceFormatException] -and
        $failure.Exception.Message -ceq $catalogRefused[$name]) "tmuxp example catalog: $name did not fail as recorded: $($failure.Exception.Message)"
}
'PASS workspace files: strict bounded UTF-8, literal paths, native resolution, variables, pipeline errors and the tmuxp example catalog'
