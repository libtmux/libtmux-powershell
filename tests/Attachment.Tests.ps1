param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: foreground attachment needs an owned Unix PTY and live tmux.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/AttachmentPty.ps1"

function Assert-Attachment([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Attachment: $Message" }
}

$command = Get-Command 'LibTmux\Enter-TmuxSession' -ErrorAction SilentlyContinue
Assert-Attachment ($null -ne $command) 'installed module has no Enter-TmuxSession'
Assert-Attachment ($command.OutputType[0].Type -eq [LibTmux.Session]) 'output metadata is not native Session'
Assert-Attachment ($command.Parameters.ContainsKey('WhatIf') -and $command.Parameters.ContainsKey('Confirm')) 'ShouldProcess metadata is missing'
Assert-Attachment (@(@() | LibTmux\Enter-TmuxSession).Count -eq 0) 'empty pipeline emitted output'

Invoke-WithOwnedTmux {
    param($fixture)
    $trace = Join-Path $fixture.DirectoryPath 'attach-trace'
    $wrapper = Join-Path $fixture.DirectoryPath 'traced-tmux'
    $quotedBinary = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    $quotedTrace = "'" + $trace.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' called >> $quotedTrace
exec $quotedBinary "`$@"
"@ | Set-Content -LiteralPath $wrapper -Encoding utf8NoBOM
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper
    $session = $server | LibTmux\Get-TmuxSession -Name fixture
    $before = [IO.File]::ReadAllLines($trace).Length
    Assert-Attachment (@($session | LibTmux\Enter-TmuxSession -WhatIf).Count -eq 0) 'WhatIf emitted a false result'
    Assert-Attachment ([IO.File]::ReadAllLines($trace).Length -eq $before) 'WhatIf reached tmux'

    $resultPath = Join-Path $fixture.DirectoryPath 'redirected.json'
    $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $null = $start.Environment.Remove('TMUX')
    $null = $start.Environment.Remove('TMUX_PANE')
    foreach ($argument in @('-NoLogo', '-NoProfile', '-File', "$PSScriptRoot/support/AttachmentChild.ps1",
        '-ModuleRoot', $ModuleRoot, '-Binary', $fixture.TmuxPath, '-Socket', $fixture.SocketPath,
        '-SessionId', $session.Id.ToString(), '-Mode', 'Redirected', '-ResultPath', $resultPath)) {
        $start.ArgumentList.Add($argument)
    }
    $child = [Diagnostics.Process]::new()
    $child.StartInfo = $start
    $started = $false
    try {
        $started = $child.Start()
        $fixture.ClientProcesses.Add($child)
        $null = $fixture.OwnedProcessIds.Add($child.Id)
        $child.StandardInput.Close()
        $output = $child.StandardOutput.ReadToEndAsync()
        $errorOutput = $child.StandardError.ReadToEndAsync()
        if (!$child.WaitForExit(5000)) { throw 'Redirected attachment child exceeded its outer deadline.' }
        if ($child.ExitCode -ne 0) { throw "Redirected attachment child failed: $($errorOutput.GetAwaiter().GetResult()) $($output.GetAwaiter().GetResult())" }
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        Assert-Attachment ($result.outcome -ceq 'RedirectedRejected') 'redirected stdin was not rejected explicitly'
        Assert-Attachment (@($server | LibTmux\Get-TmuxClient).Count -eq 0) 'redirected rejection left an attachment client'
    } finally {
        if ($started -and !$child.HasExited) {
            $child.Kill($true)
            if (!$child.WaitForExit(1000)) { throw 'Redirected attachment child did not exit.' }
        }
        if (!$started) { $child.Dispose() }
    }
}
'PASS attachment metadata, empty input, WhatIf zero dispatch, explicit redirected-stdin rejection'

$receipt = Invoke-AttachmentPty -ModuleRoot $ModuleRoot -Modes @('Detach', 'Cancel', 'Nested', 'WhatIf')
Assert-Attachment ($receipt.cases.Count -eq 4 -and $receipt.ownedClientsExited -and $receipt.fixtureRemoved) 'PTY cases or owned cleanup were incomplete'
'PASS foreground input, detach, pipeline stop, nested rejection, terminal restoration and owned cleanup'
