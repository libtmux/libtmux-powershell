function Assert-IdleCounter {
    param($Counter, [string] $Name, [string] $Lane)

    if (!$Counter -or $Counter.cpuStartTicks -lt 0 -or
        $Counter.cpuEndTicks -lt $Counter.cpuStartTicks -or
        $Counter.cpuDeltaNanoseconds -ne 100L * ($Counter.cpuEndTicks - $Counter.cpuStartTicks) -or
        $Counter.rssStartBytes -le 0 -or $Counter.rssEndBytes -le 0) {
        throw "$Lane has an invalid $Name CPU or RSS observation."
    }
}

function Assert-IdleControlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Report,
        [Parameter(Mandatory)] [string] $ExpectedIdentity,
        [Parameter(Mandatory)] [int] $SamplesPerPhase
    )

    $names = @('before', 'during', 'after')
    if (@($Report.phases).Count -ne $names.Count) {
        throw 'Idle control report omitted a phase.'
    }
    for ($index = 0; $index -lt $names.Count; $index++) {
        $phase = $Report.phases[$index]
        $name = $names[$index]
        $expectedClients = if ($name -eq 'during') { 1 } else { 0 }
        $expectedProcesses = 2 + $expectedClients
        if ($phase.name -cne $name -or $phase.identity -cne $ExpectedIdentity -or
            $phase.identityAtEnd -cne $ExpectedIdentity -or
            $phase.nativeClientCount -ne $expectedClients -or
            $phase.nativeClientCountAtEnd -ne $expectedClients -or
            $phase.aliveOwnedProcessCount -ne $expectedProcesses -or
            $phase.aliveOwnedProcessCountAtEnd -ne $expectedProcesses -or
            [bool] $phase.connectionRunning -ne ($name -eq 'during') -or
            [bool] $phase.connectionRunningAtEnd -ne ($name -eq 'during') -or
            @($phase.samples).Count -ne $SamplesPerPhase) {
            throw "$name did not preserve the owned topology, client, or sample count."
        }
        if ($name -eq 'during') {
            if ($phase.controlClientPid -le 0 -or
                $phase.controlClientPidAtEnd -ne $phase.controlClientPid) {
                throw 'during lost its native control client PID.'
            }
        } elseif ($phase.controlClientPid -or $phase.controlClientPidAtEnd) {
            throw "$name retained a native control client PID."
        }
        for ($sampleIndex = 0; $sampleIndex -lt $SamplesPerPhase; $sampleIndex++) {
            $sample = $phase.samples[$sampleIndex]
            $lane = "$name/$sampleIndex"
            if ($sample.index -ne $sampleIndex -or $sample.intervalNanoseconds -le 0 -or
                $sample.allocatedEndBytes -lt $sample.allocatedStartBytes -or
                $sample.allocatedDeltaBytes -ne ($sample.allocatedEndBytes - $sample.allocatedStartBytes)) {
                throw "$lane has invalid interval or allocation accounting."
            }
            Assert-IdleCounter $sample.powerShell 'PowerShell' $lane
            Assert-IdleCounter $sample.tmuxServer 'tmux server' $lane
            if ($name -eq 'during') {
                Assert-IdleCounter $sample.controlClient 'control client' $lane
            } elseif ($sample.controlClient) {
                throw "$lane includes a client outside the connected phase."
            }
        }
    }
    if (!$Report.cleanup.controlClientExited -or !$Report.cleanup.controlDisconnected -or
        !$Report.cleanup.ownedFixtureRemoved -or !$Report.cleanup.extractedPackageRemoved -or
        !$Report.cleanup.borrowedSessionAlive -or $Report.cleanup.nativeClientCount -ne 0) {
        throw 'Idle control cleanup left an owned resource or control client.'
    }
    $true
}

Export-ModuleMember -Function Assert-IdleControlReport
