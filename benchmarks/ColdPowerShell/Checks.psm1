Import-Module "$PSScriptRoot/../PaneEnumeration.Checks.psm1" -Force

function Assert-ColdPowerShellResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)] [string[]] $ExpectedPaneIds,
        [Parameter(Mandatory)] [string] $Lane
    )

    foreach ($name in @('paneIds', 'importNanoseconds', 'serverConstructionNanoseconds',
        'firstSnapshotNanoseconds', 'moduleVersion', 'coreAssemblyMvid', 'cmdletAssemblyMvid')) {
        if ($name -cnotin $Result.PSObject.Properties.Name) {
            throw "$Lane omitted $name."
        }
    }
    foreach ($name in @('importNanoseconds', 'serverConstructionNanoseconds',
        'firstSnapshotNanoseconds')) {
        try { $duration = [long] $Result.$name } catch { throw "$Lane has an invalid $name." }
        if ($duration -le 0) { throw "$Lane has an invalid $name." }
    }
    foreach ($name in @('moduleVersion', 'coreAssemblyMvid', 'cmdletAssemblyMvid')) {
        if ([string]::IsNullOrWhiteSpace([string] $Result.$name)) {
            throw "$Lane omitted $name."
        }
    }

    Assert-BenchmarkPaneIdentity -Reference $ExpectedPaneIds -Observed ([string[]] @($Result.paneIds)) -Lane $Lane
}

Export-ModuleMember -Function Assert-ColdPowerShellResult
