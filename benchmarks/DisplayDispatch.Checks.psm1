function Assert-BenchmarkDisplayReplySet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Expected,
        [Parameter(Mandatory)] [object[]] $Observed,
        [Parameter(Mandatory)] [string] $Lane,
        [switch] $RequireOrder
    )

    if ($Observed.Count -ne $Expected.Count) {
        throw "$Lane returned $($Observed.Count) replies; expected $($Expected.Count)."
    }
    $seen = [bool[]]::new($Expected.Count)
    for ($position = 0; $position -lt $Observed.Count; $position++) {
        $item = $Observed[$position]
        if ($null -eq $item -or $item.index -isnot [int] -or
            $item.index -lt 0 -or $item.index -ge $Expected.Count) {
            throw "$Lane returned an invalid reply index at position $position."
        }
        $index = $item.index
        if ($seen[$index]) { throw "$Lane returned duplicate reply index $index." }
        $seen[$index] = $true
        if ($item.reply -isnot [string] -or
            ![string]::Equals($Expected[$index], $item.reply, [StringComparison]::Ordinal)) {
            throw "$Lane returned a different reply for index $index."
        }
        if ($RequireOrder -and $index -ne $position) {
            throw "$Lane returned index $index at serial position $position."
        }
    }
}

Export-ModuleMember -Function Assert-BenchmarkDisplayReplySet
