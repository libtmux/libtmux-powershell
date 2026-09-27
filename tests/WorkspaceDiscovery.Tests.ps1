param([Parameter(Mandatory)] [string] $ModuleRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1')

function Assert-Discovery([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Workspace discovery: $Message" }
}

Assert-Discovery ($null -ne (Get-Command 'LibTmux.Workspace\Get-TmuxWorkspace' -ErrorAction SilentlyContinue)) 'installed module has no Get-TmuxWorkspace'

function Assert-DiscoveryOrder($Actual, [string[]] $Expected, [string] $Message) {
    $files = @()
    if ($null -ne $Actual) { $files = @($Actual) }
    Assert-Discovery ($files.Count -eq $Expected.Count -and
        @($files | Where-Object { $_ -isnot [IO.FileInfo] }).Count -eq 0) "$Message native count/type"
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        Assert-Discovery ($files[$index].FullName -ceq $Expected[$index]) "$Message ordered literal path"
    }
}

$fixture = [IO.Directory]::CreateTempSubdirectory('libtmux-powershell-discovery-')
$savedDiscoveryEnvironment = @{}
foreach ($variable in @('HOME', 'TMUXP_CONFIGDIR', 'XDG_CONFIG_HOME', 'PATH')) {
    $savedDiscoveryEnvironment[$variable] = [Environment]::GetEnvironmentVariable($variable)
}
$locationPushed = $false
try {
    $profileDirectory = $fixture.CreateSubdirectory('home')
    $project = $fixture.CreateSubdirectory('home/project')
    $child = $fixture.CreateSubdirectory('home/project/child')
    $configured = $fixture.CreateSubdirectory('configured')
    $xdgDirectory = $fixture.CreateSubdirectory('xdg')
    $xdgTmuxp = $fixture.CreateSubdirectory('xdg/tmuxp')
    $legacy = $fixture.CreateSubdirectory('home/.tmuxp')
    $explicit = $fixture.CreateSubdirectory('explicit')
    $nested = $configured.CreateSubdirectory('nested')
    $localPaths = @((Join-Path $child.FullName '.tmuxp.json'),
        (Join-Path $project.FullName '.tmuxp.yaml'), (Join-Path $profileDirectory.FullName '.tmuxp.yml'))
    $configuredFile = Join-Path $configured.FullName 'alpha.yaml'
    $xdgFile = Join-Path $xdgTmuxp.FullName 'bravo.json'
    $legacyFile = Join-Path $legacy.FullName 'charlie.yml'
    $explicitFile = Join-Path $explicit.FullName 'delta.yaml'
    foreach ($path in $localPaths + @($configuredFile, $xdgFile, $legacyFile, $explicitFile,
            (Join-Path $fixture.FullName '.tmuxp.yaml'), (Join-Path $nested.FullName 'hidden.yaml'))) {
        [IO.File]::WriteAllText($path, '{"session_name":"listed"}')
    }
    [Environment]::SetEnvironmentVariable('HOME', $profileDirectory.FullName + [IO.Path]::DirectorySeparatorChar)
    [Environment]::SetEnvironmentVariable('TMUXP_CONFIGDIR', $configured.FullName)
    [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', $xdgDirectory.FullName)
    $env:PATH = $fixture.FullName
    Push-Location -LiteralPath $child.FullName
    $locationPushed = $true

    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace) ($localPaths + $configuredFile) 'nearest locals and first global'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -ConfigurationDirectory $explicit.FullName) ($localPaths + $explicitFile) 'explicit global precedence'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -ConfigurationDirectory $explicit.FullName -AllLocations) ($localPaths + @($explicitFile, $configuredFile, $xdgFile, $legacyFile)) 'all locations preserve shadowed precedence'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Directory $project.FullName) @($localPaths[1]) 'directory excludes ancestors and globals'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Name alpha) @($configuredFile) 'global basename'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Name alpha.yaml) @($configuredFile) 'literal supported suffix'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Name absent) @() 'missing name emits nothing'

    [Environment]::SetEnvironmentVariable('TMUXP_CONFIGDIR', (Join-Path $fixture.FullName 'missing-default'))
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace) ($localPaths + $xdgFile) 'missing default falls through to XDG'
    [Environment]::SetEnvironmentVariable('TMUXP_CONFIGDIR', $configured.FullName)
    $sameName = Join-Path $xdgTmuxp.FullName 'alpha.yaml'
    [IO.File]::WriteAllText($sameName, 'session_name: shadowed')
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Name alpha -AllLocations) @($configuredFile, $sameName) 'name shadowing is explicit'
    [IO.File]::Delete($sameName)

    $literal = Join-Path $configured.FullName '[team].yaml'
    [IO.File]::WriteAllText($literal, 'session_name: literal')
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -LiteralPath $literal) @($literal) 'literal brackets'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Name '[team]') @($literal) 'name does not expand wildcards'
    $imported = LibTmux.Workspace\Get-TmuxWorkspace -LiteralPath $literal | LibTmux.Workspace\Import-TmuxWorkspace
    Assert-Discovery ($imported -is [LibTmux.Workspace.WorkspaceFile] -and $imported.SessionName -ceq 'literal') 'FileInfo feeds explicit import'
    [IO.File]::Delete($literal)

    if ($IsLinux -or $IsMacOS) {
        $link = Join-Path $explicit.FullName 'linked.yaml'
        $null = [IO.File]::CreateSymbolicLink($link, $configuredFile)
        Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -LiteralPath $link) @($link) 'literal readable file symlink'
        $directoryLink = Join-Path $configured.FullName 'linked-directory.yaml'
        $null = [IO.Directory]::CreateSymbolicLink($directoryLink, $nested.FullName)
        Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -ConfigurationDirectory $configured.FullName) ($localPaths + $configuredFile) 'directory symlink is not descended'
        [IO.File]::Delete($directoryLink)
        [IO.File]::Delete($link)
    }

    $ambiguous = Join-Path $configured.FullName 'alpha.json'
    [IO.File]::WriteAllText($ambiguous, 'session_name: ambiguous')
    $failure = $null
    try { $null = LibTmux.Workspace\Get-TmuxWorkspace -Name alpha } catch { $failure = $_ }
    Assert-Discovery ($null -ne $failure -and $failure.FullyQualifiedErrorId -like 'Tmux.WorkspaceDiscoveryFailed,*' -and
        $failure.CategoryInfo.Category -eq 'InvalidArgument' -and $failure.TargetObject -ceq 'alpha' -and
        $failure.Exception.Message.Contains($configuredFile, [StringComparison]::Ordinal) -and
        $failure.Exception.Message.Contains($ambiguous, [StringComparison]::Ordinal)) 'ambiguous suffixes lost candidate diagnostics'
    [IO.File]::Delete($ambiguous)

    foreach ($arguments in @(
            @{ LiteralPath = 'Env:PATH' }, @{ LiteralPath = $configured.FullName },
            @{ LiteralPath = (Join-Path $fixture.FullName 'absent.yaml') },
            @{ Directory = (Join-Path $fixture.FullName 'absent-directory') },
            @{ ConfigurationDirectory = (Join-Path $fixture.FullName 'absent-configuration') },
            @{ Name = '../alpha' }, @{ Name = 'nested/hidden' }
        )) {
        $failure = $null
        try { $null = LibTmux.Workspace\Get-TmuxWorkspace @arguments } catch { $failure = $_ }
        Assert-Discovery ($null -ne $failure -and $failure.FullyQualifiedErrorId -like 'Tmux.WorkspaceDiscoveryFailed,*') 'invalid literal/directory/name was accepted'
    }
    foreach ($arguments in @(
            @{ Directory = $project.FullName; AllLocations = $true },
            @{ Name = 'alpha'; Search = 'alpha' },
            @{ Search = 'alpha'; SearchIn = @('Unknown') }
        )) {
        $failure = $null
        try { $null = LibTmux.Workspace\Get-TmuxWorkspace @arguments } catch { $failure = $_ }
        Assert-Discovery ($null -ne $failure) 'conflicting discovery parameters were accepted'
    }

    $binding = [PowerShell]::Create()
    try {
        $null = $binding.AddCommand('Import-Module').AddArgument((Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1')).Invoke()
        $binding.Commands.Clear()
        $null = $binding.AddCommand('LibTmux.Workspace\Get-TmuxWorkspace').AddParameter('SearchIn', [string[]] @('Session'))
        $failure = $null
        try { $null = $binding.Invoke() } catch { $failure = $_ }
        $cause = if ($failure) { $failure.Exception } else { $null }
        while ($cause -and $cause.InnerException) { $cause = $cause.InnerException }
        Assert-Discovery ($cause -is [Management.Automation.ParameterBindingException] -and
            $cause.ErrorRecord.FullyQualifiedErrorId -eq 'MissingMandatoryParameter,LibTmux.Workspace.PowerShell.GetTmuxWorkspaceCommand') 'SearchIn without Search did not fail noninteractive mandatory binding'
    } finally { $binding.Dispose() }

    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Search 'ALPHA') @($configuredFile) 'default filename search ignores case'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Search 'ALPHA' -CaseSensitive) @() 'explicit ordinal filename search'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Search 'a.*') @() 'search does not interpret regular expressions'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Search 'configured' -SearchIn FileName) @() 'filename search does not include parent path'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Search 'configured' -SearchIn Path) @($configuredFile) 'path search includes parent directory'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Search 'CONFIGURED' -SearchIn Path -CaseSensitive) @() 'path search honors case sensitivity'
    $hostMarker = Join-Path $fixture.FullName 'host-search-must-not-run'
    $declaration = @{
        session_name = 'Deploy-App'
        start_directory = '${PROJECT_ROOT}'
        before_script = "touch '$hostMarker'"
        shell_command_before = @('printf session-before-token')
        windows = @(@{
                window_name = 'Logs-Window'
                start_directory = 'window-directory-token'
                shell_command_before = @('printf window-before-token')
                panes = @(@{
                        shell_command = @('printf pane-command-token')
                        shell_command_before = @('printf pane-before-token')
                        start_directory = 'pane-directory-token'
                    })
            })
    }
    [IO.File]::WriteAllText($configuredFile, ($declaration | ConvertTo-Json -Depth 6))
    foreach ($case in @(
            @{ Text = 'deploy-app'; Field = 'Session' }, @{ Text = 'logs-window'; Field = 'Window' },
            @{ Text = 'session-before-token'; Field = 'Command' }, @{ Text = 'window-before-token'; Field = 'Command' },
            @{ Text = 'pane-before-token'; Field = 'Command' }, @{ Text = 'pane-command-token'; Field = 'Command' },
            @{ Text = 'host-search-must-not-run'; Field = 'Command' }, @{ Text = '${PROJECT_ROOT}'; Field = 'Directory' },
            @{ Text = 'window-directory-token'; Field = 'Directory' }, @{ Text = 'pane-directory-token'; Field = 'Directory' }
        )) {
        Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Search $case.Text -SearchIn $case.Field) @($configuredFile) "explicit $($case.Field) search"
    }
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Search 'LOGS-WINDOW' -SearchIn Window -CaseSensitive) @() 'explicit field case sensitivity'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Search 'Deploy' -SearchIn @('FileName', 'Session')) @($configuredFile) 'search fields combine by OR'
    Assert-Discovery (!(Test-Path -LiteralPath $hostMarker)) 'search executed a host command'

    $malformed = Join-Path $configured.FullName 'malformed.yaml'
    [IO.File]::WriteAllText($malformed, 'windows: [')
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Search 'malformed') @($malformed) 'filename search did not parse'
    Assert-DiscoveryOrder (LibTmux.Workspace\Get-TmuxWorkspace -Search 'configured' -SearchIn Path) @($configuredFile, $malformed) 'path search parsed malformed content'
    $errors = @()
    $rows = @(LibTmux.Workspace\Get-TmuxWorkspace -Search 'Deploy' -SearchIn Session -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-Discovery ($rows.Count -eq 0 -and $errors.Count -eq 1 -and
        $errors[0].CategoryInfo.Category -eq 'InvalidData' -and
        $errors[0].Exception -is [LibTmux.Workspace.WorkspaceFormatException] -and
        $errors[0].Exception.Data['WorkspacePath'] -ceq $malformed -and
        $errors[0].TargetObject -ceq 'Deploy') 'content failure published an incomplete list or lost native file context'
    [IO.File]::Delete($malformed)

    $many = $fixture.CreateSubdirectory('many')
    for ($index = 0; $index -lt 1022; $index++) {
        [IO.File]::WriteAllText((Join-Path $many.FullName ("{0:D4}.txt" -f $index)), '')
    }
    $errors = @()
    $rows = @(LibTmux.Workspace\Get-TmuxWorkspace -ConfigurationDirectory $many.FullName -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-Discovery ($rows.Count -eq 0 -and $errors.Count -eq 1 -and
        $errors[0].CategoryInfo.Category -eq 'InvalidData' -and
        $errors[0].Exception.Message -like '*1024*') 'entry limit silently truncated or ignored unrelated filenames'

    $cancel = [Threading.CancellationTokenSource]::new()
    try {
        $cancel.Cancel()
        $flags = [Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::Public -bor [Reflection.BindingFlags]::NonPublic
        $type = [LibTmux.Workspace.PowerShell.GetTmuxWorkspaceCommand].Assembly.GetType('LibTmux.Workspace.PowerShell.WorkspaceDiscovery', $true)
        $constructor = $type.GetConstructor($flags, $null, [type[]] @([Threading.CancellationToken]), $null)
        $discovery = $constructor.Invoke([object[]] @($cancel.Token))
        $failure = $null
        try { $null = $type.GetMethod('AddLiteral', $flags).Invoke($discovery, [object[]] @([string] (Join-Path $fixture.FullName 'absent-cancelled.yaml'))) } catch { $failure = $_ }
        $cause = if ($failure) { $failure.Exception } else { $null }
        while ($cause -and $cause.InnerException) { $cause = $cause.InnerException }
        Assert-Discovery ($cause -is [OperationCanceledException]) 'pre-cancelled discovery reached filesystem admission'
    } finally { $cancel.Dispose() }
} finally {
    if ($locationPushed) { Pop-Location }
    foreach ($variable in $savedDiscoveryEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($variable, $savedDiscoveryEnvironment[$variable])
    }
    $fixture.Delete($true)
}
'PASS workspace discovery: literal files, deterministic precedence, ambiguity, bounded search, native errors and cancellation admission'
