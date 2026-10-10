function Assert-BenchmarkCommandReply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Expected,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Observed,
        [Parameter(Mandatory)] [string] $Lane
    )

    if (![string]::Equals($Expected, $Observed, [StringComparison]::Ordinal)) {
        throw "$Lane returned '$Observed'; expected '$Expected'."
    }
}

Export-ModuleMember -Function Assert-BenchmarkCommandReply
