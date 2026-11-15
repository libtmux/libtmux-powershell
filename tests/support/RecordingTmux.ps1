# Helpers for the recording tmux, the program in tests/support/RecordingTmux.

# Builds the recording tmux once per source and returns the directory that holds it.
# Socket and Sandbox start it for each tmux call they check, so it is a compiled
# program that starts in a tenth of a second, where a PowerShell script took a second.
function Get-RecordingTmuxBuild {
    $project = Join-Path $PSScriptRoot 'RecordingTmux'
    $sources = @('RecordingTmux.csproj', 'Program.cs') | ForEach-Object { Join-Path $project $_ }
    $bytes = $sources | ForEach-Object { [IO.File]::ReadAllBytes($_) }
    $key = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([byte[]] @($bytes | ForEach-Object { $_ }))).Substring(0, 12).ToLowerInvariant()
    $output = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "build/recording-tmux/$key"
    # Suites run in parallel, and the first one to need the build makes it for the rest.
    $lock = [Threading.Mutex]::new($false, "libtmux-powershell-recording-tmux-$key")
    $null = $lock.WaitOne()
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $output 'tmux.dll'))) {
            $staging = "$output.building"
            if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
            $log = & dotnet build (Join-Path $project 'RecordingTmux.csproj') --configuration Release --output $staging `
                --nologo --verbosity quiet -nodeReuse:false -p:UseSharedCompilation=false 2>&1
            if ($LASTEXITCODE) { throw "The recording tmux did not build: $($log -join ' ')" }
            Move-Item -LiteralPath $staging -Destination $output
        }
    } finally {
        $lock.ReleaseMutex()
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
