"""Prove ci.yml takes its jobs from the plan and stays bound to the release gate.

The workflow is read as text, because the CI step that runs these tests has no
YAML parser. Each rule has a mutation that must be reported.
"""

import pathlib
import re
import unittest

import plan_matrix
import release_artifacts

ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/ci.yml"
RELEASE = ROOT / ".github/workflows/release.yml"
MANIFEST = plan_matrix.load_manifest()
FULL = plan_matrix.plan(MANIFEST, event="workflow_dispatch", scope="full")


def split_jobs(text):
    """Map each job id to its text."""
    _, _, body = text.partition("\njobs:\n")
    found, name = {}, None
    for line in body.splitlines():
        header = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if header:
            name = header.group(1)
            found[name] = []
        elif name and line.startswith("    "):
            found[name].append(line)
        elif line and not line.startswith(" "):
            name = None
    return {key: "\n".join(value) for key, value in found.items()}


def field(job, key):
    match = re.search(rf"^    {re.escape(key)}: (.*)$", job, re.MULTILINE)
    return match.group(1).strip() if match else None


def render(template, values):
    return re.sub(r"\$\{\{ matrix\.(\w+) \}\}", lambda m: values[m.group(1)], template)


TMATE = "mxschmitt/action-tmate"


def steps_of(job):
    """Split a job's text into its steps."""
    return re.split(r"(?m)^(?=      - )", job)[1:]


def check_debug_sessions(text, jobs):
    """Return what makes a debugging session unsafe or misplaced."""
    problems = []
    found = 0
    for name, job in jobs.items():
        for step in steps_of(job):
            if TMATE not in step:
                continue
            found += 1
            if name != "matrix":
                problems.append(f"{name}: a debugging session belongs only in the matrix")
            if not re.search(rf"uses: {TMATE}@[0-9a-f]{{40}} #", step):
                problems.append("a debugging session must be pinned to a full commit SHA")
            if "limit-access-to-actor: true" not in step:
                problems.append("a debugging session must be limited to the actor")
            if not re.search(r"(?m)^        timeout-minutes: \d+$", step):
                problems.append("a debugging session needs its own time limit")
            condition = field_of_step(step, "if") or ""
            if "github.event_name == 'workflow_dispatch'" not in condition or (
                "matrix.tmate ==" not in condition
            ):
                problems.append(
                    "a debugging session runs only on a dispatch, on the leg the plan chose"
                )
    if found != 2:
        problems.append("the matrix must offer a debugging session before the tests and after a failure")
    if field(jobs["matrix"], "timeout-minutes") != "${{ matrix.tmate == 'off' && 20 || 50 }}":
        problems.append("matrix: the job must cap its time and give the debugging leg more")
    if "TMATE: ${{ inputs.tmate }}" not in jobs["plan"] or '--tmate "${TMATE}"' not in jobs["plan"]:
        problems.append("plan: must pass the tmate input through env")
    return problems


def field_of_step(step, key):
    match = re.search(rf"(?m)^        {re.escape(key)}: (.*)$", step)
    return match.group(1).strip() if match else None


def check(text):
    """Return what ci.yml does that breaks the plan or the release binding."""
    problems = []
    jobs = split_jobs(text)

    for needed in ("plan", "port", "matrix", "reject", "reject-old-daemon", "gate"):
        if needed not in jobs:
            problems.append(f"{needed}: missing job")
    if problems:
        return problems

    names = {
        plan_matrix.PLAN_JOB: field(jobs["plan"], "name"),
        plan_matrix.PACKAGE_JOB: field(jobs["port"], "name"),
        plan_matrix.GATE_JOB: field(jobs["gate"], "name"),
    }
    for expected, actual in names.items():
        if actual != expected:
            problems.append(f"the job named {actual!r} must be named {expected!r}")

    rendered = set(names.values())
    caller = f"{release_artifacts.CALLER_JOB} / "
    lanes = {"matrix": FULL["matrix"]["include"], "reject": FULL["reject"],
             "reject-old-daemon": FULL["old_daemon"]}
    for job, cells in lanes.items():
        template = field(jobs[job], "name") or ""
        rendered |= {render(template, cell) for cell in cells}
    rendered = {caller + name for name in rendered}
    if rendered != release_artifacts.JOBS:
        problems.append(
            "job names differ from the release gate's job set: "
            + ", ".join(sorted(rendered ^ release_artifacts.JOBS))
        )

    sources = {
        "matrix": "matrix: ${{ fromJSON(needs.plan.outputs.matrix) }}",
        "reject": "matrix: ${{ fromJSON(needs.plan.outputs.reject) }}",
        "reject-old-daemon": "matrix: ${{ fromJSON(needs.plan.outputs.old_daemon) }}",
    }
    for job, source in sources.items():
        if source not in jobs[job]:
            problems.append(f"{job}: the legs must come from the plan")
        if field(jobs[job], "needs") != "[plan, port]":
            problems.append(f"{job}: needs must be [plan, port]")
    if field(jobs["port"], "needs") != "plan":
        problems.append("port: needs must be plan")
    for job, output in (("reject", "run_reject"), ("reject-old-daemon", "run_old_daemon")):
        if field(jobs[job], "if") != f"needs.plan.outputs.{output} == 'true'":
            problems.append(f"{job}: if must be the plan's {output} output")
    if field(jobs["matrix"], "if") is not None:
        problems.append("matrix: if may not skip a leg")

    if field(jobs["gate"], "needs") != "[plan, port, matrix, reject, reject-old-daemon]":
        problems.append("gate: needs must list the plan, the build, the matrix and both lanes")
    if field(jobs["gate"], "if") != "always()":
        problems.append("gate: if must be always()")
    if "python3 eng/ci/plan_matrix.py gate" not in jobs["gate"] or (
        "NEEDS: ${{ toJSON(needs) }}" not in jobs["gate"]
    ):
        problems.append("gate: must check the needs context with the plan script")

    head = text.partition("\njobs:\n")[0]
    call = head.partition("\n  workflow_call:\n")[2].partition("\n  workflow_dispatch:")[0]
    if "      scope:\n" not in call or "        required: true\n" not in call:
        problems.append("workflow_call: the scope input must be required")
    dispatch = head.partition("\n  workflow_dispatch:\n")[2]
    if "        options: ['off', before-tests, on-failure]\n        default: 'off'\n" not in dispatch:
        problems.append(
            "workflow_dispatch: quote 'off' in the tmate options and default, "
            "which YAML reads as the boolean false"
        )
    for name in ("scope", "tmux-ref", "pwsh", "tmate"):
        if not re.search(rf"^      {re.escape(name)}:$", dispatch, re.MULTILINE):
            problems.append(f"workflow_dispatch: missing the {name} input")

    for number, line in enumerate(text.splitlines(), 1):
        if "inputs." in line and not re.match(
            r"^\s+[A-Z_]+: \$\{\{ inputs\.[a-z-]+ \}\}$", line
        ) and not line.lstrip().startswith("#"):
            problems.append(f"line {number}: pass an input to a script through env")

    problems += check_debug_sessions(text, jobs)
    group = (
        "group: powershell-${{ github.ref }}${{ github.event_name == 'workflow_dispatch' "
        "&& format('-{0}', github.run_id) || '' }}"
    )
    if f"\n  {group}\n" not in text:
        problems.append("concurrency: add github.run_id to a dispatch run's group")
    if "\n  cancel-in-progress: true\n" not in text:
        problems.append("concurrency: a superseded push must still be cancelled")
    for each in MANIFEST["supported"] + MANIFEST["rejected"] + MANIFEST["oldDaemon"]:
        if each["commit"] in text:
            problems.append(f"the source commit of tmux {each['tmux']} belongs in the manifest")
    for each in MANIFEST["supported"] + MANIFEST["development"]:
        if f"'{each['tmux']}'" in text:
            problems.append(f"tmux {each['tmux']} belongs in the manifest")
    return problems


def release_problems(text):
    """Return what release.yml does that stops a release proving the full set itself."""
    problems = []
    jobs = split_jobs(text)
    for needed in ("ci", "gallery"):
        if needed not in jobs:
            problems.append(f"{needed}: missing job")
    if problems:
        return problems
    caller = jobs["ci"]
    if field(caller, "uses") != "./.github/workflows/ci.yml":
        problems.append("ci: the release must call the CI workflow of this commit")
    if "\n      scope: full" not in "\n" + caller:
        problems.append("ci: the release must call the CI workflow at scope full")
    if field(caller, "name") is not None or release_artifacts.CALLER_JOB != "ci":
        problems.append("ci: the calling job must keep the name the job set expects")
    if field(jobs["gallery"], "needs") != "ci":
        problems.append("gallery: it must wait for the CI it called")
    if "ci_run_id" in text:
        problems.append("a release must not take the ID of a run someone else dispatched")
    if "run-id:" in text:
        problems.append("gallery: the packages must come from this run")
    if "CI_RUN_ID: ${{ github.run_id }}" not in jobs["gallery"]:
        problems.append("gallery: the provenance check must read this run")
    if "Release tag must point at the commit being released." not in jobs["gallery"]:
        problems.append("gallery: a release tag must name the commit that was tested")
    if "merge-base" in text:
        problems.append("gallery: a release tag may not be an ancestor of the tested commit")
    for name in ("ci", "gallery"):
        if "github.ref == 'refs/heads/master'" not in jobs[name]:
            problems.append(f"{name}: a release runs from master only")
    return problems


APT_WRAPPER = "eng/ci/apt-get.sh"
RAW_APT = re.compile(
    r"(?:^|[;&|(`])\s*(?:\w+=\S*\s+)*"
    r"(?:(?:sudo|env|time|timeout|nice)\s+(?:(?:-\S+|\w+=\S*|\d+[smh]?)\s+)*)*"
    r"(apt(?:-get)?)(?![\w./-])"
)


def run_lines(text):
    """List (line number, job, step, line) for each line of each `run` script."""
    lines = text.splitlines()
    found, job, step, in_jobs, index = [], None, None, False, 0
    while index < len(lines):
        line = lines[index]
        index += 1
        in_jobs = in_jobs or line == "jobs:"
        header = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if in_jobs and header:
            job, step = header.group(1), None
        named = re.match(r"^\s*- name: (.*)$", line)
        if named:
            step = named.group(1).strip()
        start = re.match(r"^(\s*)(- )?run:\s*(.*)$", line)
        if not start:
            continue
        if start.group(2):
            step = None
        indent = len(start.group(1)) + (2 if start.group(2) else 0)
        if re.match(r"^[|>][+-]?\d*\s*(#.*)?$", start.group(3)):
            while index < len(lines) and (
                not lines[index].strip() or len(lines[index]) - len(lines[index].lstrip()) > indent
            ):
                found.append((index + 1, job, step, lines[index]))
                index += 1
        else:
            found.append((index, job, step, start.group(3).lstrip("'\"")))
    return [each for each in found if not each[3].lstrip().startswith("#")]


def raw_apt_problems(path, text):
    """Return each `run` line that calls apt or apt-get without the wrapper."""
    problems = []
    for number, job, step, line in run_lines(text):
        call = RAW_APT.search(line.strip())
        if call:
            where = (f"job {job}, " if job else "") + (f"step {step!r}" if step else "an unnamed step")
            problems.append(
                f"{path}:{number}: {where} calls {call.group(1)} directly; run it through {APT_WRAPPER}"
            )
    return problems


def apt_scanned_files():
    """List the workflows and composite actions whose scripts must use the wrapper."""
    github = ROOT / ".github"
    return sorted(github.glob("workflows/*.y*ml")) + sorted(github.glob("actions/*/action.y*ml"))


class WorkflowFollowsThePlan(unittest.TestCase):
    def setUp(self):
        self.text = WORKFLOW.read_text(encoding="utf-8")

    def test_the_workflow_follows_the_plan(self):
        self.assertEqual(check(self.text), [])

    def mutated(self, old, new, expected):
        self.assertIn(old, self.text, "the mutation must change the workflow")
        problems = check(self.text.replace(old, new, 1))
        self.assertTrue(
            any(expected in problem for problem in problems), (expected, problems)
        )

    def test_a_matrix_that_lists_its_legs_is_reported(self):
        self.mutated(
            "matrix: ${{ fromJSON(needs.plan.outputs.matrix) }}",
            "matrix: {tmux: ['3.8']}",
            "matrix: the legs must come from the plan",
        )

    def test_a_refusal_lane_that_lists_its_versions_is_reported(self):
        self.mutated(
            "matrix: ${{ fromJSON(needs.plan.outputs.reject) }}",
            "matrix: {tmux: ['3.2a']}",
            "reject: the legs must come from the plan",
        )
        self.mutated(
            "matrix: ${{ fromJSON(needs.plan.outputs.old_daemon) }}",
            "matrix: {tmux: ['3.0a']}",
            "reject-old-daemon: the legs must come from the plan",
        )

    def test_a_renamed_job_is_reported_because_the_release_gate_would_not_find_it(self):
        self.mutated(
            "name: PowerShell ${{ matrix.powershell }} / tmux ${{ matrix.tmux }}\n",
            "name: pwsh ${{ matrix.powershell }} on ${{ matrix.tmux }}\n",
            "job names differ from the release gate's job set",
        )
        self.mutated("name: powershell gate", "name: gate", "must be named 'powershell gate'")
        self.mutated("    name: plan\n", "    name: planning\n", "must be named 'plan'")

    def test_a_lane_that_runs_without_the_plan_is_reported(self):
        self.mutated(
            "if: needs.plan.outputs.run_reject == 'true'",
            "if: always()",
            "reject: if must be the plan's run_reject output",
        )
        self.mutated(
            "if: needs.plan.outputs.run_old_daemon == 'true'",
            "if: true",
            "reject-old-daemon: if must be the plan's run_old_daemon output",
        )

    def test_a_job_that_does_not_wait_for_the_plan_is_reported(self):
        self.mutated("    needs: plan\n    name: build and pack", "    needs: []\n    name: build and pack",
                     "port: needs must be plan")
        self.mutated("    needs: [plan, port]\n    name: PowerShell ${{ matrix.powershell }} / tmux ${{ matrix.tmux }}\n",
                     "    needs: [port]\n    name: PowerShell ${{ matrix.powershell }} / tmux ${{ matrix.tmux }}\n",
                     "matrix: needs must be [plan, port]")

    def test_a_gate_that_stops_checking_the_plan_is_reported(self):
        self.mutated("run: python3 eng/ci/plan_matrix.py gate", "run: true",
                     "gate: must check the needs context")
        self.mutated("needs: [plan, port, matrix, reject, reject-old-daemon]",
                     "needs: [port, matrix]", "gate: needs must list")
        self.mutated("    if: always()\n    name: powershell gate", "    name: powershell gate",
                     "gate: if must be always()")

    def test_a_ci_workflow_that_cannot_be_called_at_a_scope_is_reported(self):
        self.mutated("  workflow_call:\n", "  workflow_dispatch_2:\n", "the scope input must be required")
        self.mutated("        description: How much of the tmux table to cover. The release workflow passes full.\n        required: true\n",
                     "        description: How much of the tmux table to cover. The release workflow passes full.\n        required: false\n",
                     "the scope input must be required")

    def test_a_tmate_value_that_yaml_reads_as_a_boolean_is_reported(self):
        self.mutated("        default: 'off'\n", "        default: off\n", "quote 'off' in the tmate options")
        self.mutated("options: ['off', before-tests, on-failure]", "options: [off, before-tests, on-failure]",
                     "quote 'off' in the tmate options")

    def test_a_missing_dispatch_input_is_reported(self):
        self.mutated("      pwsh:\n", "      shell:\n", "missing the pwsh input")

    def test_an_input_used_inside_a_script_is_reported(self):
        self.mutated(
            '--tmux-ref "${TMUX_REF}"',
            '--tmux-ref "${{ inputs.tmux-ref }}"',
            "pass an input to a script through env",
        )

    def test_a_pin_copied_back_into_the_workflow_is_reported(self):
        commit = MANIFEST["supported"][0]["commit"]
        self.mutated("run: eng/ci/build-tmux.sh --resolve", f"run: echo {commit}; eng/ci/build-tmux.sh --resolve",
                     "belongs in the manifest")
        self.mutated("      - name: Resolve the tmux ref\n", "      - name: Resolve '3.8'\n",
                     "tmux 3.8 belongs in the manifest")

    def test_the_debugging_session_stays_pinned_limited_and_bounded(self):
        sha = "35b54afac29c97fb54faba5b513f8fbd1882f113"
        self.mutated(f"action-tmate@{sha} # v3.24", "action-tmate@v3.24", "pinned to a full commit SHA")
        self.mutated("          limit-access-to-actor: true\n", "          limit-access-to-actor: false\n",
                     "limited to the actor")
        self.mutated("        timeout-minutes: 30\n        continue-on-error: true\n",
                     "        continue-on-error: true\n", "own time limit")
        self.mutated("if: github.event_name == 'workflow_dispatch' && matrix.tmate == 'before-tests'",
                     "if: matrix.tmate == 'before-tests'", "runs only on a dispatch")
        self.mutated("if: failure() && github.event_name == 'workflow_dispatch' && matrix.tmate == 'on-failure'",
                     "if: failure() && github.event_name == 'workflow_dispatch'", "on the leg the plan chose")

    def test_a_debugging_session_cannot_be_dropped_or_moved(self):
        start = self.text.index("      - name: Debug session after a failure")
        end = self.text.index("\n\n", start) + 2
        block = self.text[start:end]
        dropped = self.text[:start] + self.text[end:]
        self.assertIn(
            "the matrix must offer a debugging session before the tests and after a failure",
            check(dropped),
        )
        gate = dropped.index("      - name: Require every planned job")
        moved = dropped[:gate] + block + dropped[gate:]
        self.assertIn("gate: a debugging session belongs only in the matrix", check(moved))

    def test_the_job_time_limit_and_the_tmate_input_are_required(self):
        self.mutated("timeout-minutes: ${{ matrix.tmate == 'off' && 20 || 50 }}", "timeout-minutes: 20",
                     "give the debugging leg more")
        self.mutated("          TMATE: ${{ inputs.tmate }}\n", "", "pass the tmate input through env")
        self.mutated("      tmate:\n", "      debug:\n", "missing the tmate input")

    def test_a_dispatch_run_must_not_share_a_cancelling_group(self):
        self.mutated(
            "format('-{0}', github.run_id) || '' }}",
            "'' }}",
            "add github.run_id to a dispatch run's group",
        )
        self.mutated(
            "${{ github.event_name == 'workflow_dispatch' && format('-{0}', github.run_id) || '' }}",
            "-${{ github.run_id }}",
            "add github.run_id to a dispatch run's group",
        )
        self.mutated("  cancel-in-progress: true\n", "  cancel-in-progress: false\n",
                     "a superseded push must still be cancelled")

    def test_a_removed_job_is_reported(self):
        trimmed = self.text.replace("  reject:\n", "  rejected:\n", 1)
        self.assertIn("reject: missing job", check(trimmed))


class ReleaseCallsTheCi(unittest.TestCase):
    def setUp(self):
        self.text = RELEASE.read_text(encoding="utf-8")

    def test_the_release_proves_the_full_set_itself(self):
        self.assertEqual(release_problems(self.text), [])

    def mutated(self, old, new, expected):
        self.assertIn(old, self.text, "the mutation must change the workflow")
        problems = release_problems(self.text.replace(old, new, 1))
        self.assertTrue(any(expected in each for each in problems), (expected, problems))

    def test_a_release_that_stops_calling_the_ci_is_reported(self):
        self.mutated("uses: ./.github/workflows/ci.yml", "uses: libtmux/other/.github/workflows/ci.yml@v1",
                     "must call the CI workflow of this commit")
        self.mutated("      scope: full\n", "      scope: edges\n", "at scope full")
        self.mutated("  ci:\n", "  ci:\n    name: tests\n", "must keep the name")
        self.mutated("    needs: ci\n", "    needs: []\n", "it must wait for the CI it called")

    def test_a_release_that_takes_a_run_someone_passes_in_is_reported(self):
        self.mutated("      release_tag:\n", "      ci_run_id:\n        required: true\n        type: string\n      release_tag:\n",
                     "must not take the ID")
        self.mutated("          artifact-ids:", "          run-id: 1\n          artifact-ids:",
                     "must come from this run")
        self.mutated("CI_RUN_ID: ${{ github.run_id }}", "CI_RUN_ID: ${{ inputs.release_tag }}",
                     "must read this run")

    def test_a_release_tag_must_name_the_tested_commit(self):
        self.mutated("Release tag must point at the commit being released.", "Release tag is fine.",
                     "must name the commit that was tested")
        self.assertIn("a release tag may not be an ancestor",
                      " ".join(release_problems(self.text + "\n# git merge-base --is-ancestor\n")))

    def test_a_release_outside_master_is_reported(self):
        self.mutated("  ci:\n    if: github.repository == 'libtmux/libtmux-powershell' && github.ref == 'refs/heads/master'\n",
                     "  ci:\n", "ci: a release runs from master only")


class AptGoesThroughTheWrapper(unittest.TestCase):
    def test_no_workflow_or_action_calls_apt_directly(self):
        files = apt_scanned_files()
        self.assertIn(WORKFLOW, files)
        problems = []
        for path in files:
            problems += raw_apt_problems(
                path.relative_to(ROOT), path.read_text(encoding="utf-8")
            )
        self.assertEqual(problems, [])

    def test_a_raw_apt_get_is_reported_with_its_place_and_the_fix(self):
        text = (
            "jobs:\n"
            "  build:\n"
            "    steps:\n"
            "      - name: Install tmux\n"
            "        run: |\n"
            "          sudo apt-get update\n"
        )
        self.assertEqual(
            raw_apt_problems("ci.yml", text),
            [
                "ci.yml:6: job build, step 'Install tmux' calls apt-get directly; "
                "run it through eng/ci/apt-get.sh"
            ],
        )

    def test_every_way_to_call_apt_is_reported(self):
        for command in (
            "apt-get install --yes tmux",
            "sudo apt install tmux",
            "sudo -E apt-get update",
            "DEBIAN_FRONTEND=noninteractive apt-get update",
            "sudo timeout 60 apt-get update",
            "sudo apt-get update || true",
            "true && sudo apt-get update",
        ):
            with self.subTest(command=command):
                text = f"jobs:\n  a:\n    steps:\n      - run: {command}\n"
                problems = raw_apt_problems("ci.yml", text)
                self.assertEqual(len(problems), 1, problems)
                self.assertIn("run it through eng/ci/apt-get.sh", problems[0])

    def test_a_composite_action_is_scanned_too(self):
        text = "runs:\n  using: composite\n  steps:\n    - run: sudo apt-get update\n      shell: bash\n"
        self.assertEqual(
            raw_apt_problems("action.yml", text),
            [
                "action.yml:4: an unnamed step calls apt-get directly; "
                "run it through eng/ci/apt-get.sh"
            ],
        )

    def test_the_wrapper_comments_and_other_commands_pass(self):
        text = (
            "jobs:\n"
            "  build:\n"
            "    steps:\n"
            "      - name: Install tmux\n"
            "        run: |\n"
            "          # sudo apt-get update\n"
            "          ./eng/ci/apt-get.sh update\n"
            "          eng/ci/apt-get.sh install --yes \\\n"
            "            apt-utils libevent-dev\n"
            "          echo \"apt is slow\"\n"
            "      - name: Not a script\n"
            "        with:\n"
            "          note: sudo apt-get update\n"
        )
        self.assertEqual(raw_apt_problems("ci.yml", text), [])


if __name__ == "__main__":
    unittest.main()
