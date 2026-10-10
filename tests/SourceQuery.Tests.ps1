param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: explicit acquisition and cancellation use one owned endpoint.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$module = Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1'
Import-Module $module
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-SourceQuery([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Source query: $Message" }
}

function Get-SourceIdentity($Rows) {
    @($Rows | ForEach-Object {
            if ($_ -is [LibTmux.Pane]) { "$($_.Session.Id)/$($_.Window.Id)/$($_.Window.Index)/$($_.Id)" }
            elseif ($_ -is [LibTmux.Window]) { "$($_.Session.Id)/$($_.Id)/$($_.Index)" }
            else { $_.Id.ToString() }
        }) -join "`n"
}

foreach ($name in @('Get-TmuxQueryPlan', 'Invoke-TmuxQuery')) {
    Assert-SourceQuery ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "installed module has no $name"
}

Invoke-WithOwnedTmux {
    param($fixture)
    $trace = Join-Path $fixture.DirectoryPath 'query-calls'
    $wrapper = Join-Path $fixture.DirectoryPath 'source-query-tmux'
    $arm = Join-Path $fixture.DirectoryPath 'block-capture'
    $pidFile = Join-Path $fixture.DirectoryPath 'query-client'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' "`$@" >> '$trace'
case "`$*" in
    *list-panes*)
        if [ -f '$arm' ]; then
            rm '$arm'
            printf '%s\n' "`$`$" > '$pidFile'
            exec $quotedTmux -S '$($fixture.SocketPath)' wait-for -S query-capture-ready ';' wait-for query-capture-blocked
        fi
        ;;
esac
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $otherPath = Join-Path $fixture.DirectoryPath 'other-workspace'
    $null = New-Item -ItemType Directory -Path $otherPath
    $null = Invoke-OwnedTmux $fixture -Arguments @('split-window', '-d', '-t', '%0', 'exec /bin/cat')
    $null = Invoke-OwnedTmux $fixture -Arguments @('link-window', '-d', '-s', '$0:0', '-t', '$0:5')
    $null = Invoke-OwnedTmux $fixture -Arguments @('new-session', '-d', '-s', 'other', '-c', $otherPath, 'exec /bin/cat')
    $null = Invoke-OwnedTmux $fixture -Arguments @('link-window', '-d', '-s', '$0:0', '-t', 'other:5')
    $null = Invoke-OwnedTmux $fixture -Arguments @('select-window', '-t', '$0:5')
    Register-OwnedTmuxPane $fixture
    $server = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper
    $version = [LibTmux.TmuxVersion]::Parse((Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim())
    $captured = $server | Get-TmuxSnapshot
    $paneQuery = New-TmuxQuery -Target Pane -Criteria @{ Id = '%0' }
    $before = [IO.File]::ReadAllText($trace)
    $plan = $paneQuery | Get-TmuxQueryPlan -DaemonVersion $version -Pushdown Require
    $null = $plan | Format-List * | Out-String
    $null = $plan.PushedPredicate | ConvertTo-TmuxQueryJson
    Assert-SourceQuery ($plan -is [LibTmux.Query.QueryPlan[LibTmux.Pane]] -and
        $plan.DaemonVersion -eq $version -and $null -ne $plan.PushedPredicate -and
        $null -eq $plan.ResidualPredicate -and $plan.RequiredSnapshotDepth -eq [LibTmux.SnapshotDepth]::Panes) 'plan lost native type or exact predicate metadata'
    Assert-SourceQuery ([IO.File]::ReadAllText($trace) -ceq $before) 'planning or plan display contacted tmux'

    foreach ($target in @('Session', 'Window', 'Pane')) {
        $id = switch ($target) { Session { '$0' }; Window { '@0' }; Pane { '%0' } }
        $query = New-TmuxQuery -Target $target -Criteria @{ Id = $id }
        $result = $server | Invoke-TmuxQuery -Query $query -AsResult
        $rows = switch ($target) {
            Session { $result.Snapshot.Sessions }
            Window { $result.Snapshot.Windows }
            Pane { $result.Snapshot.Panes }
        }
        $expected = @($rows | Where-Object { $_.Id.ToString() -ceq $id })
        $nativeResult = switch ($target) {
            Session { $result -is [LibTmux.Query.QueryResult[LibTmux.Session]] }
            Window { $result -is [LibTmux.Query.QueryResult[LibTmux.Window]] }
            Pane { $result -is [LibTmux.Query.QueryResult[LibTmux.Pane]] }
        }
        Assert-SourceQuery ($nativeResult -and
            $result.Count -eq $expected.Count -and $result.Count -gt 0) 'document execution replaced the native result or selected wrong rows'
        for ($index = 0; $index -lt $expected.Count; $index++) {
            Assert-SourceQuery ([object]::ReferenceEquals($result[$index], $expected[$index])) 'result lost same-observation references or source order'
        }
    }
    $identity = Get-SourceIdentity ($captured.Panes | Where-Object { $_.Id.ToString() -ceq '%0' })
    foreach ($mode in @('Never', 'Auto', 'Require')) {
        $prepared = $paneQuery | Get-TmuxQueryPlan -DaemonVersion $version -Pushdown $mode
        $result = $server | Invoke-TmuxQuery -Plan $prepared -AsResult
        Assert-SourceQuery ($result -is [LibTmux.Query.QueryResult[LibTmux.Pane]] -and $result.Count -eq 3 -and
            (Get-SourceIdentity $result) -ceq $identity -and $result.Snapshot.Panes.Count -eq 7) 'evaluation mode lost linked placements or pruned the captured graph'
    }
    $rows = @($server | Invoke-TmuxQuery -Plan $plan)
    Assert-SourceQuery ($rows.Count -eq 3 -and @($rows | Where-Object { $_ -isnot [LibTmux.Pane] }).Count -eq 0) 'default execution did not enumerate native rows'
    $none = New-TmuxQuery -Target Pane -Criteria @{ Id = '%999999999' }
    Assert-SourceQuery (@($server | Invoke-TmuxQuery -Query $none).Count -eq 0) 'no matches emitted a wrapper'
    $empty = @($server | Invoke-TmuxQuery -Query $none -AsResult)
    Assert-SourceQuery ($empty.Count -eq 1 -and $empty[0] -is [LibTmux.Query.QueryResult[LibTmux.Pane]] -and
        $empty[0].Count -eq 0 -and $empty[0].Snapshot.Panes.Count -eq 7) 'AsResult erased the empty observation'

    $graph = New-TmuxQuery -Target Pane -Criteria @{ Window = @{ Is = @{ IsActive = $true; Session = @{ Is = @{ Name = 'fixture' } } } } }
    $graphPlan = $graph | Get-TmuxQueryPlan -DaemonVersion $version
    Assert-SourceQuery ($null -eq $graphPlan.PushedPredicate -and $null -ne $graphPlan.ResidualPredicate -and
        $graphPlan.FallbackReasons.Count -gt 0) 'graph fallback was not visible in the native plan'
    $result = $server | Invoke-TmuxQuery -Plan $graphPlan -AsResult
    $expected = @($result.Snapshot.Panes | Select-TmuxPane -Query $graph)
    Assert-SourceQuery ($result.Count -eq 2 -and (Get-SourceIdentity $result) -ceq (Get-SourceIdentity $expected) -and
        $result.Snapshot.Panes.Count -eq 7) 'graph residual disagreed with local evaluation or pruned relations'

    $path = (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'other:0', '#{pane_current_path}')).StdOut.Trim()
    $expectedPath = @($captured.Panes | Where-Object { $_.CurrentPath -ceq $path })
    Assert-SourceQuery ($expectedPath.Count -eq 1 -and $expectedPath[0].Session.Name -ceq 'other') 'distinct working directory fixture is ambiguous'
    $pathQuery = New-TmuxQuery -Target Pane -Criteria @{ CurrentPath = $path }
    $pathQuery = New-TmuxQuery -Json ($pathQuery | ConvertTo-TmuxQueryJson)
    $selectedPath = @($captured.Panes | Select-TmuxPane -Query $pathQuery)
    Assert-SourceQuery ($pathQuery.Version -eq 2 -and
        (Get-SourceIdentity $selectedPath) -ceq (Get-SourceIdentity $expectedPath)) 'schema-v2 CurrentPath local selection disagreed with the native pane path'
    foreach ($mode in @('Never', 'Auto')) {
        $pathResult = $server | Invoke-TmuxQuery -Query $pathQuery -Pushdown $mode -AsResult
        $freshExpected = @($pathResult.Snapshot.Panes | Where-Object { $_.CurrentPath -ceq $path })
        Assert-SourceQuery ($pathResult.Count -eq 1 -and $pathResult.Snapshot.Panes.Count -eq 7 -and
            (Get-SourceIdentity $pathResult) -ceq (Get-SourceIdentity $expectedPath) -and
            (Get-SourceIdentity $pathResult) -ceq (Get-SourceIdentity $freshExpected) -and
            [object]::ReferenceEquals($pathResult[0], $freshExpected[0])) "schema-v2 CurrentPath $mode source result lost its native graph"
    }

    $linkedAtFive = @($captured.Windows | Where-Object { $_.Index -eq 5 -and $_.Id.ToString() -ceq '@0' })
    $expectedActive = @($captured.Windows | Where-Object { $_.Index -eq 5 -and $_.IsActive })
    Assert-SourceQuery ($linkedAtFive.Count -eq 2 -and $expectedActive.Count -eq 1 -and
        $expectedActive[0].Session.Name -ceq 'fixture') 'linked-window active placement fixture is ambiguous'
    $placementQuery = New-TmuxQuery -Target Window -Criteria ([ordered] @{ IsActive = $true; Index = 5 })
    $placementQuery = New-TmuxQuery -Json ($placementQuery | ConvertTo-TmuxQueryJson)
    $placementPlan = $placementQuery | Get-TmuxQueryPlan -DaemonVersion $version
    $selectedActive = @($captured.Windows | Select-TmuxWindow -Query $placementQuery)
    Assert-SourceQuery ($placementQuery.Version -eq 2 -and
        $null -ne $placementPlan.PushedPredicate -and $null -ne $placementPlan.ResidualPredicate -and
        (Get-SourceIdentity $selectedActive) -ceq (Get-SourceIdentity $expectedActive)) 'schema-v2 placement criteria lost active/index context'
    foreach ($mode in @('Never', 'Auto')) {
        $placementResult = $server | Invoke-TmuxQuery -Query $placementQuery -Pushdown $mode -AsResult
        $freshExpected = @($placementResult.Snapshot.Windows | Where-Object { $_.Index -eq 5 -and $_.IsActive })
        Assert-SourceQuery ($placementResult.Count -eq 1 -and $placementResult.Snapshot.Windows.Count -eq 4 -and
            (Get-SourceIdentity $placementResult) -ceq (Get-SourceIdentity $expectedActive) -and
            (Get-SourceIdentity $placementResult) -ceq (Get-SourceIdentity $freshExpected) -and
            [object]::ReferenceEquals($placementResult[0], $freshExpected[0]) -and
            $placementResult[0].LinkedSessions.Count -eq 2) "schema-v2 placement $mode source result lost its linked graph"
    }
    foreach ($criteria in @(@{ Or = @(@{ Id = '%0' }, @{ Width = @{ Ge = 1 } }) }, @{ Not = @{ Width = @{ Ge = 1 } } })) {
        $residual = New-TmuxQuery -Target Pane -Criteria $criteria | Get-TmuxQueryPlan -DaemonVersion $version
        Assert-SourceQuery ($null -eq $residual.PushedPredicate -and $null -ne $residual.ResidualPredicate) 'unsafe OR or negation acquired a partial source predicate'
    }
    $before = [IO.File]::ReadAllText($trace)
    $failure = $null
    try { $graph | Get-TmuxQueryPlan -DaemonVersion $version -Pushdown Require } catch { $failure = $_ }
    Assert-SourceQuery ($null -ne $failure -and $failure.FullyQualifiedErrorId -like 'Tmux.QueryPlanFailed,*' -and
        $failure.Exception -is [LibTmux.UnsupportedQueryExpressionException] -and
        [IO.File]::ReadAllText($trace) -ceq $before) 'Require failed to reject local graph evaluation before I/O'
    $failure = $null
    try { $paneQuery | Get-TmuxQueryPlan -DaemonVersion ([Activator]::CreateInstance([LibTmux.TmuxVersion])) } catch { $failure = $_ }
    Assert-SourceQuery ($null -ne $failure -and $failure.FullyQualifiedErrorId -like 'Tmux.QueryPlanFailed,*' -and
        [IO.File]::ReadAllText($trace) -ceq $before) 'planning accepted an unobserved default version'
    $clientJson = (New-TmuxQuery -Target Pane -Criteria @{} | ConvertTo-TmuxQueryJson).Replace('"target":"pane"', '"target":"client"')
    $clientQuery = [LibTmux.Query.Json.QueryJson]::Deserialize($clientJson)
    foreach ($operation in @(
            { $clientQuery | Get-TmuxQueryPlan -DaemonVersion $version },
            { $server | Invoke-TmuxQuery -Query $clientQuery }
        )) {
        $failure = $null
        try { & $operation } catch { $failure = $_ }
        Assert-SourceQuery ($null -ne $failure -and $failure.Exception -is [LibTmux.UnsupportedQueryExpressionException] -and
            [IO.File]::ReadAllText($trace) -ceq $before) 'unsupported external document reached tmux'
    }
    foreach ($arguments in @(
            @{ NativeFilter = '1'; Target = 'Pane'; AsResult = $true },
            @{ NativeFilter = '1'; Target = 'Pane'; Query = $paneQuery },
            @{ NativeFilter = '1'; Target = 'Pane'; Pushdown = 'Never' },
            @{ Plan = $plan; Pushdown = 'Never' },
            @{ Plan = [pscustomobject] @{ Document = $paneQuery } }
        )) {
        $failure = $null
        try { $server | Invoke-TmuxQuery @arguments } catch { $failure = $_ }
        Assert-SourceQuery ($null -ne $failure -and [IO.File]::ReadAllText($trace) -ceq $before) 'invalid source parameter combination dispatched tmux'
    }
    $raw = @($server | Invoke-TmuxQuery -Target Pane -NativeFilter '#{==:#{pane_id},%0}')
    Assert-SourceQuery ($raw.Count -eq 3 -and @($raw | Where-Object { $_ -isnot [LibTmux.Pane] }).Count -eq 0) 'native filter failed on an explicit cold endpoint or returned a structured result'

    $before = [IO.File]::ReadAllText($trace)
    $errors = @()
    $failedRows = @($server | Invoke-TmuxQuery -Query $graph -Pushdown Require -ErrorAction Continue -ErrorVariable errors 2>$null)
    $dispatch = [IO.File]::ReadAllText($trace).Substring($before.Length)
    Assert-SourceQuery ($failedRows.Count -eq 0 -and $errors.Count -eq 1 -and
        $errors[0].Exception -is [LibTmux.UnsupportedQueryExpressionException] -and
        $dispatch.Contains('display-message') -and !$dispatch.Contains('list-')) 'document Require did not stop after explicit inspection and before capture'

    $wrongVersion = [LibTmux.TmuxVersion]::Parse($(if ($version.Raw -ceq '3.2a') { '3.7c' } else { '3.2a' }))
    $wrongPlan = $paneQuery | Get-TmuxQueryPlan -DaemonVersion $wrongVersion
    $errors = @()
    $failedRows = @($server | Invoke-TmuxQuery -Plan $wrongPlan -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-SourceQuery ($failedRows.Count -eq 0 -and $errors.Count -eq 1 -and
        $errors[0].FullyQualifiedErrorId -like 'Tmux.QueryExecutionFailed,*' -and
        [object]::ReferenceEquals($errors[0].TargetObject, $server) -and
        $errors[0].Exception -is [InvalidOperationException]) 'prepared-version mismatch lost native error context or published rows'
    $absentSocket = Join-Path $fixture.DirectoryPath 'absent-socket'
    $absent = New-TmuxServer -SocketPath $absentSocket -ConfigurationFile '/dev/null' -TmuxBinaryPath $wrapper
    foreach ($arguments in @(@{ Query = $paneQuery }, @{ Plan = $plan }, @{ Target = 'Pane'; NativeFilter = '1' })) {
        $failure = $null
        try { $absent | Invoke-TmuxQuery @arguments } catch { $failure = $_ }
        Assert-SourceQuery ($null -ne $failure -and $failure.FullyQualifiedErrorId -like 'Tmux.QueryExecutionFailed,*' -and
            !(Test-Path -LiteralPath $absentSocket)) 'absent endpoint produced output or started a daemon'
    }

    $initial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $initial.ImportPSModule(@($module))
    $runspace = [RunspaceFactory]::CreateRunspace($initial)
    $pipeline = [PowerShell]::Create()
    $published = [Collections.Concurrent.ConcurrentQueue[object]]::new()
    [IO.File]::WriteAllText($arm, '')
    try {
        $runspace.Open()
        $pipeline.Runspace = $runspace
        $null = $pipeline.AddScript({
                param($Server, $Query, $Published)
                $outputQueue = $Published
                $Server | Invoke-TmuxQuery -Query $Query -AsResult | ForEach-Object { $outputQueue.Enqueue($_) }
            }).AddArgument($server).AddArgument($paneQuery).AddArgument($published)
        $invocation = $pipeline.BeginInvoke()
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', 'query-capture-ready')
        $clientId = [int] [IO.File]::ReadAllText($pidFile)
        $null = $fixture.OwnedProcessIds.Add($clientId)
        $stop = $pipeline.BeginStop($null, $null)
        Assert-SourceQuery ($stop.AsyncWaitHandle.WaitOne(1000)) 'source acquisition did not stop'
        $pipeline.EndStop($stop)
        Assert-SourceQuery ($invocation.AsyncWaitHandle.WaitOne(1000)) 'stopped source pipeline did not complete'
        $stopped = $false
        try { $null = $pipeline.EndInvoke($invocation) } catch {
            if ($_.Exception.InnerException -isnot [Management.Automation.PipelineStoppedException]) { throw }
            $stopped = $true
        }
        Assert-SourceQuery ($stopped -and $published.IsEmpty -and $pipeline.Streams.Error.Count -eq 0) 'source stop published a partial result or error'
        $client = Get-Process -Id $clientId -ErrorAction SilentlyContinue
        if ($client) { $client.Dispose(); throw 'Source query: stopped acquisition retained its native client' }
    } finally {
        $pipeline.Dispose()
        $runspace.Dispose()
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', '-S', 'query-capture-blocked')
    }
    Assert-SourceQuery ([int](Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid}')).StdOut -eq $fixture.ServerPid) 'source cancellation removed the borrowed daemon'
    Remove-Item -LiteralPath $wrapper
    $offline = $paneQuery | Get-TmuxQueryPlan -DaemonVersion $version
    Assert-SourceQuery ($offline -is [LibTmux.Query.QueryPlan[LibTmux.Pane]]) 'planning needed an executable after capture'
}
'PASS source query: pure native plans, explicit acquisition, complete graph provenance, raw isolation, absence, mismatch and cancellation'
