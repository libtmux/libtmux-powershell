param([Parameter(Mandatory)] [string] $ModuleRoot)

# Integration: creation mutates an owned daemon and verifies native replacement handles.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-PhysicalDirectory([string] $Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($fullPath)
    $resolved = $root
    foreach ($segment in [IO.Path]::GetRelativePath($root, $fullPath).Split(
        [IO.Path]::DirectorySeparatorChar, [StringSplitOptions]::RemoveEmptyEntries)) {
        $candidate = [IO.Path]::Combine($resolved, $segment)
        $target = [IO.DirectoryInfo]::new($candidate).ResolveLinkTarget($true)
        $resolved = if ($target) { Resolve-PhysicalDirectory $target.FullName } else { $candidate }
    }
    $resolved
}

foreach ($name in @('New-TmuxSession', 'New-TmuxWindow', 'Split-TmuxPane')) {
    Assert-True ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "Installed module does not export $name."
}

. "$PSScriptRoot/support/OwnedTmux.ps1"
Invoke-WithOwnedTmux {
    param($fixture)

    # tmux 3.2a otherwise sizes detached windows from the command client.
    $version = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()
    if ($version -ceq '3.2a') {
        $null = Invoke-OwnedTmux $fixture -Arguments @('set-option', '-gw', 'window-size', 'manual')
    }
    $trace = Join-Path $fixture.DirectoryPath 'calls'
    $wrapper = Join-Path $fixture.DirectoryPath 'tmux'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    $quotedTrace = "'" + $trace.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' tmux >> $quotedTrace
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)

    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper -ConfigurationFile '/dev/null'
    $empty = @(@() | LibTmux\New-TmuxSession -WhatIf)
    Assert-True ($empty.Count -eq 0 -and -not (Test-Path $trace)) 'An empty owner pipeline acquired tmux or emitted a result.'
    $directoryParent = Join-Path $fixture.DirectoryPath 'physical parent'
    $directory = Join-Path $directoryParent 'working directory'
    $null = New-Item -ItemType Directory -Path $directory
    $directoryAliasParent = Join-Path $fixture.DirectoryPath 'alias parent'
    $null = New-Item -ItemType SymbolicLink -Path $directoryAliasParent -Target $directoryParent
    $directoryAlias = Join-Path $directoryAliasParent 'working directory'
    $literal = 'spaces; literal $value "quotes"'
    $creationEnvironment = @{ CREATE_VALUE = $literal; CREATE_EMPTY = '' }
    $session = & { $creationEnvironment.CREATE_VALUE = 'changed after binding'; $server } |
        LibTmux\New-TmuxSession -Name 'created session' -WindowName $literal -Width 100 -Height 30 `
            -StartDirectory $directoryAlias -Command 'exec /bin/sh' -Environment $creationEnvironment -Confirm:$false
    Register-OwnedTmuxPane $fixture
    Assert-True ($session -is [LibTmux.Session] -and $session.Name -ceq 'created session') 'Session creation did not emit its native captured session.'
    $window = $session | LibTmux\Get-TmuxWindow | Select-Object -First 1
    $pane = $window | LibTmux\Get-TmuxPane | Select-Object -First 1
    Assert-True ($window.Name -ceq $literal) "Session window name changed: '$($window.Name)'."
    Assert-True ($pane.Width -eq 100 -and $pane.Height -eq 30) "Session pane dimensions changed: $($pane.Width)x$($pane.Height)."
    Assert-True ($null -ne $pane.CurrentPath -and
        (Resolve-PhysicalDirectory $pane.CurrentPath) -ceq (Resolve-PhysicalDirectory $directoryAlias)) `
        "Session working directory changed: '$($pane.CurrentPath)'."
    $environment = Invoke-OwnedTmux $fixture -Arguments @('show-environment', '-t', $session.Id.ToString(), 'CREATE_VALUE')
    # tmux 3.4 escapes dollars when displaying values; the pane check below verifies actual bytes.
    $shownValue = if ($version -ceq '3.4') { $literal.Replace('$', '\$') } else { $literal }
    Assert-True ($environment.StdOut.TrimEnd("`r", "`n") -ceq "CREATE_VALUE=$shownValue") 'Creation changed an environment value argument.'
    Assert-True ($creationEnvironment.CREATE_VALUE -ceq 'changed after binding') 'Environment snapshot test did not mutate the original input.'
    $environment = Invoke-OwnedTmux $fixture -Arguments @('show-environment', '-t', $session.Id.ToString(), 'CREATE_EMPTY')
    Assert-True ($environment.StdOut.TrimEnd("`r", "`n") -ceq 'CREATE_EMPTY=') 'Creation lost an empty environment value.'

    $before = [IO.File]::ReadAllLines($trace).Length
    $preview = @($session | LibTmux\New-TmuxWindow -Name 'never' -WhatIf)
    $preview += @($pane | LibTmux\Split-TmuxPane -WhatIf)
    Assert-True ($preview.Count -eq 0 -and [IO.File]::ReadAllLines($trace).Length -eq $before) 'Window or pane WhatIf dispatched an acquisition or mutation.'

    $script = Join-Path $directory 'pane command.sh'
    $quotedSocket = "'" + $fixture.SocketPath.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' "`$CREATE_VALUE"
$quotedTmux -S $quotedSocket wait-for -S "`$1"
exec /bin/cat
"@ | Set-Content -LiteralPath $script
    $newWindow = $session | LibTmux\New-TmuxWindow -Name $literal -Index 5 -Activate -StartDirectory $directory `
        -Command "/bin/sh '$script' window-ready" -Environment @{ CREATE_VALUE = $literal } -Confirm:$false
    Register-OwnedTmuxPane $fixture
    $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', 'window-ready')
    Assert-True ($newWindow -is [LibTmux.Window] -and $newWindow.Index -eq 5 -and $newWindow.Name -ceq $literal) 'Window creation lost its native result, index or literal name.'
    $target = $newWindow | LibTmux\Get-TmuxPane | Select-Object -First 1
    Assert-True ($null -ne $target.CurrentPath -and
        (Resolve-PhysicalDirectory $target.CurrentPath) -ceq (Resolve-PhysicalDirectory $directory)) `
        "Window creation did not forward the start directory: '$($target.CurrentPath)'."
    $output = Invoke-OwnedTmux $fixture -Arguments @('capture-pane', '-p', '-t', $target.Id.ToString())
    Assert-True ($output.StdOut.Split("`n") -ccontains $literal) 'Window creation changed shell-command quoting or its process environment.'
    $active = Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $session.Id.ToString(), '#{window_id}')
    Assert-True ($active.StdOut.Trim() -ceq $newWindow.Id.ToString()) 'Activate did not select the new window.'

    $split = $target | LibTmux\Split-TmuxPane -Horizontal -Before -Size 20 -StartDirectory $directory `
        -Command "/bin/sh '$script' split-ready" -Environment @{ CREATE_VALUE = $literal } -Activate -Confirm:$false
    Register-OwnedTmuxPane $fixture
    $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', 'split-ready')
    Assert-True ($split -is [LibTmux.Pane] -and $split.Width -eq 20 -and
        $split.Height -eq $target.Height -and $split.AtLeft) 'Pane split lost direction, cell size or native output.'
    Assert-True ($null -ne $split.CurrentPath -and
        (Resolve-PhysicalDirectory $split.CurrentPath) -ceq (Resolve-PhysicalDirectory $directory)) `
        "Pane split did not forward the start directory: '$($split.CurrentPath)'."
    $output = Invoke-OwnedTmux $fixture -Arguments @('capture-pane', '-p', '-J', '-t', $split.Id.ToString())
    # Older tmux versions retain terminal-cell padding with capture-pane -J.
    Assert-True ($output.StdOut.Split("`n").TrimEnd([char] ' ') -ccontains $literal) 'Pane creation changed shell-command quoting or its process environment.'
    $active = Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $newWindow.Id.ToString(), '#{pane_id}')
    Assert-True ($active.StdOut.Trim() -ceq $split.Id.ToString()) 'Activate did not select the split pane.'
    $percent = $target | LibTmux\Split-TmuxPane -Percentage 30 -Command 'exec /bin/sh' -Confirm:$false
    Register-OwnedTmuxPane $fixture
    Assert-True ($percent -is [LibTmux.Pane] -and $percent.Height -gt 1 -and $percent.Height -lt $target.Height / 2) 'Percentage split did not create a smaller vertical pane.'

    $before = [IO.File]::ReadAllLines($trace).Length
    $invalid = $null
    try { $target | LibTmux\Split-TmuxPane -Size 10 -Percentage 25 -Confirm:$false | Out-Null }
    catch { $invalid = $_ }
    Assert-True ($null -ne $invalid -and [IO.File]::ReadAllLines($trace).Length -eq $before) 'Contradictory split sizing dispatched tmux.'
    $invalid = $null
    try { $server | LibTmux\New-TmuxSession -Environment @{ CREATE_VALUE = 42 } -Confirm:$false | Out-Null }
    catch { $invalid = $_ }
    Assert-True ($null -ne $invalid -and $invalid.FullyQualifiedErrorId -like 'Tmux.InvalidCreation,*' -and
        [IO.File]::ReadAllLines($trace).Length -eq $before) 'An invalid environment value was silently converted or dispatched.'

    $invalidEnvironments = @(
        @{ 'BAD=KEY' = 'value' }
        @{ '' = 'value' }
        @{ "BAD`0KEY" = 'value' }
        @{ 'KEY' = "before`0after" }
    )
    foreach ($targetCommand in @(
        @{ Name = 'New-TmuxSession'; Owner = $server }
        @{ Name = 'New-TmuxWindow'; Owner = $session }
        @{ Name = 'Split-TmuxPane'; Owner = $target }
    )) {
        foreach ($invalidEnvironment in $invalidEnvironments) {
            foreach ($preview in @($false, $true)) {
                $invalid = $null
                try {
                    $targetCommand.Owner | & "LibTmux\$($targetCommand.Name)" -Environment $invalidEnvironment `
                        -Command 'exec /bin/sh' -WhatIf:$preview -Confirm:$false | Out-Null
                } catch { $invalid = $_ }
                Assert-True ($null -ne $invalid -and $invalid.FullyQualifiedErrorId -like 'Tmux.InvalidCreation,*' -and
                    [IO.File]::ReadAllLines($trace).Length -eq $before) "$($targetCommand.Name) accepted or dispatched an ambiguous environment entry (WhatIf=$preview)."
            }
        }
    }

    $duplicate = $null
    try { $server | LibTmux\New-TmuxSession -Name 'created session' -Confirm:$false | Out-Null }
    catch { $duplicate = $_ }
    Assert-True ($null -ne $duplicate -and $duplicate.FullyQualifiedErrorId -like 'Tmux.SessionCreateFailed,*' -and
        $duplicate.Exception -is [LibTmux.TmuxSessionExistsException] -and $duplicate.TargetObject -eq $server) 'Duplicate session creation lost its core failure or target.'

    $unavailable = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath (Join-Path $fixture.DirectoryPath 'no-binary')
    $errors = @()
    $continued = @(@($unavailable, $server) | LibTmux\New-TmuxSession -Name 'continued' -Command 'exec /bin/sh' -Confirm:$false -ErrorAction Continue -ErrorVariable errors 2>$null)
    Register-OwnedTmuxPane $fixture
    Assert-True ($continued.Count -eq 1 -and $continued[0] -is [LibTmux.Session] -and $errors.Count -eq 1 -and
        $errors[0].FullyQualifiedErrorId -like 'Tmux.SessionCreateFailed,*' -and $errors[0].TargetObject -eq $unavailable -and
        $errors[0].Exception -is [LibTmux.LibTmuxException]) 'A failed session owner stopped later input or lost its error.'

    $stale = $server | LibTmux\New-TmuxSession -Name 'stale' -Command 'exec /bin/sh' -Confirm:$false
    $stalePane = $stale | LibTmux\Get-TmuxPane | Select-Object -First 1
    Register-OwnedTmuxPane $fixture
    $null = Invoke-OwnedTmux $fixture -Arguments @('kill-session', '-t', $stale.Id.ToString())
    $errors = @()
    $continued = @(@($stale, $session, $session) | LibTmux\New-TmuxWindow -Name 'continued' -Command 'exec /bin/sh' -Confirm:$false -ErrorAction Continue -ErrorVariable errors 2>$null)
    Register-OwnedTmuxPane $fixture
    Assert-True ($continued.Count -eq 2 -and $continued[0] -is [LibTmux.Window] -and $continued[1] -is [LibTmux.Window] -and
        $continued[0].Id -ne $continued[1].Id -and $errors.Count -eq 1 -and
        $errors[0].FullyQualifiedErrorId -like 'Tmux.WindowCreateFailed,*' -and $errors[0].TargetObject -eq $stale -and
        $errors[0].Exception -is [LibTmux.LibTmuxException]) 'A failed window owner stopped later input or lost its error.'
    $windowCount = @($session | LibTmux\Get-TmuxWindow).Count
    $stopped = $null
    try { @($stale, $session) | LibTmux\New-TmuxWindow -Name 'never' -Confirm:$false -ErrorAction Stop | Out-Null }
    catch { $stopped = $_ }
    Assert-True ($null -ne $stopped -and $stopped.FullyQualifiedErrorId -like 'Tmux.WindowCreateFailed,*' -and
        @($session | LibTmux\Get-TmuxWindow).Count -eq $windowCount) 'ErrorAction Stop allowed a later owner to create a window.'
    $errors = @()
    $continued = @(@($stalePane, $pane) | LibTmux\Split-TmuxPane -Command 'exec /bin/sh' -Confirm:$false -ErrorAction Continue -ErrorVariable errors 2>$null)
    Register-OwnedTmuxPane $fixture
    Assert-True ($continued.Count -eq 1 -and $continued[0] -is [LibTmux.Pane] -and $errors.Count -eq 1 -and
        $errors[0].FullyQualifiedErrorId -like 'Tmux.PaneSplitFailed,*' -and $errors[0].TargetObject -eq $stalePane -and
        $errors[0].Exception -is [LibTmux.LibTmuxException]) 'A failed split owner stopped later input or lost its error.'
}

'PASS: installed native session/window/pane creation, literal values, placement, WhatIf and per-owner errors'
