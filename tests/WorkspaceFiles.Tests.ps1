param([Parameter(Mandatory)] [string] $ModuleRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/support/HangGuard.ps1"
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
            Assert-WorkspaceFile ($mkfifo.WaitForExit($HangGuardMilliseconds) -and $mkfifo.ExitCode -eq 0) 'owned FIFO creation failed'
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
            Assert-WorkspaceFile ($child.WaitForExit($HangGuardMilliseconds)) 'opening a replaced FIFO blocked before cancellation could be observed'
            $category = $child.StandardOutput.ReadToEnd().Trim()
            Assert-WorkspaceFile ($child.ExitCode -eq 0 -and $category -ceq 'InvalidData') 'nonseekable input was admitted or miscategorized'
            Assert-WorkspaceFile ($stderr.GetAwaiter().GetResult().Length -eq 0) 'owned FIFO probe wrote unexpected errors'
        } finally {
            if (!$child.HasExited) { $child.Kill($true) }
            Assert-WorkspaceFile ($child.WaitForExit($HangGuardMilliseconds)) 'owned FIFO probe did not exit during cleanup'
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
'PASS workspace files: strict bounded UTF-8, literal paths, native resolution, variables and pipeline errors'
