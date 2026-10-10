param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [switch] $RunExamples,
    [ValidateSet('All', 'Lifecycle', 'CoreFirst', 'CoreSecond', 'CoreThird', 'CoreFourth', 'CoreFifth', 'Workspace', 'Terminal')]
    [string] $ExampleGroup = 'All',
    [ValidateSet('Full', 'Metadata', 'Examples')] [string] $Phase = 'Full',
    [string] $AdmissionPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path

# The registry is independent of discovered help; new examples cannot inherit a fallback assertion.
. "$PSScriptRoot/support/HelpExampleAssertions.ps1"
$assertions = Get-HelpExampleAssertion

function Get-HelpAdmissionContext {
    $files = @(Get-Item $PSCommandPath) + @(Get-ChildItem "$PSScriptRoot/support" -File) + @(
        foreach ($module in @('LibTmux', 'LibTmux.Workspace')) {
            Get-ChildItem (Join-Path $ModuleRoot "$module/0.1.0") -File -Recurse
        }
    )
    $hashes = @($files | Sort-Object FullName | ForEach-Object {
        "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
    })
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes($ModuleRoot + "`n" + ($hashes -join "`n"))))
}

function Get-HelpGroupId([string[]] $Ids, [string] $Group) {
    $core = @($Ids | Where-Object {
        $_.StartsWith('LibTmux\', [StringComparison]::Ordinal) -and !$assertions[$_].ContainsKey('TerminalMode')
    })
    $cut = [int] [Math]::Ceiling($core.Count / 5)
    switch ($Group) {
        'Lifecycle' {
            $commands = @('ConvertTo-TmuxOwnedResource', 'Invoke-TmuxScope',
                'Close-TmuxScope', 'Get-TmuxScopeFailure', 'Find-TmuxServer',
                'Start-TmuxServer', 'Resolve-TmuxServer', 'Resolve-TmuxSession', 'Resolve-TmuxWindow', 'Resolve-TmuxPane')
            $core | Where-Object { $_.Split('\')[1].Split('#')[0] -in $commands }
        }
        'CoreFirst' { $core | Select-Object -First $cut }
        'CoreSecond' { $core | Select-Object -Skip $cut -First $cut }
        'CoreThird' { $core | Select-Object -Skip (2 * $cut) -First $cut }
        'CoreFourth' { $core | Select-Object -Skip (3 * $cut) -First $cut }
        'CoreFifth' { $core | Select-Object -Skip (4 * $cut) }
        'Workspace' { $Ids | Where-Object { $_.StartsWith('LibTmux.Workspace\', [StringComparison]::Ordinal) } }
        'Terminal' { $Ids | Where-Object { $assertions[$_].ContainsKey('TerminalMode') } }
        default { $Ids }
    }
}

$omittedId = 'LibTmux\New-TmuxSession#1'
$requiredCommands = $null
if ($Phase -ne 'Full' -and !$AdmissionPath) { throw '-AdmissionPath is required with -Phase.' }
if ($Phase -eq 'Examples') {
    $admission = Get-Content -LiteralPath $AdmissionPath -Raw | ConvertFrom-Json -AsHashtable
    if ($admission.Kind -cne 'Help' -or $admission.Context -cne (Get-HelpAdmissionContext)) {
        throw 'Help metadata admission does not match the source and installed modules.'
    }
    Assert-HelpExampleRegistration $admission.Examples $assertions
    $selectedIds = @(Get-HelpGroupId @($admission.Examples.Id) $ExampleGroup)
    $requiredIds = @($selectedIds)
    if ($ExampleGroup -in @('All', 'CoreFirst')) { $requiredIds += $omittedId, 'LibTmux\Get-TmuxClient#1' }
    $requiredCommands = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($id in $requiredIds) { $null = $requiredCommands.Add($id.Split('#')[0]) }
    $RunExamples = $true
}

function Invoke-HelpExample($Example, $Assertion, $Context) {
    try {
        $SocketPath = $Context.Fixture.SocketPath
        if ($Assertion.ContainsKey('Prepare')) {
            # Preparation binds the documented native owner in this example's local scope.
            . $Assertion.Prepare $Context
            Register-OwnedTmuxPane $Context.Fixture
        }
        $result = @(& ([scriptblock]::Create($Example.Code)))
        $Context.Executed = $true
        if ($Assertion.Isolated) { Register-OwnedTmuxPane $Context.Fixture }
        if ($result.Count -ne $Assertion.ExpectedCount) {
            throw "$($Example.Id) expected $($Assertion.ExpectedCount) output objects; received $($result.Count)."
        }
        foreach ($item in $result) {
            $types = @($Example.Command.OutputType | ForEach-Object Type)
            $matchingTypes = @($types | Where-Object { $null -ne $_ -and $item -is $_ })
            if (!$matchingTypes.Count) { throw "$($Example.Id) returned the wrong native type." }
            $nativeEntity = $item -is [LibTmux.Session] -or $item -is [LibTmux.Window] -or $item -is [LibTmux.Pane]
            if ($Assertion.Isolated -and $nativeEntity) {
                $actualSocket = $item.Server.ConnectionOptions.SocketPath
                if (!$actualSocket) {
                    # Environment-selected handles retain input options; probe their captured endpoint.
                    $reply = $item.Server | Invoke-TmuxCommand -Arguments @('display-message', '-p', '#{socket_path}')
                    $actualSocket = $reply.StandardOutputLines -join ''
                }
                if ($actualSocket -cne $SocketPath) { throw "$($Example.Id) returned an object from the wrong server." }
            }
        }
        # Zero-output examples still require their registered state-change assertion.
        & $Assertion.Assert $result $Context $Assertion['Expected']
    } finally {
        if ($Assertion.ContainsKey('Cleanup')) { & $Assertion.Cleanup $Context }
    }
}

function Assert-HelpFixtureCleanup($Fixtures) {
    foreach ($fixture in $Fixtures) {
        if (!$fixture.Closed -or (Test-Path -LiteralPath $fixture.DirectoryPath) -or
            (Test-Path -LiteralPath $fixture.SocketPath)) { throw 'Help fixture cleanup left owned resources.' }
        foreach ($processId in $fixture.OwnedProcessIds) {
            $remaining = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($remaining) {
                $remaining.Dispose()
                throw "Help fixture cleanup left an owned process: $processId"
            }
        }
    }
}

$examples = [Collections.Generic.List[object]]::new()
foreach ($module in @('LibTmux', 'LibTmux.Workspace')) {
    Import-Module (Join-Path $ModuleRoot "$module/0.1.0/$module.psd1")
    foreach ($command in Get-Command -Module $module) {
        if ($requiredCommands -and !$requiredCommands.Contains("$module\$($command.Name)")) { continue }
        $help = Get-Help "$module\$($command.Name)" -Full
        if ($help.PSTypeNames -notcontains 'MamlCommandHelpInfo') {
            throw "$($command.Name) has no packaged native help."
        }
        if (!$help.description -or !$help.examples.example) {
            throw "$($command.Name) is missing its description or examples."
        }
        if (($help | Out-String) -match '\{\{.*\}\}') {
            throw "$($command.Name) contains help authoring placeholders."
        }
        $expected = @($command.Parameters.Values | Where-Object {
            $_.Name -notin [Management.Automation.PSCmdlet]::CommonParameters
        })
        $documented = @($help.parameters.parameter)
        if (Compare-Object @($expected.Name | Sort-Object) @($documented.name | Sort-Object)) {
            throw "$($command.Name) help parameters disagree: command=[$($expected.Name -join ', ')], help=[$($documented.name -join ', ')]."
        }
        foreach ($parameter in $expected) {
            $entry = $documented | Where-Object name -EQ $parameter.Name
            $pipeline = @($parameter.Attributes | Where-Object {
                $_ -is [Management.Automation.ParameterAttribute] -and $_.ValueFromPipeline
            }).Count -gt 0
            if (($entry.pipelineInput -match 'true') -ne $pipeline) {
                throw "$($command.Name).$($parameter.Name) help has incorrect pipeline binding."
            }
        }
        $ordinal = 0
        foreach ($example in $help.examples.example) {
            $ordinal++
            $code = Get-HelpExampleCode $example $command.Name
            $id = "$module\$($command.Name)#$ordinal"
            if ($Phase -eq 'Examples') {
                $registered = @($admission.Examples | Where-Object Id -CEQ $id)
                $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($code)))
                if ($registered.Count -ne 1 -or $registered[0].CodeSha256 -cne $digest) {
                    throw "Help example differs from its metadata admission: $id"
                }
            }
            $examples.Add(@{ Id = $id; Command = $command; Code = $code })
        }
    }
}

if ($Phase -ne 'Examples') {
    Assert-HelpExampleRegistration $examples $assertions
    # These controls run before any tmux fixture or example execution.
    $omitted = $assertions.Clone()
    $omitted.Remove($omittedId)
    $rejected = $false
    try { Assert-HelpExampleRegistration $examples $omitted } catch {
        if ($_.Exception.Message -cne "Missing help example assertion: $omittedId") { throw }
        $rejected = $true
    }
    if (!$rejected) { throw 'Missing-registration control was accepted.' }
    $extra = $assertions.Clone()
    $extraId = 'LibTmux\New-TmuxSession#999'
    $extra[$extraId] = $assertions[$omittedId]
    $rejected = $false
    try { Assert-HelpExampleRegistration $examples $extra } catch {
        if ($_.Exception.Message -cne "Help example assertion has no packaged example: $extraId") { throw }
        $rejected = $true
    }
    if (!$rejected) { throw 'Extra-registration control was accepted.' }
    Assert-HelpExampleRegistration $examples $assertions
    'PASS missing and extra help assertion registrations rejected before fixture setup'
}
if ($Phase -eq 'Metadata') {
    $groups = @('CoreFirst', 'CoreSecond', 'CoreThird', 'CoreFourth', 'CoreFifth', 'Workspace', 'Terminal')
    $groupIds = @(foreach ($group in $groups) { Get-HelpGroupId @($examples.Id) $group })
    if ($groupIds.Count -ne $examples.Count -or (Compare-Object @($examples.Id) $groupIds)) {
        throw 'Help execution group registration differs from the packaged examples.'
    }
    @{ Kind = 'Help'; Context = Get-HelpAdmissionContext; Groups = $groups; Examples = @($examples | ForEach-Object {
        @{ Id = $_.Id; CodeSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes($_.Code))) }
    }) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $AdmissionPath
    'PASS native help metadata admission'
    return
}

if ($RunExamples) {
    # Outer integration: packaged examples execute against owned sockets with native outcome checks.
    . "$PSScriptRoot/support/OwnedTmux.ps1"
    . "$PSScriptRoot/support/InputReceiver.ps1"
    $owned = [Collections.Generic.List[object]]::new()
    if ($Phase -ne 'Examples') { $selectedIds = @(Get-HelpGroupId @($examples.Id) $ExampleGroup) }
    $selectedExamples = @($examples | Where-Object { $_.Id -cin $selectedIds })
    if (Compare-Object $selectedIds @($selectedExamples.Id)) { throw 'Admitted help example selection is incomplete.' }
    if ($ExampleGroup -in @('All', 'CoreFirst')) {
        $negative = @{ Executed = $false; Fixture = $null }
        $wrong = $assertions[$omittedId].Clone()
        $wrong.Expected = 'deliberately-wrong-session|work'
        $example = $examples | Where-Object Id -CEQ $omittedId
        $rejected = $false
        try {
            Invoke-WithOwnedTmux {
                param($fixture)
                $owned.Add($fixture)
                $negative.Fixture = $fixture
                Invoke-HelpExample $example $wrong $negative
            }
        } catch {
            if ($_.Exception.Message -cne 'Session creation example did not create its named session and initial window.') { throw }
            $rejected = $true
        } finally {
            Assert-HelpFixtureCleanup $owned
        }
        if (!$rejected -or !$negative.Executed) { throw 'Wrong-output control did not reject a live example outcome.' }
        'PASS wrong help example outcome rejected after live execution; owned resources removed'

        Invoke-WithOwnedTmux {
            param($fixture)
            $owned.Add($fixture)
            $clientExample = $examples | Where-Object Id -CEQ 'LibTmux\Get-TmuxClient#1'
            $clientAssertion = $assertions[$clientExample.Id].Clone()
            $clientAssertion.Assert = { throw 'injected client help assertion failure' }
            $clientContext = @{ Fixture = $fixture; Executed = $false }
            $failed = $false
            try { Invoke-HelpExample $clientExample $clientAssertion $clientContext } catch {
                if ($_.Exception.Message -cne 'injected client help assertion failure') { throw }
                $failed = $true
            }
            if (!$failed -or !$clientContext.Executed -or $clientContext.Control.IsRunning -or
                $clientContext.Client.Server.GetClientsAsync().GetAwaiter().GetResult().Count -ne 0) {
                throw 'Failed client help example left its owned control client.'
            }
            if ((Invoke-OwnedTmux $fixture -Arguments @('list-sessions', '-F', '#{session_name}')).StdOut.Trim() -cne 'fixture') {
                throw 'Client help cleanup removed its borrowed session.'
            }
        }
        'PASS failed client help assertion closes its owned client and preserves the session'
    }

    try {
        Invoke-WithOwnedTmux {
            param($fixture)
            $owned.Add($fixture)
            $SocketPath = $fixture.SocketPath
            $script = Join-Path $fixture.DirectoryPath 'help-output.sh'
            $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
            $quotedSocket = "'" + $SocketPath.Replace("'", "'\''") + "'"
            @"
#!/bin/sh
printf '%s\n' 'libtmux-help-example-output'
$quotedTmux -S $quotedSocket wait-for -S help-ready
exec /bin/cat
"@ | Set-Content -LiteralPath $script
            $null = Invoke-OwnedTmux $fixture -Arguments @('respawn-pane', '-k', '-t', 'fixture:0.0', "/bin/sh '$script'")
            Register-OwnedTmuxPane $fixture
            $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', 'help-ready')
            $null = Invoke-OwnedTmux $fixture -Arguments @('select-pane', '-t', 'fixture:0.0', '-T', 'help-example-pane')
            $identity = Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', 'fixture:0.0', '#{window_id} #{pane_id} #{version}')
            $windowId, $paneId, $version = $identity.StdOut.Trim().Split(' ')
            $context = @{ Fixture = $fixture; WindowId = $windowId; PaneId = $paneId; Version = $version; Executed = $false }
            foreach ($example in $selectedExamples) {
                $assertion = $assertions[$example.Id]
                if ($assertion.ContainsKey('TerminalMode')) { continue }
                if ($assertion.Isolated) {
                    Invoke-WithOwnedTmux {
                        param($isolatedFixture)
                        $owned.Add($isolatedFixture)
                        $original = Invoke-OwnedTmux $isolatedFixture -Arguments @('display-message', '-p', '-t', 'fixture:0.0',
                            '#{session_id}|#{session_name}|#{window_id}|#{window_name}|#{pane_id}|#{pane_pid}')
                        $anchor = $original.StdOut.Trim()
                        $isolated = @{ Fixture = $isolatedFixture; PaneId = $anchor.Split('|')[4]; Anchor = $anchor; Executed = $false }
                        Invoke-HelpExample $example $assertion $isolated
                    }
                } else {
                    Invoke-HelpExample $example $assertion $context
                }
            }
            $remaining = Invoke-OwnedTmux $fixture -Arguments @('list-panes', '-a', '-F', '#{pane_id}')
            if ($remaining.StdOut.Trim() -cne $paneId) { throw 'Help examples changed the shared fixture pane set.' }
        }
    } finally {
        Assert-HelpFixtureCleanup $owned
    }
    . "$PSScriptRoot/support/AttachmentPty.ps1"
    foreach ($example in $selectedExamples) {
        $assertion = $assertions[$example.Id]
        if ($assertion.ContainsKey('TerminalMode')) {
            $receipt = Invoke-AttachmentPty -ModuleRoot $ModuleRoot -Modes @($assertion.TerminalMode)
            if ($receipt.cases.Count -ne 1 -or $receipt.cases[0].result.example -cne $example.Id -or
                $receipt.cases[0].result.codeSha256 -cne [Convert]::ToHexString(
                    [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($example.Code)))) {
                throw 'Terminal help execution did not match the packaged example.'
            }
        }
    }
    "PASS $($selectedExamples.Count) $ExampleGroup native help examples executed against owned tmux"
}

'PASS packaged native help, example content, parameter coverage, and pipeline metadata'
