# Proves the recording tmux build is bounded: a lock another suite holds stops a
# waiter, a lock its owner abandoned does not, and a build past its limit is killed.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/support/RecordingTmux.ps1"

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

# Starts a PowerShell child that takes the named mutex and says so. With -Hold it keeps
# the mutex until its input closes; without it the child exits still owning the mutex.
function Start-LockOwner([string] $Name, [switch] $Hold) {
    $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
    foreach ($argument in @('-NoLogo', '-NoProfile', '-Command',
            "`$m = [Threading.Mutex]::new(`$false, '$Name'); `$null = `$m.WaitOne(); 'held'" +
            $(if ($Hold) { '; [Console]::In.ReadLine()' } else { '' }))) {
        $start.ArgumentList.Add($argument)
    }
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $process = [Diagnostics.Process]::Start($start)
    Assert-True ($process.StandardOutput.ReadLine() -ceq 'held') 'The lock owner did not take the mutex.'
    $process
}

function New-LockName { "libtmux-powershell-recording-tmux-test-$([Guid]::NewGuid().ToString('N'))" }

$name = New-LockName
$lock = [Threading.Mutex]::new($false, $name)
$owner = Start-LockOwner $name -Hold
try {
    $failure = $null
    try { $null = Enter-RecordingTmuxLock $lock 0 } catch { $failure = $_.Exception.Message }
    Assert-True ($failure -clike '*held the recording tmux build*') 'A held lock did not stop the waiter.'
} finally {
    $owner.StandardInput.Close()
    if (-not $owner.WaitForExit(5000)) { $owner.Kill($true) }
    $owner.Dispose()
    $lock.Dispose()
}

$name = New-LockName
$lock = [Threading.Mutex]::new($false, $name)
$dead = Start-LockOwner $name
try {
    Assert-True ($dead.WaitForExit(5000)) 'The lock owner did not exit.'
    Assert-True (Enter-RecordingTmuxLock $lock 5) 'An abandoned lock was not reported as abandoned.'
    $lock.ReleaseMutex()
    Assert-True (-not (Enter-RecordingTmuxLock $lock 5)) 'A released lock was reported as abandoned.'
    $lock.ReleaseMutex()
} finally {
    $dead.Dispose()
    $lock.Dispose()
}

$project = Join-Path $PSScriptRoot 'support/RecordingTmux/RecordingTmux.csproj'
$output = Join-Path ([IO.Path]::GetTempPath()) "libtmux-powershell-recording-tmux-test-$([Guid]::NewGuid().ToString('N'))"
try {
    $failure = $null
    try { Invoke-RecordingTmuxBuild $project $output 0 } catch { $failure = $_.Exception.Message }
    Assert-True ($failure -clike '*ran past 0 seconds*') 'A build past its limit was not stopped.'
} finally {
    Remove-Item -LiteralPath $output -Recurse -Force -ErrorAction SilentlyContinue
}

'PASS: the recording tmux build waits for a bounded time and survives an abandoned lock'
