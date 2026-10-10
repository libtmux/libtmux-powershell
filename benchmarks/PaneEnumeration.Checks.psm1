function Assert-BenchmarkPaneIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Reference,
        [Parameter(Mandatory)] [string[]] $Observed,
        [Parameter(Mandatory)] [string] $Lane
    )

    $expected = [string[]] $Reference.Clone()
    $actual = [string[]] $Observed.Clone()
    [Array]::Sort($expected, [StringComparer]::Ordinal)
    [Array]::Sort($actual, [StringComparer]::Ordinal)
    if ($expected.Length -ne $actual.Length) {
        throw "$Lane returned $($actual.Length) pane IDs; expected $($expected.Length)."
    }
    for ($index = 0; $index -lt $expected.Length; $index++) {
        if ($expected[$index] -cne $actual[$index]) {
            throw "$Lane returned different pane IDs: expected $($expected -join ', '); observed $($actual -join ', ')."
        }
    }
}

Export-ModuleMember -Function Assert-BenchmarkPaneIdentity
