@{
    RootModule = 'LibTmux.Workspace.psm1'
    ModuleVersion = '0.1.0'
    GUID = '56caa6c5-aab3-40d8-b5ad-289bd79780ab'
    Author = 'libtmux contributors'
    Description = 'Workspace declarations and automation over LibTmux.'
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
            Tags = @('tmux', 'tmuxp', 'workspace', 'Linux', 'macOS')
            ProjectUri = 'https://github.com/libtmux/libtmux-powershell'
            LicenseUri = 'https://github.com/libtmux/libtmux-powershell/blob/master/LICENSE'
            ReleaseNotes = @'
Requires tmux 3.3a or newer, as the core module does.

Requires the LibTmux package of the same version. Built on libtmux for .NET 0.1.1.
The API is not settled: pin an exact version.
https://github.com/libtmux/libtmux-dotnet

Release details:
https://github.com/libtmux/libtmux-powershell/blob/master/CHANGELOG.md
'@
        }
    }
}
