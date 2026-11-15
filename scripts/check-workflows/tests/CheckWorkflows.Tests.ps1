# Proves the workflow checks pass this repository's workflows and report each
# fault planted in them: a rule that cannot fail checks nothing.
[CmdletBinding()]
param([string] $Root = (Split-Path (Split-Path (Split-Path $PSScriptRoot))))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../CheckWorkflows.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../../plan-matrix/PlanMatrix.psm1') -Force
$module = Get-Module CheckWorkflows
$manifest = Read-MatrixManifest (Join-Path $Root 'scripts/plan-matrix/matrix.json')
$ci = Get-Content -LiteralPath (Join-Path $Root '.github/workflows/ci.yml') -Raw
$release = Get-Content -LiteralPath (Join-Path $Root '.github/workflows/release.yml') -Raw

function Assert-That([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw $Message }
}

function Assert-Empty($Problems, [string] $Label) {
    $found = @($Problems | Where-Object { $_ })
    Assert-That (!$found.Count) "$Label reported: $($found -join '; ')"
}

# Replaces the first occurrence of `Old` and requires the named problem.
function Assert-Mutation([string] $Text, [string] $Old, [string] $New, [string] $Expected, [string] $Check = 'ci') {
    $at = $Text.IndexOf($Old, [StringComparison]::Ordinal)
    Assert-That ($at -ge 0) "The mutation must change the workflow: $Old"
    $changed = $Text.Remove($at, $Old.Length).Insert($at, $New)
    $problems = if ($Check -ceq 'ci') { @(Test-CiWorkflow $changed $manifest) } else { @(Test-ReleaseWorkflow $changed) }
    Assert-That (@($problems | Where-Object { $_.Contains($Expected) }).Count -gt 0) `
        "Mutating '$Old' did not report '$Expected'; got: $($problems -join '; ')"
}

function Assert-CiMutation($Old, $New, $Expected) { Assert-Mutation $ci $Old $New $Expected }
function Assert-ReleaseMutation($Old, $New, $Expected) { Assert-Mutation $release $Old $New $Expected 'release' }

# ci.yml follows the plan.
Assert-Empty (Test-CiWorkflow $ci $manifest) 'ci.yml'
Assert-CiMutation 'matrix: ${{ fromJSON(needs.plan.outputs.matrix) }}' "matrix: {tmux: ['3.8']}" 'matrix: the legs must come from the plan'
Assert-CiMutation 'matrix: ${{ fromJSON(needs.plan.outputs.reject) }}' "matrix: {tmux: ['3.2a']}" 'reject: the legs must come from the plan'
Assert-CiMutation 'matrix: ${{ fromJSON(needs.plan.outputs.old_daemon) }}' "matrix: {tmux: ['3.0a']}" 'reject-old-daemon: the legs must come from the plan'

# A renamed job would not be found by the release gate.
Assert-CiMutation "name: PowerShell `${{ matrix.powershell }} / tmux `${{ matrix.tmux }}`n" "name: pwsh `${{ matrix.powershell }} on `${{ matrix.tmux }}`n" "job names differ from the release gate's job set"
Assert-CiMutation 'name: powershell gate' 'name: gate' "must be named 'powershell gate'"
Assert-CiMutation "    name: plan`n" "    name: planning`n" "must be named 'plan'"

# A lane runs only when the plan asked for it.
Assert-CiMutation "if: needs.plan.outputs.run_reject == 'true'" 'if: always()' "reject: if must be the plan's run_reject output"
Assert-CiMutation "if: needs.plan.outputs.run_old_daemon == 'true'" 'if: true' "reject-old-daemon: if must be the plan's run_old_daemon output"

# Jobs wait for the plan.
Assert-CiMutation "    needs: plan`n    name: build and pack" "    needs: []`n    name: build and pack" 'port: needs must be plan'
$legName = "    needs: [plan, port]`n    name: PowerShell `${{ matrix.powershell }} / tmux `${{ matrix.tmux }}`n"
Assert-CiMutation $legName $legName.Replace('[plan, port]', '[port]') 'matrix: needs must be [plan, port]'

# The gate keeps checking the plan.
Assert-CiMutation 'run: pwsh -NoLogo -NoProfile -File scripts/plan-matrix/PlanMatrix.ps1 gate' 'run: true' 'gate: must check the needs context'
Assert-CiMutation 'needs: [plan, port, matrix, reject, reject-old-daemon]' 'needs: [port, matrix]' 'gate: needs must list'
Assert-CiMutation "    if: always()`n    name: powershell gate" "    name: powershell gate" 'gate: if must be always()'

# The CI can be called at a scope.
Assert-CiMutation "  workflow_call:`n" "  workflow_dispatch_2:`n" 'the scope input must be required'
$scopeInput = "        description: How much of the tmux table to cover. The release workflow passes full.`n        required: true`n"
Assert-CiMutation $scopeInput $scopeInput.Replace('required: true', 'required: false') 'the scope input must be required'

# YAML reads a bare off as the boolean false.
Assert-CiMutation "        default: 'off'`n" "        default: off`n" "quote 'off' in the tmate options"
Assert-CiMutation "options: ['off', before-tests, on-failure]" 'options: [off, before-tests, on-failure]' "quote 'off' in the tmate options"
Assert-CiMutation "      pwsh:`n" "      shell:`n" 'missing the pwsh input'

# An input reaches a script through env, never through the script text.
Assert-CiMutation '-TmuxRef "${TMUX_REF}"' '-TmuxRef "${{ inputs.tmux-ref }}"' 'pass an input to a script through env'

# A pin copied back into the workflow, which belongs in the manifest.
$commit = $manifest.supported[0].commit
Assert-CiMutation "run: printf 'TMUX_BINARY=%s\n' `"`${REF_BINARY}`"" "run: echo $commit; printf 'TMUX_BINARY=%s\n' `"`${REF_BINARY}`"" 'belongs in the manifest'
Assert-CiMutation "      - name: Select the ref build`n" "      - name: Select the '$($manifest.supported[-1].tmux)' build`n" "tmux $($manifest.supported[-1].tmux) belongs in the manifest"

# The debugging session stays pinned, limited and bounded.
$sha = '35b54afac29c97fb54faba5b513f8fbd1882f113'
Assert-CiMutation "action-tmate@$sha # v3.24" 'action-tmate@v3.24' 'pinned to a full commit SHA'
Assert-CiMutation "          limit-access-to-actor: true`n" "          limit-access-to-actor: false`n" 'limited to the actor'
Assert-CiMutation "        timeout-minutes: 30`n        continue-on-error: true`n" "        continue-on-error: true`n" 'own time limit'
Assert-CiMutation "if: github.event_name == 'workflow_dispatch' && matrix.tmate == 'before-tests'" "if: matrix.tmate == 'before-tests'" 'runs only on a dispatch'
Assert-CiMutation "if: failure() && github.event_name == 'workflow_dispatch' && matrix.tmate == 'on-failure'" "if: failure() && github.event_name == 'workflow_dispatch'" 'on the leg the plan chose'
Assert-CiMutation "timeout-minutes: `${{ matrix.tmate == 'off' && 20 || 50 }}" 'timeout-minutes: 20' 'give the debugging leg more'
Assert-CiMutation "          TMATE: `${{ inputs.tmate }}`n" '' 'pass the tmate input through env'
Assert-CiMutation "      tmate:`n" "      debug:`n" 'missing the tmate input'

# A debugging session can be neither dropped nor moved out of the matrix.
$start = $ci.IndexOf("      - name: Debug session after a failure", [StringComparison]::Ordinal)
$end = $ci.IndexOf("`n`n", $start, [StringComparison]::Ordinal) + 2
$block = $ci.Substring($start, $end - $start)
$dropped = $ci.Remove($start, $end - $start)
Assert-That (@(Test-CiWorkflow $dropped $manifest) -contains 'the matrix must offer a debugging session before the tests and after a failure') 'A dropped debugging session passed.'
$gate = $dropped.IndexOf('      - name: Require every planned job', [StringComparison]::Ordinal)
$moved = $dropped.Insert($gate, $block)
Assert-That (@(Test-CiWorkflow $moved $manifest) -contains 'gate: a debugging session belongs only in the matrix') 'A debugging session moved into the gate passed.'

# A dispatch run must not share a cancelling group.
$group = "format('-{0}', github.run_id) || '' }}"
Assert-CiMutation $group "'' }}" "add github.run_id to a dispatch run's group"
Assert-CiMutation "`${{ github.event_name == 'workflow_dispatch' && format('-{0}', github.run_id) || '' }}" '-${{ github.run_id }}' "add github.run_id to a dispatch run's group"
Assert-CiMutation "  cancel-in-progress: true`n" "  cancel-in-progress: false`n" 'a superseded push must still be cancelled'
Assert-That (@(Test-CiWorkflow $ci.Replace("  reject:`n", "  rejected:`n") $manifest) -contains 'reject: missing job') 'A removed job passed.'

# release.yml proves the full set itself.
Assert-Empty (Test-ReleaseWorkflow $release) 'release.yml'
Assert-ReleaseMutation 'uses: ./.github/workflows/ci.yml' 'uses: libtmux/other/.github/workflows/ci.yml@v1' 'must call the CI workflow of this commit'
Assert-ReleaseMutation "      scope: full`n" "      scope: edges`n" 'at scope full'
Assert-ReleaseMutation "  ci:`n" "  ci:`n    name: tests`n" 'must keep the name'
Assert-ReleaseMutation "    needs: ci`n" "    needs: []`n" 'it must wait for the CI it called'
Assert-ReleaseMutation "      release_tag:`n" "      ci_run_id:`n        required: true`n        type: string`n      release_tag:`n" 'must not take the ID'
Assert-ReleaseMutation '          artifact-ids:' "          run-id: 1`n          artifact-ids:" 'must come from this run'
Assert-ReleaseMutation 'CI_RUN_ID: ${{ github.run_id }}' 'CI_RUN_ID: ${{ inputs.release_tag }}' 'must read this run'
Assert-ReleaseMutation 'Release tag must point at the commit being released.' 'Release tag is fine.' 'must name the commit that was tested'
Assert-That (@(@(Test-ReleaseWorkflow ($release + "`n# git merge-base --is-ancestor`n")) -match 'a release tag may not be an ancestor').Count -gt 0) 'A tag that may be an ancestor passed.'
Assert-ReleaseMutation "  ci:`n    if: github.repository == 'libtmux/libtmux-powershell' && github.ref == 'refs/heads/master'`n" "  ci:`n" 'ci: a release runs from master only'

# No run line calls apt or apt-get; the shared action does.
Assert-That (@(Get-RawAptProblem 'ci.yml' $ci).Count -eq 0) 'ci.yml calls apt directly.'
$sample = "jobs:`n  build:`n    steps:`n      - name: Install tmux`n        run: |`n          sudo apt-get update`n"
Assert-That ((Get-RawAptProblem 'ci.yml' $sample) -ceq "ci.yml:6: job build, step 'Install tmux' calls apt-get directly; use libtmux/.github/actions/apt-get") 'A raw apt-get was not reported with its place and the fix.'
foreach ($command in 'apt-get install --yes tmux', 'sudo apt install tmux', 'sudo -E apt-get update', 'DEBIAN_FRONTEND=noninteractive apt-get update',
    'sudo timeout 60 apt-get update', 'sudo apt-get update || true', 'true && sudo apt-get update') {
    $problems = @(Get-RawAptProblem 'ci.yml' "jobs:`n  a:`n    steps:`n      - run: $command`n")
    Assert-That ($problems.Count -eq 1 -and $problems[0].Contains('use libtmux/.github/actions/apt-get')) "A way to call apt went unreported: $command"
}
$clean = "jobs:`n  build:`n    steps:`n      - name: Install tmux`n        run: |`n          # sudo apt-get update`n          echo `"apt is slow`"`n      - name: Not a script`n        with:`n          note: sudo apt-get update`n"
Assert-Empty (Get-RawAptProblem 'ci.yml' $clean) 'A comment, an echo and a non-script line'

# A shared action is pinned to a full commit.
Assert-Empty (Get-UnpinnedActionProblem 'ci.yml' $ci) 'ci.yml pins'
foreach ($ref in 'main', 'v1', 'bd3bae7', '') {
    Assert-That (@(Get-UnpinnedActionProblem 'x.yml' "      - uses: libtmux/.github/actions/apt-get@$ref`n").Count -eq 1) "A shared action at '$ref' went unreported."
}
'PASS workflow checks: this repository passes and each planted fault is reported'
