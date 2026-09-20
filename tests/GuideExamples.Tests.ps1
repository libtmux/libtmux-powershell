param([string] $ModuleRoot, [switch] $RunExamples)

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
            if ($units.ContainsKey($id)) { throw "Duplicate guide example: $id" }
            $null = $fileIds.Add($id)
            $units[$id] = $match.Groups['code'].Value.TrimEnd("`n")
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
    'read.endpoint' = @{ Group = 'Pure'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.Server -is [LibTmux.Server] -and !$o.Server.IsMaterialized -and
                $o.Server.ConnectionOptions.SocketName -ceq 'development') 'endpoint identity'
        } }
    'readme.create' = @{ Group = 'Readme'; Count = 0; Assert = {
            param($o)
            Assert-Guide ($o.Captured -is [LibTmux.Session] -and $o.Captured.Name -ceq 'demo' -and
                $o.Captured.Panes.Count -eq 2 -and $o.Captured.Windows.Count -eq 1 -and
                @($o.Captured.Panes | Where-Object { $_.Width -eq 40 }).Count -eq 1) 'captured split session'
            $o.Context.Captured = $o.Captured
            $sessions = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Split("`n")
            Assert-Guide ($sessions -cnotcontains 'demo' -and $sessions -ccontains 'fixture') 'demo cleanup and unrelated session'
        } }
    'readme.filter' = @{ Group = 'Readme'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0].Width -eq 59 -and $o.Result[0].Height -eq 30 -and
                $o.Result[0].Id -is [LibTmux.PaneId] -and (Get-GuideTraceCount $o.Context) -eq $o.BeforeDispatch) 'local captured pane filtering'
        } }
    'readme.input' = @{ Group = 'Readme'; Count = -1; Assert = {
            param($o)
            Assert-Guide ($o.Result -ccontains 'hello from PowerShell' -and
                @($o.Result | Where-Object { $_ -isnot [string] }).Count -eq 0) 'input completion and captured output'
            $sessions = (Invoke-OwnedTmux $o.Context.Fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Split("`n")
            Assert-Guide ($sessions -cnotcontains 'input-demo' -and $sessions -ccontains 'fixture') 'input cleanup and unrelated session'
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
    'workspace.parse' = @{ Group = 'Pure'; Count = 1; Assert = {
            param($o)
            Assert-Guide ($o.Result[0] -is [LibTmux.Workspace.WorkspaceFile] -and
                $o.Result[0].SessionName -ceq 'development') 'workspace session name'
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
            $entry.Group -cnotin @('Pure', 'Capture', 'Create', 'Remove', 'Readme', 'Settings', 'Clients') -or
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
    if (Compare-Object @('Guides.ps1') $Files) { throw 'Guide source file registration differs.' }
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
    $null = Invoke-OwnedTmux $Fixture -Arguments @('set-option', '-gw', 'window-size', 'manual')
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
    $currentPane = $newPane = $null
    $captured = $Context['Captured']
    $before = if ($entry.Group -ne 'Pure') { Get-GuideTraceCount $Context } else { 0 }
    $result = @(. $sources[$Id].Code)
    $Context.Executed.Add($Id)
    if ($entry.Group -eq 'Create') { Register-OwnedTmuxPane $Context.Fixture }
    Assert-Guide ($entry.Count -lt 0 -or $result.Count -eq $entry.Count) "$Id output cardinality"
    $observation = @{ Result = $result; Server = $server; Session = $session; Pane = $pane; Window = $window;
        Client = $client; CurrentPane = $currentPane; NewPane = $newPane; Captured = $captured; Context = $Context; BeforeDispatch = $before }
    & $entry.Assert $observation
    if ($entry.Group -eq 'Remove') {
        Assert-Guide ((Get-GuideField $Context 'fixture:0.0' '#{session_id}|#{window_id}|#{pane_id}|#{pane_pid}') -ceq $Context.Anchor) 'unrelated removal anchor'
    }
}

# Outer integration: exact guide operations run on owned fixtures, with readiness events.
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
$completed = [Collections.Generic.List[string]]::new()
foreach ($group in @('Pure', 'Capture', 'Create', 'Remove', 'Readme', 'Settings', 'Clients')) {
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
            if ($control) { $null = $control.DisposeAsync().AsTask().GetAwaiter().GetResult() }
        }
    }
    if ($group -eq 'Pure') { & $run } else {
        Invoke-GuideFixture -Setup { param($fixture) Initialize-GuideContext $fixture $context $group } -Body $run
    }
}
Assert-Guide ($completed.Count -eq $sources.Count) 'not every registered guide operation executed'
"PASS $($sources.Count) exact guide operations, assigned results, native outcomes and owned cleanup"
