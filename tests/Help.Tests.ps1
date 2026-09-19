param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [switch] $RunExamples
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path

function Assert-HelpExampleResult($Example, [object[]] $Result) {
    if ($Result.Count -ne 1) { throw "$($Example.Command.Name) example did not return one fixture result." }
    $types = @($Example.Command.OutputType | ForEach-Object Type)
    $matchingTypes = @($types | Where-Object { $null -ne $_ -and $Result[0] -is $_ })
    if (!$matchingTypes.Count) { throw "$($Example.Command.Name) example returned the wrong native type." }
}

$examples = [Collections.Generic.List[object]]::new()
foreach ($module in @('LibTmux', 'LibTmux.Workspace')) {
    Import-Module (Join-Path $ModuleRoot "$module/0.1.0/$module.psd1")
    foreach ($command in Get-Command -Module $module) {
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
        foreach ($example in $help.examples.example) {
            $code = [string] $example.code
            if ([string]::IsNullOrWhiteSpace($code)) {
                # PlatyPS 1.0.3 keeps Markdown examples in introduction, leaving dev:code empty.
                $text = $example.introduction.Text -join "`n"
                $blocks = [regex]::Matches($text, '(?ms)^```powershell[ \t]*\r?\n(?<code>.*?)^```[ \t]*\r?$')
                if ($blocks.Count -ne 1) {
                    throw "$($command.Name) must have exactly one executable PowerShell block per example."
                }
                $code = $blocks[0].Groups['code'].Value
            }
            if ([string]::IsNullOrWhiteSpace($code)) { throw "$($command.Name) has an example without executable code." }
            $parseErrors = $null
            $null = [Management.Automation.Language.Parser]::ParseInput($code, [ref] $null, [ref] $parseErrors)
            if ($parseErrors.Count) { throw "$($command.Name) has invalid example syntax: $($parseErrors.Message -join '; ')." }
            $examples.Add(@{ Command = $command; Code = $code })
        }
    }
}

if ($RunExamples) {
    # Integration: examples use this owned socket instead of a user's running server.
    . "$PSScriptRoot/support/OwnedTmux.ps1"
    $owned = [Collections.Generic.List[object]]::new()
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
        foreach ($example in $examples) {
            if ($example.Command.Name -in @('New-TmuxSession', 'New-TmuxWindow', 'Split-TmuxPane')) {
                Invoke-WithOwnedTmux {
                    param($creationFixture)
                    $owned.Add($creationFixture)
                    $SocketPath = $creationFixture.SocketPath
                    $original = Invoke-OwnedTmux $creationFixture -Arguments @('display-message', '-p', '#{pane_id}')
                    $result = @(& ([scriptblock]::Create($example.Code)))
                    Register-OwnedTmuxPane $creationFixture
                    Assert-HelpExampleResult $example $result
                    if ($result[0].Server.ConnectionOptions.SocketPath -cne $SocketPath) {
                        throw 'Creation example returned an object from the wrong server.'
                    }
                    $target = $result[0].Id.ToString()
                    switch ($example.Command.Name) {
                        'New-TmuxSession' {
                            $actual = Invoke-OwnedTmux $creationFixture -Arguments @('display-message', '-p', '-t', $target, '#{session_name}|#{window_name}')
                            if ($result[0].Name -cne 'help-session' -or $actual.StdOut.Trim() -cne 'help-session|work') {
                                throw 'Session creation example did not create its named session and initial window.'
                            }
                        }
                        'New-TmuxWindow' {
                            $actual = Invoke-OwnedTmux $creationFixture -Arguments @('display-message', '-p', '-t', $target, '#{session_name}|#{window_name}|#{window_index}')
                            if ($result[0].Name -cne 'help-window' -or $actual.StdOut.Trim() -cne 'fixture|help-window|5') {
                                throw 'Window creation example did not create its named window at the requested index.'
                            }
                        }
                        'Split-TmuxPane' {
                            $actual = Invoke-OwnedTmux $creationFixture -Arguments @('display-message', '-p', '-t', $target, '#{pane_width}|#{pane_active}')
                            if ($target -ceq $original.StdOut.Trim() -or $actual.StdOut.Trim() -cne '20|0') {
                                throw 'Split example did not return a new unselected pane with the requested width.'
                            }
                        }
                    }
                }
                continue
            }
            $result = @(& ([scriptblock]::Create($example.Code)))
            Assert-HelpExampleResult $example $result
            switch ($example.Command.Name) {
                'New-TmuxServer' {
                    if ($result[0].IsMaterialized -or $result[0].ConnectionOptions.SocketPath -cne $SocketPath) {
                        throw 'Endpoint example acquired data or selected the wrong socket.'
                    }
                }
                'Connect-TmuxServer' {
                    if (!$result[0].IsMaterialized -or $result[0].ConnectionOptions.SocketPath -cne $SocketPath) {
                        throw 'Connection example did not materialize the owned endpoint.'
                    }
                }
                'Get-TmuxSnapshot' {
                    if ($result[0].Panes.Count -ne 1 -or $result[0].Panes[0].Id.ToString() -cne $paneId) {
                        throw 'Snapshot example did not capture the fixture pane.'
                    }
                }
                'Get-TmuxSession' {
                    if ($result[0].Name -cne 'fixture') { throw 'Session example selected the wrong fixture session.' }
                }
                'Get-TmuxWindow' {
                    if ($result[0].Id.ToString() -cne $windowId) { throw 'Window example selected the wrong fixture window.' }
                }
                'Get-TmuxPane' {
                    if ($result[0].Id.ToString() -cne $paneId) { throw 'Pane example selected the wrong fixture pane.' }
                }
                'Update-TmuxPane' {
                    if ($result[0].Id.ToString() -cne $paneId -or $result[0].Title -cne 'help-example-pane') {
                        throw 'Refresh example did not return current fixture metadata.'
                    }
                }
                'Get-TmuxPaneContent' {
                    if (!$result[0].Contains('libtmux-help-example-output')) { throw 'Capture example lost the completed fixture output.' }
                }
                'Import-TmuxWorkspace' {
                    if ($result[0].SessionName -cne 'development') { throw 'Workspace example parsed the wrong session.' }
                }
                'Invoke-TmuxCommand' {
                    if ($result[0].ExitCode -ne 0 -or $result[0].StandardOutputLines.Count -ne 1 -or
                        $result[0].StandardOutputLines[0] -cne $version) {
                        throw 'Raw command example did not return a successful version.'
                    }
                }
            }
        }
        $remaining = Invoke-OwnedTmux $fixture -Arguments @('list-panes', '-a', '-F', '#{pane_id}')
        if ($remaining.StdOut.Trim() -cne $paneId) { throw 'Help examples changed the shared fixture pane set.' }
    }
    foreach ($fixture in $owned) {
        if (!$fixture.Closed -or (Test-Path -LiteralPath $fixture.DirectoryPath)) { throw 'Help fixture cleanup left owned resources.' }
    }
    "PASS $($examples.Count) native help examples executed against owned tmux"
}

'PASS packaged native help, example content, parameter coverage, and pipeline metadata'
