function Assert-BenchmarkCaptureEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Reference,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Observed,
        [Parameter(Mandatory)] [string] $Lane
    )

    if (![string]::Equals($Reference, $Observed, [StringComparison]::Ordinal)) {
        $index = 0
        $limit = [Math]::Min($Reference.Length, $Observed.Length)
        while ($index -lt $limit -and $Reference[$index] -ceq $Observed[$index]) { $index++ }
        $expectedCode = if ($index -lt $Reference.Length) { [int] $Reference[$index] } else { 'end' }
        $observedCode = if ($index -lt $Observed.Length) { [int] $Observed[$index] } else { 'end' }
        throw "$Lane returned different captured text at character $index (expected $expectedCode, observed $observedCode; lengths $($Reference.Length) and $($Observed.Length))."
    }
}

function Assert-BenchmarkCaptureFixture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $ExpectedLines,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Observed,
        [Parameter(Mandatory)] [string] $Size
    )

    $lines = $Observed.Split("`n")
    if ($lines.Length -lt $ExpectedLines.Length) {
        throw "$Size capture lost payload lines: $($lines.Length) observed; $($ExpectedLines.Length) expected."
    }
    for ($index = 0; $index -lt $ExpectedLines.Length; $index++) {
        if ($lines[$index] -cne $ExpectedLines[$index]) {
            throw "$Size capture changed payload line $index."
        }
    }
    for ($index = $ExpectedLines.Length; $index -lt $lines.Length; $index++) {
        if ($lines[$index] -cne '') {
            throw "$Size capture added nonempty text after the payload."
        }
    }
}

Export-ModuleMember -Function Assert-BenchmarkCaptureEqual, Assert-BenchmarkCaptureFixture
