function Get-StreamPayloadBlock {
    param([string] $Text, [string] $Begin, [string] $End, [string] $Lane)

    $start = $Text.IndexOf($Begin, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "$Lane has no begin marker." }
    if ($Text.IndexOf($Begin, $start + $Begin.Length, [StringComparison]::Ordinal) -ge 0) {
        throw "$Lane has duplicate begin markers."
    }
    $finish = $Text.IndexOf($End, $start + $Begin.Length, [StringComparison]::Ordinal)
    if ($finish -lt 0) { throw "$Lane has no end marker." }
    if ($Text.IndexOf($End, $finish + $End.Length, [StringComparison]::Ordinal) -ge 0) {
        throw "$Lane has duplicate end markers."
    }
    $Text.Substring($start, $finish + $End.Length - $start)
}

function Get-StreamPayloadHash {
    param([string] $Text)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::HashData($bytes)
    [Convert]::ToHexString($sha).ToLowerInvariant()
}

function Assert-StreamPayloadRound {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Observation,
        [Parameter(Mandatory)] [string] $Lane
    )

    if (!$Observation.beginMarker -or !$Observation.endMarker -or !$Observation.payload -or
        !$Observation.expectedPaneId -or $Observation.eventPaneId -cne $Observation.expectedPaneId -or
        $Observation.dropped -or !$Observation.initialAbsent) {
        throw "$Lane lost payload identity, pane identity, or event output."
    }
    if (!$Observation.payload.StartsWith($Observation.beginMarker, [StringComparison]::Ordinal) -or
        !$Observation.payload.EndsWith($Observation.endMarker, [StringComparison]::Ordinal) -or
        $Observation.payload.Contains("`r", [StringComparison]::Ordinal)) {
        throw "$Lane has an invalid expected canonical payload."
    }
    if ($Observation.markerTicks -le 0 -or $Observation.pollerReadyTicks -le 0 -or
        $Observation.markerTicks -ge $Observation.startTicks -or
        $Observation.pollerReadyTicks -ge $Observation.startTicks -or
        $Observation.producerDoneTicks -lt $Observation.startTicks -or
        $Observation.producerDoneTicks -gt $Observation.deadlineTicks -or
        $Observation.eventTicks -le $Observation.startTicks -or
        $Observation.captureTicks -le $Observation.startTicks -or
        $Observation.deadlineTicks -le $Observation.startTicks -or
        $Observation.eventTicks -gt $Observation.deadlineTicks -or
        $Observation.captureTicks -gt $Observation.deadlineTicks) {
        throw "$Lane observers were not ready or completion exceeded the deadline."
    }
    if ($Observation.eventFragments -lt 1 -or $Observation.captureAttempts -lt 1 -or
        !$Observation.eventRaw -or !$Observation.captureText) {
        throw "$Lane did not observe output in both paths."
    }

    $eventRaw = [string] $Observation.eventRaw
    $captureText = [string] $Observation.captureText
    if ([Text.Encoding]::UTF8.GetByteCount($eventRaw) -gt 65536 -or
        [Text.Encoding]::UTF8.GetByteCount($captureText) -gt 65536) {
        throw "$Lane exceeded the per-round observation bound."
    }
    $eventCanonical = $eventRaw.Replace("`r`n", "`n")
    $eventBlock = Get-StreamPayloadBlock $eventCanonical $Observation.beginMarker $Observation.endMarker 'Event stream'
    $captureBlock = Get-StreamPayloadBlock $captureText $Observation.beginMarker $Observation.endMarker 'Rendered capture'
    if ($eventBlock -cne $Observation.payload -or $captureBlock -cne $Observation.payload) {
        throw "$Lane did not observe the exact canonical multiline payload in both paths."
    }
    [pscustomobject]@{
        payloadBytes = [Text.Encoding]::UTF8.GetByteCount($Observation.payload)
        eventRawBytes = [Text.Encoding]::UTF8.GetByteCount($eventRaw)
        captureRawBytes = [Text.Encoding]::UTF8.GetByteCount($captureText)
        payloadSha256 = Get-StreamPayloadHash $Observation.payload
        eventPayloadSha256 = Get-StreamPayloadHash $eventBlock
        capturePayloadSha256 = Get-StreamPayloadHash $captureBlock
    }
}

Export-ModuleMember -Function Assert-StreamPayloadRound
