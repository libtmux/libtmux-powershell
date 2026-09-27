param(
    [string] $ModuleRoot,
    [switch] $RunExamples,
    [ValidateSet('All', 'Lifecycle', 'Operations', 'Planning')]
    [string] $ExampleGroup = 'All'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot

function Get-GuideDocumentUnit([IO.FileInfo[]] $Files) {
    if (!$Files) {
        $Files = @(Get-Item "$root/README.md") + @(Get-ChildItem "$root/docs" -Filter '*.md' -Recurse |
            Where-Object { !$_.FullName.StartsWith("$root/docs/reference/", [StringComparison]::Ordinal) })
    }
    $units = @{}
    foreach ($file in $files) {
        $text = [IO.File]::ReadAllText($file.FullName).Replace("`r`n", "`n")
        # Fail closed on CommonMark fence forms the small source extractor does not support.
        $openings = [regex]::Matches($text, '(?im)^[ \t>0-9.)*+-]*(?:`{3,}|~{3,})[ \t]*(?:powershell|pwsh|ps1)(?:[ \t][^\n]*)?$')
        foreach ($opening in $openings) {
            if ($opening.Value -notmatch '^```(?:powershell|pwsh|ps1)(?:[ \t][^\n]*)?$') {
                throw "Unsupported guide fence: $($file.Name)"
            }
        }
        $blocks = [regex]::Matches($text, '(?im)^```(?:powershell|pwsh|ps1)(?:[ \t][^\n]*)?\n(?<code>[\s\S]*?)^```[ \t]*$')
        if ($blocks.Count -ne $openings.Count) { throw "Unparsed guide fence: $($file.Name)" }
        $fileIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($match in $blocks) {
            $before = $text.Substring(0, $match.Index)
            $marker = [regex]::Match($before, '<!-- example: (?<id>[a-z][a-z0-9.-]+) -->\s*\z')
            if (!$marker.Success) { throw "Unregistered guide fence: $($file.Name)" }
            $id = $marker.Groups['id'].Value
            if (!$fileIds.Add($id)) { throw "Duplicate guide example in $($file.Name): $id" }
            $code = $match.Groups['code'].Value.TrimEnd("`n")
            if ($units.ContainsKey($id)) {
                if ($units[$id] -cne $code) { throw "Guide copy drift: $id" }
            } else {
                $units[$id] = $code
            }
        }
        foreach ($marker in [regex]::Matches($text, '<!-- example: (?<id>[a-z][a-z0-9.-]+) -->')) {
            if (!$fileIds.Contains($marker.Groups['id'].Value)) { throw "Guide marker has no fence: $($marker.Groups['id'].Value)" }
        }
    }
    $units
}

function Assert-Guide([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Guide assertion: $Message" }
}

function Get-GuideField($Context, [string] $Target, [string] $Format) {
    (Invoke-OwnedTmux $Context.Fixture -Arguments @('display-message', '-p', '-t', $Target, $Format)).StdOut.TrimEnd("`n")
}

$assertions = @{
    'query.01-capture' = @{ Group = 'Query'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.Captured -is [LibTmux.Server] -and $o.Captured.Panes.Count -eq 2 -and
                $o.Captured.Windows.Count -eq 1 -and $o.Captured.Sessions.Count -eq 1 -and
                $o.Captured.Sessions[0].Name -ceq 'development' -and
                (Get-GuideTraceCount $o.Context) -gt $o.BeforeDispatch) 'explicit query capture'
            $o.Context.Captured = $o.Captured
        } }
    'query.02-native' = @{ Group = 'Query'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.Pane] -and $o.Result[0].Width -eq 59 -and
                $o.Result[0].Height -eq 30 -and
                [object]::ReferenceEquals($o.Result[0], $o.Captured.Panes[0])) 'native local size selection'
        } }
    'query.03-criteria' = @{ Group = 'Query'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.Query -is [LibTmux.Query.QueryDocument] -and
                $o.Query.Target -eq [LibTmux.Query.QueryTarget]::Pane -and $o.Query.Version -eq 2) 'reusable native criteria'
            $o.Context.Query = $o.Query
        } }
    'query.04-select' = @{ Group = 'Query'; Count = 1; Assert = {
            param($o)
            Assert-Guide ([object]::ReferenceEquals($o.Result[0], $o.Captured.Panes[0]) -and
                $o.Result[0].Width -eq 59 -and $o.Result[0].Window.Panes.Count -eq 2 -and
                $o.Result[0].Window.Panes[1].Width -eq 40) 'structured match preserves the excluded child in its graph'
        } }
    'query.05-fields' = @{ Group = 'Query'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.Query.QueryFieldDescriptor] -and
                $o.Result[0].ScalarPropertyPath -ceq 'Width' -and
                $o.Result[0].Operators -ccontains 'greaterThanOrEqual') 'native discovery operator vocabulary'
        } }
    'query.06-related' = @{ Group = 'Query'; Count = 1; Assert = {
            param($o)
            Assert-Guide ([object]::ReferenceEquals($o.Result[0], $o.Captured.Windows[0]) -and
                $o.Result[0].Panes.Count -eq 2 -and
                @($o.Result[0].Panes | Where-Object { $_.Width -ge 50 -and $_.Height -gt 0 }).Count -eq 1) 'correlated captured relation criteria'
        } }
    'query.07-boolean' = @{ Group = 'Query'; Count = 1; Assert = {
            param($o)
            Assert-Guide ([object]::ReferenceEquals($o.Result[0], $o.Captured.Windows[0]) -and
                $o.Result[0].Name -ceq 'api-editor') 'Boolean prefix and exclusion criteria'
        } }
    'query.08-regex' = @{ Group = 'Query'; Count = 1; Assert = {
            param($o)
            Assert-Guide ([object]::ReferenceEquals($o.Result[0], $o.Captured.Windows[0]) -and
                $o.Result[0].Name.StartsWith('api-', [StringComparison]::Ordinal)) 'explicit case-insensitive regex criteria'
        } }
    'query.09-json' = @{ Group = 'Query'; Count = 1; Assert = {
            param($o)
            $restored = $o.Result[0]
            $restoredPanes = @($o.Captured.Panes | Select-TmuxPane -Query $restored)
            Assert-Guide ($restored -is [LibTmux.Query.QueryDocument] -and
                ($restored | ConvertTo-TmuxQueryJson) -ceq ($o.Query | ConvertTo-TmuxQueryJson) -and
                $restoredPanes.Count -eq 1 -and [object]::ReferenceEquals($restoredPanes[0], $o.Captured.Panes[0])) 'query JSON round-trip preserves native matching'
        } }
    'query.10-plan' = @{ Group = 'Query'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.QueryPlan -is [LibTmux.Query.QueryPlan[LibTmux.Pane]] -and
                $o.QueryPlan.DaemonVersion -eq $o.Captured.DaemonVersion -and
                $o.QueryPlan.Pushdown -eq [LibTmux.Query.QueryPushdown]::Auto -and
                $o.QueryPlan.RequiredSnapshotDepth -eq [LibTmux.SnapshotDepth]::Panes -and
                $o.QueryPlan.RequiredFields.Count -eq 2 -and $null -ne $o.QueryPlan.ResidualPredicate) 'pure observed-version query plan'
            $o.Context.QueryPlan = $o.QueryPlan
        } }
    'query.11-execute' = @{ Group = 'Query'; Count = 1; Assert = {
            param($o)
            $result = $o.Result[0]
            Assert-Guide ($result -is [LibTmux.Query.QueryResult[LibTmux.Pane]] -and
                $result.Count -eq 1 -and $result.Snapshot.Panes.Count -eq 2 -and
                $result[0].Width -eq 59 -and $result.Snapshot.Panes[1].Width -eq 40 -and
                [object]::ReferenceEquals($result[0], $result.Snapshot.Panes[0]) -and
                ![object]::ReferenceEquals($result[0], $o.Captured.Panes[0]) -and
                (Get-GuideTraceCount $o.Context) -gt $o.BeforeDispatch) 'explicit query result keeps its complete fresh observation'
        } }
    'query.12-one' = @{ Group = 'Query'; Count = 1; Assert = {
            param($o)
            Assert-Guide ([object]::ReferenceEquals($o.Result[0], $o.Captured.Sessions[0]) -and
                $o.Result[0].Name -ceq 'development') 'exact native session selection'
        } }
    'read.endpoint' = @{ Group = 'Pure'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.Server -is [LibTmux.Server] -and !$o.Server.IsMaterialized -and
                $o.Server.ConnectionOptions.SocketName -cmatch '^libtmux-readme-[a-f0-9]{32}$') 'endpoint identity'
        } }
    'readme.install.import' = @{ Group = 'Pure'; Count = 0; Prepare = {
            param($c)
            $c.PriorReviewModuleRoot = $env:LIBTMUX_REVIEW_MODULE_ROOT
            $env:LIBTMUX_REVIEW_MODULE_ROOT = $ModuleRoot
        }; Assert = {
            param($o)
            try {
                foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
                    $loaded = @(Get-Module -Name $name)
                    Assert-Guide ($loaded.Count -eq 1 -and
                        $loaded[0].ModuleBase -ceq (Join-Path $ModuleRoot "$name/0.1.0")) 'README exact staged module import'
                }
            } finally { $env:LIBTMUX_REVIEW_MODULE_ROOT = $o.Context.PriorReviewModuleRoot }
        } }
    'readme.quickstart' = @{ Group = 'Readme'; Count = 2; Assert = {
            param($o)
            Assert-Guide ($o.Result[0].Name -ceq 'editor' -and
                $o.Result[0].PaneIds -ceq '%0, %1' -and
                $o.Result[1].Name -ceq 'logs' -and
                $o.Result[1].PaneIds -ceq '%2') 'README quick start window and pane IDs'
        } }
    'readme.create' = @{ Group = 'Readme'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.Captured -is [LibTmux.Session] -and $o.Captured.Name -ceq 'demo' -and
                $o.Captured.Panes.Count -eq 3 -and $o.Captured.Windows.Count -eq 2 -and
                $o.Captured.Windows[0].Name -ceq 'editor' -and $o.Captured.Windows[1].Name -ceq 'logs' -and
                $o.Captured.Windows[0].Panes.Count -eq 2 -and
                $o.Captured.Windows[1].Panes.Count -eq 1) 'captured split session'
            $o.Context.Captured = $o.Captured
            $sessions = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Split("`n")
            Assert-Guide ($sessions -cnotcontains 'demo' -and $sessions -ccontains 'fixture') 'demo cleanup and unrelated session'
        } }
    'readme.filter' = @{ Group = 'Readme'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0].Name -ceq 'editor' -and $o.Result[0].PaneCount -eq 2 -and
                (Get-GuideTraceCount $o.Context) -eq $o.BeforeDispatch) 'local captured window filtering'
        } }
    'readme.related' = @{ Group = 'Readme'; Count = 1; Assert = {
            param($o)
            Assert-Guide ([object]::ReferenceEquals($o.Result[0], $o.Captured.Windows[0]) -and
                $o.Result[0].Panes.Count -eq 2 -and
                (Get-GuideTraceCount $o.Context) -eq $o.BeforeDispatch) 'local captured pane-count selection'
        } }
    'readme.input' = @{ Group = 'Readme'; Count = -1; Assert = {
            param($o)
            Assert-Guide ($o.Result -ccontains 'hello from PowerShell' -and
                @($o.Result | Where-Object { $_ -isnot [string] }).Count -eq 0) 'input completion and captured output'
            $sessions = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Split("`n")
            Assert-Guide ($sessions -cnotcontains 'input-demo' -and $sessions -ccontains 'fixture') 'input cleanup and unrelated session'
        } }
    'readme.control' = @{ Group = 'Readme'; Count = 1; Assert = {
            param($o)
            $sessions = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Split("`n")
            Assert-Guide ($o.Result[0] -is [string] -and $o.Result[0] -ceq 'control-demo' -and
                $sessions -cnotcontains 'control-demo' -and $sessions -ccontains 'fixture' -and
                @($o.Server | Get-TmuxClient).Count -eq 0) 'README control reply and owned cleanup'
        } }
    'watch.job-create' = @{ Group = 'Watch'; Count = 0; Assert = {
            param($o)
            $o.Context.Job = $o.Job
            Assert-Guide ($o.Job -is [Management.Automation.Job]) 'thread job handle'
        } }
    'watch.job-receive' = @{ Group = 'Watch'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.TmuxEvent] -and @($o.Server | Get-TmuxClient).Count -eq 0 -and
                $null -eq (Get-Job -Id $o.Job.Id -ErrorAction SilentlyContinue)) 'thread job native result and owned cleanup'
        } }
    'watch.parallel' = @{ Group = 'Watch'; Count = 2; Assert = {
            param($o)
            Assert-Guide (($o.Result | Sort-Object) -join '|' -ceq 'first|second' -and
                @($o.Result | Where-Object { $_ -isnot [string] }).Count -eq 0 -and
                @($o.Server | Get-TmuxClient).Count -eq 0) 'parallel native replies and client cleanup'
        } }
    'commands.chain' = @{ Group = 'Commands'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.TmuxCommandResult] -and $o.Result[0].ExitCode -eq 0 -and
                [string]::Join('|', $o.Result[0].StandardOutputLines) -ceq 'first|second') 'chain merged result'
        } }
    'commands.control' = @{ Group = 'Commands'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [string] -and $o.Result[0] -ceq 'fixture' -and
                @($o.Server | Get-TmuxClient).Count -eq 0 -and
                (Get-GuideField $o.Context 'fixture:0.0' '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}') -ceq $o.Context.Anchor) 'control reply, client cleanup and borrowed topology'
        } }
    'layout.pane-size' = @{ Group = 'Settings'; Count = 1; Prepare = {
            param($c)
            $c.Window = $c.Session | Get-TmuxWindow | Select-Object -First 1
            $null = $c.Window | Set-TmuxWindowSize -Width 120 -Height 40 -PassThru
            $null = $c.Pane | Split-TmuxPane -Horizontal -Command 'exec /bin/cat'
        }; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.Pane] -and $o.Result[0].Width -eq 40 -and
                (Get-GuideField $o.Context $o.Pane.Id.ToString() '#{pane_width}') -ceq '40') 'pane size readback and live width'
        } }
    'layout.select' = @{ Group = 'Settings'; Count = 1; Assert = {
            param($o)
            $panes = @($o.Result[0] | Get-TmuxPane)
            Assert-Guide ($o.Result[0] -is [LibTmux.Window] -and $panes.Count -eq 2 -and
                [Math]::Abs($panes[0].Width - $panes[1].Width) -le 1 -and $panes[0].Height -eq 40) 'horizontal layout geometry'
        } }
    'layout.window-size' = @{ Group = 'Settings'; Count = 1; Prepare = {
            param($c)
            $null = $c.Window | Set-TmuxWindowSize -Width 100 -Height 30 -PassThru
        }; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.Window] -and $o.Result[0].Width -eq 120 -and
                $o.Result[0].Height -eq 40 -and
                (Get-GuideField $o.Context $o.Window.Id.ToString() '#{window_width}x#{window_height}') -ceq '120x40') 'window size observed and live dimensions'
        } }
    'layout.zoom' = @{ Group = 'Settings'; Count = 0; Assert = {
            param($o)
            Assert-Guide ((Get-GuideField $o.Context $o.Pane.Id.ToString() '#{window_zoomed_flag}') -ceq '1') 'zoom toggle applied'
        } }
    'clients.read' = @{ Group = 'Clients'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.Client] -and $o.Result[0].Name -ceq $o.Client.Name -and $o.Result[0].IsControlClient) 'native attached client listing'
        } }
    'clients.refresh' = @{ Group = 'Clients'; Count = 1; Prepare = {
            param($c)
            $other = $c.Server | New-TmuxSession -Name 'client-other' -Command 'exec /bin/cat'
            $c.OtherId = $other.Id
            $null = Invoke-OwnedTmux $c.Fixture -Arguments @('switch-client', '-c', $c.Client.Name, '-t', $other.Id.ToString())
        }; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.Client] -and $o.Result[0].AttachedSessionId -eq $o.Context.OtherId -and
                $o.Client.AttachedSessionId -ne $o.Context.OtherId) 'replacement client captures changed session'
        } }
    'clients.attachment' = @{ Group = 'Clients'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.ClientAttachment] -and
                $o.Result[0].Session.Id -eq $o.Client.AttachedSessionId -and
                $o.Result[0].Window -is [LibTmux.Window] -and $o.Result[0].Pane -is [LibTmux.Pane]) 'live native client attachment'
        } }
    'options.read' = @{ Group = 'Settings'; Count = 1; Prepare = {
            param($c)
            $null = Invoke-OwnedTmux $c.Fixture -Arguments @('set-option', '-g', 'status-keys', 'vi')
        }; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.TmuxOption] -and $o.Result[0].Value.Raw -ceq 'vi' -and $o.Result[0].Inherited) 'native inherited option'
        } }
    'options.set' = @{ Group = 'Settings'; Count = 1; Assert = {
            param($o)
            $actual = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('show-options', '-v', '-t', $o.Session.Id.ToString(), '@project')).StdOut.TrimEnd("`n")
            Assert-Guide ($o.Result[0] -is [LibTmux.TmuxOptionValue] -and $o.Result[0].Raw -ceq 'api' -and $actual -ceq 'api') 'stored option readback'
        } }
    'options.remove' = @{ Group = 'Settings'; Count = 0; Prepare = {
            param($c)
            $null = Invoke-OwnedTmux $c.Fixture -Arguments @('set-option', '-t', $c.Session.Id.ToString(), '@scratch', 'temporary')
        }; Assert = {
            param($o)
            $actual = Invoke-OwnedTmux $o.Context.Fixture -Arguments @('show-options', '-q', '-t', $o.Session.Id.ToString(), '@scratch')
            Assert-Guide ($actual.StdOut -ceq '') 'removed user option'
        } }
    'hooks.read' = @{ Group = 'Settings'; Count = 1; Prepare = {
            param($c)
            $null = Invoke-OwnedTmux $c.Fixture -Arguments @('set-hook', '-t', $c.Session.Id.ToString(), 'alert-bell[7]', 'display-message seven')
        }; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.TmuxHook] -and $o.Result[0].Name -ceq 'alert-bell' -and
                @($o.Result[0].Values | Where-Object Index -EQ 7).Count -eq 1) 'grouped hook entry'
        } }
    'hooks.set' = @{ Group = 'Settings'; Count = 1; Assert = {
            param($o)
            $entry = $o.Result[0].Values | Where-Object Index -EQ 7
            $actual = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('show-hooks', '-t', $o.Session.Id.ToString(), 'alert-bell')).StdOut
            Assert-Guide ($o.Result[0] -is [LibTmux.TmuxHook] -and $entry.Command.Contains('build finished') -and
                $actual.Contains('alert-bell[7]') -and $actual.Contains('build finished')) 'indexed hook stored readback'
        } }
    'hooks.invoke' = @{ Group = 'Settings'; Count = 0; Prepare = {
            param($c)
            $null = Invoke-OwnedTmux $c.Fixture -Arguments @('set-hook', '-t', $c.Session.Id.ToString(), 'alert-bell', 'wait-for -S guide-hook-completed')
        }; Assert = {
            param($o)
            Assert-Guide ($o.Context.Server | Wait-TmuxChannel -Channel 'guide-hook-completed' -Timeout 0.5) 'hook completion signal'
        } }
    'hooks.remove' = @{ Group = 'Settings'; Count = 0; Prepare = {
            param($c)
            foreach ($index in @(7, 19)) {
                $null = Invoke-OwnedTmux $c.Fixture -Arguments @('set-hook', '-t', $c.Session.Id.ToString(), "alert-bell[$index]", "display-message $index")
            }
        }; Assert = {
            param($o)
            $actual = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('show-hooks', '-t', $o.Session.Id.ToString(), 'alert-bell')).StdOut
            Assert-Guide (!$actual.Contains('alert-bell[7]') -and $actual.Contains('alert-bell[19]')) 'indexed hook removal preserves neighbour'
        } }
    'environment.read' = @{ Group = 'Settings'; Count = 1; Prepare = {
            param($c)
            $null = Invoke-OwnedTmux $c.Fixture -Arguments @('set-environment', '-t', $c.Session.Id.ToString(), 'APP_MODE', 'development')
        }; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.TmuxEnvironmentEntry] -and $o.Result[0].Value -ceq 'development' -and
                !$o.Result[0].IsRemoved) 'native environment value'
        } }
    'environment.set' = @{ Group = 'Settings'; Count = 1; Assert = {
            param($o)
            $actual = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('show-environment', '-t', $o.Session.Id.ToString(), 'APP_MODE')).StdOut.TrimEnd("`n")
            Assert-Guide ($o.Result[0] -is [LibTmux.TmuxEnvironmentEntry] -and $o.Result[0].Value -ceq 'development' -and
                $actual -ceq 'APP_MODE=development') 'stored environment readback'
        } }
    'environment.unset' = @{ Group = 'Settings'; Count = 0; Prepare = {
            param($c)
            $null = Invoke-OwnedTmux $c.Fixture -Arguments @('set-environment', '-t', $c.Session.Id.ToString(), 'APP_MODE', 'development')
        }; Assert = {
            param($o)
            $actual = Invoke-OwnedTmux $o.Context.Fixture -Arguments @('show-environment', '-t', $o.Session.Id.ToString(), 'APP_MODE') -AllowFailure
            Assert-Guide ($actual.ExitCode -ne 0 -and $actual.StdErr.Contains('unknown variable')) 'unset removes the local entry'
        } }
    'environment.mark-removed' = @{ Group = 'Settings'; Count = 0; Prepare = {
            param($c)
            $null = Invoke-OwnedTmux $c.Fixture -Arguments @('set-environment', '-g', 'APP_MODE', 'inherited')
        }; Assert = {
            param($o)
            $actual = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('show-environment', '-t', $o.Session.Id.ToString(), 'APP_MODE')).StdOut.TrimEnd("`n")
            Assert-Guide ($actual -ceq '-APP_MODE') 'explicit environment removal marker'
        } }
    'workspace.01-load' = @{ Group = 'Workspace'; Count = 0; Prepare = {
            param($c)
            $c.ProjectRoot = [IO.Directory]::CreateDirectory((Join-Path $c.Fixture.DirectoryPath 'project')).FullName
            $c.WorkspacePath = Join-Path $c.Fixture.DirectoryPath 'development.yaml'
            $text = [IO.File]::ReadAllText("$root/docs/workspace.md")
            $declaration = [regex]::Match($text.Replace("`r`n", "`n"), '(?m)<!-- declaration: workspace.basic -->\s*^```yaml\n(?<yaml>[\s\S]*?)^```$')
            Assert-Guide $declaration.Success 'workspace guide declaration missing'
            [IO.File]::WriteAllText($c.WorkspacePath, $declaration.Groups['yaml'].Value)
        }; Assert = {
            param($o)
            Assert-Guide ($o.Workspace -is [LibTmux.Workspace.WorkspaceFile] -and
                $o.Workspace.SessionName -ceq 'development' -and
                $o.Workspace.DocumentDirectory -ceq $o.Context.Fixture.DirectoryPath -and
                $o.Workspace.StartDirectory -ceq $o.Context.ProjectRoot -and
                $o.Workspace.Windows.Count -eq 1 -and $o.Workspace.Windows[0].Panes.Count -eq 2 -and
                $o.Workspace.Windows[0].Panes[1].StartDirectory -ceq $o.Context.ProjectRoot) 'native file import and explicit inherited resolution'
            $o.Context.Workspace = $o.Workspace
        } }
    'workspace.02-validate' = @{ Group = 'Workspace'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [bool] -and $o.Result[0]) 'pure workspace validation'
        } }
    'workspace.03-plan' = @{ Group = 'Workspace'; Count = 0; Assert = {
            param($o)
            $plan = $o.WorkspacePlan
            Assert-Guide ($plan -is [LibTmux.Workspace.WorkspacePlan] -and
                [object]::ReferenceEquals($plan.Endpoint, $o.Server) -and
                $plan.SessionName -ceq 'development' -and $plan.ExistingSessionPolicy -eq 'Error' -and
                $plan.ServerStartup -eq 'CreateOrJoin' -and $plan.Readiness -eq 'Immediate' -and
                @($plan.Actions | Where-Object Kind -eq RunHostScript).Count -eq 0 -and
                $plan.Actions[$plan.Actions.Count - 1].Kind -eq 'CaptureResult' -and
                (Get-GuideTraceCount $o.Context) -gt $o.BeforeDispatch) 'explicit endpoint plan with frozen policies'
            Assert-Guide ((Invoke-OwnedTmux $o.Context.Fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.TrimEnd("`n") -ceq 'fixture') 'planning created a session'
            $o.Context.WorkspacePlan = $plan
        } }
    'workspace.04-review' = @{ Group = 'Workspace'; Count = -1; Assert = {
            param($o)
            Assert-Guide ($o.Result.Count -eq $o.WorkspacePlan.Actions.Count) 'review action cardinality'
            for ($index = 0; $index -lt $o.Result.Count; $index++) {
                Assert-Guide ($o.Result[$index] -is [LibTmux.Workspace.WorkspaceAction] -and
                    [object]::ReferenceEquals($o.Result[$index], $o.WorkspacePlan.Actions[$index])) 'review exact native action'
            }
        } }
    'workspace.05-preview' = @{ Group = 'Workspace'; Count = 0; Assert = {
            param($o)
            Assert-Guide ((Get-GuideTraceCount $o.Context) -eq $o.BeforeDispatch) 'workspace preview dispatched'
        } }
    'workspace.06-apply' = @{ Group = 'Workspace'; Count = 0; Prepare = {
            param($c)
            [IO.File]::Delete($c.WorkspacePath)
        }; Assert = {
            param($o)
            $result = $o.WorkspaceResult
            Assert-Guide ($result -is [LibTmux.Workspace.WorkspaceResult] -and
                $result.Session.Name -ceq 'development' -and $result.Windows.Count -eq 1 -and
                $result.Windows[0].Name -ceq 'editor' -and $result.Windows[0].Panes.Count -eq 2 -and
                $result.Unsupported.Count -eq 0 -and $result.Journal.Count -eq $o.WorkspacePlan.Actions.Count -and
                (Get-GuideTraceCount $o.Context) -gt $o.BeforeDispatch) 'applied the reviewed declaration after its source file was removed'
            for ($index = 0; $index -lt $result.Journal.Count; $index++) {
                Assert-Guide ([object]::ReferenceEquals($result.Journal[$index].Action, $o.WorkspacePlan.Actions[$index]) -and
                    $result.Journal[$index].State -eq [LibTmux.Workspace.WorkspaceActionState]::Completed) 'workspace exact-plan completed journal'
            }
            $panes = $result.Windows[0].Panes
            Assert-Guide ($panes[0].CurrentPath -ceq $o.Context.ProjectRoot -and
                $panes[1].CurrentPath -ceq $o.Context.ProjectRoot -and
                [Math]::Abs($panes[0].Width - $panes[1].Width) -le 1 -and
                $panes[0].Height -eq $panes[1].Height -and
                ($panes[0] | Get-TmuxOption -Name '@role').Value.Raw -ceq 'editor' -and
                $result.Windows[0].ActivePane.Value.Id -eq $panes[1].Id) 'workspace directory, layout, pane option and final focus'
            Assert-Guide ((Get-GuideField $o.Context 'fixture:0.0' '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}') -ceq $o.Context.Anchor) 'workspace preserved unrelated anchor'
            $o.Context.WorkspaceResult = $result
        } }
    'workspace.07-export' = @{ Group = 'Workspace'; Count = 0; Prepare = {
            param($c)
            $c.ExportPath = Join-Path $c.Fixture.DirectoryPath 'export [literal] $workspace.yaml'
        }; Assert = {
            param($o)
            $path = $o.ExportPath
            Assert-Guide (Test-Path -LiteralPath $path -PathType Leaf) 'workspace export file missing'
            $exported = Get-Item -LiteralPath $path | Import-TmuxWorkspace -ErrorAction Stop
            Assert-Guide ($exported -is [LibTmux.Workspace.WorkspaceFile] -and
                $exported.SessionName -ceq 'development' -and $exported.Windows.Count -eq 1 -and
                $exported.Windows[0].Panes.Count -eq 2 -and
                @($exported.Windows | ForEach-Object { $_.Panes } | ForEach-Object { $_.ShellCommands }).Count -eq 0 -and
                (Get-GuideTraceCount $o.Context) -gt $o.BeforeDispatch) 'exported captured structure without invented commands'
        } }
    'workspace.08-edit' = @{ Group = 'Workspace'; Count = 0; Prepare = {
            param($c)
            $path = Join-Path $c.Fixture.DirectoryPath 'edited [literal] $workspace.yaml'
            $c.EditorSibling = Join-Path $c.Fixture.DirectoryPath 'editor-sibling.yaml'
            $c.EditorTrace = Join-Path $c.Fixture.DirectoryPath 'editor-arguments'
            [IO.File]::WriteAllText($path, 'session_name: before-edit')
            [IO.File]::WriteAllText($c.EditorSibling, 'session_name: sibling')
            $c.WorkspaceFile = Get-TmuxWorkspace -LiteralPath $path -ErrorAction Stop
            $program = Join-Path $c.Fixture.DirectoryPath 'editor.sh'
            $quotedTrace = ConvertTo-GuideShellLiteral $c.EditorTrace
            $c.EditorProgram = "#!/bin/sh`nprintf '%s\0' `"`$@`" > $quotedTrace`nfor selected do :; done`nprintf 'session_name: after-edit\n' > `"`$selected`"`nexit 0`n"
            [IO.File]::WriteAllText($program, $c.EditorProgram)
            [IO.File]::SetUnixFileMode($program, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
            $c.Editor = Get-Command -Name $program -CommandType Application -ErrorAction Stop
            $c.EditorArguments = [string[]] @('space value', 'quote"value', '', '$(printf not-executed); *')
        }; Assert = {
            param($o)
            $c = $o.Context
            $expected = [string]::Join([char] 0, @($c.EditorArguments) + @($c.WorkspaceFile.FullName)) + [char] 0
            Assert-Guide ([IO.File]::ReadAllText($c.EditorTrace) -ceq $expected) 'editor exact argv and literal final path'
            Assert-Guide (($c.WorkspaceFile | Import-TmuxWorkspace -ErrorAction Stop).SessionName -ceq 'after-edit' -and
                [IO.File]::ReadAllText($c.EditorSibling) -ceq 'session_name: sibling' -and
                $o.WorkspacePlan.SessionName -ceq 'development') 'editor selected file changes without rewriting the frozen plan'
            Assert-Guide ($o.EditorPreferences -ceq 'Continue|Legacy|True') 'editor source preferences escaped its child scope'
            $workspaceFile, $editor, $editorArguments = $c.WorkspaceFile, $c.Editor, $c.EditorArguments
            try {
                [IO.File]::WriteAllText($editor.Path, $c.EditorProgram.Replace('exit 0', 'exit 23'))
                Assert-GuideRejection { & $sources['workspace.08-edit'].Code } 'Editor exited with code 23.'
                $missingInterpreter = Join-Path $c.Fixture.DirectoryPath 'missing-editor-interpreter'
                [IO.File]::WriteAllText($editor.Path, "#!$missingInterpreter`n")
                $LASTEXITCODE = 0
                $launchFailed = $false
                try { & $sources['workspace.08-edit'].Code } catch {
                    if ($_.Exception.Message -like '*Editor exited with code*') { throw }
                    $launchFailed = $_.FullyQualifiedErrorId -like 'NativeCommandFailed*'
                }
                Assert-Guide $launchFailed 'editor launch failure reused a previous zero exit status'
                Assert-Guide ([IO.File]::ReadAllText($c.EditorTrace) -ceq $expected -and
                    [IO.File]::ReadAllText($c.EditorSibling) -ceq 'session_name: sibling') 'editor failure changed arguments or sibling file'
            } finally {
                [IO.File]::WriteAllText($editor.Path, $c.EditorProgram)
            }
        } }
    'readme.workspace.01-import' = @{ Group = 'Workspace'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.Workspace -is [LibTmux.Workspace.WorkspaceFile] -and
                $o.Workspace.Windows.Count -eq 1 -and $o.Workspace.Windows[0].Panes.Count -eq 2) 'README workspace import'
            $o.Context.Workspace = $o.Workspace
        } }
    'readme.workspace.02-plan' = @{ Group = 'Workspace'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.WorkspacePlan -is [LibTmux.Workspace.WorkspacePlan] -and
                $o.WorkspacePlan.SessionName -ceq 'readme-workspace-preview' -and
                @($o.WorkspacePlan.Actions | Where-Object Kind -eq 'CreateWindow').Count -eq 1 -and
                @($o.WorkspacePlan.Actions | Where-Object Kind -eq 'SplitPane').Count -eq 1) 'README workspace plan'
            $o.Context.WorkspacePlan = $o.WorkspacePlan
        } }
    'readme.workspace.03-review' = @{ Group = 'Workspace'; Count = -1; Assert = {
            param($o)
            Assert-Guide ($o.Result.Count -eq $o.WorkspacePlan.Actions.Count) 'README workspace review actions'
        } }
    'readme.workspace.04-preview' = @{ Group = 'Workspace'; Count = 0; Assert = {
            param($o)
            $sessions = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Split("`n")
            Assert-Guide ($sessions -cnotcontains 'readme-workspace-preview') 'README workspace preview created a session'
        } }
    'readme.workspace.05-apply' = @{ Group = 'Workspace'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.WorkspaceResult -is [LibTmux.Workspace.WorkspaceResult] -and
                $o.WorkspaceResult.Session -is [LibTmux.Session] -and
                $o.WorkspaceResult.Session.Name -ceq 'readme-workspace-preview' -and
                $o.WorkspaceResult.Windows.Count -eq 1 -and
                $o.WorkspaceResult.Windows[0].Panes.Count -eq 2 -and
                (Get-GuideTraceCount $o.Context) -gt $o.BeforeDispatch) 'README workspace native result'
            $sessions = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Split("`n")
            Assert-Guide ($sessions -cnotcontains 'readme-workspace-preview') 'README workspace apply left its session'
            $o.Context.WorkspaceResult = $o.WorkspaceResult
        } }
    'readme.workspace.06-graph' = @{ Group = 'Workspace'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0].Name -ceq 'editor' -and
                $o.Result[0].PaneCount -eq 2) 'README workspace captured graph'
        } }
    'capture.lines' = @{ Group = 'Capture'; Count = -1; Assert = {
            param($o)
            Assert-Guide ($o.Result -ccontains 'guide-ready' -and $o.Result -cnotcontains 'history-00' -and
                @($o.Result | Where-Object { $_ -isnot [string] }).Count -eq 0) 'visible captured lines'
        } }
    'capture.history' = @{ Group = 'Capture'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [string] -and $o.Result[0].Contains($o.Context.ExpectedHistory) -and
                $o.Result[0].Contains(('w' * 120))) 'history and joined wrapped output'
        } }
    'capture.range' = @{ Group = 'Capture'; Count = -1; Assert = {
            param($o)
            $native = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('capture-pane', '-p', '-t',
                    $o.Pane.Id.ToString(), '-S', '-10', '-E', '4')).StdOut
            Assert-Guide ([string]::Join("`n", $o.Result) -ceq $native.Substring(0, $native.Length - 1)) 'inclusive native capture range'
        } }
    'capture.refresh' = @{ Group = 'Capture'; Count = 0; Prepare = {
            param($c)
            $c.OldTitle = $c.Pane.Title
            $null = Invoke-OwnedTmux $c.Fixture -Arguments @('select-pane', '-t', $c.Pane.Id.ToString(), '-T', 'guide-refreshed')
        }; Assert = {
            param($o)
            Assert-Guide ($o.CurrentPane -is [LibTmux.Pane] -and $o.CurrentPane.Id -eq $o.Pane.Id -and
                ![object]::ReferenceEquals($o.Pane, $o.CurrentPane) -and $o.CurrentPane.Title -ceq 'guide-refreshed' -and
                $o.Pane.Title -ceq $o.Context.OldTitle) 'assigned refresh replacement'
        } }
    'capture.raw-list' = @{ Group = 'Capture'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.TmuxCommandResult] -and $o.Result[0].ExitCode -eq 0 -and
                $o.Result[0].StandardOutputLines.Count -eq 1 -and $o.Result[0].StandardOutputLines[0] -ceq 'fixture') 'raw session listing'
        } }
    'capture.buffer' = @{ Group = 'Capture'; Count = 1; Prepare = {
            param($c)
            $c.BeforeBuffers = (Invoke-OwnedTmux $c.Fixture -Arguments @('list-buffers', '-F', '#{buffer_name}') -AllowFailure).StdOut
        }; Assert = {
            param($o)
            $after = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('list-buffers', '-F', '#{buffer_name}') -AllowFailure).StdOut
            Assert-Guide ($o.Result[0] -is [string] -and $o.Result[0] -ceq 'hello from PowerShell' -and
                $after -ceq $o.Context.BeforeBuffers) 'raw named buffer round trip and cleanup'
        } }
    'capture.raw-preview' = @{ Group = 'Capture'; Count = 0; Assert = {
            param($o)
            Assert-Guide ((Get-GuideTraceCount $o.Context) -eq $o.BeforeDispatch) 'raw preview dispatched'
        } }
    'create.session' = @{ Group = 'Create'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.Session -is [LibTmux.Session] -and
                (Get-GuideField $o.Context $o.Session.Id.ToString() '#{session_name}|#{window_name}|#{window_width}|#{window_height}') -ceq
                'work|editor|100|30') 'assigned session identity and geometry'
        } }
    'create.window' = @{ Group = 'Create'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.Window -is [LibTmux.Window] -and
                (Get-GuideField $o.Context $o.Window.Id.ToString() '#{window_name}|#{window_index}|#{window_active}') -ceq
                'tools|5|1') 'assigned active window at index 5'
        } }
    'create.split' = @{ Group = 'Create'; Count = 0; Assert = {
            param($o)
            $left = Get-GuideField $o.Context $o.NewPane.Id.ToString() '#{pane_left}|#{pane_width}|#{pane_active}'
            $targetLeft = [int] (Get-GuideField $o.Context $o.Pane.Id.ToString() '#{pane_left}')
            Assert-Guide ($o.NewPane -is [LibTmux.Pane] -and $o.NewPane.Id -ne $o.Pane.Id -and
                $left -ceq '0|20|0' -and $targetLeft -eq 21) 'assigned left split size and selection'
        } }
    'create.command' = @{ Group = 'Create'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.Window -is [LibTmux.Window] -and
                (Get-GuideField $o.Context $o.Window.Id.ToString() '#{window_name}|#{pane_current_command}') -ceq 'shell|sh') 'assigned shell window'
        } }
    'create.environment' = @{ Group = 'Create'; Count = 0; Prepare = {
            param($c)
            $c.HostMode = [Environment]::GetEnvironmentVariable('APP_MODE')
            $c.HostOptional = [Environment]::GetEnvironmentVariable('OPTIONAL')
            $c.EnvironmentFile = Join-Path $c.Fixture.DirectoryPath 'child-environment'
            $program = Join-Path $c.Fixture.DirectoryPath 'environment.sh'
            $quotedTmux = ConvertTo-GuideShellLiteral $c.Fixture.TmuxPath
            $quotedSocket = ConvertTo-GuideShellLiteral $c.Fixture.SocketPath
            $quotedOutput = ConvertTo-GuideShellLiteral $c.EnvironmentFile
            @"
#!/bin/sh
printf '%s|%s|%s' "`$APP_MODE" "`${OPTIONAL+x}" "`$OPTIONAL" > $quotedOutput
$quotedTmux -S $quotedSocket wait-for -S guide-environment
exec /bin/sh
"@ | Set-Content -LiteralPath $program
            $null = Invoke-OwnedTmux $c.Fixture -Arguments @('set-option', '-g', 'default-command', "/bin/sh '$program'")
        }; Assert = {
            param($o)
            $null = Invoke-OwnedTmux $o.Context.Fixture -Arguments @('wait-for', 'guide-environment')
            Assert-Guide ($o.Window -is [LibTmux.Window] -and [IO.File]::ReadAllText($o.Context.EnvironmentFile) -ceq 'development|x|' -and
                [Environment]::GetEnvironmentVariable('APP_MODE') -ceq $o.Context.HostMode -and
                [Environment]::GetEnvironmentVariable('OPTIONAL') -ceq $o.Context.HostOptional) 'assigned child environment and unchanged host'
        } }
    'placement.01-link' = @{ Group = 'Placement'; Count = 0; Prepare = {
            param($c)
            $c.SourceSession = $c.Server | New-TmuxSession -Name 'guide-placement-source' -Command 'exec /bin/sh'
            $c.Window = $c.SourceSession | Get-TmuxWindow
        }; Assert = {
            param($o)
            $linked = @($o.Session | Get-TmuxWindow | Where-Object { $_.Id -eq $o.Window.Id -and $_.Index -eq 5 })
            Assert-Guide ($linked.Count -eq 1 -and $linked[0].EntityKey.SessionId -eq $o.Session.Id -and
                @($o.Context.SourceSession | Get-TmuxWindow | Where-Object Id -EQ $o.Window.Id).Count -eq 1) 'linked one captured window into destination session'
            $o.Context.SourceWindow = $o.Window
        } }
    'placement.02-select' = @{ Group = 'Placement'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.Window -is [LibTmux.Window] -and
                $o.Window.Id -eq $o.Context.SourceWindow.Id -and $o.Window.Index -eq 5 -and
                $o.Window.EntityKey.SessionId -eq $o.Session.Id -and
                $o.Context.SourceWindow.EntityKey.SessionId -eq $o.Context.SourceSession.Id) 'read selected the destination link, not the source placement'
            $o.Context.Window = $o.Window
        } }
    'placement.03-move' = @{ Group = 'Placement'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.Window -is [LibTmux.Window] -and $o.Window.Index -eq 6 -and
                $o.Window.EntityKey.SessionId -eq $o.Session.Id -and $o.Context.Window.Index -eq 5 -and
                @($o.Session | Get-TmuxWindow | Where-Object { $_.Id -eq $o.Window.Id -and $_.Index -eq 6 }).Count -eq 1) 'move returned replacement placement'
            $o.Context.Window = $o.Window
        } }
    'placement.04-remove' = @{ Group = 'Placement'; Count = 0; Assert = {
            param($o)
            Assert-Guide (@($o.Session | Get-TmuxWindow | Where-Object Id -EQ $o.Window.Id).Count -eq 0 -and
                @($o.Context.SourceSession | Get-TmuxWindow | Where-Object Id -EQ $o.Window.Id).Count -eq 1) 'unlink removed only the destination placement'
        } }
    'remove.preview' = @{ Group = 'Remove'; Count = 0; Prepare = {
            param($c)
            $c.Session = $c.Server | New-TmuxSession -Name 'guide-preview' -Command 'exec /bin/sh'
        }; Assert = {
            param($o)
            Assert-Guide ((Get-GuideTraceCount $o.Context) -eq $o.BeforeDispatch -and
                (Get-GuideField $o.Context $o.Session.Id.ToString() '#{session_name}') -ceq 'guide-preview') 'session preview dispatched or removed target'
        } }
    'remove.session' = @{ Group = 'Remove'; Count = 0; Prepare = {
            param($c)
            $c.Session = $c.Server | New-TmuxSession -Name 'guide-session' -Command 'exec /bin/sh'
        }; Assert = {
            param($o)
            $ids = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('list-sessions', '-F', '#{session_id}')).StdOut.Split("`n")
            Assert-Guide ($ids -cnotcontains $o.Session.Id.ToString()) 'session target remains'
        } }
    'remove.window' = @{ Group = 'Remove'; Count = 0; Prepare = {
            param($c)
            $c.Window = $c.AnchorSession | New-TmuxWindow -Name 'guide-shared' -Command 'exec /bin/sh'
            $other = $c.Server | New-TmuxSession -Name 'guide-links' -Command 'exec /bin/sh'
            $c.LinkedSession = $other.Id.ToString()
            $null = Invoke-OwnedTmux $c.Fixture -Arguments @('link-window', '-s', $c.Window.Id.ToString(), '-t', "$($other.Id):5")
            $null = Invoke-OwnedTmux $c.Fixture -Arguments @('link-window', '-s', $c.Window.Id.ToString(), '-t', "$($other.Id):6")
        }; Assert = {
            param($o)
            $ids = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('list-windows', '-a', '-F', '#{window_id}')).StdOut.Split("`n")
            Assert-Guide ($ids -cnotcontains $o.Window.Id.ToString() -and
                (Get-GuideField $o.Context $o.Context.LinkedSession '#{session_name}') -ceq 'guide-links') 'shared window links or unrelated session'
        } }
    'remove.pane' = @{ Group = 'Remove'; Count = 0; Prepare = {
            param($c)
            $target = $c.Server | New-TmuxSession -Name 'guide-cascade' -Command 'exec /bin/sh'
            $c.Pane = $target | Get-TmuxPane
            $c.CascadeSession = $target.Id.ToString()
        }; Assert = {
            param($o)
            $ids = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('list-panes', '-a', '-F', '#{pane_id}')).StdOut.Split("`n")
            $sessions = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('list-sessions', '-F', '#{session_id}')).StdOut.Split("`n")
            Assert-Guide ($ids -cnotcontains $o.Pane.Id.ToString() -and $sessions -cnotcontains $o.Context.CascadeSession) 'last-pane cascade'
        } }
}

function Assert-GuideRegistration($Documents, $Sources, $Assertions) {
    foreach ($id in $Documents.Keys) {
        if (!$Sources.ContainsKey($id)) { throw "Guide source missing: $id" }
        if ($Documents[$id] -cne $Sources[$id].Code.ToString().Trim()) { throw "Guide source drift: $id" }
    }
    foreach ($id in $Sources.Keys) {
        if (!$Documents.ContainsKey($id)) { throw "Guide source has no document: $id" }
        if (!$Assertions.ContainsKey($id)) { throw "Guide assertion missing: $id" }
        $entry = $Assertions[$id]
        if ($entry.Assert -isnot [scriptblock] -or $entry.Count -isnot [int] -or $entry.Count -lt -1 -or
            $entry.Group -cnotin @('Pure', 'Capture', 'Create', 'Remove', 'Placement', 'Readme', 'Settings', 'Clients', 'Commands', 'Watch', 'Query', 'Workspace') -or
            ($entry.ContainsKey('Prepare') -and $entry.Prepare -isnot [scriptblock])) { throw "Guide assertion invalid: $id" }
        $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseInput($Documents[$id], [ref] $null, [ref] $parseErrors)
        if ($parseErrors.Count) { throw "Guide syntax invalid: $id" }
    }
    foreach ($id in $Assertions.Keys) {
        if (!$Sources.ContainsKey($id)) { throw "Guide assertion has no source: $id" }
    }
}

function Assert-GuideSourceFile([string[]] $Files) {
    if (Compare-Object @('Guides.ps1', 'QuickStart.ps1') $Files) { throw 'Guide source file registration differs.' }
}

function Assert-GuideExecutionGroup($Groups, $Assertions) {
    if (Compare-Object @('Lifecycle', 'Operations', 'Planning') @($Groups.Keys)) {
        throw 'Guide execution child registration differs.'
    }
    $registered = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Assertions.Values) { $null = $registered.Add($entry.Group) }
    $assigned = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($groupsInChild in $Groups.Values) {
        foreach ($group in $groupsInChild) {
            if (!$registered.Contains($group)) { throw "Guide execution group has no assertions: $group" }
            if (!$assigned.Add($group)) { throw "Guide execution group repeated: $group" }
        }
    }
    foreach ($group in $registered) {
        if (!$assigned.Contains($group)) { throw "Guide execution group missing: $group" }
    }
}

function Assert-GuideRejection([scriptblock] $Body, [string] $Message) {
    $rejected = $false
    try { & $Body } catch {
        if ($_.Exception.Message -cne $Message) { throw }
        $rejected = $true
    }
    if (!$rejected) { throw "Guide negative control accepted: $Message" }
}

# Copied-document controls must reject unregistered fences even when their syntax varies.
$copied = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-powershell-guide-markdown-' + [Guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -ItemType Directory -Path $copied
    $path = Join-Path $copied 'guide-negative.md'
    $original = [IO.File]::ReadAllText("$root/README.md")
    foreach ($fence in @('~~~PowerShell', '~~~~pwsh', '````powershell', ' ```powershell', '   ```PS1', '``` powershell', '> ```pwsh', '- ```powershell')) {
        $closing = [regex]::Match($fence, '[`~]+').Value
        [IO.File]::WriteAllText($path, $original + "`n$fence`n'not registered'`n$closing`n")
        Assert-GuideRejection { $null = Get-GuideDocumentUnit @(Get-Item $path) } 'Unsupported guide fence: guide-negative.md'
    }
    foreach ($fence in @('```PowerShell', '```pwsh')) {
        [IO.File]::WriteAllText($path, $original + "`n$fence`n'not registered'`n" + '```' + "`n")
        Assert-GuideRejection { $null = Get-GuideDocumentUnit @(Get-Item $path) } 'Unregistered guide fence: guide-negative.md'
    }
    [IO.File]::WriteAllText($path, $original + "`n" + '```powershell' + "`n'not registered'`n" + '````' + "`n")
    Assert-GuideRejection { $null = Get-GuideDocumentUnit @(Get-Item $path) } 'Unparsed guide fence: guide-negative.md'
    $firstCopy = Join-Path $copied 'guide-copy-a.md'
    $secondCopy = Join-Path $copied 'guide-copy-b.md'
    $opening = '<!-- example: readme.input -->' + "`n" + '```powershell' + "`n"
    [IO.File]::WriteAllText($firstCopy, $opening + "'same'`n" + '```' + "`n")
    [IO.File]::WriteAllText($secondCopy, $opening + "'same'`n" + '```' + "`n")
    if ((Get-GuideDocumentUnit @((Get-Item $firstCopy), (Get-Item $secondCopy))).Count -ne 1) {
        throw 'Identical guide copies did not share one executable unit.'
    }
    [IO.File]::WriteAllText($secondCopy, $opening + "'different'`n" + '```' + "`n")
    Assert-GuideRejection {
        $null = Get-GuideDocumentUnit @((Get-Item $firstCopy), (Get-Item $secondCopy))
    } 'Guide copy drift: readme.input'
} finally {
    if (Test-Path -LiteralPath $copied) { Remove-Item -LiteralPath $copied -Recurse -Force }
}
$documents = Get-GuideDocumentUnit
$sourceFiles = @(Get-ChildItem "$root/examples" -Filter '*.ps1' -Recurse | ForEach-Object { [IO.Path]::GetRelativePath("$root/examples", $_.FullName) })
Assert-GuideSourceFile $sourceFiles
$sources = & "$root/examples/Guides.ps1"
Assert-GuideRegistration $documents $sources $assertions
$omitted = $assertions.Clone()
$omitted.Remove('capture.history')
Assert-GuideRejection { Assert-GuideRegistration $documents $sources $omitted } 'Guide assertion missing: capture.history'
$extra = $assertions.Clone()
$extra['missing.example'] = $assertions['capture.history']
Assert-GuideRejection { Assert-GuideRegistration $documents $sources $extra } 'Guide assertion has no source: missing.example'
$missing = $documents.Clone()
$missing.Remove('capture.history')
Assert-GuideRejection { Assert-GuideRegistration $missing $sources $assertions } 'Guide source has no document: capture.history'
$missingSource = $sources.Clone()
$missingSource.Remove('capture.history')
Assert-GuideRejection { Assert-GuideRegistration $documents $missingSource $assertions } 'Guide source missing: capture.history'
$drifted = $documents.Clone()
$drifted['capture.history'] += ' -WhatIf'
Assert-GuideRejection { Assert-GuideRegistration $drifted $sources $assertions } 'Guide source drift: capture.history'
Assert-GuideRejection { Assert-GuideSourceFile @('Guides.ps1', 'unregistered.ps1') } 'Guide source file registration differs.'
$executionGroups = @{
    Lifecycle = @('Pure', 'Capture', 'Create', 'Remove', 'Readme')
    Operations = @('Settings', 'Clients', 'Commands', 'Watch', 'Placement')
    Planning = @('Query', 'Workspace')
}
Assert-GuideExecutionGroup $executionGroups $assertions
$missingGroup = $executionGroups.Clone()
$missingGroup['Planning'] = @('Query')
Assert-GuideRejection { Assert-GuideExecutionGroup $missingGroup $assertions } 'Guide execution group missing: Workspace'
$duplicateGroup = $executionGroups.Clone()
$duplicateGroup['Planning'] += 'Capture'
Assert-GuideRejection { Assert-GuideExecutionGroup $duplicateGroup $assertions } 'Guide execution group repeated: Capture'
"PASS $($sources.Count) guide units: source/document/assertion discovery, drift and negative controls"
if (!$RunExamples) { return }
if (!$ModuleRoot) { throw '-ModuleRoot is required with -RunExamples.' }
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
foreach ($module in @('LibTmux', 'LibTmux.Workspace')) {
    Import-Module (Join-Path $ModuleRoot "$module/0.1.0/$module.psd1")
}
. "$PSScriptRoot/support/OwnedTmux.ps1"

function ConvertTo-GuideShellLiteral([string] $Value) { "'" + $Value.Replace("'", "'\''") + "'" }
function Get-GuideTraceCount($Context) {
    if (Test-Path -LiteralPath $Context.Trace) { [IO.File]::ReadAllLines($Context.Trace).Length } else { 0 }
}

function Assert-GuideCleanup($Fixture) {
    Assert-Guide ($Fixture.Closed -and !(Test-Path $Fixture.DirectoryPath) -and !(Test-Path $Fixture.SocketPath)) 'owned files remain'
    foreach ($processId in $Fixture.OwnedProcessIds) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($process) { $process.Dispose(); throw 'Guide cleanup left an owned process.' }
    }
}

function Invoke-GuideFixture([Alias('Setup')] [scriptblock] $GuideSetup, [Alias('Body')] [scriptblock] $GuideBody,
    [Threading.CancellationToken] $CancellationToken = [Threading.CancellationToken]::None) {
    $state = @{ Fixture = $null }
    try {
        Invoke-WithOwnedTmux -CancellationToken $CancellationToken -Setup {
            param($fixture)
            $state.Fixture = $fixture
            & $GuideSetup $fixture
        } -Body $GuideBody
    } finally {
        if ($state.Fixture) { Assert-GuideCleanup $state.Fixture }
    }
}

function Initialize-GuideContext($Fixture, [hashtable] $Context, [string] $Group) {
    $Context.Fixture = $Fixture
    $Context.Trace = Join-Path $Fixture.DirectoryPath 'dispatch'
    $wrapperName = if ($Group -eq 'Readme') { "tmux 'guide" } else { 'tmux' }
    $wrapper = Join-Path $Fixture.DirectoryPath $wrapperName
    $quotedTmux = ConvertTo-GuideShellLiteral $Fixture.TmuxPath
    $quotedTrace = ConvertTo-GuideShellLiteral $Context.Trace
    @"
#!/bin/sh
printf '%s\n' dispatch >> $quotedTrace
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    # Only 3.2a needs manual detached sizing; global manual sizing crashes tmux 3.4 on new-session.
    $version = (Invoke-OwnedTmux $Fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()
    if ($version -ceq '3.2a') {
        $null = Invoke-OwnedTmux $Fixture -Arguments @('set-option', '-gw', 'window-size', 'manual')
    }
    if ($Group -eq 'Capture') {
        $program = Join-Path $Fixture.DirectoryPath 'capture.sh'
        $quotedSocket = ConvertTo-GuideShellLiteral $Fixture.SocketPath
        $wide = 'w' * 120
        @"
#!/bin/sh
i=0
while [ "`$i" -lt 40 ]; do printf 'history-%02d\n' "`$i"; i=`$((i + 1)); done
printf '%s\nguide-ready\n' '$wide'
$quotedTmux -S $quotedSocket wait-for -S guide-ready
exec /bin/cat
"@ | Set-Content -LiteralPath $program
        $null = Invoke-OwnedTmux $Fixture -Arguments @('respawn-pane', '-k', '-t', 'fixture:0.0', "/bin/sh '$program'")
        Register-OwnedTmuxPane $Fixture
        $null = Invoke-OwnedTmux $Fixture -Arguments @('wait-for', 'guide-ready')
        $Context.ExpectedHistory = 'history-00'
    }
    $Context.Server = New-TmuxServer -SocketPath $Fixture.SocketPath -TmuxBinaryPath $wrapper -ConfigurationFile '/dev/null'
    $Context.AnchorSession = $Context.Server | Get-TmuxSession -Name 'fixture'
    $Context.Session = $Context.AnchorSession
    $Context.Pane = $Context.AnchorSession | Get-TmuxPane
    $Context.Anchor = Get-GuideField $Context 'fixture:0.0' '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}'
    if ($Group -eq 'Query') {
        $null = Invoke-OwnedTmux $Fixture -Arguments @('resize-window', '-t', 'fixture:0', '-x', '100', '-y', '30')
        $null = Invoke-OwnedTmux $Fixture -Arguments @('split-window', '-h', '-d', '-l', '40', '-t', 'fixture:0.0', 'exec /bin/cat')
        $null = Invoke-OwnedTmux $Fixture -Arguments @('set-window-option', '-t', 'fixture:0', 'automatic-rename', 'off')
        $null = Invoke-OwnedTmux $Fixture -Arguments @('rename-window', '-t', 'fixture:0', 'api-editor')
        $null = Invoke-OwnedTmux $Fixture -Arguments @('rename-session', '-t', 'fixture', 'development')
    }
}

function Invoke-GuideUnit([string] $Id, [hashtable] $Context) {
    $entry = $assertions[$Id]
    if ($entry.ContainsKey('Prepare')) { & $entry.Prepare $Context }
    if ($entry.Group -ne 'Pure') { Register-OwnedTmuxPane $Context.Fixture }
    foreach ($required in $sources[$Id].Requires) {
        if (!$Context.ContainsKey($required) -or $null -eq $Context[$required]) { throw "Guide prerequisite missing: $Id/$required" }
    }
    $server, $session, $pane, $window = $Context['Server'], $Context['Session'], $Context['Pane'], $Context['Window']
    $client = $Context['Client']
    $job = $Context['Job']
    $currentPane = $newPane = $null
    $captured = $Context['Captured']
    $query, $queryPlan = $Context['Query'], $Context['QueryPlan']
    $workspacePath, $projectRoot = $Context['WorkspacePath'], $Context['ProjectRoot']
    $workspace, $workspacePlan, $workspaceResult = $Context['Workspace'], $Context['WorkspacePlan'], $Context['WorkspaceResult']
    $workspaceFile, $editor, $editorArguments = $Context['WorkspaceFile'], $Context['Editor'], $Context['EditorArguments']
    $exportPath = $Context['ExportPath']
    if ($Id -ceq 'workspace.08-edit') {
        $ErrorActionPreference = 'Continue'
        $PSNativeCommandArgumentPassing = 'Legacy'
        $PSNativeCommandUseErrorActionPreference = $true
    }
    $before = if ($entry.Group -ne 'Pure') { Get-GuideTraceCount $Context } else { 0 }
    $result = @(. $sources[$Id].Code)
    $Context.Executed.Add($Id)
    if ($entry.Group -eq 'Create' -or $Id -ceq 'workspace.06-apply') { Register-OwnedTmuxPane $Context.Fixture }
    Assert-Guide ($entry.Count -lt 0 -or $result.Count -eq $entry.Count) "$Id output cardinality"
    $observation = @{ Result = $result; Server = $server; Session = $session; Pane = $pane; Window = $window;
        Job = $job; Client = $client; CurrentPane = $currentPane; NewPane = $newPane; Captured = $captured; Query = $query; QueryPlan = $queryPlan;
        Workspace = $workspace; WorkspacePlan = $workspacePlan; WorkspaceResult = $workspaceResult; Context = $Context; BeforeDispatch = $before;
        WorkspaceFile = $workspaceFile; Editor = $editor; EditorArguments = $editorArguments; ExportPath = $exportPath;
        EditorPreferences = "$ErrorActionPreference|$PSNativeCommandArgumentPassing|$PSNativeCommandUseErrorActionPreference" }
    & $entry.Assert $observation
    if ($entry.Group -eq 'Query' -and $Id -cnotin @('query.01-capture', 'query.11-execute')) {
        Assert-Guide ((Get-GuideTraceCount $Context) -eq $before) "$Id local operation dispatched tmux"
    }
    if ($entry.Group -eq 'Workspace' -and $Id -cnotin @('readme.workspace.02-plan', 'readme.workspace.05-apply', 'workspace.03-plan', 'workspace.06-apply', 'workspace.07-export')) {
        Assert-Guide ((Get-GuideTraceCount $Context) -eq $before) "$Id local or preview operation dispatched tmux"
    }
    if ($entry.Group -eq 'Remove') {
        Assert-Guide ((Get-GuideField $Context 'fixture:0.0' '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}') -ceq $Context.Anchor) 'unrelated removal anchor'
    }
}

# Outer integration: exact guide operations run on owned fixtures, with readiness events.
if ($ExampleGroup -in @('All', 'Lifecycle')) {
    Assert-GuideRejection {
        Invoke-GuideFixture -Setup { param($fixture)
            Register-OwnedTmuxPane $fixture
            throw 'injected guide setup failure'
        } -Body { throw 'Guide body ran after failed setup.' }
    } 'injected guide setup failure'
    $cancellation = [Threading.CancellationTokenSource]::new()
    $cancelled = $false
    try {
        Invoke-GuideFixture -CancellationToken $cancellation.Token -Setup {
            param($fixture)
            $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', 'never-signalled') -OnStarted {
                param($client)
                Assert-Guide (!$client.HasExited) 'cancellation must reach a running owned client'
                $cancellation.Cancel()
            }
        } -Body { throw 'Guide body ran after cancellation.' }
    } catch {
        if ($_.Exception -isnot [OperationCanceledException]) { throw }
        $cancelled = $true
    } finally { $cancellation.Dispose() }
    Assert-Guide $cancelled 'guide setup cancellation was swallowed'
    $negative = @{ Executed = [Collections.Generic.List[string]]::new() }
    Assert-GuideRejection {
        Invoke-GuideFixture -Setup { param($fixture)
            Initialize-GuideContext $fixture $negative 'Capture'
            $negative.ExpectedHistory = 'intentionally-wrong-history'
        } -Body { Invoke-GuideUnit 'capture.history' $negative }
    } 'Guide assertion: history and joined wrapped output'
    Assert-Guide ($negative.Executed -contains 'capture.history') 'wrong-output control did not execute its real operation'
    'PASS guide setup failure, in-flight client cancellation and wrong live outcome; owned resources removed'
}
$completed = [Collections.Generic.List[string]]::new()
$selectedGroups = if ($ExampleGroup -eq 'All') {
    @('Lifecycle', 'Operations', 'Planning') | ForEach-Object { $executionGroups[$_] }
} else { $executionGroups[$ExampleGroup] }
$expected = @($sources.Keys | Where-Object { $assertions[$_].Group -cin $selectedGroups } | Sort-Object)
foreach ($group in $selectedGroups) {
    $context = @{ Executed = $completed }
    $run = {
        $control = $null
        try {
            if ($group -eq 'Clients') {
                $control = $context.Server.EnterControlModeAsync('fixture').GetAwaiter().GetResult()
                $context.Client = $context.Server.GetClientsAsync().GetAwaiter().GetResult()[0]
                $null = $context.Fixture.OwnedProcessIds.Add([int] $context.Client.RawFormatFields['client_pid'])
            }
            foreach ($id in $sources.Keys | Sort-Object) {
                if ($assertions[$id].Group -ceq $group) { Invoke-GuideUnit $id $context }
            }
            if ($group -eq 'Readme') {
                $wrapper = $context.Server.ConnectionOptions.TmuxBinaryPath
                $originalWrapper = [IO.File]::ReadAllText($wrapper)
                $rejection = @'
for argument in "$@"; do
    if [ "$argument" = split-window ]; then
        printf '%s\n' 'injected guide split failure' >&2
        exit 1
    fi
done
'@
                $failed = $false
                try {
                    [IO.File]::WriteAllText($wrapper, $originalWrapper.Replace("#!/bin/sh`n", "#!/bin/sh`n$rejection`n"))
                    try { Invoke-GuideUnit 'readme.create' $context } catch {
                        if ($_.FullyQualifiedErrorId -notlike 'Tmux.PaneSplitFailed,*' -or
                            $_.Exception.Message -notlike '*injected guide split failure*') { throw }
                        $failed = $true
                    }
                    Assert-Guide $failed 'demo accepted injected split failure'
                    $sessions = (Invoke-OwnedTmux $context.Fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Split("`n")
                    Assert-Guide ($sessions -cnotcontains 'demo' -and $sessions -ccontains 'fixture') 'demo failure cleanup and unrelated session'
                } finally { [IO.File]::WriteAllText($wrapper, $originalWrapper) }
            }
        } finally {
            if ($context.ContainsKey('Job') -and $context.Job -and (Get-Job -Id $context.Job.Id -ErrorAction SilentlyContinue)) {
                $context.Job | Stop-Job
                $context.Job | Remove-Job
            }
            if ($control) { $null = $control.DisposeAsync().AsTask().GetAwaiter().GetResult() }
        }
    }
    if ($group -eq 'Pure') { & $run } else {
        Invoke-GuideFixture -Setup { param($fixture) Initialize-GuideContext $fixture $context $group } -Body $run
    }
}
Assert-Guide ($completed.Count -eq $expected.Count -and
    !(Compare-Object $expected @($completed | Sort-Object))) 'selected guide execution differs from its registration'
"PASS $($completed.Count) $ExampleGroup guide operations, assigned results, native outcomes and owned cleanup"
