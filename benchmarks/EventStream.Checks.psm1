function Assert-BenchmarkEventBurst {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int] $ExpectedBurst,
        [Parameter(Mandatory)] [string] $ExpectedWindowId,
        [Parameter(Mandatory)] [string] $ExpectedFinalName,
        [Parameter(Mandatory)] [object[]] $Events,
        [Parameter(Mandatory)] [string] $ObservedFinalName,
        [Parameter(Mandatory)] [long] $PreviousTotalDropped,
        [Parameter(Mandatory)] [string] $Lane
    )

    if ($ExpectedBurst -lt 2 -or $Events.Count -ne 2 -or
        $Events[0].kind -cne 'dropped' -or $Events[1].kind -cne 'notification') {
        throw "$Lane did not return one loss record followed by one notification."
    }
    $dropped = $Events[0]
    $latest = $Events[1]
    if ($dropped.count -ne $ExpectedBurst - 1) {
        throw "$Lane did not account for every produced notification."
    }
    if ($dropped.totalDropped -ne $PreviousTotalDropped + $dropped.count) {
        throw "$Lane returned an inconsistent cumulative loss count."
    }
    if ($latest.name -cne 'window-renamed' -or @($latest.arguments).Count -ne 2 -or
        $latest.arguments[0] -cne $ExpectedWindowId -or
        $latest.arguments[1] -cne $ExpectedFinalName) {
        throw "$Lane did not retain the final window-renamed notification."
    }
    if ($ObservedFinalName -cne $ExpectedFinalName) {
        throw "$Lane did not leave the native window at the final name."
    }
    [pscustomobject]@{ produced = $ExpectedBurst; delivered = 1; dropped = $dropped.count;
        totalDropped = $dropped.totalDropped }
}

Export-ModuleMember -Function Assert-BenchmarkEventBurst
