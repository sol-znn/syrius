"""Finite parser and ownership regressions. No native or network execution."""

import importlib.util
import base64
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import types
import unittest
from unittest.mock import patch


TOOLS = Path(__file__).resolve().parents[2] / "tool/ci"
sys.path.insert(0, str(TOOLS))
try:
    SPEC = importlib.util.spec_from_file_location("windows_baseline", TOOLS / "windows_baseline.py")
    baseline = importlib.util.module_from_spec(SPEC)
    sys.modules[SPEC.name] = baseline
    SPEC.loader.exec_module(baseline)
finally:
    sys.path.pop(0)

SOURCE = "1" * 40
PRIVATE = "private-value-not-for-public-output"


class InventoryOnlyTests(unittest.TestCase):
    def test_hosted_native_inventory_environment_is_scoped_and_strips_credentials(self):
        parent = dict(GITHUB_ACTIONS='true', RUNNER_ENVIRONMENT='github-hosted',
            GITHUB_EVENT_NAME='workflow_dispatch', GITHUB_REPOSITORY='edgepillar/syrius',
            HOME='synthetic-runner-profile', GH_TOKEN='synthetic-private-token', PATH='synthetic-path')
        report = baseline.Baseline(Path('/fixture'), parent, SOURCE)
        report.inventory_only = True
        with patch.object(baseline, 'run_bounded', return_value=baseline.Outcome()) as run, \
                patch.object(baseline, 'fresh_environment') as profile:
            report.command('inventory_windows', ['synthetic-powershell'], hosted_inventory=True, required=False)
        env = run.call_args.kwargs['env']
        self.assertEqual(env['HOME'], 'synthetic-runner-profile')
        self.assertNotIn('GH_TOKEN', env)
        profile.assert_not_called()
        for field, value in (('GITHUB_REPOSITORY', 'other/repo'), ('RUNNER_ENVIRONMENT', 'self-hosted')):
            refused = baseline.Baseline(Path('/fixture'), {**parent, field:value}, SOURCE)
            refused.inventory_only = True
            with self.subTest(field=field), patch.object(baseline, 'run_bounded') as launch, \
                    self.assertRaises(baseline.BaselineFailure):
                refused.command('inventory_windows', ['synthetic'], hosted_inventory=True)
            launch.assert_not_called()

    def test_native_query_uses_exact_encoded_script_and_complete_ordered_progress(self):
        command = baseline.native_inventory_command('synthetic-powershell')
        self.assertEqual(command[-2], '-EncodedCommand')
        self.assertEqual(base64.b64decode(command[-1]).decode('utf-16-le'), baseline.WINDOWS_INVENTORY)
        values = dict(chrome=dict(status='present', version='1.2.3.4', scope='standard_install'))
        stages = list(baseline.NATIVE_INVENTORY_STAGES)
        stages[2:2] = baseline.NATIVE_INVENTORY_DETAILS
        lines = ['SYRIUS_INVENTORY_STAGE:' + stage for stage in stages]
        parsed, receipt = baseline.native_inventory_reply(('\n'.join(lines) + '\nSYRIUS_INVENTORY_JSON:' + json.dumps(values)).encode())
        self.assertEqual(parsed, values)
        self.assertTrue(receipt['complete'])
        self.assertEqual(receipt['details'], list(baseline.NATIVE_INVENTORY_DETAILS))
        self.assertEqual(receipt['frame_count'], 1)
        self.assertEqual(receipt['unframed_lines'], 0)

    def test_unframed_or_duplicate_json_cannot_qualify_native_tool_discovery(self):
        prefix = '\n'.join('SYRIUS_INVENTORY_STAGE:' + stage for stage in baseline.NATIVE_INVENTORY_STAGES)
        for suffix in ('{}', 'SYRIUS_INVENTORY_JSON:{}\nsynthetic-private-diagnostic',
                       'SYRIUS_INVENTORY_JSON:{}\nSYRIUS_INVENTORY_JSON:{}'):
            with self.subTest(bytes=len(suffix)):
                values, receipt = baseline.native_inventory_reply((prefix+'\n'+suffix).encode())
                self.assertIsNone(values)
                self.assertFalse(receipt['complete'])
                self.assertNotIn('synthetic-private-diagnostic', json.dumps(receipt))

    def test_partial_duplicate_unknown_and_private_output_never_complete_a_query(self):
        for raw in (b'', b'SYRIUS_INVENTORY_STAGE:entry\n',
                    b'SYRIUS_INVENTORY_STAGE:entry\nSYRIUS_INVENTORY_STAGE:entry\n{}',
                    b'SYRIUS_INVENTORY_STAGE:private\n{}',
                    b'synthetic-private-output\n'):
            with self.subTest(bytes=len(raw)):
                values, receipt = baseline.native_inventory_reply(raw)
                self.assertIsNone(values)
                self.assertFalse(receipt['complete'])
                self.assertNotIn('synthetic-private-output', json.dumps(receipt))

    def test_git_bash_discovery_handles_cmd_bin_and_mingw_layouts(self):
        expected = Path('/fixture/Git/bin/bash.exe')
        for offered in ('/fixture/Git/cmd/git.exe', '/fixture/Git/bin/git.exe',
                        '/fixture/Git/mingw64/bin/git.exe'):
            probes = []
            def present(path):
                probes.append(str(path))
                return path == expected
            with patch.object(Path, 'is_file', autospec=True, side_effect=present):
                self.assertEqual(baseline.find_git_bash(offered), str(expected))
            self.assertLessEqual(len(probes), 8)

    def test_inventory_mode_never_runs_build_tests_doctor_or_dependency_resolution(self):
        report = baseline.Baseline(Path('/fixture'), dict(PATH='fixture'), SOURCE)
        report.inventory_only = True
        replies = dict(source_head=SOURCE.encode(), source_tree=b'2'*40,
                       source_clean_before=b'', source_clean_after=b'')
        def command(name, *args, **kwargs):
            self.assertIn(name, replies)
            return types.SimpleNamespace(output=replies[name])
        def collect():
            report.inventory = {key: baseline.version_record('1.2', 'path')
                                for key in baseline.INVENTORY if key != 'docker_daemon'}
        def found(name, **kwargs):
            return '/fixture/' + name + ('.bat' if name == 'flutter' else '.exe')
        with patch.object(report, 'command', side_effect=command) as calls, \
                patch.object(report, 'collect_inventory', side_effect=collect), \
                patch.object(baseline.shutil, 'which', side_effect=found), \
                patch.object(Path, 'is_file', return_value=True):
            report.run()
        self.assertEqual([call.args[0] for call in calls.call_args_list],
            ['source_head', 'source_tree', 'source_clean_before', 'source_clean_after'])
        public = report.public()
        self.assertTrue(public['success'])
        self.assertEqual(public['scope'], 'github_hosted_windows_inventory')
        self.assertFalse(public['baseline_qualified'])
        self.assertFalse(public['wallet_qualified'])

    def test_unknown_inventory_cannot_become_complete_from_source_checks_alone(self):
        report = baseline.Baseline(Path('/fixture'), {}, SOURCE)
        report.inventory_only = True
        report.checks['source'] = report.checks['source_unchanged'] = True
        self.assertFalse(report.public()['success'])
        self.assertFalse(report.public()['checks']['inventory'])


def events(*values):
    return b"\n".join(json.dumps(value).encode() for value in values) + b"\n"


def finished(identity, *, result="success", skipped=False, hidden=False):
    return {"type": "testDone", "testID": identity, "result": result,
            "skipped": skipped, "hidden": hidden}


class ParserTests(unittest.TestCase):
    def test_terminal_counts_distinguish_visible_hidden_skipped_and_failures(self):
        parsed = baseline.test_counts(events(
            {"type": "start"}, {"type": "suite", "suite": {"path": PRIVATE}},
            {"type": "testStart", "test": {"id": 100, "name": PRIVATE}},
            finished(1, hidden=True), finished(2), finished(3, skipped=True),
            finished(4, hidden=True, result="error"),
            {"type": "error", "testID": 4, "error": PRIVATE},
            {"type": "done", "success": False},
        ))
        self.assertEqual(parsed, {
            "passed": 1, "failed": 1, "skipped": 1, "hidden": 2,
            "terminal_events": 4, "error_events": 1, "terminal_success": False,
        })
        self.assertNotIn(PRIVATE, json.dumps(parsed))

    def test_real_hidden_loading_and_skipped_events_can_finish_successfully(self):
        parsed = baseline.test_counts(events(
            finished(1, hidden=True), finished(2), finished(3, skipped=True),
            {"type": "print", "message": PRIVATE},
            {"type": "done", "success": True},
        ))
        self.assertEqual((parsed["passed"], parsed["skipped"], parsed["hidden"]), (1, 1, 1))
        self.assertTrue(parsed["terminal_success"])

    def test_missing_false_typed_duplicate_or_early_terminal_never_passes(self):
        for payload in (
            b"", events(finished(1)), events({"type": "done", "success": True}),
            events(finished(1), finished(1), {"type": "done", "success": True}),
            events(finished(1), {"type": "done", "success": "true"}),
            events(finished(1), {"type": "done", "success": True}, finished(2)),
            events(finished(True), {"type": "done", "success": True}),
            events(finished(1, skipped="false"), {"type": "done", "success": True}),
            events(finished(1, result="unknown"), {"type": "done", "success": True}),
            b"not JSON\n", b"\xff\n",
        ):
            with self.subTest(payload=payload[:80]), self.assertRaises(baseline.BaselineFailure) as failure:
                baseline.test_counts(payload)
            self.assertEqual(failure.exception.code, "TEST_EVENTS_INVALID")

    def test_analysis_infos_remain_distinct_and_private_diagnostics_are_removed(self):
        parsed = baseline.analysis_counts((
            "Analyzing checkout...\r\n"
            " info • " + PRIVATE + " • file.dart:1:1 • lint\n"
            " warning • " + PRIVATE + " • file.dart:2:1 • lint\n"
            " error • " + PRIVATE + " • file.dart:3:1 • code\n"
            "3 issues found. (ran in 1.0s)\n"
        ).encode())
        self.assertEqual(parsed, {"errors": 1, "warnings": 1, "infos": 1})
        self.assertNotIn(PRIVATE, json.dumps(parsed))
        self.assertEqual(baseline.analysis_counts(b"No issues found! (ran in 1.0s)\n"),
                         {"errors": 0, "warnings": 0, "infos": 0})

    def test_analysis_missing_mismatched_and_duplicate_summaries_fail(self):
        for output in (b"", b"2 issues found.\n", b"No issues found!\nNo issues found!\n",
                       "info • private\nNo issues found!\n".encode()):
            with self.subTest(output=output), self.assertRaises(baseline.BaselineFailure) as failure:
                baseline.analysis_counts(output)
            self.assertEqual(failure.exception.code, "ANALYSIS_INVALID")

    def test_doctor_reports_only_windows_headings_not_other_failures_or_details(self):
        text = (
            "[✓] Windows Version (Windows 11)\n"
            "    " + PRIVATE + "\n"
            "[√] Visual Studio - develop Windows apps (" + PRIVATE + ")\n"
            "[X] Android toolchain - " + PRIVATE + "\n"
        ).encode()
        self.assertEqual(baseline.doctor_status(text),
                         {"windows_version": "pass", "visual_studio": "pass"})
        self.assertNotIn(PRIVATE, json.dumps(baseline.doctor_status(text)))

    def test_doctor_accepts_only_pinned_timing_prefix_and_original_status(self):
        for prefix in ("[        ] ", "[   +1 ms] ", "[  +12 ms] ", "[+1234 ms] "):
            for marker in ("✓", "√"):
                with self.subTest(prefix=prefix, marker=marker):
                    output = (prefix + "[" + marker + "] Windows Version (" + PRIVATE + ")\n"
                              + prefix + "[" + marker + "] Visual Studio - " + PRIVATE + "\n")
                    parsed = baseline.doctor_status(output.encode())
                    self.assertEqual(parsed, {"windows_version": "pass", "visual_studio": "pass"})
                    self.assertNotIn(PRIVATE, json.dumps(parsed))
        self.assertEqual(baseline.doctor_status(
            b"[   +1 ms] [!] Windows Version warning\n"
            b"[        ] [X] Visual Studio failed\n"),
            {"windows_version": "warning", "visual_studio": "fail"})

    def test_doctor_verbose_noise_or_malformed_prefix_cannot_create_proof(self):
        for prefix in ("[trace] ", "[ +0 ms] ", "[ -1 ms] ", "[ +1.5 ms] ",
                       "[ +1 s] ", "[ +1 ms] Executing ", "[ +1 ms] [ +2 ms] "):
            with self.subTest(prefix=prefix):
                parsed = baseline.doctor_status((prefix + "[✓] Windows Version\n"
                                                 + prefix + "[✓] Visual Studio\n").encode())
                self.assertEqual(set(parsed.values()), {"unknown"})
        with self.assertRaises(baseline.BaselineFailure):
            baseline.doctor_status("[✓] Windows Version\n[   +1 ms] [✓] Windows Version\n".encode())

    def test_doctor_warning_failure_missing_and_duplicate_stay_unproven(self):
        self.assertEqual(baseline.doctor_status(b"[!] Visual Studio - warning\n")["visual_studio"], "warning")
        self.assertEqual(baseline.doctor_status(b"[X] Windows Version broken\n")["windows_version"], "fail")
        self.assertEqual(set(baseline.doctor_status(b"").values()), {"unknown"})
        with self.assertRaises(baseline.BaselineFailure):
            baseline.doctor_status(b"[X] Windows Version bad\n[X] Windows Version bad\n")

    def test_version_inventory_does_not_extract_version_shaped_data_from_private_paths(self):
        values = {
            "python": baseline.version_record(PRIVATE + "/3.13.0", "path"),
            "pillow": baseline.version_record(None, "metadata", absent=True),
            "developer_mode": {"status": "disabled", "version": None, "scope": "registry"},
            "chrome": {"status": "present", "version": PRIVATE, "scope": PRIVATE, "path": PRIVATE},
            "extra": {"status": "present", "version": PRIVATE},
        }
        public = baseline.inventory_projection(values)
        self.assertEqual(public["python"]["status"], "unknown")
        self.assertEqual(public["pillow"]["status"], "absent")
        self.assertEqual(public["developer_mode"]["status"], "disabled")
        self.assertEqual(public["chrome"]["status"], "unknown")
        self.assertNotIn("extra", public)
        self.assertNotIn(PRIVATE, json.dumps(public))

    def test_library_reply_requires_exact_boolean_lookup_without_extra_output(self):
        valid = {"schema": 1, "mapped": True, "run_node_lookup": True,
                 "stop_node_lookup": True, "exports_invoked": False}
        self.assertEqual(baseline.library_reply(json.dumps(valid)), valid)
        for reply in (
            {**valid, "mapped": 1}, {**valid, "exports_invoked": True},
            {**valid, "stop_node_lookup": False}, {**valid, "path": PRIVATE},
            {"mapped": True}, [],
        ):
            with self.subTest(reply=reply), self.assertRaises(baseline.BaselineFailure):
                baseline.library_reply(json.dumps(reply))
        with self.assertRaises(baseline.BaselineFailure):
            baseline.library_reply(json.dumps(valid) + "\n" + PRIVATE)

    def test_malformed_inventory_values_are_unknown_and_cannot_break_public_projection(self):
        values = {
            "node": {"status": {"private": PRIVATE}, "version": PRIVATE, "scope": []},
            "chrome": [PRIVATE],
            "developer_mode": {"status": "unknown", "version": None, "scope": "registry"},
        }
        public = baseline.inventory_projection(values)
        self.assertEqual(public["node"]["status"], "unknown")
        self.assertEqual(public["chrome"]["status"], "unknown")
        self.assertNotIn(PRIVATE, json.dumps(public))


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


class OriginalProcess:
    def __init__(self, clock, *, code=0, hung=False, kill_error=False):
        self.clock, self.code, self.hung = clock, code, hung
        self.returncode = None
        self.stdout = io.BytesIO(PRIVATE.encode())
        self.kills = 0
        self.kill_error = kill_error

    def poll(self):
        return self.returncode

    def wait(self, timeout):
        if self.returncode is None:
            if self.hung:
                self.clock.now += timeout
                raise subprocess.TimeoutExpired(PRIVATE, timeout)
            self.returncode = self.code
        return self.returncode

    def kill(self):
        self.kills += 1
        if self.kill_error:
            raise OSError(PRIVATE)
        self.returncode = 0


class Drain:
    def __init__(self, *, complete=True, overflow=False):
        self.done = complete
        self.overflow = threading.Event()
        if overflow:
            self.overflow.set()
        self.data = PRIVATE.encode()
        self.count = len(self.data)

    def finish(self, timeout):
        return self.done


class ProcessTests(unittest.TestCase):
    def invoke(self, process, drain=None):
        return baseline.run_bounded(
            ["fixed-child"], cwd=Path("."), env={}, timeout=0.5, cap=128,
            spawn=lambda *args, **kwargs: process,
            drain_factory=lambda *args, **kwargs: drain or Drain(), clock=process.clock,
        )

    def test_original_zero_exit_and_complete_output_is_required(self):
        process = OriginalProcess(Clock())
        result = self.invoke(process)
        self.assertTrue(result.success)
        self.assertEqual(result.exit_code, 0)
        self.assertEqual(process.kills, 0)
        self.assertNotIn(PRIVATE, json.dumps(result.public()))

    def test_nonzero_original_exit_retains_actual_status(self):
        result = self.invoke(OriginalProcess(Clock(), code=7))
        self.assertFalse(result.success)
        self.assertEqual(result.exit_code, 7)
        self.assertTrue(result.exit_observed)

    def test_timeout_kills_only_original_and_forced_zero_exit_stays_failure(self):
        original = OriginalProcess(Clock(), hung=True)
        unrelated = OriginalProcess(Clock(), hung=True)
        result = self.invoke(original)
        self.assertEqual(original.kills, 1)
        self.assertEqual(unrelated.kills, 0)
        self.assertEqual(result.exit_code, 0)
        self.assertTrue(result.forced_kill)
        self.assertFalse(result.success)
        self.assertIn("COMMAND_TIMEOUT", result.errors)

    def test_output_overflow_kills_original_even_before_deadline(self):
        original = OriginalProcess(Clock(), hung=True)
        result = self.invoke(original, Drain(overflow=True))
        self.assertTrue(result.output_overflow)
        self.assertFalse(result.success)
        self.assertEqual(original.kills, 1)
        self.assertIn("OUTPUT_OVERFLOW", result.errors)

    def test_incomplete_output_does_not_pass_after_zero_exit(self):
        result = self.invoke(OriginalProcess(Clock()), Drain(complete=False))
        self.assertEqual(result.exit_code, 0)
        self.assertFalse(result.success)
        self.assertIn("OUTPUT_INCOMPLETE", result.errors)

    def test_uncertain_cleanup_never_claims_original_exit(self):
        original = OriginalProcess(Clock(), hung=True, kill_error=True)
        result = self.invoke(original)
        self.assertFalse(result.exit_observed)
        self.assertFalse(result.success)
        self.assertIn("CLEANUP_FAILED", result.errors)
        self.assertNotIn(PRIVATE, json.dumps(result.public()))

    def test_launch_failure_has_no_exit_or_raw_exception(self):
        def refuse(*args, **kwargs):
            raise OSError(PRIVATE)
        result = baseline.run_bounded(["fixed"], cwd=Path("."), env={}, spawn=refuse)
        self.assertFalse(result.exit_observed)
        self.assertFalse(result.success)
        self.assertEqual(result.errors, ("LAUNCH_FAILED",))
        self.assertNotIn(PRIVATE, json.dumps(result.public()))

    def test_batch_wrapper_quotes_spaces_and_refuses_cmd_metacharacters(self):
        env = {"SYSTEMROOT": r"C:\Windows"}
        command = baseline.command_line([r"C:\Flutter Tools\flutter.bat", "--version"], env)
        self.assertIn(' /d /s /c ""C:\\Flutter Tools\\flutter.bat" --version"', command)
        for suffix in ('&other', '%SECRET%', 'unsafe"', "two\nlines"):
            with self.subTest(suffix=suffix), self.assertRaises(baseline.BaselineFailure):
                baseline.command_line(["flutter.bat", suffix], env)
        native = ["dart.exe", PRIVATE]
        self.assertIs(baseline.command_line(native, env), native)


class AdmissionAndCorrespondenceTests(unittest.TestCase):
    def test_non_ci_main_refuses_before_profile_process_or_network_effect(self):
        with patch.dict(os.environ, {}, clear=True), \
                patch.object(baseline, "fresh_environment") as profile, \
                patch.object(baseline.subprocess, "Popen") as launch, \
                patch("sys.stdout", new_callable=io.StringIO) as output:
            code = baseline.main([])
        self.assertEqual(code, 1)
        result = json.loads(output.getvalue())
        self.assertEqual(result["error_codes"], ["ENVIRONMENT_REFUSED"])
        self.assertFalse(result["success"])
        profile.assert_not_called()
        launch.assert_not_called()

    def test_profile_is_fresh_isolated_and_excludes_private_inheritance(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            parent = {"GITHUB_SHA": SOURCE, "PATH": "runtime-path", "SYSTEMROOT": "system",
                      "APPDATA": PRIVATE, "GITHUB_TOKEN": PRIVATE, "HTTP_PROXY": PRIVATE,
                      "SYRIUS_HARNESS_TOKEN": PRIVATE, "PUB_CACHE": "tool-cache"}
            original = dict(parent)
            first = baseline.fresh_environment(repo, parent)
            second = baseline.fresh_environment(repo, parent)
            self.assertNotEqual(first["HOME"], second["HOME"])
            self.assertEqual(parent, original)
            self.assertNotIn(PRIVATE, first.values())
            self.assertEqual(first["PUB_CACHE"], "tool-cache")
            self.assertEqual(first["USERPROFILE"], first["HOME"])
            self.assertTrue(Path(first["APPDATA"]).is_dir())
            self.assertTrue(Path(second["TEMP"]).is_dir())

    def test_existing_profile_is_refused_and_kept(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            folder = repo / ".harness" / ("ci-windows-baseline-" + "a" * 24)
            folder.mkdir(parents=True)
            marker = folder / "retained"
            marker.write_text(PRIVATE)
            with patch.object(baseline.secrets, "token_hex", return_value="a" * 24):
                with self.assertRaises(FileExistsError):
                    baseline.fresh_environment(repo, {"GITHUB_SHA": SOURCE})
            self.assertEqual(marker.read_text(), PRIVATE)

    def test_localization_snapshot_binds_sources_outputs_and_new_locale(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            folder = repo / "lib/l10n"
            folder.mkdir(parents=True)
            for name in ("app_en.arb", "app_localizations.dart", "untranslated.json"):
                (folder / name).write_text("original")
            (repo / "l10n.yaml").write_text("configuration")
            before = baseline.localization_snapshot(repo)
            self.assertEqual(before["files"], 4)
            self.assertEqual(before, baseline.localization_snapshot(repo))
            (folder / "app_en.arb").write_text("changed source")
            self.assertNotEqual(before, baseline.localization_snapshot(repo))
            (folder / "app_en.arb").write_text("original")
            (folder / "app_localizations.dart").write_text("changed output")
            self.assertNotEqual(before, baseline.localization_snapshot(repo))
            (folder / "app_localizations.dart").write_text("original")
            (folder / "app_new.arb").write_text("new locale")
            self.assertNotEqual(before, baseline.localization_snapshot(repo))

    def test_unknown_inventory_does_not_satisfy_required_baseline_checks(self):
        report = baseline.Baseline(Path("."), {}, SOURCE)
        report.inventory = {"node": baseline.version_record(None, "path")}
        self.assertFalse(report.public()["success"])
        report.checks = dict.fromkeys(baseline.CHECKS, True)
        self.assertTrue(report.public()["success"])
        self.assertEqual(report.public()["inventory"]["node"]["status"], "unknown")
        report.errors.append("DOCTOR_UNPROVEN")
        self.assertFalse(report.public()["success"])

    def test_failed_required_command_preserves_its_public_receipt(self):
        report = baseline.Baseline(Path("."), {}, SOURCE)
        report.tool_env = {"SYSTEMROOT": "system"}
        failed = baseline.Outcome(output=PRIVATE.encode(), exit_code=9,
                                  exit_observed=True, output_complete=True)
        with patch.object(baseline, "run_bounded", return_value=failed):
            with self.assertRaises(baseline.BaselineFailure) as error:
                report.command("build_debug", ["fixed"])
        self.assertEqual(error.exception.code, "REQUIRED_COMMAND_FAILED")
        self.assertEqual(report.public()["stages"]["build_debug"]["exit_code"], 9)
        self.assertNotIn(PRIVATE, json.dumps(report.public()))


class PipelineTests(unittest.TestCase):
    """Exercise real orchestration against finite receipts, without children."""

    def exercise(self, *, suite=None, changed=None, bad_library=False):
        report = baseline.Baseline(Path("checkout"), {}, SOURCE)
        calls = []
        library = {"schema": 1, "mapped": True, "run_node_lookup": True,
                   "stop_node_lookup": not bad_library, "exports_invoked": False}

        def command(name, arguments, **options):
            calls.append((name, arguments, options))
            output = b""
            code = 0
            if name == "source_head":
                output = SOURCE.encode()
            elif name == "source_tree":
                output = b"2" * 40
            elif name == "doctor":
                output = "[√] Windows Version (11)\n[√] Visual Studio - desktop\n[X] Android missing\n".encode()
                code = 1
            elif name.startswith("analyze_"):
                output = b"No issues found! (ran in 1s)\n"
            elif name == "unit_widget_tests":
                if suite is not None:
                    return suite
                output = events(finished(1, hidden=True), finished(2),
                                finished(3, skipped=True), {"type": "done", "success": True})
            elif name.startswith("map_"):
                output = json.dumps(library).encode()
            if name == changed:
                output = PRIVATE.encode()
            return baseline.Outcome(output=output, exit_code=code, exit_observed=True,
                                    output_complete=True)

        failure = None
        with patch.object(baseline.shutil, "which", side_effect=lambda name, **kw: name + ".exe"), \
                patch.object(Path, "is_file", return_value=True), \
                patch.object(report, "collect_inventory"), \
                patch.object(report, "command", side_effect=command), \
                patch.object(baseline, "localization_snapshot", return_value={"files": 8, "sha256": "3" * 64}), \
                patch.object(baseline, "binary_hash", return_value=(Path("selected"), "4" * 64, (1, 2, 3, 4))):
            try:
                report.run()
            except baseline.BaselineFailure as error:
                failure = error.code
        return report, calls, failure

    def test_pipeline_allows_unrelated_doctor_failure_and_preserves_exact_commands(self):
        report, calls, failure = self.exercise()
        self.assertIsNone(failure)
        self.assertTrue(report.public()["success"])
        selected = {name: (arguments, options) for name, arguments, options in calls}
        self.assertIn("--enforce-lockfile", selected["restore_vendored"][0])
        self.assertEqual(selected["restore_vendored"][1]["cwd"],
                         Path("checkout/patched_packages/reown_core-1.3.8"))
        suite = selected["unit_widget_tests"][0]
        self.assertIn("--no-pub", suite)
        self.assertEqual(suite[suite.index("--exclude-tags") + 1], "chain")
        self.assertEqual(set(report.libraries), {"source", "debug", "release"})
        for variant in baseline.LIBRARIES:
            self.assertTrue(selected["map_" + variant][1]["fresh"])
            self.assertEqual(selected["map_" + variant][0][-2:], ["--variant", variant])
        self.assertEqual(report.tests["passed"], 1)
        self.assertEqual(report.tests["skipped"], 1)

    def test_incomplete_overflow_forced_exit_or_nonzero_suite_stops_before_generation(self):
        for options in (
            {"output_complete": False}, {"output_overflow": True},
            {"forced_kill": True}, {"exit_code": 9},
        ):
            outcome = baseline.Outcome(
                output=events(finished(1), {"type": "done", "success": True}),
                exit_code=0, exit_observed=True, output_complete=True,
            )
            for key, value in options.items():
                setattr(outcome, key, value)
            with self.subTest(options=options):
                report, calls, failure = self.exercise(suite=outcome)
                self.assertEqual(failure, "TESTS_FAILED")
                self.assertFalse(report.checks["unit_widget_tests"])
                self.assertNotIn("generate_sources", [name for name, _, _ in calls])

    def test_original_root_failure_exports_only_a_closed_source_location(self):
        failed = baseline.Outcome(output=events(
            dict(type='error', testID=1, isFailure=True,
                error='Expected: <1> private error and wallet text',
                stackTrace='private-root/test/welcome/welcome_surface_test.dart:554:7'),
            finished(1, result='error'), dict(type='done', success=False)),
            exit_code=1, exit_observed=True, output_complete=True)
        report, calls, failure = self.exercise(suite=failed)
        self.assertEqual(failure, 'TESTS_FAILED')
        self.assertFalse(report.checks['unit_widget_tests'])
        self.assertNotIn('generate_sources', [name for name, _, _ in calls])
        self.assertEqual(report.public()['test_failures'], dict(status='OBSERVED',
            total=1, items=[dict(file='welcome_surface_test.dart', line=554,
                kind='ASSERTION', category='ASSERTION')]))
        self.assertNotIn('private', json.dumps(report.public()))
        self.assertFalse(report.public()['success'])

    def test_restoration_or_generation_drift_refuses_later_builds(self):
        for name in ("source_clean_restored", "source_clean_generated"):
            with self.subTest(stage=name):
                report, calls, failure = self.exercise(changed=name)
                self.assertEqual(failure, "SOURCE_CHANGED")
                self.assertFalse(report.checks["generated_correspondence"])
                self.assertNotIn("build_debug", [stage for stage, _, _ in calls])

    def test_missing_export_refuses_remaining_library_probes(self):
        report, calls, failure = self.exercise(bad_library=True)
        self.assertEqual(failure, "LIBRARY_PROBE_INVALID")
        self.assertFalse(report.checks["library_map_exports"])
        self.assertNotIn("map_debug", [name for name, _, _ in calls])


if __name__ == "__main__":
    unittest.main()
