function Assert-BenchmarkQuerySelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $ExpectedPlacements,
        [Parameter(Mandatory)] [string[]] $ObservedPlacements,
        [Parameter(Mandatory)] [int] $ExpectedSessions,
        [Parameter(Mandatory)] [int] $ObservedSessions,
        [Parameter(Mandatory)] [int] $ExpectedWindows,
        [Parameter(Mandatory)] [int] $ObservedWindows,
        [Parameter(Mandatory)] [int] $ExpectedPanes,
        [Parameter(Mandatory)] [int] $ObservedPanes,
        [Parameter(Mandatory)] [string] $Lane,
        [switch] $RequireOrder
    )

    if ($ObservedSessions -ne $ExpectedSessions -or $ObservedWindows -ne $ExpectedWindows -or
        $ObservedPanes -ne $ExpectedPanes) {
        throw "$Lane returned an incomplete captured graph."
    }
    if ($ObservedPlacements.Count -ne $ExpectedPlacements.Count) {
        throw "$Lane returned $($ObservedPlacements.Count) placements; expected $($ExpectedPlacements.Count)."
    }
    if ($RequireOrder) {
        for ($index = 0; $index -lt $ExpectedPlacements.Count; $index++) {
            if ($ObservedPlacements[$index] -cne $ExpectedPlacements[$index]) {
                throw "$Lane changed local input order at placement $index."
            }
        }
    }
    $reference = [string[]] $ExpectedPlacements.Clone()
    $actual = [string[]] $ObservedPlacements.Clone()
    [Array]::Sort($reference, [StringComparer]::Ordinal)
    [Array]::Sort($actual, [StringComparer]::Ordinal)
    for ($index = 0; $index -lt $reference.Length; $index++) {
        if ($actual[$index] -cne $reference[$index]) {
            throw "$Lane returned different placement identities."
        }
    }
}

Export-ModuleMember -Function Assert-BenchmarkQuerySelection
