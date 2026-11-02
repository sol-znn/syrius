"""Finite, transport-free controller tests; these do not qualify Windows UI."""

import importlib.util
import io
import json
from pathlib import Path, PureWindowsPath
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

CONTROLLER = Path(__file__).resolve().parents[2] / "tool/ci/windows_presentation_smoke.py"
SPEC = importlib.util.spec_from_file_location("windows_presentation_smoke", CONTROLLER)
smoke = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = smoke
SPEC.loader.exec_module(smoke)


SOURCE = "1" * 40
BINARY_HASH = "2" * 64
KERNEL_HASH = "3" * 64
TOKEN = "private-test-token-never-public"
LIMITS = smoke.Limits(
    total=10, ready=0.3, request=0.2, poll=0.1,
    exit=0.2, cleanup=0.2, drain=0.1,
)


def reply(body, status=200):
    return smoke.Reply(status, json.dumps(body).encode())


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class OriginalProcess:
    def __init__(self):
        self.pid = 4141
        self.returncode = None
        self.close_requested = False
        self.can_close = True
        self.kill_count = 0
        self.waits = []
        self.kill_error = None
        self.close_exit = 0

    def poll(self):
        return self.returncode

    def wait(self, timeout):
        self.waits.append(timeout)
        if self.returncode is None:
            if self.close_requested and self.can_close:
                self.returncode = self.close_exit
            else:
                raise subprocess.TimeoutExpired("original-owned-process", timeout)
        return self.returncode

    def kill(self):
        self.kill_count += 1
        if self.kill_error:
            raise self.kill_error
        self.returncode = 1


class Drain:
    def __init__(self):
        self.overflow = threading.Event()
        self.error = None
        self.complete = True
        self.finishes = []
        self.overflow_on_finish = False

    def finish(self, timeout):
        self.finishes.append(timeout)
        if self.overflow_on_finish:
            self.overflow.set()
        return self.complete


class PresentationModel:
    """External observable host model; hooks model violations and uncertainty."""

    def __init__(self, process):
        self.process = process
        self.surface = "welcome"
        self.theme = "dark"
        self.field = ""
        self.calls = []
        self.hook = None
        self.booted = True
        self.pid = process.pid
        self.mode = "presentation"

    def facts(self):
        return {
            "presentation": True, "readOnly": True,
            "surface": self.surface, "theme": self.theme,
            "actualCapture": False, "walletOwnerMounted": False,
        }

    def response(self, extra=None):
        return reply({
            "ok": True, "harnessMode": "presentation",
            "presentationScreen": self.surface, "readOnly": True,
            **(extra or {}),
        })

    def exchange(self, command, token, timeout):
        self.calls.append((dict(command), token, timeout))
        if self.hook is not None:
            override = self.hook(command, token)
            if override is not None:
                return override
        if token != TOKEN:
            return reply({"ok": False, "error": "bad token"}, 400)
        name = command["cmd"]
        if name == "ping":
            return reply({
                "ok": True, "pid": self.pid, "booted": self.booted,
                "harnessMode": self.mode, "presentationScreen": self.surface,
            })
        if name == "theme":
            self.theme = command["mode"]
            return self.response({**self.facts(), "mode": self.theme, "brightness": self.theme})
        if name == "presentation":
            self.surface = command["surface"]
            return self.response({**self.facts(), "mode": self.theme, "brightness": self.theme})
        if name == "state":
            return self.response({
                **self.facts(), "booted": True, "walletUnlocked": False,
                "walletInitCompleted": False, "tabs": [],
            })
        if name == "assert":
            target = {"key": command["key"], "kind": "text"}
            if command["key"] == "import_seed_field":
                target.update(kind="field", value=self.field)
            return self.response({
                "asserted": True, "presentationOnly": True,
                "actualCapture": False, "target": target,
            })
        if name in smoke.BLOCKED:
            return reply({"ok": False, "error": smoke.REFUSED}, 400)
        if name == "quit":
            self.process.close_requested = True
            return self.response({"close": {
                "status": "queued", "queued": True, "admitted": False,
                "completed": False, "exitProved": False,
            }})
        raise AssertionError("unexpected controller command")


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.process = OriginalProcess()
        self.host = PresentationModel(self.process)
        self.drain = Drain()
        self.report = smoke.Report()
        self.report.source_sha = SOURCE
        self.report.runner_sha256 = BINARY_HASH
        self.report.dart_kernel_sha256 = KERNEL_HASH
        for name in ("environment", "source", "profile", "preflight"):
            self.report.checks[name] = True

    def run_smoke(self):
        return smoke.PresentationSmoke(
            self.process, self.host, TOKEN, self.drain, self.report,
            limits=LIMITS, clock=self.clock, sleep=self.clock.sleep,
        ).run()

    def commands(self):
        return [command["cmd"] for command, _, _ in self.host.calls]

    def test_both_themes_original_identity_all_refusals_and_actual_exit(self):
        result = self.run_smoke()
        self.assertTrue(result["success"])
        self.assertTrue(all(result["checks"].values()))
        self.assertEqual(result["exit_code"], 0)
        self.assertTrue(result["exit_observed"])
        self.assertEqual(self.commands().count("quit"), 1)
        self.assertEqual(self.process.kill_count, 0)
        self.assertEqual(
            [command["cmd"] for command, _, _ in self.host.calls
             if command["cmd"] in smoke.BLOCKED], list(smoke.BLOCKED),
        )
        self.assertEqual(self.host.field, "")
        self.assertEqual(
            [command["mode"] for command, _, _ in self.host.calls if command["cmd"] == "theme"],
            ["dark", "light", "dark", "light"],
        )

    def test_wrong_pid_or_wallet_mode_refuses_before_theme_or_close(self):
        for wrong, code in (("pid", "IDENTITY_REFUSED"), ("mode", "MODE_REFUSED")):
            with self.subTest(wrong=wrong):
                self.setUp()
                setattr(self.host, wrong, 9191 if wrong == "pid" else "wallet")
                result = self.run_smoke()
                self.assertIn(code, result["error_codes"])
                self.assertEqual(self.commands(), ["ping"])
                self.assertEqual(self.process.kill_count, 1)

    def test_negative_token_must_be_refused_before_any_scene_change(self):
        def accept_bad_token(command, token):
            if token != TOKEN:
                return reply({"ok": True})
        self.host.hook = accept_bad_token
        result = self.run_smoke()
        self.assertIn("AUTH_REFUSAL_INVALID", result["error_codes"])
        self.assertNotIn("theme", self.commands())

    def test_invalid_responses_are_not_readiness_retries(self):
        invalid = (
            smoke.Reply(200, b"not JSON"), smoke.Reply(200, b"[]"),
            smoke.Reply(200, b'{"ok":true,"ok":false}'),
            smoke.Reply(200, b'{"ok":true,"value":NaN}'),
            smoke.Reply(200, b"{}", "text/plain"),
            smoke.Reply(200, b"x" * (LIMITS.response_bytes + 1)),
        )
        for response in invalid:
            with self.subTest(response_size=len(response.body)):
                self.setUp()
                self.host.hook = lambda command, token: response
                result = self.run_smoke()
                self.assertIn("RESPONSE_INVALID", result["error_codes"])
                self.assertEqual(self.commands(), ["ping"])

    def test_readiness_has_a_finite_deadline_and_no_mutating_retry(self):
        self.host.booted = False
        result = self.run_smoke()
        self.assertIn("READINESS_TIMEOUT", result["error_codes"])
        self.assertLessEqual(len(self.commands()), 4)
        self.assertEqual(set(self.commands()), {"ping"})
        self.assertGreaterEqual(self.clock.now, LIMITS.ready)

    def test_initial_connection_refusal_can_wait_for_original_boot(self):
        pending = [True]

        def first_connection(command, token):
            if pending:
                pending.pop()
                raise ConnectionRefusedError()
        self.host.hook = first_connection
        self.assertTrue(self.run_smoke()["success"])
        self.assertEqual(self.clock.now, LIMITS.poll)

    def test_late_boot_reply_does_not_extend_original_readiness_budget(self):
        def late_boot(command, token):
            self.clock.now = LIMITS.ready
        self.host.hook = late_boot
        result = self.run_smoke()
        self.assertIn("READINESS_TIMEOUT", result["error_codes"])
        self.assertEqual(self.commands(), ["ping"])
        self.assertFalse(result["checks"]["identity"])

    def test_uncertain_theme_is_never_repeated_or_followed_by_another_command(self):
        def lost_reply(command, token):
            if command["cmd"] == "theme":
                self.host.theme = command["mode"]
                raise TimeoutError(TOKEN)
        self.host.hook = lost_reply
        result = self.run_smoke()
        self.assertIn("HTTP_FAILED", result["error_codes"])
        self.assertEqual(self.commands()[-1], "theme")
        self.assertEqual(self.commands().count("theme"), 1)
        self.assertEqual(self.process.kill_count, 1)

    def test_deadline_crossing_response_does_not_become_completion(self):
        def late_theme(command, token):
            if command["cmd"] == "theme":
                self.clock.now += LIMITS.total
        self.host.hook = late_theme
        result = self.run_smoke()
        self.assertIn("TOTAL_DEADLINE", result["error_codes"])
        self.assertNotIn("assert", self.commands())

    def test_claimed_theme_without_observed_brightness_is_refused(self):
        def wrong_brightness(command, token):
            if command["cmd"] == "theme":
                return self.host.response({**self.host.facts(), "mode": "dark", "brightness": "light"})
        self.host.hook = wrong_brightness
        result = self.run_smoke()
        self.assertIn("THEME_INVALID", result["error_codes"])
        self.assertNotIn("assert", self.commands())

    def test_hidden_selector_is_not_accepted_as_visible(self):
        def hidden(command, token):
            if command["cmd"] == "assert":
                return reply({"ok": False, "error": "presentation target is hidden"}, 400)
        self.host.hook = hidden
        result = self.run_smoke()
        self.assertFalse(result["checks"]["welcome_dark"])
        self.assertNotIn("presentation", self.commands())

    def test_wallet_owner_or_state_change_after_refusal_cannot_pass(self):
        changed = [False]

        def altered_state(command, token):
            if command["cmd"] in smoke.BLOCKED:
                changed[0] = True
            if command["cmd"] == "state" and changed[0]:
                return self.host.response({
                    **self.host.facts(), "booted": True, "walletUnlocked": False,
                    "walletInitCompleted": False, "tabs": [], "walletOwnerMounted": True,
                })
        self.host.hook = altered_state
        result = self.run_smoke()
        self.assertIn("STATE_INVALID", result["error_codes"])
        self.assertFalse(result["checks"]["refusals"])
        self.assertNotIn("quit", self.commands())

    def test_refused_type_that_changes_draft_is_detected_without_entering_text(self):
        def forbidden_effect(command, token):
            if command["cmd"] == "type":
                self.host.field = "unexpected input"
        self.host.hook = forbidden_effect
        result = self.run_smoke()
        self.assertIn("VISIBILITY_INVALID", result["error_codes"])
        self.assertFalse(result["checks"]["refusals"])
        self.assertNotIn("quit", self.commands())

    def test_allowed_forbidden_command_is_immediate_failure(self):
        def wrong_admission(command, token):
            if command["cmd"] == "shot":
                return self.host.response()
        self.host.hook = wrong_admission
        result = self.run_smoke()
        self.assertIn("REFUSAL_INVALID", result["error_codes"])
        self.assertEqual(self.commands()[-1], "shot")
        self.assertNotIn("quit", self.commands())

    def test_failed_close_receipt_never_proves_exit(self):
        def failed_close(command, token):
            if command["cmd"] == "quit":
                return self.host.response({"close": {
                    "status": "failed", "queued": False, "admitted": True,
                    "completed": False, "exitProved": False,
                }})
        self.host.hook = failed_close
        result = self.run_smoke()
        self.assertIn("CLOSE_FAILED", result["error_codes"])
        self.assertFalse(result["checks"]["close_ack"])
        self.assertEqual(self.commands().count("quit"), 1)
        self.assertEqual(self.process.kill_count, 1)

    def test_lost_close_ack_remains_failure_even_if_original_process_exits_zero(self):
        def lost_close(command, token):
            if command["cmd"] == "quit":
                self.process.close_requested = True
                raise TimeoutError("late close " + TOKEN)
        self.host.hook = lost_close
        result = self.run_smoke()
        self.assertIn("CLOSE_UNCERTAIN", result["error_codes"])
        self.assertEqual(result["exit_code"], 0)
        self.assertTrue(result["exit_observed"])
        self.assertFalse(result["success"])
        self.assertEqual(self.process.kill_count, 0)
        self.assertEqual(self.commands().count("quit"), 1)

    def test_queued_close_that_never_exits_is_failure_and_kills_only_original(self):
        self.process.can_close = False
        unrelated = OriginalProcess()
        result = self.run_smoke()
        self.assertIn("EXIT_TIMEOUT", result["error_codes"])
        self.assertTrue(result["forced_kill"])
        self.assertFalse(result["success"])
        self.assertEqual(self.process.kill_count, 1)
        self.assertEqual(unrelated.kill_count, 0)
        self.assertEqual(self.commands().count("quit"), 1)

    def test_nonzero_original_exit_is_not_a_successful_close(self):
        self.process.close_exit = 7
        result = self.run_smoke()
        self.assertIn("EXIT_FAILED", result["error_codes"])
        self.assertEqual(result["exit_code"], 7)
        self.assertEqual(self.process.kill_count, 0)

    def test_cleanup_failure_output_overflow_and_incomplete_output_always_fail(self):
        for fault, code in (("kill", "CLEANUP_FAILED"), ("overflow", "OUTPUT_OVERFLOW"),
                            ("incomplete", "OUTPUT_INCOMPLETE")):
            with self.subTest(fault=fault):
                self.setUp()
                if fault == "kill":
                    self.host.mode = "wallet"
                    self.process.kill_error = OSError(TOKEN)
                elif fault == "overflow":
                    self.drain.overflow_on_finish = True
                else:
                    self.drain.complete = False
                result = self.run_smoke()
                self.assertIn(code, result["error_codes"])
                self.assertFalse(result["success"])

    def test_public_summary_does_not_expose_exception_response_token_or_pid(self):
        def private_error(command, token):
            raise RuntimeError(TOKEN + " private-location " + str(self.process.pid))
        self.host.hook = private_error
        result = self.run_smoke()
        text = json.dumps(result)
        for private in (TOKEN, "private-location", str(self.process.pid), "stack", "target"):
            self.assertNotIn(private, text)
        self.assertEqual(set(result), {
            "schema", "source_sha", "runner_sha256", "dart_kernel_sha256", "checks", "exit_code",
            "exit_observed", "forced_kill", "output_complete", "output_overflow",
            "complete", "success", "error_codes",
        })
        self.assertTrue(set(result["error_codes"]).issubset(smoke.CODES))


class AdmissionTests(unittest.TestCase):
    def test_ci_source_default_and_mixed_case_systemroot_are_admitted(self):
        parent = {
            "GITHUB_ACTIONS": "true", "GITHUB_SHA": SOURCE,
            "RUNNER_OS": "Windows", "RUNNER_ENVIRONMENT": "github-hosted",
            "GITHUB_WORKSPACE": "checkout", "SystemRoot": r"C:\Windows",
        }
        normalized, expected = smoke.require_ci(parent, None, platform="nt")
        self.assertEqual(expected, SOURCE)
        self.assertEqual(normalized["SYSTEMROOT"], r"C:\Windows")
        self.assertNotIn("SystemRoot", normalized)
        with self.assertRaises(smoke.SmokeFailure):
            smoke.require_ci(parent, "4" * 40, platform="nt")
        with self.assertRaises(smoke.SmokeFailure):
            smoke.require_ci({**parent, "RUNNER_ENVIRONMENT": "self-hosted"}, None, platform="nt")

    def test_case_conflicting_environment_is_not_arbitrarily_adopted(self):
        with self.assertRaises(smoke.SmokeFailure) as failure:
            smoke.require_ci({"SystemRoot": "one", "SYSTEMROOT": "two"}, SOURCE, platform="nt")
        self.assertEqual(failure.exception.code, "ENVIRONMENT_REFUSED")

    def test_profile_and_control_environment_are_replaced_case_insensitively(self):
        parent = {key.lower(): "inherited-private-value" for key in smoke.REPLACED}
        parent.update({
            "sYrIuS_hArNeSs_ToKeN": "old-token", "syrius_harness_other": "unsafe",
            "GITHUB_TOKEN": "private-ci-token", "HTTP_PROXY": "unsafe-proxy",
            "Path": "runtime-path", "SystemRoot": r"C:\Windows",
        })
        original = dict(parent)
        profile = PureWindowsPath(r"D:\workspace\.harness\ci-presentation-smoke-new")
        env = smoke.child_environment(parent, profile, 32123, TOKEN)
        self.assertEqual(parent, original)
        self.assertEqual(env["SYRIUS_HARNESS_TOKEN"], TOKEN)
        self.assertEqual(env["SYRIUS_HARNESS_PRESENTATION"], "welcome")
        self.assertEqual(env["APPDATA"], str(profile / "AppData" / "Roaming"))
        self.assertEqual(env["HOME"], str(profile))
        self.assertEqual(env["PATH"], "runtime-path")
        self.assertNotIn("inherited-private-value", env.values())
        self.assertNotIn("GITHUB_TOKEN", env)
        self.assertNotIn("HTTP_PROXY", env)
        self.assertNotIn("SYRIUS_HARNESS_OTHER", env)

    def test_branch_and_detached_layouts_use_the_same_fixed_head_query(self):
        for head in (SOURCE + "\n", "ref: refs/heads/redesign\n"):
            with self.subTest(head_kind="branch" if head.startswith("ref:") else "detached"):
                with tempfile.TemporaryDirectory() as temporary:
                    repo = Path(temporary)
                    (repo / ".git").mkdir()
                    (repo / ".git" / "HEAD").write_text(head, encoding="ascii")
                    calls = []

                    def query(arguments, **kwargs):
                        calls.append((arguments, kwargs))
                        return 0, (SOURCE + "\n").encode()

                    smoke.verify_source(repo, SOURCE, {"GIT_DIR": "refuse-inheritance"}, run=query)
                    self.assertEqual(calls[0][0], ["git", "-C", str(repo), "rev-parse", "HEAD"])
                    self.assertNotIn("GIT_DIR", calls[0][1]["env"])
                    self.assertEqual(calls[0][1]["cap"], 128)

    def test_wrong_source_is_refused_without_using_environment_as_proof(self):
        with self.assertRaises(smoke.SmokeFailure) as failure:
            smoke.verify_source(Path("checkout"), SOURCE, {}, run=lambda *args, **kwargs: (0, b"3" * 40 + b"\n"))
        self.assertEqual(failure.exception.code, "SOURCE_REFUSED")

    def test_preflight_refuses_existing_process_and_uncertain_helper(self):
        parent = {"SYSTEMROOT": "system-root"}
        for code, expected in ((23, "EXISTING_PROCESS"), (7, "PREFLIGHT_FAILED")):
            with self.subTest(code=code), self.assertRaises(smoke.SmokeFailure) as failure:
                smoke.check_no_existing(
                    Path("checkout"), parent, run=lambda *args, **kwargs: (code, b""),
                )
            self.assertEqual(failure.exception.code, expected)

    def test_helper_timeout_terminates_only_the_original_helper(self):
        original = OriginalProcess()
        unrelated = OriginalProcess()
        with patch.object(smoke.subprocess, "Popen", return_value=original), \
                self.assertRaises(smoke.SmokeFailure) as failure:
            smoke.fixed_command(["fixed-helper"], cwd=Path("checkout"), env={})
        self.assertEqual(failure.exception.code, "PREFLIGHT_TIMEOUT")
        self.assertEqual(original.kill_count, 1)
        self.assertEqual(unrelated.kill_count, 0)
        self.assertEqual(original.waits, [5, 5])

    def test_process_preflight_allows_a_bounded_slow_native_helper(self):
        original = OriginalProcess()

        def wait(timeout):
            original.waits.append(timeout)
            if timeout < 6:
                raise subprocess.TimeoutExpired(TOKEN, timeout)
            original.returncode = 0
            return 0

        original.wait = wait
        parent = {"SYSTEMROOT": "system-root", "GITHUB_TOKEN": TOKEN,
                  "PYTHONPATH": "untrusted-module-path"}
        with patch.object(smoke.subprocess, "Popen", return_value=original) as launch:
            smoke.check_no_existing(Path("checkout"), parent)
        self.assertEqual(original.waits, [15])
        self.assertEqual(original.kill_count, 0)
        self.assertEqual(launch.call_args.args[0], [sys.executable, '-I', '-S', '-B',
            str(CONTROLLER.with_name('windows_process_preflight.py'))])
        self.assertEqual(launch.call_args.kwargs['env'], {'SYSTEMROOT': 'system-root'})
        self.assertFalse(launch.call_args.kwargs["shell"])
        self.assertEqual(launch.call_args.kwargs["stdout"], subprocess.DEVNULL)
        self.assertEqual(launch.call_args.kwargs["stderr"], subprocess.DEVNULL)

    def test_process_preflight_timeout_keeps_the_original_helper_and_deadline(self):
        original = OriginalProcess()
        unrelated = OriginalProcess()
        with patch.object(smoke.subprocess, "Popen", return_value=original), \
                self.assertRaises(smoke.SmokeFailure) as failure:
            smoke.check_no_existing(Path("checkout"), {"SYSTEMROOT": "system-root"})
        self.assertEqual(failure.exception.code, "PREFLIGHT_TIMEOUT")
        self.assertEqual(original.waits, [15, 5])
        self.assertEqual(original.kill_count, 1)
        self.assertEqual(unrelated.kill_count, 0)

    def test_helper_output_overflow_is_distinct_from_a_timeout(self):
        original = OriginalProcess()
        original.close_requested = True
        original.stdout = io.BytesIO(TOKEN.encode())
        with patch.object(smoke.subprocess, "Popen", return_value=original), \
                self.assertRaises(smoke.SmokeFailure) as failure:
            smoke.fixed_command(["fixed-helper"], cwd=Path("checkout"), env={}, cap=2)
        self.assertEqual(failure.exception.code, "PREFLIGHT_OUTPUT_REFUSED")
        self.assertEqual(original.kill_count, 0)
        self.assertEqual(original.waits, [5, 5])

    def test_incomplete_helper_output_requires_a_positive_final_drain(self):
        original = OriginalProcess()
        original.close_requested = True
        original.stdout = io.BytesIO()
        drain = Drain()
        for final, expected in ((True, "PREFLIGHT_OUTPUT_REFUSED"), (False, "CLEANUP_FAILED")):
            with self.subTest(final_drain=final), \
                    patch.object(smoke.subprocess, "Popen", return_value=original), \
                    patch.object(smoke, "OutputDrain", return_value=drain), \
                    patch.object(drain, "finish", side_effect=[False, final]), \
                    self.assertRaises(smoke.SmokeFailure) as failure:
                smoke.fixed_command(["fixed-helper"], cwd=Path("checkout"), env={}, cap=2)
            self.assertEqual(failure.exception.code, expected)
        self.assertEqual(original.kill_count, 0)

    def test_uncertain_helper_cleanup_overrides_timeout_without_exposing_detail(self):
        original = OriginalProcess()
        original.kill_error = RuntimeError(TOKEN)
        with patch.object(smoke.subprocess, "Popen", return_value=original), \
                self.assertRaises(smoke.SmokeFailure) as failure:
            smoke.fixed_command(["fixed-helper"], cwd=Path("checkout"), env={})
        self.assertEqual(failure.exception.code, "CLEANUP_FAILED")
        report = smoke.Report()
        report.fail(failure.exception.code, original.kill_error)
        public = json.dumps(report.public())
        self.assertNotIn(TOKEN, public)
        self.assertEqual(report.public()["error_codes"], ["CLEANUP_FAILED"])

    def test_selected_runner_and_debug_kernel_have_separate_hashes(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            runner = repo / smoke.BINARY
            kernel = repo / smoke.KERNEL
            runner.parent.mkdir(parents=True)
            runner.write_bytes(b"abc")
            with self.assertRaises(FileNotFoundError):
                smoke.binary_hash(repo, smoke.KERNEL)
            kernel.parent.mkdir(parents=True)
            kernel.write_bytes(b"")
            with self.assertRaises(smoke.SmokeFailure) as failure:
                smoke.binary_hash(repo, smoke.KERNEL)
            self.assertEqual(failure.exception.code, "BINARY_REFUSED")
            kernel.write_bytes(b"hello")
            self.assertEqual(smoke.binary_hash(repo)[1],
                             "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
            self.assertEqual(smoke.binary_hash(repo, smoke.KERNEL)[1],
                             "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

    def test_existing_profile_is_refused_and_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / ".harness").mkdir()
            existing = root / ".harness" / ("ci-presentation-smoke-" + "a" * 24)
            existing.mkdir()
            marker = existing / "retained"
            marker.write_text("original", encoding="ascii")
            with patch.object(smoke.secrets, "token_hex", return_value="a" * 24):
                with self.assertRaises(FileExistsError):
                    smoke.new_profile(root)
            self.assertEqual(marker.read_text(encoding="ascii"), "original")

    def test_output_drain_retains_cap_and_drains_the_original_pipe_to_eof(self):
        pipe = io.BytesIO(b"a" * 100)
        drain = smoke.OutputDrain(pipe, 16, retain=True)
        self.assertTrue(drain.finish(1))
        self.assertTrue(drain.overflow.is_set())
        self.assertEqual(drain.count, 100)
        self.assertEqual(bytes(drain.data), b"a" * 16)

    def test_main_refuses_missing_ci_before_any_process_or_network_effect(self):
        with patch.dict(smoke.os.environ, {}, clear=True), \
                patch.object(smoke.subprocess, "Popen") as launch, \
                patch.object(smoke.socket, "socket") as connect, \
                patch("sys.stdout", new_callable=io.StringIO) as output:
            code = smoke.main(["--source-sha", SOURCE])
        self.assertEqual(code, 1)
        result = json.loads(output.getvalue())
        self.assertEqual(result["error_codes"], ["ENVIRONMENT_REFUSED"])
        launch.assert_not_called()
        connect.assert_not_called()

    def test_main_default_source_and_preexisting_refusal_stop_before_profile_or_launch(self):
        parent = {"GITHUB_WORKSPACE": str(Path.cwd()), "SYSTEMROOT": "system-root"}
        selected = Path.cwd() / smoke.BINARY
        with patch.object(smoke, "require_ci", return_value=(parent, SOURCE)) as admission, \
                patch.object(smoke, "verify_source"), \
                patch.object(smoke, "binary_hash", return_value=(selected, BINARY_HASH, (1, 2, 3, 4))), \
                patch.object(smoke, "check_no_existing", side_effect=smoke.SmokeFailure("EXISTING_PROCESS")), \
                patch.object(smoke, "new_profile") as profile, \
                patch.object(smoke.subprocess, "Popen") as launch, \
                patch("sys.stdout", new_callable=io.StringIO) as output:
            code = smoke.main([])
        self.assertIsNone(admission.call_args[0][1])
        self.assertEqual(code, 1)
        self.assertEqual(json.loads(output.getvalue())["error_codes"], ["EXISTING_PROCESS"])
        profile.assert_not_called()
        launch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
