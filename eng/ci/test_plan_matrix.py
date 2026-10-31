"""Prove the matrix plan picks what each event should run, and that it can fail.

Every rule has a check, and every check has a deliberate break: the rule is
replaced with its absence and the check has to notice. A check that passes
with its rule removed would prove nothing about the rule.
"""

import unittest
from unittest import mock

import plan_matrix

MANIFEST = plan_matrix.load_manifest()
SUPPORTED = [each["tmux"] for each in MANIFEST["supported"]]
DEVELOPMENT = [each["tmux"] for each in MANIFEST["development"]]
POWERSHELL = [each["version"] for each in MANIFEST["powershell"]]
OLDEST, NEWEST = SUPPORTED[0], SUPPORTED[-1]

# The rules as the module defines them, before any deliberate break.
RULES = {
    name: getattr(plan_matrix, name)
    for name in (
        "resolve_scope",
        "select_lanes",
        "assign_tmate",
        "tmux_entries",
        "check_needs",
    )
}


def cells(result):
    return result["matrix"]["include"]


def tmux_of(result):
    return list(dict.fromkeys(each["tmux"] for each in cells(result)))


def run(event, **inputs):
    return plan_matrix.plan(MANIFEST, event=event, **inputs)


def refused(test, match, event="workflow_dispatch", **inputs):
    """Fail the check unless the plan is refused with a message naming the problem."""
    try:
        run(event, **inputs)
    except plan_matrix.PlanError as error:
        test.assertRegex(str(error), match)
        return
    test.fail(f"the plan was not refused: {match}")


def check_push_runs_the_edges_only(test):
    result = run("push")
    test.assertEqual(result["scope"], "edges")
    test.assertEqual(tmux_of(result), [OLDEST, NEWEST])
    test.assertEqual(
        [(each["tmux"], each["powershell"]) for each in cells(result)],
        [(tmux, shell) for tmux in (OLDEST, NEWEST) for shell in POWERSHELL],
    )
    test.assertEqual((result["reject"], result["old_daemon"]), ([], []))
    test.assertNotIn("master", tmux_of(result))


def check_pull_request_runs_the_edges_only(test):
    result = run("pull_request")
    test.assertEqual(result["scope"], "edges")
    test.assertEqual(tmux_of(result), [OLDEST, NEWEST])
    test.assertEqual((result["reject"], result["old_daemon"]), ([], []))


def check_dispatch_defaults_to_the_edges(test):
    test.assertEqual(tmux_of(run("workflow_dispatch")), [OLDEST, NEWEST])


def check_full_runs_the_whole_table(test):
    result = run("workflow_dispatch", scope="full")
    test.assertEqual(result["scope"], "full")
    test.assertEqual(tmux_of(result), [*SUPPORTED, *DEVELOPMENT])
    test.assertEqual(len(cells(result)), (len(SUPPORTED) + len(DEVELOPMENT)) * len(POWERSHELL))
    test.assertEqual(
        [each["tmux"] for each in result["reject"]],
        [each["tmux"] for each in MANIFEST["rejected"]],
    )
    test.assertEqual(
        [each["tmux"] for each in result["old_daemon"]],
        [each["tmux"] for each in MANIFEST["oldDaemon"]],
    )
    test.assertEqual({each["client_tmux"] for each in result["old_daemon"]}, {OLDEST})
    test.assertEqual({each["powershell"] for each in result["reject"]}, {POWERSHELL[0]})


def check_a_table_name_keeps_its_pin_and_other_refs_are_built(test):
    sha = "a" * 40
    result = run(
        "workflow_dispatch",
        scope="custom",
        tmux_ref=f"{SUPPORTED[1]}, {NEWEST},master,3.6b,{sha}",
        pwsh=POWERSHELL[0],
    )
    by_name = {each["tmux"]: each for each in cells(result)}
    test.assertEqual(list(by_name), [SUPPORTED[1], NEWEST, "master", "3.6b", sha])
    pinned = MANIFEST["supported"][1]
    test.assertEqual(
        (by_name[SUPPORTED[1]]["build"], by_name[SUPPORTED[1]]["tmux_commit"]),
        (pinned["build"], pinned["commit"]),
    )
    test.assertEqual(by_name[NEWEST]["build"], MANIFEST["supported"][-1]["build"])
    test.assertEqual(by_name["master"]["build"], "clone")
    test.assertEqual((by_name["3.6b"]["build"], by_name["3.6b"]["tmux_commit"]), ("ref", ""))
    test.assertEqual(by_name[sha]["build"], "ref")
    test.assertEqual((result["reject"], result["old_daemon"]), ([], []))
    slashed = run("workflow_dispatch", scope="custom", tmux_ref="feature/x")
    test.assertEqual({each["slug"] for each in cells(slashed)}, {"feature-x"})


def check_a_custom_run_needs_refs(test):
    refused(test, "needs tmux-ref", scope="custom")


def check_a_ref_list_needs_the_custom_scope(test):
    refused(test, "only used with scope custom", tmux_ref="3.6b")
    refused(test, "only used with scope custom", scope="full", tmux_ref="3.6b")


def check_a_scope_must_be_known(test):
    refused(test, "scope must be one of", scope="everything")


def check_an_unknown_event_is_refused(test):
    refused(test, "no scope is defined", event="schedule")


BAD_REFS = [
    "3.6b;rm",
    "$(id)",
    "a b",
    "x`id`",
    "a" * 65,
    "--upload-pack=x",
    "-x",
    "a..b",
    "topic.lock",
    "topic/",
    "deadbeef",
    "é",
]


def check_every_ref_is_validated(test):
    for bad in BAD_REFS:
        with test.assertRaises(plan_matrix.PlanError, msg=bad):
            run("workflow_dispatch", scope="custom", tmux_ref=f"{NEWEST},{bad}")
    for good in ["next-3.8", "feature/x_y.z", "a" * 40, "A-b_c.1"]:
        test.assertEqual(
            tmux_of(run("workflow_dispatch", scope="custom", tmux_ref=good)), [good]
        )


def check_too_many_refs_are_refused(test):
    eight = ",".join(f"v{n}" for n in range(8))
    test.assertEqual(len(tmux_of(run("workflow_dispatch", scope="custom", tmux_ref=eight))), 8)
    refused(test, "fit one run", scope="custom", tmux_ref=eight + ",v8")


def check_a_pwsh_input_narrows_the_stack(test):
    result = run("workflow_dispatch", pwsh=POWERSHELL[1])
    test.assertEqual({each["powershell"] for each in cells(result)}, {POWERSHELL[1]})
    test.assertEqual(
        {each["powershell_sha256"] for each in cells(result)},
        {MANIFEST["powershell"][1]["sha256"]},
    )
    test.assertEqual(tmux_of(result), [OLDEST, NEWEST])


def check_an_unknown_pwsh_is_refused(test):
    refused(test, "pwsh must name versions", pwsh="7.2.0")


def check_mcp_discovery_follows_the_edges(test):
    expected = sorted(
        (tmux, POWERSHELL[0]) for tmux in (OLDEST, NEWEST)
    )
    for result in (run("push"), run("workflow_dispatch", scope="full")):
        marked = sorted(
            (each["tmux"], each["powershell"]) for each in cells(result) if each["mcp"] == "true"
        )
        test.assertEqual(marked, expected)
    middle = run("workflow_dispatch", scope="custom", tmux_ref=SUPPORTED[1])
    test.assertEqual({each["mcp"] for each in cells(middle)}, {"false"})
    ref = run("workflow_dispatch", scope="custom", tmux_ref="3.6b")
    test.assertEqual({each["mcp"] for each in cells(ref)}, {"false"})


def check_one_leg_gets_the_debug_session(test):
    result = run(
        "workflow_dispatch",
        scope="custom",
        tmux_ref="master",
        pwsh=POWERSHELL[0],
        tmate="on-failure",
    )
    test.assertEqual([each["tmate"] for each in cells(result)], ["on-failure"])


def check_no_debug_session_by_default(test):
    result = run("workflow_dispatch", scope="custom", tmux_ref="master", pwsh=POWERSHELL[0])
    test.assertEqual([each["tmate"] for each in cells(result)], ["off"])


def check_several_legs_cannot_share_a_debug_session(test):
    refused(test, "exactly one leg", tmate="before-tests")
    refused(test, "exactly one leg", scope="full", tmate="before-tests")
    refused(test, "exactly one leg", scope="custom", tmux_ref="master", tmate="before-tests")
    refused(
        test,
        "exactly one leg",
        scope="custom",
        tmux_ref=f"{OLDEST},master",
        pwsh=POWERSHELL[0],
        tmate="before-tests",
    )


def check_a_debug_session_needs_a_dispatch(test):
    refused(
        test,
        "only available on a workflow_dispatch",
        event="push",
        scope="custom",
        tmux_ref="master",
        pwsh=POWERSHELL[0],
        tmate="on-failure",
    )


def check_a_debug_mode_must_be_known(test):
    refused(
        test,
        "tmate must be one of",
        scope="custom",
        tmux_ref="master",
        pwsh=POWERSHELL[0],
        tmate="always",
    )


def check_the_job_count_adds_up(test):
    # The plan, the package build and the gate.
    fixed = 3
    test.assertEqual(run("push")["expected_jobs"], fixed + 2 * len(POWERSHELL))
    full = run("workflow_dispatch", scope="full")
    test.assertEqual(
        full["expected_jobs"],
        fixed
        + (len(SUPPORTED) + len(DEVELOPMENT)) * len(POWERSHELL)
        + len(MANIFEST["rejected"])
        + len(MANIFEST["oldDaemon"]),
    )


def check_the_manifest_alone_decides_the_table(test):
    other = {
        "powershell": [{"version": "9.0.1", "sha256": "1" * 64}],
        "supported": [
            {"tmux": "9.1", "commit": "a" * 40, "build": "core"},
            {"tmux": "9.2", "commit": "b" * 40, "build": "core"},
            {"tmux": "9.3", "commit": "c" * 40, "build": "clone"},
        ],
        "development": [{"tmux": "next", "commit": "", "build": "clone"}],
        "rejected": [{"tmux": "9.0", "commit": "d" * 40}],
        "oldDaemon": [{"tmux": "8.9", "commit": "e" * 40}],
    }
    edges = plan_matrix.plan(other, event="push")
    test.assertEqual(
        [(each["tmux"], each["powershell"]) for each in cells(edges)],
        [("9.1", "9.0.1"), ("9.3", "9.0.1")],
    )
    full = plan_matrix.plan(other, event="workflow_dispatch", scope="full")
    test.assertEqual(tmux_of(full), ["9.1", "9.2", "9.3", "next"])
    test.assertEqual([each["tmux"] for each in full["reject"]], ["9.0"])
    test.assertEqual(full["old_daemon"][0]["client_tmux"], "9.1")
    test.assertEqual(full["old_daemon"][0]["client_commit"], "a" * 40)
    custom = plan_matrix.plan(other, event="workflow_dispatch", scope="custom", tmux_ref="9.2")
    test.assertEqual(cells(custom)[0]["tmux_commit"], "b" * 40)


def check_the_matrix_is_never_empty(test):
    empty = {**MANIFEST, "supported": [], "development": []}
    with test.assertRaisesRegex(plan_matrix.PlanError, "no test leg"):
        plan_matrix.plan(empty, event="push")


def check_a_single_release_is_one_edge(test):
    only = {**MANIFEST, "supported": MANIFEST["supported"][-1:]}
    test.assertEqual(tmux_of(plan_matrix.plan(only, event="push")), [NEWEST])


def check_job_names_follow_the_plan(test):
    names = plan_matrix.full_job_names(MANIFEST)
    test.assertEqual(len(names), run("workflow_dispatch", scope="full")["expected_jobs"])
    test.assertIn(f"PowerShell {POWERSHELL[1]} / tmux master", names)
    test.assertIn(f"PowerShell {POWERSHELL[0]} / tmux {MANIFEST['rejected'][0]['tmux']} rejected", names)
    test.assertIn(
        f"PowerShell {POWERSHELL[0]} / tmux {MANIFEST['oldDaemon'][0]['tmux']} "
        f"daemon behind a {OLDEST} client",
        names,
    )
    test.assertTrue({"plan", "build and pack PowerShell modules", "powershell gate"} <= names)
    edge_names = plan_matrix.job_names(run("push"))
    test.assertNotIn(f"PowerShell {POWERSHELL[0]} / tmux master", edge_names)


def needs(plan_result="success", port="success", matrix="success", reject="skipped", old="skipped",
          planned=False):
    listed = "[1]" if planned else "[]"
    return {
        "plan": {"result": plan_result, "outputs": {"reject": listed, "old_daemon": listed}},
        "port": {"result": port},
        "matrix": {"result": matrix},
        "reject": {"result": reject},
        "reject-old-daemon": {"result": old},
    }


def check_the_gate_passes_what_the_plan_scheduled(test):
    test.assertEqual(plan_matrix.check_needs(needs()), [])
    test.assertEqual(
        plan_matrix.check_needs(needs(reject="success", old="success", planned=True)), []
    )


def check_the_gate_needs_the_plan_the_package_and_the_matrix(test):
    for broken in (
        needs(plan_result="failure"),
        needs(port="failure"),
        needs(port="skipped"),
        needs(matrix="failure"),
        needs(matrix="cancelled"),
    ):
        test.assertNotEqual(plan_matrix.check_needs(broken), [])
    missing = needs()
    del missing["matrix"]
    test.assertNotEqual(plan_matrix.check_needs(missing), [])


def check_a_planned_lane_that_was_skipped_fails_the_gate(test):
    test.assertNotEqual(plan_matrix.check_needs(needs(reject="skipped", old="success", planned=True)), [])
    test.assertNotEqual(plan_matrix.check_needs(needs(reject="success", old="skipped", planned=True)), [])
    test.assertNotEqual(plan_matrix.check_needs(needs(reject="failure", old="success", planned=True)), [])


def check_a_lane_the_plan_left_out_must_not_have_run(test):
    test.assertNotEqual(plan_matrix.check_needs(needs(reject="success")), [])
    test.assertNotEqual(plan_matrix.check_needs(needs(old="failure")), [])


def resolving(**replaced):
    real = RULES["resolve_scope"]
    return lambda event, scope: real(replaced.get("event", event), replaced.get("scope", scope))


def laning(scope):
    real = RULES["select_lanes"]
    return lambda manifest, got: real(manifest, scope)


def every_version(supported):
    return list(supported)


def hard_coded(supported):
    return ["3.3a", "3.8"]


def anything(item):
    return item


def ignored(*arguments):
    return None


def always_ref(manifest, scope, tmux_ref):
    return [
        {"tmux": item, "commit": "", "build": "ref"} for item in plan_matrix.split_list(tmux_ref)
    ] or RULES["tmux_entries"](manifest, scope, tmux_ref)


def unchecked_refs(tmux_ref):
    return [anything(item) for item in plan_matrix.split_list(tmux_ref)]


def every_shell(manifest, requested):
    return list(manifest["powershell"])


def unchecked_shell(manifest, requested):
    available = {each["version"]: each for each in manifest["powershell"]}
    chosen = plan_matrix.split_list(requested)
    return [available[v] for v in chosen if v in available] or list(manifest["powershell"])


def no_mcp(manifest, got_cells):
    return None


def mcp_everywhere(manifest, got_cells):
    for each in got_cells:
        each["mcp"] = "true"


def no_debug_session(*arguments):
    return None


def debug_session_everywhere(event, mode, got_cells, lanes):
    for each in got_cells:
        each["tmate"] = mode


def debug_session_without_event(event, mode, got_cells, lanes):
    RULES["assign_tmate"]("workflow_dispatch", mode, got_cells, lanes)


def gate_without_lanes(got):
    return [p for p in RULES["check_needs"](got) if not p.startswith("reject")]


def gate_that_always_expects_a_skip(got):
    planned = {**got, "plan": {**got["plan"], "outputs": {"reject": "[]", "old_daemon": "[]"}}}
    return RULES["check_needs"](planned)


def gate_that_always_expects_a_run(got):
    planned = {**got, "plan": {**got["plan"], "outputs": {"reject": "[1]", "old_daemon": "[1]"}}}
    return RULES["check_needs"](planned)


def gate_that_accepts_unplanned_runs(got):
    return [p for p in RULES["check_needs"](got) if "not skipped" not in p]


def gate_without_the_matrix(got):
    return [p for p in RULES["check_needs"](got) if not p.startswith("matrix")]


def gate_without_the_package(got):
    return [p for p in RULES["check_needs"](got) if not p.startswith("port")]


def gate_without_the_plan(got):
    return [p for p in RULES["check_needs"](got) if not p.startswith("plan")]


def unchecked_event(event, scope):
    return "edges"


DELIBERATE_BREAKS = [
    ("the edges rule takes every version", "edge_versions", every_version,
     check_push_runs_the_edges_only),
    ("the edges are written into the plan", "edge_versions", hard_coded,
     check_the_manifest_alone_decides_the_table),
    ("a pull request runs the full scope", "resolve_scope",
     lambda event, scope: "full" if event == "pull_request" else RULES["resolve_scope"](event, scope),
     check_pull_request_runs_the_edges_only),
    ("a dispatch ignores the scope it was given", "resolve_scope", resolving(scope=""),
     check_full_runs_the_whole_table),
    ("a dispatch does not default to the edges", "resolve_scope", resolving(scope="full"),
     check_dispatch_defaults_to_the_edges),
    ("an unknown scope is accepted", "resolve_scope", resolving(scope="edges"),
     check_a_scope_must_be_known),
    ("an unknown event is accepted", "resolve_scope", unchecked_event,
     check_an_unknown_event_is_refused),
    ("the edges run the refusal lanes", "select_lanes", laning("full"),
     check_push_runs_the_edges_only),
    ("the full scope drops its lanes", "select_lanes", laning("edges"),
     check_full_runs_the_whole_table),
    ("a custom ref is always built from source", "tmux_entries", always_ref,
     check_a_table_name_keeps_its_pin_and_other_refs_are_built),
    ("a custom run without refs is planned", "custom_refs", unchecked_refs,
     check_a_custom_run_needs_refs),
    ("refs the scope ignores are accepted", "check_scope_inputs", ignored,
     check_a_ref_list_needs_the_custom_scope),
    ("a ref is not validated", "check_ref", anything, check_every_ref_is_validated),
    ("the ref count is unlimited", "MAX_REFS", 1000, check_too_many_refs_are_refused),
    ("the pwsh input is ignored", "select_powershell", every_shell,
     check_a_pwsh_input_narrows_the_stack),
    ("an unknown pwsh is accepted", "select_powershell", unchecked_shell,
     check_an_unknown_pwsh_is_refused),
    ("no leg runs MCP discovery", "mark_mcp", no_mcp, check_mcp_discovery_follows_the_edges),
    ("every leg runs MCP discovery", "mark_mcp", mcp_everywhere,
     check_mcp_discovery_follows_the_edges),
    ("no leg gets the debug session", "assign_tmate", no_debug_session,
     check_one_leg_gets_the_debug_session),
    ("every leg gets the debug session", "assign_tmate", debug_session_everywhere,
     check_several_legs_cannot_share_a_debug_session),
    ("the debug session runs outside a dispatch", "assign_tmate", debug_session_without_event,
     check_a_debug_session_needs_a_dispatch),
    ("an unknown debug mode is accepted", "assign_tmate", no_debug_session,
     check_a_debug_mode_must_be_known),
    ("the job count omits the fixed jobs", "FIXED_JOBS", 0, check_the_job_count_adds_up),
    ("an empty matrix is emitted", "require_cells", ignored, check_the_matrix_is_never_empty),
    ("the job names omit the matrix", "job_names", lambda result: {"plan"},
     check_job_names_follow_the_plan),
    ("the gate ignores the refusal lanes", "check_needs", gate_without_lanes,
     check_a_planned_lane_that_was_skipped_fails_the_gate),
    ("the gate expects every lane skipped", "check_needs", gate_that_always_expects_a_skip,
     check_the_gate_passes_what_the_plan_scheduled),
    ("the gate expects every lane run", "check_needs", gate_that_always_expects_a_run,
     check_the_gate_passes_what_the_plan_scheduled),
    ("the gate lets an unplanned lane run", "check_needs", gate_that_accepts_unplanned_runs,
     check_a_lane_the_plan_left_out_must_not_have_run),
    ("the gate ignores the matrix", "check_needs", gate_without_the_matrix,
     check_the_gate_needs_the_plan_the_package_and_the_matrix),
    ("the gate ignores the package build", "check_needs", gate_without_the_package,
     check_the_gate_needs_the_plan_the_package_and_the_matrix),
    ("the gate ignores the plan", "check_needs", gate_without_the_plan,
     check_the_gate_needs_the_plan_the_package_and_the_matrix),
]

ALL_CHECKS = [
    check_push_runs_the_edges_only,
    check_pull_request_runs_the_edges_only,
    check_dispatch_defaults_to_the_edges,
    check_full_runs_the_whole_table,
    check_a_table_name_keeps_its_pin_and_other_refs_are_built,
    check_a_custom_run_needs_refs,
    check_a_ref_list_needs_the_custom_scope,
    check_a_scope_must_be_known,
    check_an_unknown_event_is_refused,
    check_every_ref_is_validated,
    check_too_many_refs_are_refused,
    check_a_pwsh_input_narrows_the_stack,
    check_an_unknown_pwsh_is_refused,
    check_mcp_discovery_follows_the_edges,
    check_one_leg_gets_the_debug_session,
    check_no_debug_session_by_default,
    check_several_legs_cannot_share_a_debug_session,
    check_a_debug_session_needs_a_dispatch,
    check_a_debug_mode_must_be_known,
    check_the_job_count_adds_up,
    check_the_manifest_alone_decides_the_table,
    check_the_matrix_is_never_empty,
    check_a_single_release_is_one_edge,
    check_job_names_follow_the_plan,
    check_the_gate_passes_what_the_plan_scheduled,
    check_the_gate_needs_the_plan_the_package_and_the_matrix,
    check_a_planned_lane_that_was_skipped_fails_the_gate,
    check_a_lane_the_plan_left_out_must_not_have_run,
]

# Checks that state a default or a boundary no single removal can reach.
WITHOUT_A_BREAK = {
    check_no_debug_session_by_default,
    check_a_single_release_is_one_edge,
}


class PlanFollowsItsRules(unittest.TestCase):
    def test_every_check_passes(self):
        for check in ALL_CHECKS:
            with self.subTest(check=check.__name__):
                check(self)

    def test_every_check_has_a_deliberate_break(self):
        broken = {each[3] for each in DELIBERATE_BREAKS}
        self.assertEqual(
            {check for check in ALL_CHECKS if check not in broken}, WITHOUT_A_BREAK
        )

    def test_a_check_fails_when_its_rule_is_removed(self):
        for description, attribute, replacement, check in DELIBERATE_BREAKS:
            with self.subTest(description):
                check(self)
                with mock.patch.object(plan_matrix, attribute, replacement):
                    with self.assertRaises(Exception):
                        check(self)


class PlanOutputs(unittest.TestCase):
    def test_the_outputs_are_single_line_json(self):
        import contextlib
        import io
        import json
        import pathlib
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "output"
            summary = pathlib.Path(directory) / "summary"
            with contextlib.redirect_stdout(io.StringIO()):
                status = plan_matrix.main(
                    ["plan", "--event", "push", "--github-output", str(output),
                     "--summary", str(summary)]
                )
            self.assertEqual(status, 0)
            lines = output.read_text(encoding="utf-8").splitlines()
            values = dict(line.split("=", 1) for line in lines)
            self.assertEqual(list(values), ["scope", "matrix", "reject", "old_daemon", "expected_jobs"])
            self.assertEqual(len(lines), len(values))
            self.assertEqual(json.loads(values["matrix"])["include"], cells(run("push")))
            self.assertEqual(json.loads(values["reject"]), [])
            self.assertEqual(values["expected_jobs"], str(3 + 2 * len(POWERSHELL)))
            text = summary.read_text(encoding="utf-8")
            self.assertIn(f"PowerShell {POWERSHELL[0]} with tmux {OLDEST}", text)

    def test_a_refused_plan_exits_nonzero_and_writes_nothing(self):
        import contextlib
        import io
        import pathlib
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "output"
            errors = io.StringIO()
            with contextlib.redirect_stderr(errors):
                status = plan_matrix.main(
                    ["plan", "--event", "workflow_dispatch", "--scope", "custom",
                     "--github-output", str(output)]
                )
            self.assertEqual(status, 1)
            self.assertIn("needs tmux-ref", errors.getvalue())
            self.assertFalse(output.exists())

    def test_the_gate_command_reads_the_needs_context(self):
        import contextlib
        import io
        import json
        import os

        errors = io.StringIO()
        with mock.patch.dict(os.environ, {"NEEDS": json.dumps(needs())}):
            self.assertEqual(plan_matrix.main(["gate"]), 0)
        with mock.patch.dict(os.environ, {"NEEDS": json.dumps(needs(port="failure"))}):
            with contextlib.redirect_stderr(errors):
                self.assertEqual(plan_matrix.main(["gate"]), 1)
        self.assertIn("port finished failure, not success", errors.getvalue())


if __name__ == "__main__":
    unittest.main()
