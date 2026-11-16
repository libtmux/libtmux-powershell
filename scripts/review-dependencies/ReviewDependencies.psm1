# Uses one source-pinned CORE review build in an isolated CI checkout.
# ReviewDependencies.ps1 is the command line.
Set-StrictMode -Version Latest

$script:Shared = @('LibTmux', 'LibTmux.Query.Json', 'LibTmux.Workspace')
$script:Locks = @('src/LibTmux.PowerShell/packages.lock.json', 'src/LibTmux.Workspace.PowerShell/packages.lock.json')

function Stop-Review([string] $Message) {
    throw [InvalidOperationException]::new($Message)
}

# Returns the parsed props file and the shared PackageVersion elements by name.
function Read-SharedPins([string] $Root) {
    $document = [xml]::new()
    $document.PreserveWhitespace = $false
    $document.Load((Join-Path $Root 'Directory.Packages.props'))
    $found = [ordered]@{}
    foreach ($element in $document.GetElementsByTagName('PackageVersion')) {
        $name = $element.GetAttribute('Include')
        if ($name -cin $script:Shared) {
            if ($found.Contains($name)) { Stop-Review "duplicate shared dependency pin: $name" }
            $found[$name] = $element
        }
    }
    if ($found.Count -ne $script:Shared.Count) { Stop-Review 'all three shared dependency pins are required' }
    $values = @($found.Values | ForEach-Object { $_.GetAttribute('Version') } | Select-Object -Unique)
    if ($values.Count -ne 1 -or $values[0] -cnotmatch '^\[[^\[\]]+\]\z') {
        Stop-Review 'shared dependency pins must have matching exact versions'
    }
    @{ Document = $document; Pins = $found }
}

function Get-BasePin($Pins) {
    $pin = $Pins[$script:Shared[0]].GetAttribute('Version')
    $pin.Substring(1, $pin.Length - 2)
}

function Get-ReviewVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root, [Parameter(Mandatory)] [long] $RunId, [Parameter(Mandatory)] [long] $Attempt)
    if ($RunId -lt 1 -or $Attempt -lt 1) { Stop-Review 'run ID and attempt must be positive' }
    $base = Get-BasePin (Read-SharedPins $Root).Pins
    if ($base -cnotmatch '^\d+\.\d+\.\d+-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*\z') {
        Stop-Review 'base shared dependency pin must be a prerelease'
    }
    "$base.ci.$RunId.$Attempt"
}

# Rewrites the three shared pins to the review version and keeps the committed
# locks as the baseline `Test-ReviewLocks` compares against.
function Initialize-ReviewPins {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root, [Parameter(Mandatory)] [string] $Version, [Parameter(Mandatory)] [string] $Baseline)
    $read = Read-SharedPins $Root
    $base = Get-BasePin $read.Pins
    if ($Version -cnotmatch ('^' + [regex]::Escape($base) + '\.ci\.[1-9]\d*\.[1-9]\d*\z')) {
        Stop-Review 'CI review version must extend the exact shared pin'
    }
    if (Test-Path -LiteralPath $Baseline) { Stop-Review 'CI lock baseline already exists' }
    foreach ($relative in $script:Locks) {
        if (!(Test-Path -LiteralPath (Join-Path $Root $relative) -PathType Leaf)) {
            Stop-Review "missing committed dependency lock: $relative"
        }
    }
    foreach ($relative in $script:Locks) {
        $target = Join-Path $Baseline $relative
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
        Copy-Item -LiteralPath (Join-Path $Root $relative) -Destination $target
    }
    foreach ($element in $read.Pins.Values) { $element.SetAttribute('Version', "[$Version]") }
    $settings = [Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.IndentChars = '  '
    $settings.OmitXmlDeclaration = $true
    $settings.NewLineChars = "`n"
    $settings.Encoding = [Text.UTF8Encoding]::new($false)
    $writer = [Xml.XmlWriter]::Create((Join-Path $Root 'Directory.Packages.props'), $settings)
    try { $read.Document.Save($writer) } finally { $writer.Dispose() }
    [IO.File]::AppendAllText((Join-Path $Root 'Directory.Packages.props'), "`n", [Text.UTF8Encoding]::new($false))
}

# Returns a lock as nested sorted dictionaries, with the review version put back
# to the base pin and the content hash of each shared package dropped, so two
# locks compare equal when only the review package bytes differ.
function ConvertTo-NormalLock($Value, [string] $Version, [string] $Base, [bool] $Top = $true) {
    if ($Value -is [string]) { return $Value.Replace($Version, $Base) }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in ($Value.Keys | Sort-Object { $_ } -CaseSensitive)) {
            $result[$key] = ConvertTo-NormalLock $Value[$key] $Version $Base $false
        }
        if ($Top -and $result.Contains('dependencies') -and $result['dependencies'] -is [System.Collections.IDictionary]) {
            foreach ($packages in $result['dependencies'].Values) {
                foreach ($name in $script:Shared) {
                    if ($packages.Contains($name)) { $packages[$name].Remove('contentHash') }
                }
            }
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        return , @($Value | ForEach-Object { ConvertTo-NormalLock $_ $Version $Base $false })
    }
    $Value
}

function Read-Lock([string] $Path) {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}

# Checks that the locks resolve the review version and differ from the baseline
# only in the review packages' own hashes.
function Test-ReviewLocks {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root, [Parameter(Mandatory)] [string] $Version, [Parameter(Mandatory)] [string] $Baseline)
    $pins = (Read-SharedPins $Root).Pins
    if ($pins[$script:Shared[0]].GetAttribute('Version') -cne "[$Version]") {
        Stop-Review 'CI dependency pins differ from the built review version'
    }
    $match = [regex]::Match($Version, '^(.+)\.ci\.[1-9]\d*\.[1-9]\d*\z')
    if (!$match.Success) { Stop-Review 'invalid CI review version' }
    $base = $match.Groups[1].Value
    foreach ($relative in $script:Locks) {
        $old = Read-Lock (Join-Path $Baseline $relative)
        $new = Read-Lock (Join-Path $Root $relative)
        if ($old.Contains('dependencies')) {
            foreach ($framework in $old['dependencies'].Keys) {
                $updated = @{}
                if ($new.Contains('dependencies') -and $new['dependencies'].Contains($framework)) {
                    $updated = $new['dependencies'][$framework]
                }
                foreach ($name in $script:Shared) {
                    if (!$old['dependencies'][$framework].Contains($name)) { continue }
                    $resolved = $null
                    if ($updated.Contains($name) -and $updated[$name].Contains('resolved')) {
                        $resolved = $updated[$name]['resolved']
                    }
                    if ($resolved -cne $Version) { Stop-Review "$relative does not resolve CI review version for $name" }
                }
            }
        }
        $left = ConvertTo-Json -InputObject (ConvertTo-NormalLock $old $Version $base) -Depth 20 -Compress
        $right = ConvertTo-Json -InputObject (ConvertTo-NormalLock $new $Version $base) -Depth 20 -Compress
        if ($left -cne $right) { Stop-Review "unexpected dependency graph change: $relative" }
    }
}

Export-ModuleMember -Function Get-ReviewVersion, Initialize-ReviewPins, Test-ReviewLocks
