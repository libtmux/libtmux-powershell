@{
    RootModule = 'LibTmux.Workspace.psm1'
    ModuleVersion = '0.1.0'
    GUID = '56caa6c5-aab3-40d8-b5ad-289bd79780ab'
    Author = 'libtmux contributors'
    Description = 'Workspace declarations and automation over LibTmux. Alpha.'
    PowerShellVersion = '7.4'
    CompatiblePSEditions = @('Core')
    RequiredModules = @(@{ ModuleName = 'LibTmux'; RequiredVersion = '0.1.0' })
    FormatsToProcess = @('LibTmux.Workspace.Format.ps1xml')
    FunctionsToExport = @()
    CmdletsToExport = @(
        'Import-TmuxWorkspace', 'Resolve-TmuxWorkspace', 'Test-TmuxWorkspace',
        'Get-TmuxWorkspace', 'Get-TmuxWorkspacePlan', 'Invoke-TmuxWorkspace',
        'ConvertTo-TmuxWorkspace', 'ConvertTo-TmuxWorkspaceYaml', 'ConvertTo-TmuxWorkspaceJson'
    )
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Prerelease = 'alpha2'
            Tags = @('tmux', 'tmuxp', 'workspace', 'Linux', 'macOS')
            ProjectUri = 'https://github.com/libtmux/libtmux-powershell'
            LicenseUri = 'https://github.com/libtmux/libtmux-powershell/blob/master/LICENSE'
            ReleaseNotes = @'
Alpha 2 prerelease (0.1.0-alpha2). Install with the matching core dependency
and follow the workspace plan/apply examples.

Requires LibTmux 0.1.0-alpha2. Built on libtmux for .NET 0.0.0-alpha.20.
APIs may change before a stable release.
https://github.com/libtmux/libtmux-dotnet

Release details:
https://github.com/libtmux/libtmux-powershell/blob/master/CHANGELOG.md
'@
        }
    }
}
