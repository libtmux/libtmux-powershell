@{
    RootModule = 'LibTmux.Workspace.psm1'
    ModuleVersion = '0.1.0'
    GUID = '56caa6c5-aab3-40d8-b5ad-289bd79780ab'
    Author = 'libtmux contributors'
    Description = 'Workspace declarations and automation over LibTmux. Alpha.'
    PowerShellVersion = '7.4'
    CompatiblePSEditions = @('Core')
    RequiredModules = @(@{ ModuleName = 'LibTmux'; RequiredVersion = '0.1.0' })
    FunctionsToExport = @()
    CmdletsToExport = @('Import-TmuxWorkspace')
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('tmux', 'tmuxp', 'workspace', 'Linux', 'macOS')
            ProjectUri = 'https://github.com/libtmux/libtmux-powershell'
        }
    }
}
