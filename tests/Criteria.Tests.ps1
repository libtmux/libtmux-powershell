param([Parameter(Mandatory)] [string] $ModuleRoot)

# Installed admission and native matching; live capture uses one owned tmux server.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Resolve-Path $ModuleRoot).Path 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-Criterion([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Criteria: $Message" }
}

function Assert-RejectedCriterion([scriptblock] $Operation) {
    $failed = $false
    try { & $Operation | Out-Null } catch {
        $failed = $true
        Assert-Criterion ($_.FullyQualifiedErrorId -like 'Tmux.InvalidQuery,*') 'admission lost its terminating error ID'
    }
    Assert-Criterion $failed 'invalid criteria were accepted'
}

foreach ($name in @('New-TmuxQuery', 'ConvertTo-TmuxQueryJson', 'Get-TmuxQueryField')) {
    Assert-Criterion ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "installed module has no $name"
}
$fields = @(Get-TmuxQueryField -Target Pane)
Assert-Criterion ($fields.Count -gt 0 -and @($fields | Where-Object { $_ -isnot [LibTmux.Query.QueryFieldDescriptor] }).Count -eq 0) 'discovery replaced native descriptors'
Assert-Criterion (@($fields | Where-Object ScalarPropertyPath -CEQ Width).Count -eq 1 -and
    @($fields | Where-Object ScalarPropertyPath -CEQ Height).Count -eq 1) 'dimensions are missing from the native catalog'
Assert-Criterion (@(Get-TmuxQueryField -Target Client | Where-Object { $_.WireName -ceq 'client_id' -and $null -eq $_.ScalarPropertyPath }).Count -eq 1) 'schema-only discovery invented a native client binding'

$names = [object[]] @('fixture', 'other')
$criteria = [ordered] @{ Name = @{ In = $names }; Attached = $false }
$query = New-TmuxQuery -Target Session -Criteria $criteria
$before = $query | ConvertTo-TmuxQueryJson
$names[0] = 'changed'
$criteria['Attached'] = $true
Assert-Criterion ($query -is [LibTmux.Query.QueryDocument] -and $before -ceq ($query | ConvertTo-TmuxQueryJson)) 'document borrowed mutable criteria'
Assert-Criterion ((New-TmuxQuery -Json $before | ConvertTo-TmuxQueryJson) -ceq $before) 'schema round trip changed the document'
Assert-Criterion (($before | ConvertFrom-Json).version -eq 2) 'document did not use the current schema'
Assert-RejectedCriterion { New-TmuxQuery -Json $before.Replace('"version":2', '"version":1') }
Assert-RejectedCriterion { New-TmuxQuery -Json $before.Replace('"version":2', '"version":2,"version":2') }
Assert-RejectedCriterion { New-TmuxQuery -Json $before.Replace('"schema":', '"unexpected":0,"schema":') }

foreach ($invalid in @(
        @{ Unknown = 'x' }, @{ Width = $true }, @{ Width = '50' }, @{ Width = 1.5 },
        @{ Width = [decimal] 1 }, @{ Width = [uint64]::MaxValue }, @{ CurrentCommand = 1 },
        @{ Width = [DayOfWeek]::Monday }, @{ Width = @{ In = @($true) } },
        @{ Width = @{ In = [Linq.Enumerable]::Range(0, 2) } },
        @{ CurrentCommand = { 'cat' } }, @{ Id = '$1' }, @{ Id = [LibTmux.WindowId]::Parse('@1') },
        @{ CurrentCommand = @{ StartsWith = $null } }, @{ CurrentCommand = @{ IsNull = $false } },
        @{ CurrentCommand = @{ Regex = @{ Pattern = 'cat'; Options = @('Compiled') } } },
        @{ CurrentCommand = @{ Regex = @{ Pattern = '[' } } }, @{ Width = @{ Unknown = 1 } },
        @{ Window = @{ Some = @{} } }, @{ CurrentCommand = [string][char]0xD800 }
    )) {
    Assert-RejectedCriterion { New-TmuxQuery -Target Pane -Criteria $invalid }
}
$caseCollision = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
$caseCollision.Add('Name', 'fixture')
$caseCollision.Add('name', 'fixture')
Assert-RejectedCriterion { New-TmuxQuery -Target Session -Criteria $caseCollision }
Assert-RejectedCriterion { New-TmuxQuery -Target Session -Criteria @{ Name = 'fixture'; session_name = 'fixture' } }
Assert-RejectedCriterion { New-TmuxQuery -Target Session -Criteria @{ Windows = 1 } }
Assert-RejectedCriterion { New-TmuxQuery -Target Session -Criteria @{ 'Windows.Count' = @{ Some = @{} } } }
Assert-RejectedCriterion { New-TmuxQuery -Target Session -Criteria @{ 'Windows.Count' = 1; Windows = @{ Some = @{} } } }
$operatorCollision = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
$operatorCollision.Add('Eq', 'cat')
$operatorCollision.Add('eq', 'cat')
Assert-RejectedCriterion { New-TmuxQuery -Target Pane -Criteria @{ CurrentCommand = $operatorCollision } }
$cycle = @{}
$cycle.Not = $cycle
Assert-RejectedCriterion { New-TmuxQuery -Target Pane -Criteria $cycle }
$deep = @{}
1..33 | ForEach-Object { $deep = @{ Not = $deep } }
Assert-RejectedCriterion { New-TmuxQuery -Target Pane -Criteria $deep }
Assert-RejectedCriterion { New-TmuxQuery -Target Pane -Criteria @{ Id = @{ In = @('%1') * 129 } } }
Assert-RejectedCriterion { New-TmuxQuery -Target Pane -Criteria @{ CurrentCommand = ('x' * 4097) } }
Assert-RejectedCriterion { New-TmuxQuery -Target Pane -Criteria @{ CurrentCommand = @{ Regex = @{ Pattern = 'x' * 1025 } } } }
Assert-RejectedCriterion { New-TmuxQuery -Target Pane -Criteria @{ Or = @(@{ Width = 1 }) * 171 } }
Assert-RejectedCriterion { New-TmuxQuery -Target Pane -Criteria @{ CurrentCommand = @{ In = @(('x' * 4096)) * 128 } } }
$shared = @{ Width = @{ Ge = [byte] 1 } }
$null = New-TmuxQuery -Target Pane -Criteria @{ And = @($shared, $shared) }
$null = New-TmuxQuery -Target Pane -Criteria @{ Width = $null }
$null = New-TmuxQuery -Target Session -Criteria @{ And = @(@{ 'Windows.Count' = @{ Ge = 1 } }, @{ Windows = @{ Every = @{} } }) }

Invoke-WithOwnedTmux {
    param($fixture)
    $wrapper = Join-Path $fixture.DirectoryPath 'query-tmux'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    "#!/bin/sh`nexec $quotedTmux `"`$@`"`n" | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $server = New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper
    $snapshot = $server | Get-TmuxSnapshot
    Remove-Item -LiteralPath $wrapper
    $panes = [LibTmux.Pane[]] @($snapshot.Panes)
    $native = @($panes | Where-Object { $_.Width -ge 1 -and $_.Height -gt 0 })
    $dimensions = New-TmuxQuery -Target Pane -Criteria ([ordered] @{ Width = @{ Ge = 1 }; Height = @{ Gt = 0 } })
    $matched = @([LibTmux.Query.QueryExtensions]::Matching[LibTmux.Pane]($panes, $dimensions, [Threading.CancellationToken]::None))
    Assert-Criterion ($matched.Count -eq $native.Count -and $matched.Count -gt 0) 'dimensions disagree with native captured values'
    for ($index = 0; $index -lt $native.Count; $index++) {
        Assert-Criterion ([object]::ReferenceEquals($native[$index], $matched[$index])) 'query changed the selected object reference or order'
    }
    $sessions = [LibTmux.Session[]] @($snapshot.Sessions)
    $graph = New-TmuxQuery -Target Session -Criteria @{ Windows = @{ Some = @{ ActivePane = @{ Is = @{ Width = @{ Ge = 1 } } } } } }
    Assert-Criterion (@([LibTmux.Query.QueryExtensions]::Matching[LibTmux.Session]($sessions, $graph, [Threading.CancellationToken]::None)).Count -eq $sessions.Count) 'nested relation criteria did not use captured native relations'
    $ordinal = New-TmuxQuery -Target Session -Criteria @{ nAmE = 'FIXTURE' }
    Assert-Criterion (@([LibTmux.Query.QueryExtensions]::Matching[LibTmux.Session]($sessions, $ordinal, [Threading.CancellationToken]::None)).Count -eq 0) 'case-insensitive field aliases changed ordinal string equality'
    $regex = New-TmuxQuery -Target Session -Criteria @{ Name = @{ Regex = @{ Pattern = '^FIXTURE$'; Options = @('IgnoreCase') } } }
    Assert-Criterion (@([LibTmux.Query.QueryExtensions]::Matching[LibTmux.Session]($sessions, $regex, [Threading.CancellationToken]::None)).Count -eq 1) 'regex options did not reach native matching'
    $identity = New-TmuxQuery -Target Pane -Criteria @{ Id = $panes[0].Id }
    $identified = @([LibTmux.Query.QueryExtensions]::Matching[LibTmux.Pane]($panes, $identity, [Threading.CancellationToken]::None))
    Assert-Criterion ($identified.Count -eq 1 -and [object]::ReferenceEquals($identified[0], $panes[0])) 'native typed ID was not preserved'
    $none = New-TmuxQuery -Target Pane -Criteria @{ Id = @{ In = @() } }
    Assert-Criterion (@([LibTmux.Query.QueryExtensions]::Matching[LibTmux.Pane]($panes, $none, [Threading.CancellationToken]::None)).Count -eq 0) 'empty membership was not false'
    $all = New-TmuxQuery -Target Pane -Criteria @{ Id = @{ NotIn = @() } }
    Assert-Criterion (@([LibTmux.Query.QueryExtensions]::Matching[LibTmux.Pane]($panes, $all, [Threading.CancellationToken]::None)).Count -eq $panes.Count) 'empty negated membership was not true'
    $null = $dimensions | Format-List | Out-String
    Assert-Criterion (!(Test-Path -LiteralPath $wrapper)) 'local criteria required executable availability'
}
'PASS criteria: native documents, strict bounded admission, copied values, discovery, JSON and captured-data equivalence'
