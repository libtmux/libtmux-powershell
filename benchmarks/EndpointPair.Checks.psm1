function Assert-EndpointPairReplySet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Expected,
        [Parameter(Mandatory)] [object[]] $Observed,
        [Parameter(Mandatory)] [string[]] $StateAfter,
        [Parameter(Mandatory)] [string] $Lane,
        [switch] $RequireOrder
    )

    if ($Expected.Count -ne 2 -or $Expected[0] -ceq $Expected[1]) {
        throw "$Lane requires two distinct endpoint identities."
    }
    if ($Observed.Count -ne 2 -or $StateAfter.Count -ne 2) {
        throw "$Lane did not cover both endpoints."
    }
    $seen = [bool[]]::new(2)
    for ($position = 0; $position -lt 2; $position++) {
        $item = $Observed[$position]
        if ($null -eq $item -or $item.index -isnot [int] -or
            $item.index -lt 0 -or $item.index -ge 2) {
            throw "$Lane returned an invalid endpoint index."
        }
        $index = $item.index
        if ($seen[$index]) { throw "$Lane returned endpoint $index twice." }
        $seen[$index] = $true
        if ($RequireOrder -and $index -ne $position) {
            throw "$Lane changed serial endpoint order."
        }
        if ($item.reply -isnot [string] -or
            ![string]::Equals($item.reply, $Expected[$index], [StringComparison]::Ordinal)) {
            throw "$Lane returned the wrong reply for endpoint $index."
        }
    }
    for ($index = 0; $index -lt 2; $index++) {
        if (![string]::Equals($StateAfter[$index], $Expected[$index], [StringComparison]::Ordinal)) {
            throw "$Lane changed endpoint $index after the read."
        }
    }
}

Export-ModuleMember -Function Assert-EndpointPairReplySet
