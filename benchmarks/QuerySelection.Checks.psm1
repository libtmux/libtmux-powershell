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

function Assert-BenchmarkQueryGraph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $ExpectedSessionIds,
        [Parameter(Mandatory)] [string[]] $ObservedSessionIds,
        [Parameter(Mandatory)] [string[]] $ExpectedWindowPlacements,
        [Parameter(Mandatory)] [string[]] $ObservedWindowPlacements,
        [Parameter(Mandatory)] [string[]] $ExpectedPanePlacements,
        [Parameter(Mandatory)] [string[]] $ObservedPanePlacements,
        [Parameter(Mandatory)] [string] $Lane
    )

    $relations = @(
        @{ kind = 'session'; expected = $ExpectedSessionIds; observed = $ObservedSessionIds }
        @{ kind = 'window'; expected = $ExpectedWindowPlacements; observed = $ObservedWindowPlacements }
        @{ kind = 'pane'; expected = $ExpectedPanePlacements; observed = $ObservedPanePlacements }
    )
    foreach ($relation in $relations) {
        $kind = $relation.kind
        $expected = [string[]] $relation.expected
        $observed = [string[]] $relation.observed
        if ($observed.Length -ne $expected.Length) {
            throw "$Lane returned $($observed.Length) $kind identities; expected $($expected.Length)."
        }
        $want = [string[]] $expected.Clone()
        $actual = [string[]] $observed.Clone()
        [Array]::Sort($want, [StringComparer]::Ordinal)
        [Array]::Sort($actual, [StringComparer]::Ordinal)
        for ($index = 0; $index -lt $want.Length; $index++) {
            if ($actual[$index] -cne $want[$index]) {
                throw "$Lane returned different $kind identities."
            }
        }
    }
}

Export-ModuleMember -Function Assert-BenchmarkQuerySelection, Assert-BenchmarkQueryGraph
