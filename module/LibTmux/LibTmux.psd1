@{
    RootModule = 'LibTmux.psm1'
    ModuleVersion = '0.1.0'
    GUID = '769d8b5e-807e-43c7-9c89-d6c9c6e32fbf'
    Author = 'libtmux contributors'
    Description = 'Native PowerShell automation over the LibTmux .NET core. Alpha.'
    PowerShellVersion = '7.4'
    CompatiblePSEditions = @('Core')
    FormatsToProcess = @('LibTmux.Format.ps1xml')
    FunctionsToExport = @()
    CmdletsToExport = @(
        'New-TmuxServer', 'Connect-TmuxServer', 'Get-TmuxServer', 'Get-TmuxSnapshot',
        'Get-TmuxSession', 'Get-TmuxWindow', 'Get-TmuxPane',
        'Enter-TmuxSession',
        'New-TmuxQuery', 'ConvertTo-TmuxQueryJson', 'Get-TmuxQueryField',
        'Get-TmuxQueryPlan', 'Invoke-TmuxQuery',
        'Select-TmuxSession', 'Select-TmuxWindow', 'Select-TmuxPane',
        'Get-TmuxPaneContent', 'Invoke-TmuxCommand', 'Update-TmuxPane',
        'New-TmuxSession', 'New-TmuxWindow', 'Split-TmuxPane',
        'Remove-TmuxSession', 'Remove-TmuxWindow', 'Remove-TmuxPane',
        'New-TmuxWindowLink', 'Move-TmuxWindow', 'Remove-TmuxWindowLink',
        'Send-TmuxText', 'Send-TmuxKey', 'Invoke-TmuxPaneCommand', 'Wait-TmuxChannel', 'Wait-TmuxPaneText',
        'Get-TmuxOption', 'Set-TmuxOption', 'Remove-TmuxOption',
        'Get-TmuxHook', 'Set-TmuxHook', 'Invoke-TmuxHook', 'Remove-TmuxHook',
        'Get-TmuxEnvironment', 'Set-TmuxEnvironment', 'Remove-TmuxEnvironment',
        'Set-TmuxLayout', 'Set-TmuxWindowSize', 'Set-TmuxPaneSize',
        'Get-TmuxClient', 'Update-TmuxClient', 'Get-TmuxClientAttachment',
        'New-TmuxCommand', 'Invoke-TmuxChain', 'Connect-TmuxControl',
        'Invoke-TmuxControlCommand', 'Disconnect-TmuxControl', 'Watch-TmuxEvent'
    )
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Prerelease = 'alpha2'
            Tags = @('tmux', 'automation', 'Linux', 'macOS')
            ProjectUri = 'https://github.com/libtmux/libtmux-powershell'
            LicenseUri = 'https://github.com/libtmux/libtmux-powershell/blob/master/LICENSE'
            ReleaseNotes = @'
Alpha 2 prerelease (0.1.0-alpha2). Follow Gallery installation and runnable
object-graph examples with direct documentation links.

Built on libtmux for .NET 0.0.0-alpha.20.
APIs may change before a stable release.
https://github.com/libtmux/libtmux-dotnet

Release details:
https://github.com/libtmux/libtmux-powershell/blob/master/CHANGELOG.md
'@
        }
    }
}
