param([Parameter(Mandatory)] [string] $ModuleRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1')

function Assert-WorkspaceValidation([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Workspace validation: $Message" }
}

Assert-WorkspaceValidation ($null -ne (Get-Command LibTmux.Workspace\Test-TmuxWorkspace -ErrorAction SilentlyContinue)) 'installed module has no Test-TmuxWorkspace'
$directory = [IO.Directory]::CreateTempSubdirectory('libtmux-powershell-validation-')
$oldPath = $env:PATH
try {
    $env:PATH = $directory.FullName
    $complete = LibTmux.Workspace\Import-TmuxWorkspace -Yaml '{session_name: validate, windows: [{panes: [null]}]}'
    Assert-WorkspaceValidation ($complete | LibTmux.Workspace\Test-TmuxWorkspace) 'complete declaration failed without an executable'
    $partial = LibTmux.Workspace\Import-TmuxWorkspace -Yaml 'session_name: incomplete'
    $diagnostics = @()
    $results = @(@($partial, $complete) | LibTmux.Workspace\Test-TmuxWorkspace -ErrorAction Continue -ErrorVariable diagnostics 2>$null)
    Assert-WorkspaceValidation ($results.Count -eq 2 -and $results[0] -eq $false -and $results[1] -eq $true -and
        $diagnostics.Count -eq 1 -and $diagnostics[0].Exception -is [LibTmux.Workspace.WorkspaceFormatException] -and
        $diagnostics[0].FullyQualifiedErrorId -like 'Tmux.WorkspaceValidationFailed,*' -and
        [object]::ReferenceEquals($diagnostics[0].TargetObject, $partial)) 'incomplete declaration passed, lost its native error, or stopped later validation'
    $caught = $false
    try { $partial | LibTmux.Workspace\Test-TmuxWorkspace -ErrorAction Stop } catch { $caught = $true }
    Assert-WorkspaceValidation $caught 'ErrorAction Stop did not terminate invalid validation'

    $sentinel = Join-Path $directory.FullName 'must-not-execute'
    $escaped = "'" + $sentinel.Replace("'", "'\''") + "'"
    $hostDeclaration = [LibTmux.Workspace.WorkspaceFile]::new('host-check', $directory.FullName, $null,
        [LibTmux.Workspace.WorkspaceWindow[]] $complete.Windows, ": > $escaped")
    $hostDeclaration = $hostDeclaration.Resolve($directory.FullName)
    $diagnostics = @()
    $denied = $hostDeclaration | LibTmux.Workspace\Test-TmuxWorkspace -ErrorAction Continue -ErrorVariable diagnostics 2>$null
    Assert-WorkspaceValidation ($denied -eq $false -and $diagnostics.Count -eq 1) 'host execution policy was ignored'
    Assert-WorkspaceValidation ($hostDeclaration | LibTmux.Workspace\Test-TmuxWorkspace -AllowHostScripts) 'explicit host policy failed pure validation'
    Assert-WorkspaceValidation ($hostDeclaration | LibTmux.Workspace\Test-TmuxWorkspace -ExistingSession Reuse) 'Reuse did not defer conditional host admission'
    Assert-WorkspaceValidation (!(Test-Path -LiteralPath $sentinel)) 'validation executed a host script'

    foreach ($arguments in @(
            @{ ReadinessTimeout = [double]::NaN }, @{ HostScriptTimeout = [double]::PositiveInfinity },
            @{ CleanupTimeout = 0 }, @{ MaxHostOutputBytes = 0 }, @{ ExistingSession = 99 }
        )) {
        $failure = $null
        try { $complete | LibTmux.Workspace\Test-TmuxWorkspace @arguments -ErrorAction Continue } catch { $failure = $_ }
        Assert-WorkspaceValidation ($null -ne $failure) 'invalid policy was accepted'
    }
} finally {
    $env:PATH = $oldPath
    $directory.Delete($true)
}
'PASS workspace validation: native preflight, incomplete declarations, policies, diagnostics and no execution'
