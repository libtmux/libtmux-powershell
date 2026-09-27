function Assert-OutputLatencyRound {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Observation,
        [Parameter(Mandatory)] [string] $Lane
    )

    if (!$Observation.token -or !$Observation.expectedPaneId -or
        $Observation.eventPaneId -cne $Observation.expectedPaneId -or $Observation.dropped -or
        !$Observation.initialAbsent) {
        throw "$Lane lost the token, pane identity, or event stream."
    }
    if ($Observation.markerTicks -le 0 -or $Observation.pollerReadyTicks -le 0 -or
        $Observation.markerTicks -ge $Observation.startTicks -or
        $Observation.pollerReadyTicks -ge $Observation.startTicks -or
        $Observation.eventTicks -le $Observation.startTicks -or
        $Observation.captureTicks -le $Observation.startTicks -or
        $Observation.deadlineTicks -le $Observation.startTicks -or
        $Observation.eventTicks -gt $Observation.deadlineTicks -or
        $Observation.captureTicks -gt $Observation.deadlineTicks) {
        throw "$Lane did not arm both observers before sending the token."
    }
    if ($Observation.eventFragments -lt 1 -or $Observation.captureAttempts -lt 1 -or
        !$Observation.eventText.Contains($Observation.token, [StringComparison]::Ordinal) -or
        !$Observation.captureText.Contains($Observation.token, [StringComparison]::Ordinal)) {
        throw "$Lane did not observe the same output token in both paths."
    }
}

Export-ModuleMember -Function Assert-OutputLatencyRound
