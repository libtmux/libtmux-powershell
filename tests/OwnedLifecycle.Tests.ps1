param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: the Python parent owns accepted foreground daemon handles.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$ModuleRoot/LibTmux/0.1.0/LibTmux.psd1"
$server = New-TmuxServer
$script:checks = 0
function Assert-Scope([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Owned lifecycle: $Message" }
    $script:checks++
}
function Set-ScopeFault([string] $Value) {
    [IO.File]::WriteAllText($env:LIBTMUX_SCOPE_FAULT, $Value)
}
function Test-SessionGone([LibTmux.Session] $Session) {
    return @($Session.Server | Get-TmuxSession -Id $Session.Id -ErrorAction SilentlyContinue).Count -eq 0
}
function Test-CleanupCause([Exception] $Failure) {
    for ($error = $Failure; $null -ne $error; $error = $error.InnerException) {
        $cleanup = [LibTmux.OwnedScope]::CleanupFailure($error)
        if ($cleanup) { return $cleanup }
    }
    return $null
}
$initial = @($server | Get-TmuxSession)
Assert-Scope ($initial.Count -eq 1 -and $initial[0].Name -ceq 'fixture') 'external fixture missing'
$sessionOwner = $server | New-TmuxSession -Owned -Name 'scope-session'
Assert-Scope ($sessionOwner -is [LibTmux.OwnedSessionScope]) 'owned session output type'
$value = $sessionOwner | Invoke-TmuxScope {
    param($session)
    $windowOwner = $session | New-TmuxWindow -Owned -Name 'scope-window'
    Assert-Scope ($windowOwner -is [LibTmux.OwnedWindowScope]) 'owned window output type'
    $window = $windowOwner.Value
    $pane = $window | Get-TmuxPane | Select-Object -First 1
    $paneOwner = $pane | Split-TmuxPane -Owned
    Assert-Scope ($paneOwner -is [LibTmux.OwnedPaneScope]) 'owned pane output type'
    $paneOwner | Close-TmuxScope
    $paneOwner | Close-TmuxScope
    Assert-Scope (@($window | Get-TmuxPane).Count -eq 1) 'pane cleanup did not run'
    $windowOwner | Close-TmuxScope
    Assert-Scope (@($session | Get-TmuxWindow).Count -eq 1) 'window cleanup did not run'
    'scope-result'
}
Assert-Scope ($value -ceq 'scope-result' -and (Test-SessionGone $sessionOwner.Value)) 'body output or session cleanup'
$sessionOwner | Close-TmuxScope
$borrowed = $server | New-TmuxSession -Name 'adopted'
$server | Invoke-TmuxCommand -Arguments @('rename-session', '-t', $borrowed.Id.ToString(), 'renamed') | Out-Null
$adopted = $borrowed | ConvertTo-TmuxOwnedResource
$adopted | Close-TmuxScope
Assert-Scope (Test-SessionGone $borrowed) 'adopted session rename cleanup'
$parent = $initial[0]
$other = $parent | New-TmuxWindow -Name 'destination'
$window = $parent | New-TmuxWindow -Name 'adopt-window'
$ownedWindow = $window | ConvertTo-TmuxOwnedResource
$ownedPane = ($window | Get-TmuxPane | Select-Object -First 1) | Split-TmuxPane -Owned
$movedPane = $ownedPane.Value
$null = $server | Invoke-TmuxCommand -Arguments @('join-pane', '-s', $movedPane.Id.ToString(), '-t', ($other | Get-TmuxPane | Select-Object -First 1).Id.ToString())
$ownedPane | Close-TmuxScope
Assert-Scope (@($other | Get-TmuxPane).Count -eq 1) 'moved pane cleanup'
$ownedWindow | Close-TmuxScope
Assert-Scope (@($parent | Get-TmuxWindow -Name 'adopt-window').Count -eq 0) 'adopted window cleanup'
$extra = ($other | Get-TmuxPane | Select-Object -First 1) | Split-TmuxPane
$extra | ConvertTo-TmuxOwnedResource | Invoke-TmuxScope { param($pane) Assert-Scope ($pane.Id -eq $extra.Id) 'adopted pane value' }
Assert-Scope (@($other | Get-TmuxPane).Count -eq 1) 'adopted pane cleanup'
$other | Remove-TmuxWindow -Confirm:$false
$created = $server | Resolve-TmuxSession -Name 'literal-#{pid}'
$reused = $server | Resolve-TmuxSession -Name 'literal-#{pid}'
Assert-Scope ($created.Created -and !$reused.Created -and $null -eq $reused.Owner) 'session created/reused ownership'
Assert-Scope ($created.Value.Name -ceq 'literal-#{pid}') 'session matching expands literal name'
$reused | Close-TmuxScope
Assert-Scope (!(Test-SessionGone $created.Value)) 'reuse acquired destruction authority'
$winCreated = $created.Value | Resolve-TmuxWindow -Name 'exact'
$winReused = $created.Value | Resolve-TmuxWindow -Name 'exact'
Assert-Scope ($winCreated.Created -and !$winReused.Created) 'window created/reused'
$winReused | Close-TmuxScope
$paneCreated = $winCreated.Value | Resolve-TmuxPane -Identity 'application:one'
$paneReused = $winCreated.Value | Resolve-TmuxPane -Identity 'application:one'
Assert-Scope ($paneCreated.Created -and !$paneReused.Created -and $paneCreated.Value.Id -eq $paneReused.Value.Id) 'pane created/reused'
$paneReused | Close-TmuxScope
Assert-Scope (@($winCreated.Value | Get-TmuxPane).Count -eq 2) 'pane reuse cleanup destroyed borrowed value'
$duplicate = $created.Value | New-TmuxWindow -Name 'exact'
$failed = $false
try { $created.Value | Resolve-TmuxWindow -Name 'exact' } catch { $failed = $true; Assert-Scope ($_.Exception -is [LibTmux.TmuxAmbiguousMatchException]) 'window ambiguity lost native type' }
Assert-Scope $failed 'duplicate windows silently selected'
$duplicate | Remove-TmuxWindow -Confirm:$false
$copy = ($winCreated.Value | Get-TmuxPane | Select-Object -First 1)
$null = $server | Invoke-TmuxCommand -Arguments @('set-option', '-p', '-t', $copy.Id.ToString(), '@libtmux-identity', 'application:one')
$failed = $false
try { $winCreated.Value | Resolve-TmuxPane -Identity 'application:one' } catch { $failed = $true; Assert-Scope ($_.Exception -is [LibTmux.TmuxAmbiguousMatchException]) 'pane ambiguity lost native type' }
Assert-Scope $failed 'duplicate pane identities silently selected'
$created | Close-TmuxScope
Assert-Scope (Test-SessionGone $created.Value) 'created result did not clean session'
$serverResult = $server | Resolve-TmuxServer
Assert-Scope (!$serverResult.Created -and $null -eq $serverResult.Owner) 'existing server was claimed'
$serverResult | Close-TmuxScope
Assert-Scope (@($server | Get-TmuxSession).Count -eq 1) 'server reuse destroyed fixture'
foreach ($mode in @('body', 'cleanup', 'both')) {
    $owner = $server | New-TmuxSession -Owned -Name "failure-$mode"
    $caught = $null
    if ($mode -in @('cleanup', 'both')) { Set-ScopeFault 'cleanup' }
    try {
        $owner | Invoke-TmuxScope {
            param($session)
            if ($mode -in @('body', 'both')) { throw [InvalidOperationException]::new('scope body sentinel') }
            'should-not-escape-cleanup-failure'
        }
    } catch { $caught = $_.Exception }
    finally { Set-ScopeFault '' }
    Assert-Scope ($null -ne $caught) "$mode failure vanished"
    if ($mode -in @('body', 'both')) { Assert-Scope ($caught.ToString().Contains('scope body sentinel')) 'body cause vanished' }
    if ($mode -eq 'both') { Assert-Scope ((Test-CleanupCause $caught).ToString().Contains('injected scope cleanup failure')) 'paired cleanup cause vanished' }
    if ($mode -in @('cleanup', 'both')) {
        Assert-Scope (!(Test-SessionGone $owner.Value)) 'cleanup injection did not leave retryable target'
        $owner | Close-TmuxScope
    }
    Assert-Scope (Test-SessionGone $owner.Value) 'failed disposal was not retryable'
}
Set-ScopeFault 'receipt'
try {
    $caught = $null
    try { $server | New-TmuxSession -Owned -Name 'receipt-failure' } catch { $caught = $_.Exception }
    Assert-Scope ($null -ne $caught -and $caught.ToString().Contains('injected nonzero creation result')) 'nonzero receipt failure was lost'
} finally { Set-ScopeFault '' }
Assert-Scope (@($server | Get-TmuxSession -Name 'receipt-failure').Count -eq 0) 'known creation receipt was not rolled back'
Set-ScopeFault 'receipt-lost'
try {
    $caught = $null
    try { $server | New-TmuxSession -Owned -Name 'lost-receipt' } catch { $caught = $_.Exception }
    Assert-Scope ($caught -is [LibTmux.LibTmuxException] -and $caught.Dispatch -eq [LibTmux.TmuxDispatchState]::Unknown) 'lost creation reply claimed a known outcome'
} finally { Set-ScopeFault '' }
$unclaimed = @($server | Get-TmuxSession -Name 'lost-receipt')
Assert-Scope ($unclaimed.Count -eq 1) 'unknown creation effect was hidden or deleted by a guessed target'
# Reconcile the test's observed object before accepting new cleanup authority.
$unclaimed[0] | ConvertTo-TmuxOwnedResource | Close-TmuxScope
$discovery = Find-TmuxServer -Root $env:LIBTMUX_SCOPE_SOCKET_DIRECTORY -NoConfiguredRoots -Connection $server.ConnectionOptions
Assert-Scope ($discovery.Servers.Count -eq 1 -and !$discovery.Truncated -and $discovery.ProbesAttempted -eq 1) 'bounded discovery did not find owned endpoint'
$limited = Find-TmuxServer -Root @($env:LIBTMUX_SCOPE_SOCKET_DIRECTORY, $env:LIBTMUX_SCOPE_SOCKET_DIRECTORY) -NoConfiguredRoots -MaximumRoots 1 -Connection $server.ConnectionOptions
Assert-Scope ($limited.Truncated -and @($limited.Diagnostics | Where-Object Kind -EQ limit).Count -eq 1) 'discovery silently truncated roots'
$missing = Find-TmuxServer -Root "$env:LIBTMUX_SCOPE_ROOT/missing" -NoConfiguredRoots -Connection $server.ConnectionOptions
Assert-Scope ($missing.Servers.Count -eq 0 -and @($missing.Diagnostics | Where-Object Kind -EQ root-error).Count -eq 1) 'discovery omitted failed root'
$ownedPath = "$env:LIBTMUX_SCOPE_ROOT/owned-server"
$whole = New-TmuxServer -SocketPath $ownedPath -Owned -ConfigurationFile '/dev/null'
Assert-Scope ($whole -is [LibTmux.OwnedServerScope]) 'new owned server output type'
$again = $whole.Value | Resolve-TmuxServer
Assert-Scope (!$again.Created) 'new server reused with ownership'
$again | Close-TmuxScope
$whole | Close-TmuxScope
$whole | Close-TmuxScope
$anotherPath = "$env:LIBTMUX_SCOPE_ROOT/resolved-server"
$resolved = New-TmuxServer -SocketPath $anotherPath -ConfigurationFile '/dev/null' | Resolve-TmuxServer
Assert-Scope ($resolved.Created) 'missing server not created'
$resolved | Close-TmuxScope
$adoptServer = $server | ConvertTo-TmuxOwnedResource
Assert-Scope ($adoptServer -is [LibTmux.OwnedServerScope]) 'adopted server output type'
$adoptServer | Close-TmuxScope
[pscustomobject] @{ Passed = $true; Assertions = $script:checks } | ConvertTo-Json -Compress
