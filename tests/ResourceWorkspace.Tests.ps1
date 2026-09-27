param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: use the modules saved by PSResourceGet against owned tmux.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$modules = (Resolve-Path -LiteralPath $ModuleRoot).Path

Import-Module LibTmux.Workspace -RequiredVersion '0.1.0' -ErrorAction Stop
$core = @(Get-Module LibTmux)
$workspace = @(Get-Module LibTmux.Workspace)
foreach ($entry in @(@{ Name = 'LibTmux'; Loaded = $core },
        @{ Name = 'LibTmux.Workspace'; Loaded = $workspace })) {
    $expected = Join-Path $modules "$($entry.Name)/0.1.0"
    if ($entry.Loaded.Count -ne 1 -or $entry.Loaded[0].ModuleBase -cne $expected) {
        throw "The package consumer loaded another $($entry.Name) module."
    }
}
$assemblies = @([AppDomain]::CurrentDomain.GetAssemblies().Where({ $_.GetName().Name -eq 'LibTmux' }))
if ($assemblies.Count -ne 1 -or
    [LibTmux.Workspace.WorkspaceBuilder].Assembly.GetReferencedAssemblies().Where({ $_.Name -eq 'LibTmux' }).FullName -cne $assemblies[0].FullName) {
    throw 'The package consumer did not load one shared LibTmux assembly.'
}
if ($env:TMUX -or $env:TMUX_PANE) { throw 'The package consumer inherited an ambient tmux endpoint.' }

. "$PSScriptRoot/support/OwnedTmux.ps1"

Invoke-WithOwnedTmux {
    param($fixture)

    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $workspaceFile = LibTmux.Workspace\Import-TmuxWorkspace -Yaml @'
session_name: resource-consumer
windows:
  - window_name: editor
    panes:
      - shell_command: exec /bin/sh
      - shell_command: exec /bin/sh
'@
    $plan = $workspaceFile | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server `
        -ServerStartup RequireExisting -ExistingSession Error -ErrorAction Stop
    if ($plan -isnot [LibTmux.Workspace.WorkspacePlan] -or
        -not [object]::ReferenceEquals($plan.Endpoint, $server) -or
        @($plan.Actions | Where-Object Kind -eq SplitPane).Count -ne 1) {
        throw 'The saved workspace module did not plan the two-pane declaration.'
    }

    $before = (Invoke-OwnedTmux $fixture -Arguments @('list-sessions', '-F', '#S')).StdOut.Trim()
    $preview = @($plan | LibTmux.Workspace\Invoke-TmuxWorkspace -WhatIf)
    $after = (Invoke-OwnedTmux $fixture -Arguments @('list-sessions', '-F', '#S')).StdOut.Trim()
    if ($preview.Count -ne 0 -or $before -cne 'fixture' -or $after -cne $before) {
        throw 'WhatIf emitted a result or changed the owned tmux server.'
    }

    $result = $null
    try {
        $result = $plan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
        Register-OwnedTmuxPane $fixture
        if ($result -isnot [LibTmux.Workspace.WorkspaceResult] -or
            $result.Session -isnot [LibTmux.Session] -or
            $result.Session.Name -cne 'resource-consumer' -or
            $result.Windows.Count -ne 1 -or
            $result.Windows[0] -isnot [LibTmux.Window] -or
            $result.Windows[0].Name -cne 'editor' -or
            $result.Windows[0].Panes.Count -ne 2 -or
            @($result.Windows[0].Panes | Where-Object { $_ -isnot [LibTmux.Pane] }).Count -ne 0 -or
            @($result.Windows[0].Panes.Id | Select-Object -Unique).Count -ne 2) {
            throw 'The installed package did not return a native two-pane workspace graph.'
        }
        $sessions = (Invoke-OwnedTmux $fixture -Arguments @('list-sessions', '-F', '#S')).StdOut.Trim().Split("`n")
        if ($sessions.Count -ne 2 -or $sessions -cnotcontains 'fixture' -or
            $sessions -cnotcontains 'resource-consumer') {
            throw 'Workspace application changed an unexpected session.'
        }
    } finally {
        if ($result -is [LibTmux.Workspace.WorkspaceResult] -and
            $result.Session -is [LibTmux.Session]) {
            $result.Session | LibTmux\Remove-TmuxSession -Confirm:$false -ErrorAction Stop
        }
    }
    $remaining = (Invoke-OwnedTmux $fixture -Arguments @('list-sessions', '-F', '#S')).StdOut.Trim()
    $daemonPid = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid}')).StdOut.Trim()
    if ($remaining -cne 'fixture' -or [int] $daemonPid -ne $fixture.ServerPid) {
        throw 'Workspace cleanup removed the borrowed fixture server or left its session.'
    }
}
'PASS saved workspace package consumer: by-name dependency, reviewed plan, preview, native graph and owned cleanup'
