function Assert-ResourceCancellationRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Record,
        [Parameter(Mandatory)] [string] $ExpectedIdentity,
        [Parameter(Mandatory)] [int] $BaselineClientCount,
        [Parameter(Mandatory)] [string] $Lane
    )

    if ($Record.lane -cnotin @('timeout', 'pipeline-stop')) {
        throw "$Lane has an unknown cancellation path."
    }
    if (!$Record.clientStartAcknowledged -or !$Record.activeClientAlive -or
        !$Record.clientExited -or $Record.outputCount -ne 0 -or
        !$Record.nextSignalObserved -or $Record.identityAfter -cne $ExpectedIdentity) {
        throw "$Lane did not withdraw its waiter or preserve the owned topology."
    }
    if ($Record.clientCount.after -ne $BaselineClientCount -or
        $Record.processCount.after -ne $Record.processCount.before -or
        $Record.processCount.active -ne $Record.processCount.before + 1) {
        throw "$Lane left an owned client or process behind."
    }
    if ($Record.rssBytes.activeClient -le 0 -or $Record.rssBytes.beforePowerShell -le 0 -or
        $Record.rssBytes.afterPowerShell -le 0 -or $Record.rssBytes.beforeServer -le 0 -or
        $Record.rssBytes.afterServer -le 0 -or
        $Record.timingNanoseconds.startToClientMarker -le 0 -or
        $Record.timingNanoseconds.triggerToCompletion -le 0) {
        throw "$Lane omitted a resource or timing observation."
    }
    if ($Record.lane -ceq 'timeout') {
        if ($Record.pipelineState -cne 'Completed' -or $Record.errorCount -ne 1 -or
            $Record.errorType -cne 'System.TimeoutException' -or
            $Record.errorCategory -cne 'OperationTimeout' -or
            $Record.errorId -cnotlike 'Tmux.ChannelWaitFailed,*' -or $Record.stopExceptionType) {
            throw "$Lane lost the timeout outcome."
        }
    } elseif ($Record.pipelineState -cne 'Stopped' -or $Record.errorCount -ne 0 -or
        $Record.stopExceptionType -cne 'System.Management.Automation.PipelineStoppedException') {
        throw "$Lane lost the pipeline-stop outcome."
    }
    $true
}

Export-ModuleMember -Function Assert-ResourceCancellationRecord
