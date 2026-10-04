param([Parameter(Mandatory)] [string] $ModuleRoot)

# Installed integration: selection uses captured native data and mutation sentinels on one owned server.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$module = Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1'
Import-Module $module
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-Selection([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Selectors: $Message" }
}

foreach ($name in @('Select-TmuxSession', 'Select-TmuxWindow', 'Select-TmuxPane')) {
    Assert-Selection ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "installed module has no $name"
}

Invoke-WithOwnedTmux {
    param($fixture)
    $trace = Join-Path $fixture.DirectoryPath 'selection-calls'
    $wrapper = Join-Path $fixture.DirectoryPath 'selection-tmux'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' call >> '$trace'
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $null = Invoke-OwnedTmux $fixture -Arguments @('split-window', '-d', '-t', '%0', 'exec /bin/cat')
    Register-OwnedTmuxPane $fixture
    $server = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper
    $captured = $server | Get-TmuxSnapshot
    $shallow = $server | Get-TmuxSnapshot -Depth Windows
    $first = $captured.Panes[0]
    $second = $captured.Panes[1]
    $window = $captured.Windows[0]
    $session = $captured.Sessions[0]
    $before = [IO.File]::ReadAllLines($trace).Length

    # Stop can be visible to the pipeline before StopProcessing cancels the token.
    if (-not ('LibTmux.Testing.SelectorStopProbe' -as [type])) {
        Add-Type -Path "$PSScriptRoot/support/SelectorStopProbe.cs"
    }
    Assert-Selection ([LibTmux.Testing.SelectorStopProbe]::RetainedMatchIsSuppressed(
            [LibTmux.PowerShell.SelectTmuxPaneCommand], $first)) 'stopping selector published a retained match before token cancellation'

    $selected = @($captured.Panes | Select-TmuxPane -Criteria @{ Width = @{ Ge = 1 } })
    $expected = @($captured.Panes | Where-Object Width -GE 1)
    Assert-Selection ($selected.Count -eq $expected.Count -and $selected.Count -eq 2) 'ordinary selection lost native matches'
    for ($index = 0; $index -lt $selected.Count; $index++) {
        Assert-Selection ([object]::ReferenceEquals($selected[$index], $expected[$index])) 'selection changed object references or order'
    }
    $sessionQuery = New-TmuxQuery -Target Session -Criteria @{ Name = 'fixture' }
    Assert-Selection ([object]::ReferenceEquals(($captured.Sessions | Select-TmuxSession -Query $sessionQuery -ExactlyOne), $session)) 'session query did not return the native object'
    Assert-Selection ([object]::ReferenceEquals(($captured.Windows | Select-TmuxWindow -Criteria @{ Panes = @{ Some = @{ Width = @{ Ge = 1 } } } } -ExactlyOne), $window)) 'window graph selection lost its native object'
    Assert-Selection (@(@() | Select-TmuxPane -Criteria @{}).Count -eq 0 -and
        @(Select-TmuxPane -InputObject @() -Criteria @{}).Count -eq 0) 'empty input emitted an ordinary selection'
    Assert-Selection (@(@($first, $first) | Select-TmuxPane -Criteria @{}).Count -eq 2) 'ordinary selection deduplicated repeated inputs'

    $criteria = @{ Id = $first.Id }
    $frozen = @(& { $criteria.Id = $second.Id; $first; $second } | Select-TmuxPane -Criteria $criteria)
    Assert-Selection ($frozen.Count -eq 1 -and [object]::ReferenceEquals($frozen[0], $first)) 'BeginProcessing retained mutable criteria'
    $produced = [Collections.Generic.List[int]]::new()
    $streamed = @(& {
            $produced.Add(1); $first
            $produced.Add(2); $second
        } | Select-TmuxPane -Criteria @{} | Select-Object -First 1)
    Assert-Selection ($streamed.Count -eq 1 -and $produced.Count -eq 1) 'ordinary selection buffered until upstream completed'
    Assert-Selection ([IO.File]::ReadAllLines($trace).Length -eq $before) 'local selection contacted tmux'

    $first | Select-TmuxPane -Criteria @{} -ExactlyOne | Set-TmuxOption -Name '@selected-once' -Value 'yes'
    Assert-Selection (($first | Get-TmuxOption -Name '@selected-once').Value.Raw -ceq 'yes') 'successful single selection did not reach the mutation'
    $before = [IO.File]::ReadAllLines($trace).Length
    foreach ($case in @(
            @{ Id = 'Tmux.NoMatch,*'; Call = { @() | Select-TmuxPane -Criteria @{} -ExactlyOne } },
            @{ Id = 'Tmux.NoMatch,*'; Call = { $first | Select-TmuxPane -Criteria @{ Id = '%999999999' } -ExactlyOne } },
            @{ Id = 'Tmux.MultipleMatches,*'; Call = { @($first, $second) | Select-TmuxPane -Criteria @{} -ExactlyOne -ErrorAction Continue } },
            @{ Id = 'Tmux.MultipleMatches,*'; Call = { @($first, $first) | Select-TmuxPane -Criteria @{} -ExactlyOne -ErrorAction Continue } },
            @{ Id = 'Tmux.QuerySelectionFailed,*'; Call = { @($first, [pscustomobject] @{ Id = $second.Id }) | Select-TmuxPane -Criteria @{} -ExactlyOne -ErrorAction Continue } },
            @{ Id = 'Tmux.QuerySelectionFailed,*'; Call = { Select-TmuxPane -InputObject @($first, $null) -Criteria @{} -ExactlyOne -ErrorAction Continue } },
            @{ Id = 'Tmux.QuerySelectionFailed,*'; Call = { Select-TmuxPane -InputObject $null -Criteria @{} -ExactlyOne -ErrorAction Continue } },
            @{ Id = 'Tmux.InvalidQuery,*'; Call = { $first | Select-TmuxPane -Query $sessionQuery -ExactlyOne -ErrorAction Continue } },
            @{ Id = 'Tmux.InvalidQuery,*'; Call = { @() | Select-TmuxPane -Query $sessionQuery -ExactlyOne -ErrorAction Continue } }
        )) {
        $failure = $null
        try { & $case.Call | Set-TmuxOption -Name '@must-not-select' -Value 'wrong' } catch { $failure = $_ }
        Assert-Selection ($null -ne $failure -and $failure.FullyQualifiedErrorId -like $case.Id) 'cardinality or admission error lost its terminating identifier'
        Assert-Selection ([IO.File]::ReadAllLines($trace).Length -eq $before) 'failed finite selection published an earlier retained match'
    }
    $failure = $null
    try {
        @($window, $shallow.Windows[0]) | Select-TmuxWindow -Criteria @{ Panes = @{ Some = @{} } } -ExactlyOne -ErrorAction Continue |
            Set-TmuxOption -Name '@must-not-select' -Value 'wrong'
    } catch { $failure = $_ }
    Assert-Selection ($null -ne $failure -and $failure.Exception -is [LibTmux.IncompleteSnapshotException] -and
        [object]::ReferenceEquals($failure.TargetObject, $shallow.Windows[0])) 'unavailable relation lost its native exception or failing target'
    Assert-Selection ([IO.File]::ReadAllLines($trace).Length -eq $before) 'availability failure emitted the earlier match'
    $failure = $null
    try {
        & { $first; throw 'injected upstream failure' } | Select-TmuxPane -Criteria @{} -ExactlyOne |
            Set-TmuxOption -Name '@must-not-select' -Value 'wrong'
    } catch { $failure = $_ }
    Assert-Selection ($null -ne $failure -and $failure.Exception.Message -like '*injected upstream failure*' -and
        [IO.File]::ReadAllLines($trace).Length -eq $before) 'upstream failure published an incomplete single match'
    $failure = $null
    try {
        & { $first; Write-Error 'injected acquisition failure' -ErrorAction Stop } |
            Select-TmuxPane -Criteria @{} -ExactlyOne |
            Set-TmuxOption -Name '@must-not-select' -Value 'wrong'
    } catch { $failure = $_ }
    Assert-Selection ($null -ne $failure -and $failure.Exception.Message -like '*injected acquisition failure*' -and
        [IO.File]::ReadAllLines($trace).Length -eq $before) 'upstream ErrorAction Stop published an incomplete single match'

    $initial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $initial.ImportPSModule(@($module))
    $runspace = [RunspaceFactory]::CreateRunspace($initial)
    $pipeline = [PowerShell]::Create()
    $reached = [Threading.ManualResetEventSlim]::new($false)
    $release = [Threading.ManualResetEventSlim]::new($false)
    try {
        $runspace.Open()
        $pipeline.Runspace = $runspace
        $null = $pipeline.AddScript({
                param($Pane, $Reached, $Release)
                $inputPane = $Pane
                $delivered = $Reached
                $resume = $Release
                & { $inputPane; $delivered.Set(); $resume.Wait() } |
                    Select-TmuxPane -Criteria @{} -ExactlyOne |
                    Set-TmuxOption -Name '@must-not-select' -Value 'wrong'
            }).AddArgument($first).AddArgument($reached).AddArgument($release)
        $invocation = $pipeline.BeginInvoke()
        Assert-Selection ($reached.Wait(10000)) 'stop fixture never delivered its first matching input'
        $stop = $pipeline.BeginStop($null, $null)
        Assert-Selection ($pipeline.InvocationStateInfo.State -eq [Management.Automation.PSInvocationState]::Stopping) 'selection stop was not acknowledged before input release'
        $release.Set()
        Assert-Selection ($stop.AsyncWaitHandle.WaitOne($HangGuardMilliseconds)) 'selection stop did not complete'
        $pipeline.EndStop($stop)
        $stopped = $false
        try { $null = $pipeline.EndInvoke($invocation) } catch {
            if ($_.Exception.InnerException -isnot [Management.Automation.PipelineStoppedException]) { throw }
            $stopped = $true
        }
        Assert-Selection $stopped 'stopped input completed without PipelineStoppedException'
        Assert-Selection ([IO.File]::ReadAllLines($trace).Length -eq $before) 'stopped input published its retained match'
    } finally {
        $release.Set()
        $pipeline.Dispose()
        $runspace.Dispose()
        $reached.Dispose()
        $release.Dispose()
    }
    Remove-Item -LiteralPath $wrapper
    Assert-Selection ([object]::ReferenceEquals(($first | Select-TmuxPane -Criteria @{} -ExactlyOne), $first)) 'selection required an executable after capture'
}
'PASS selectors: native streaming, copied criteria, cardinality, terminating admission, availability, upstream failure and stop'
