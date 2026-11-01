param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [switch] $Child,
    [switch] $Workspace,
    [switch] $Late,
    [string] $SocketName,
    [string] $SocketPath
)

# Outer integration: which socket a server handle makes tmux use. A handle that names no
# socket passes neither -L nor -S, so tmux picks the server; LIBTMUX_SOCKET_PATH becomes -S
# and LIBTMUX_SOCKET becomes -L, the path first; a parameter beats both; a blank variable
# is unset; a variable changed after a handle is made changes nothing. The recording tmux
# keeps argument lists and variable names, never values, so a failure names the flags a
# call passed and never what followed them. Run through eng/Test.ps1, which enters the
# sandbox.
#
# Each case runs in a process of its own, because the library reads its variables when a
# handle is made and a blank value cannot be set in a running process. The cases are
# started together and read back in order.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path

if ($Child) {
    Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')
    $options = @{ TmuxBinaryPath = $env:LIBTMUX_TEST_TMUX }
    if ($PSBoundParameters.ContainsKey('SocketName')) { $options['SocketName'] = $SocketName }
    if ($PSBoundParameters.ContainsKey('SocketPath')) { $options['SocketPath'] = $SocketPath }
    $server = LibTmux\New-TmuxServer @options
    if ($Late) { $env:LIBTMUX_SOCKET_PATH = '/late/socket'; $env:LIBTMUX_SOCKET = 'late' }
    try {
        if ($Workspace) {
            Import-Module (Join-Path $ModuleRoot 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1')
            $yaml = "session_name: probe`nwindows:`n  - window_name: w`n    panes:`n      - echo hi`n"
            $null = LibTmux.Workspace\Import-TmuxWorkspace -Yaml $yaml |
                LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ErrorAction Stop
        } else {
            $null = $server | LibTmux\Get-TmuxSession -ErrorAction Stop
        }
    } catch { $null = $_ }
    return
}

. "$PSScriptRoot/support/Sandbox.ps1"
. "$PSScriptRoot/support/RecordingTmux.ps1"
Assert-TestSandbox

function Assert-Socket([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw "Socket default: $Message" }
}

# What is wrong with the calls a case recorded, by flag name and never by value; empty when
# nothing is. The first call, tmux -V, carries no connection flags, so a call counts when it
# passes anything else.
function Get-RouteProblem($Calls, $Case) {
    $routed = @($Calls | Where-Object { $_.Arguments.Count -gt 1 -or $_.Arguments[0] -cne '-V' })
    if (-not $routed) { return 'the recording tmux was never asked for more than its version' }
    foreach ($call in $routed) {
        $arguments = $call.Arguments.ToArray()
        $name = [array]::IndexOf($arguments, '-L')
        $path = [array]::IndexOf($arguments, '-S')
        $passed = @(if ($name -ge 0) { '-L' }; if ($path -ge 0) { '-S' }) -join ' and '
        if (-not $passed) { $passed = 'no socket flag' }
        $expected = if ($Case.Flag -ceq 'none') { 'no socket flag' } else { $Case.Flag }
        if ($passed -cne $expected) { return "it passed $passed, not $expected" }
        $index = if ($Case.Flag -ceq '-L') { $name } elseif ($Case.Flag -ceq '-S') { $path } else { -1 }
        if ($index -ge 0 -and ($index + 1 -ge $arguments.Count -or $arguments[$index + 1] -cne $Case['Value'])) {
            return "$($Case.Flag) named a different socket than expected"
        }
        if ($null -ne $Case['Tmux'] -and ($call.Set -contains 'TMUX') -ne $Case['Tmux']) {
            return $(if ($Case['Tmux']) { 'tmux was not handed TMUX' } else { 'tmux was handed TMUX' })
        }
    }
}

$scratch = Join-Path $env:TMUX_TMPDIR 'socket'
$null = New-Item -ItemType Directory -Path $scratch -Force
$recorder = Join-Path $PSScriptRoot 'support/RecordingTmux.sh'
$name = 'libtmux-case-name'
$other = 'libtmux-case-other'
$path = Join-Path $scratch 'case-path.sock'
$otherPath = Join-Path $scratch 'case-other.sock'
$pane = '/decoy/server,1,0'

# Flag is none, -L or -S; Value is what follows the flag; Tmux is whether tmux is handed the
# TMUX variable, or null where the case does not say.
$cases = @(
    @{ Id = 'neither'; Rule = 'no variable passes no socket'
        Variables = @{}; Flag = 'none' }
    @{ Id = 'name'; Rule = 'LIBTMUX_SOCKET becomes -L'
        Variables = @{ LIBTMUX_SOCKET = $name }; Flag = '-L'; Value = $name }
    @{ Id = 'path'; Rule = 'LIBTMUX_SOCKET_PATH becomes -S'
        Variables = @{ LIBTMUX_SOCKET_PATH = $path }; Flag = '-S'; Value = $path }
    @{ Id = 'both'; Rule = 'the path wins when both variables are set'
        Variables = @{ LIBTMUX_SOCKET = $name; LIBTMUX_SOCKET_PATH = $path }; Flag = '-S'; Value = $path }
    @{ Id = 'empty'; Rule = 'empty variables are unset'
        Variables = @{ LIBTMUX_SOCKET = ''; LIBTMUX_SOCKET_PATH = '' }; Flag = 'none' }
    @{ Id = 'blank'; Rule = 'blank variables are unset'
        Variables = @{ LIBTMUX_SOCKET = '   '; LIBTMUX_SOCKET_PATH = ' ' }; Flag = 'none' }
    @{ Id = 'blank-path'; Rule = 'a blank path does not hide the name'
        Variables = @{ LIBTMUX_SOCKET = $name; LIBTMUX_SOCKET_PATH = ' ' }; Flag = '-L'; Value = $name }
    @{ Id = 'blank-name'; Rule = 'a blank name does not hide the path'
        Variables = @{ LIBTMUX_SOCKET = ' '; LIBTMUX_SOCKET_PATH = $path }; Flag = '-S'; Value = $path }
    @{ Id = 'retired'; Rule = 'LIBTMUX_SOCKET_NAME selects nothing'
        Variables = @{ LIBTMUX_SOCKET_NAME = $name }; Flag = 'none' }
    @{ Id = 'parameter-name'; Rule = '-SocketName beats both variables'
        Variables = @{ LIBTMUX_SOCKET = $name; LIBTMUX_SOCKET_PATH = $path }
        Arguments = @('-SocketName', $other); Flag = '-L'; Value = $other }
    @{ Id = 'parameter-path'; Rule = '-SocketPath beats both variables'
        Variables = @{ LIBTMUX_SOCKET = $name; LIBTMUX_SOCKET_PATH = $path }
        Arguments = @('-SocketPath', $otherPath); Flag = '-S'; Value = $otherPath }
    @{ Id = 'late'; Rule = 'a variable set after the handle is made changes nothing'
        Variables = @{ LIBTMUX_SOCKET = $name }; Late = $true; Flag = '-L'; Value = $name }
    @{ Id = 'pane'; Rule = 'a handle that chose nothing follows TMUX'
        Variables = @{ TMUX = $pane }; Flag = 'none'; Tmux = $true }
    @{ Id = 'pane-variable'; Rule = 'a variable keeps TMUX from the server it names'
        Variables = @{ TMUX = $pane; LIBTMUX_SOCKET = $name }; Flag = '-L'; Value = $name; Tmux = $false }
    @{ Id = 'pane-path'; Rule = 'a path keeps TMUX from the server it names'
        Variables = @{ TMUX = $pane; LIBTMUX_SOCKET_PATH = $path }; Flag = '-S'; Value = $path; Tmux = $false }
    @{ Id = 'pane-parameter'; Rule = 'a parameter keeps TMUX from the server it names'
        Variables = @{ TMUX = $pane }; Arguments = @('-SocketName', $other); Flag = '-L'; Value = $other; Tmux = $false }
    @{ Id = 'workspace-neither'; Rule = 'a workspace plan on a bare handle passes no socket'
        Variables = @{}; Workspace = $true; Flag = 'none' }
    @{ Id = 'workspace-name'; Rule = 'a workspace plan on a bare handle follows LIBTMUX_SOCKET'
        Variables = @{ LIBTMUX_SOCKET = $name }; Workspace = $true; Flag = '-L'; Value = $name })

$started = [Collections.Generic.List[object]]::new()
try {
    foreach ($case in $cases) {
        $case.Record = Join-Path $scratch "$($case.Id).record"
        $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
        foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $PSCommandPath, '-ModuleRoot', $ModuleRoot, '-Child')) {
            $start.ArgumentList.Add($argument)
        }
        if ($case['Workspace']) { $start.ArgumentList.Add('-Workspace') }
        if ($case['Late']) { $start.ArgumentList.Add('-Late') }
        foreach ($argument in @($case['Arguments'])) { if ($argument) { $start.ArgumentList.Add($argument) } }
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        Clear-TestSandboxSelector $start
        foreach ($variable in $case.Variables.Keys) { $start.Environment[$variable] = $case.Variables[$variable] }
        $start.Environment['LIBTMUX_CONTROL_TRANSPORT'] = '0'
        $start.Environment['LIBTMUX_TEST_TMUX'] = $recorder
        $start.Environment['LIBTMUX_TEST_RECORD'] = $case.Record
        $case.Process = [Diagnostics.Process]::Start($start)
        $case.Output = $case.Process.StandardOutput.ReadToEndAsync()
        $case.Errors = $case.Process.StandardError.ReadToEndAsync()
        $started.Add($case)
    }

    # Each rule fails when the calls break it. The same check is handed calls that do, to
    # show that it can tell: a name that stands in for none, both flags, the wrong flag, the
    # wrong socket, and a TMUX that is handed or kept back.
    function New-Call([string[]] $Arguments, [string[]] $Set = @()) {
        [pscustomobject]@{ Arguments = [Collections.Generic.List[string]]::new($Arguments)
            Set = [Collections.Generic.List[string]]::new($Set) }
    }
    $none = @{ Flag = 'none' }
    $byName = @{ Flag = '-L'; Value = 'wanted' }
    $byPath = @{ Flag = '-S'; Value = 'wanted' }
    foreach ($control in @(
        @{ Fault = 'a default name for no socket'; Case = $none; Calls = @(New-Call '-u', '-L', 'default', 'list-sessions') }
        @{ Fault = 'a path for no socket'; Case = $none; Calls = @(New-Call '-u', '-S', 'x', 'list-sessions') }
        @{ Fault = 'both flags for a path'; Case = $byPath; Calls = @(New-Call '-u', '-L', 'wanted', '-S', 'wanted', 'list-sessions') }
        @{ Fault = 'no flag for a name'; Case = $byName; Calls = @(New-Call '-u', 'list-sessions') }
        @{ Fault = 'a name for a path'; Case = $byPath; Calls = @(New-Call '-u', '-L', 'wanted', 'list-sessions') }
        @{ Fault = 'another name'; Case = $byName; Calls = @(New-Call '-u', '-L', 'unwanted', 'list-sessions') }
        @{ Fault = 'a flag with no socket after it'; Case = $byName; Calls = @(New-Call '-u', '-L') }
        @{ Fault = 'TMUX kept back from a bare handle'; Case = @{ Flag = 'none'; Tmux = $true }
            Calls = @(New-Call '-u', 'list-sessions') }
        @{ Fault = 'TMUX handed to a chosen socket'; Case = @{ Flag = '-L'; Value = 'wanted'; Tmux = $false }
            Calls = @(New-Call '-u', '-L', 'wanted', 'list-sessions' -Set 'TMUX') }
        @{ Fault = 'a version probe and nothing else'; Case = $none; Calls = @(New-Call '-V') })) {
        Assert-Socket (-not [string]::IsNullOrEmpty((Get-RouteProblem $control.Calls $control.Case))) `
            "the check did not catch $($control.Fault)."
    }
    $right = @((New-Call '-V'), (New-Call '-u', '-L', 'wanted', 'list-sessions'))
    Assert-Socket ([string]::IsNullOrEmpty((Get-RouteProblem $right $byName))) 'the check refused a call that is right.'

    $failures = [Collections.Generic.List[string]]::new()
    foreach ($case in $started) {
        if (-not $case.Process.WaitForExit(60000)) { $case.Process.Kill($true); throw "Socket default: case $($case.Id) exceeded its deadline." }
        $null = $case.Output.GetAwaiter().GetResult()
        $null = $case.Errors.GetAwaiter().GetResult()
        $problem = Get-RouteProblem @(Read-RecordedCall $case.Record) $case
        # A process that died before it reached tmux says so here, not only by its silence.
        if ($problem -and $case.Process.ExitCode -ne 0) { $problem += " (the process exited with $($case.Process.ExitCode))" }
        if ($problem) { $failures.Add("$($case.Rule) ($($case.Id)): $problem.") }
    }
    Assert-Socket ($failures.Count -eq 0) ("$($failures.Count) of $($cases.Count) cases failed:`n" + ($failures -join "`n"))
} finally {
    foreach ($case in $started) {
        try { if (-not $case.Process.HasExited) { $case.Process.Kill($true) } } catch { $null = $_ }
        $case.Process.Dispose()
    }
}

"PASS socket default: $($cases.Count) cases for no socket, both variables, blank values, parameters, TMUX and the workspace"
