param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [Parameter(Mandatory)] [string] $Binary,
    [Parameter(Mandatory)] [string] $Socket,
    [Parameter(Mandatory)] [string] $SessionId,
    [Parameter(Mandatory)] [ValidateSet('Detach', 'ReadOnly', 'Cancel', 'Nested', 'WhatIf', 'Redirected')] [string] $Mode,
    [string] $CancelChannel,
    [long] $ReadyHandle = -1,
    [Parameter(Mandatory)] [string] $ResultPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/HangGuard.ps1"
$module = Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1'
Import-Module $module
$server = LibTmux\New-TmuxServer -SocketPath $Socket -TmuxBinaryPath $Binary
$session = $server.GetSessionAsync([LibTmux.SessionId]::Parse($SessionId)).GetAwaiter().GetResult()
$report = @{ mode = $Mode; outcome = 'NotStarted'; powershell = $PSVersionTable.PSVersion.ToString() }
$runspace = $null
$pipeline = $null
function Send-AttachmentPrepared {
    param([long] $Descriptor)
    if ($Descriptor -lt 0) { return }
    $handle = [Microsoft.Win32.SafeHandles.SafeFileHandle]::new([IntPtr] $Descriptor, $true)
    $stream = $null
    try {
        $stream = [IO.FileStream]::new($handle, [IO.FileAccess]::Write)
        $stream.WriteByte(1)
        $stream.Flush()
    } finally {
        if ($stream) { $stream.Dispose() } else { $handle.Dispose() }
    }
}
try {
    if ($Mode -ceq 'Detach') {
        Import-Module (Join-Path $ModuleRoot 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1')
        $workspace = LibTmux.Workspace\Import-TmuxWorkspace -Yaml @'
session_name: fixture
windows:
  - window_name: workspace-attachment
    focus: true
    options:
      automatic-rename: 'off'
      '@workspace-attachment': installed
    panes:
      - shell_command: stty -echo; printf 'LIBTMUX_ATTACHMENT_%s\n' READY; exec /bin/cat
'@
        $plan = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server `
            -ExistingSession Append -ServerStartup RequireExisting -ErrorAction Stop
        $applied = $plan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
        if ($applied -isnot [LibTmux.Workspace.WorkspaceResult] -or
            $applied.Session.Id.ToString() -cne $SessionId -or $applied.Windows.Count -ne 1 -or
            $applied.Windows[0].Panes.Count -ne 1) {
            throw 'Workspace application did not return the appended native session, window and pane.'
        }
        $session = $applied.Session
        $report.workspaceApplied = $true
        $report.appliedSessionId = $session.Id.ToString()
        $report.workspaceWindowId = $applied.Windows[0].Id.ToString()
        $report.workspacePaneId = $applied.Windows[0].Panes[0].Id.ToString()
    }
    if ($Mode -ceq 'Cancel') {
        # This test host can stop the second pipeline after the observed attach event.
        $initial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
        $initial.ImportPSModule(@($module))
        $runspace = [RunspaceFactory]::CreateRunspace($Host, $initial)
        $runspace.Open()
        $pipeline = [PowerShell]::Create()
        $pipeline.Runspace = $runspace
        $null = $pipeline.AddCommand('LibTmux\Enter-TmuxSession').AddParameter('Session', $session)
        Send-AttachmentPrepared $ReadyHandle
        $invocation = $pipeline.BeginInvoke()
        $wait = $server.OpenWaitChannel($CancelChannel)
        try {
            if (!$wait.WaitAsync($HangGuard).GetAwaiter().GetResult()) {
                throw 'Parent did not signal cancellation after attachment.'
            }
        } finally {
            $wait.DisposeAsync().AsTask().GetAwaiter().GetResult()
        }
        $stop = $pipeline.BeginStop($null, $null)
        if (!$stop.AsyncWaitHandle.WaitOne($HangGuardMilliseconds)) { throw 'Pipeline stop exceeded the hang guard.' }
        $pipeline.EndStop($stop)
        try {
            $null = $pipeline.EndInvoke($invocation)
            throw 'Stopped attachment returned successfully.'
        } catch {
            if ($_.Exception.InnerException -isnot [Management.Automation.PipelineStoppedException]) { throw }
        }
        if ($pipeline.Streams.Error.Count -ne 0) { throw 'Pipeline stop became a cmdlet error.' }
        $report.outcome = 'Stopped'
    } elseif ($Mode -in @('Nested', 'Redirected')) {
        if ($Mode -ceq 'Nested') {
            if ([Console]::IsInputRedirected) { throw 'Nested rejection requires real terminal stdin.' }
            $env:TMUX = 'owned-test-marker'
            $message = '*inside another tmux*'
        } else {
            if (![Console]::IsInputRedirected) { throw 'Redirected rejection requires redirected stdin.' }
            $message = '*requires terminal stdin*'
        }
        $errors = @()
        $result = @($session | LibTmux\Enter-TmuxSession -ErrorAction Continue -ErrorVariable errors 2>$null)
        if ($result.Count -ne 0 -or $errors.Count -ne 1 -or
            $errors[0].Exception -isnot [InvalidOperationException] -or
            $errors[0].FullyQualifiedErrorId -notlike 'Tmux.SessionAttachFailed,*' -or
            ![object]::ReferenceEquals($errors[0].TargetObject, $session) -or
            $errors[0].Exception.Message -notlike $message) { throw "$Mode attachment was not rejected with its native error and target." }
        $report.outcome = $Mode + 'Rejected'
    } elseif ($Mode -ceq 'WhatIf') {
        if (@($session | LibTmux\Enter-TmuxSession -WhatIf).Count -ne 0) { throw 'WhatIf emitted a result.' }
        $report.outcome = 'Previewed'
    } else {
        if ($Mode -ceq 'ReadOnly') {
            . "$PSScriptRoot/HelpExampleAssertions.ps1"
            $id = 'LibTmux\Enter-TmuxSession#2'
            $help = Get-Help 'LibTmux\Enter-TmuxSession' -Full
            if ($help.PSTypeNames -notcontains 'MamlCommandHelpInfo') { throw 'Attachment example has no installed native help.' }
            $code = Get-HelpExampleCode @($help.examples.example)[1] 'Enter-TmuxSession'
            $assertion = (Get-HelpExampleAssertion)[$id]
            $script = [scriptblock]::Create($code)
            Send-AttachmentPrepared $ReadyHandle
            $result = @(& $script)
            & $assertion.Assert $result @{ Session = $session }
            $report.example = $id
            $report.codeSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($code)))
        } else {
            Send-AttachmentPrepared $ReadyHandle
            $result = @($session | LibTmux\Enter-TmuxSession)
        }
        if ($result.Count -ne 1 -or $result[0] -isnot [LibTmux.Session] -or
            $result[0].Id -ne $session.Id -or [object]::ReferenceEquals($session, $result[0])) {
            throw 'Successful detach did not return one refreshed native Session.'
        }
        $report.outcome = 'Returned'
        $report.returnedId = $result[0].Id.ToString()
    }
} catch {
    $report.outcome = 'Failed'
    $report.error = $_.ToString()
    throw
} finally {
    try {
        if ($pipeline) { $pipeline.Dispose() }
    } finally {
        try { if ($runspace) { $runspace.Dispose() } } finally {
            $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ResultPath -Encoding utf8NoBOM
        }
    }
}
