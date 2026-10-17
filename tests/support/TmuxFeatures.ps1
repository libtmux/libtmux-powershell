# Per-feature tmux requirements, read from the tmux first on PATH.
$script:FeatureFloors = @{ Control = '3.7'; NamedBuffers = '3.4' }

function Get-TestTmuxVersion {
    $tmux = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $null = (& $tmux -V) -match '^\S+ (\S+)$'
    [LibTmux.TmuxVersion]::Parse($Matches[1])
}

function Test-TmuxFeature([ValidateSet('Control', 'NamedBuffers')] [string] $Name) {
    (Get-TestTmuxVersion) -ge [LibTmux.TmuxVersion]::Parse($script:FeatureFloors[$Name])
}

# A skipped section is reported, never counted as a pass; Features.Tests.ps1 asserts the refusal.
function Write-FeatureSkip([string] $Section, [ValidateSet('Control', 'NamedBuffers')] [string] $Name) {
    "SKIP ${Section}: needs tmux $($script:FeatureFloors[$Name]) for $Name; this daemon reports $((Get-TestTmuxVersion).Raw)"
}
