# Helpers for the recording tmux, the program in tests/support/RecordingTmux.

# Runs `dotnet build` and returns its output, or throws when it fails or runs past the limit.
function Invoke-RecordingTmuxBuild([string] $Project, [string] $Output, [int] $TimeoutSeconds) {
    $start = [Diagnostics.ProcessStartInfo]::new('dotnet')
    foreach ($argument in @('build', $Project, '--configuration', 'Release', '--output', $Output,
            '--nologo', '--verbosity', 'quiet', '-nodeReuse:false', '-p:UseSharedCompilation=false')) {
        $start.ArgumentList.Add($argument)
    }
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $out = $process.StandardOutput.ReadToEndAsync()
        $err = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            $process.Kill($true)
            throw "The recording tmux build ran past $TimeoutSeconds seconds."
        }
        $log = "$($out.GetAwaiter().GetResult()) $($err.GetAwaiter().GetResult())".Trim()
        if ($process.ExitCode) { throw "The recording tmux did not build: $log" }
    } finally {
        $process.Dispose()
    }
}

# Takes the named mutex, waiting up to the limit, and returns whether its last owner died
# without releasing it. The new owner owns it either way.
function Enter-RecordingTmuxLock([Threading.Mutex] $Lock, [int] $TimeoutSeconds) {
    $abandoned = $false
    try {
        $acquired = $Lock.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
    } catch {
        # PowerShell wraps the .NET exception a method call throws.
        if ($_.Exception.InnerException -isnot [Threading.AbandonedMutexException]) { throw }
        $acquired = $true
        $abandoned = $true
    }
    if (-not $acquired) { throw "Another suite held the recording tmux build for more than $TimeoutSeconds seconds." }
    $abandoned
}

# Builds the recording tmux once per source and returns the directory that holds it.
# Socket and Sandbox start it for each tmux call they check, so it is a compiled
# program: a PowerShell script starts too slowly for that many calls.
function Get-RecordingTmuxBuild {
    param([int] $LockTimeoutSeconds = 25, [int] $BuildTimeoutSeconds = 25)
    $project = Join-Path $PSScriptRoot 'RecordingTmux'
    $sources = @('RecordingTmux.csproj', 'Program.cs') | ForEach-Object { Join-Path $project $_ }
    $bytes = $sources | ForEach-Object { [IO.File]::ReadAllBytes($_) }
    $hash = [Security.Cryptography.SHA256]::HashData([byte[]] @($bytes | ForEach-Object { $_ }))
    $key = [Convert]::ToHexString($hash).Substring(0, 12).ToLowerInvariant()
    $output = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "build/recording-tmux/$key"
    # Suites run in parallel, and the first one to need the build makes it for the rest.
    $lock = [Threading.Mutex]::new($false, "libtmux-powershell-recording-tmux-$key")
    $held = $false
    try {
        $null = Enter-RecordingTmuxLock $lock $LockTimeoutSeconds
        $held = $true
        if (-not (Test-Path -LiteralPath (Join-Path $output 'tmux.dll'))) {
            $staging = "$output.building"
            if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
            Invoke-RecordingTmuxBuild (Join-Path $project 'RecordingTmux.csproj') $staging $BuildTimeoutSeconds
            Move-Item -LiteralPath $staging -Destination $output
        }
    } finally {
        if ($held) { $lock.ReleaseMutex() }
        $lock.Dispose()
    }
    $output
}

# Copies the recording tmux into a directory, as `tmux`, and returns its path. A child
# whose PATH holds only that directory can start it.
function Install-RecordingTmux([string] $Directory) {
    $build = Get-RecordingTmuxBuild
    $null = New-Item -ItemType Directory -Path $Directory -Force
    foreach ($name in @('tmux', 'tmux.dll', 'tmux.deps.json', 'tmux.runtimeconfig.json')) {
        Copy-Item -LiteralPath (Join-Path $build $name) -Destination (Join-Path $Directory $name) -Force
    }
    Join-Path $Directory 'tmux'
}

# Reads what the recording tmux appended to $LIBTMUX_TEST_RECORD: one object
# for each call, with its argument list, the names of the selector variables it
# inherited, and whether TMUX_TMPDIR was unset, the sandbox, or something else.
function Read-RecordedCall([string] $Path) {
    $calls = [Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $Path)) { return }
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $kind, $value = $line.Split("`t", 2)
        switch ($kind) {
            'call' {
                $calls.Add([pscustomobject]@{ Arguments = [Collections.Generic.List[string]]::new()
                    Set = [Collections.Generic.List[string]]::new(); TmpDir = '' })
            }
            'arg' { $calls[$calls.Count - 1].Arguments.Add($value) }
            'set' { $calls[$calls.Count - 1].Set.Add($value) }
            'tmpdir' { $calls[$calls.Count - 1].TmpDir = $value }
        }
    }
    $calls.ToArray()
}
