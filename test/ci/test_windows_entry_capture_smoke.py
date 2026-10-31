"""Finite fake-process/parser cases. No Windows, HTTP or wallet is executed."""

import base64
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path, PureWindowsPath
import re
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
import zlib

CONTROLLER = Path(__file__).resolve().parents[2] / "tool/ci/windows_entry_capture_smoke.py"
SPEC = importlib.util.spec_from_file_location("windows_entry_capture_smoke", CONTROLLER)
smoke = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = smoke
sys.path.insert(0, str(CONTROLLER.parent))
try:
    SPEC.loader.exec_module(smoke)
finally:
    sys.path.pop(0)

SOURCE, TREE = "1" * 40, "2" * 40
TOKEN = "private-original-entry-test-token"
LIMITS = smoke.bounded.Limits(total=10, ready=.3, request=.2, poll=.1,
                              exit=.2, cleanup=.2, drain=.1,
                              response_bytes=smoke.LIMITS.response_bytes)


def chunk(kind, payload):
    return (struct.pack(">I", len(payload)) + kind + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))


HEADER = struct.pack(">IIBBBBB", 1280, 780, 8, 6, 0, 0, 0)
PIXELS = (b"\0" + bytes(1280 * 4)) * 780
PNG = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", HEADER)
       + chunk(b"IDAT", zlib.compress(PIXELS)) + chunk(b"IEND", b""))
ENCODED = base64.b64encode(PNG).decode("ascii")


def color_png(colors):
    if colors == 6:
        return PNG
    header = struct.pack(">IIBBBBB", 1280, 780, 8, 2, 0, 0, 0)
    pixels = (b"\0" + bytes(1280 * 3)) * 780
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))


def reply(body, status=200):
    return smoke.bounded.Reply(status, json.dumps(body).encode())


def capture_reply(screen="welcome", theme="dark"):
    return {"ok": True, "screen": screen, "theme": theme, "width": 1280,
            "height": 780, "scale": 1, "client": [1280, 780],
            "physical": [1920, 1170], "devicePixelRatio": 1.5, "png": ENCODED,
            "harnessMode": "wallet", "captureMode": "entry", "restorationVerified": True,
            "referenceArtwork": ([dict(kind='welcome_globe', frame=720, frame_count=1800)]
                                 if screen == 'welcome' else []) +
                                [dict(kind='entry_field', seconds=6)]}


def resize_detail(**changes):
    result = {"requestedClient": [1280, 780], "client": [1264, 741],
              "physical": [1896, 1111.5], "devicePixelRatio": 1.5,
              "outer": [1280, 780], "resizeAttempts": 5, "clientMatched": False}
    result.update(changes)
    return result


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now

    def sleep(self, duration):
        self.now += duration


class OriginalProcess:
    def __init__(self):
        self.pid = 4141
        self.returncode = None
        self.close_requested = False
        self.can_close = True
        self.close_exit = 0
        self.kill_count = 0
        self.kill_error = None
        self.waits = []

    def poll(self):
        return self.returncode

    def wait(self, timeout):
        self.waits.append(timeout)
        if self.returncode is None:
            if self.close_requested and self.can_close:
                self.returncode = self.close_exit
            else:
                raise subprocess.TimeoutExpired("original-process", timeout)
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
        self.count = 73
        self.complete = True
        self.overflow_on_finish = False

    def finish(self, timeout):
        if self.overflow_on_finish:
            self.overflow.set()
        return self.complete


class Artifacts:
    def __init__(self):
        self.records = []
        self.writes = {}

    def png(self, name, data):
        if name in self.writes:
            raise AssertionError("duplicate artifact")
        self.writes[name] = data
        self.records.append({"file": name, "bytes": len(data),
                             "sha256": hashlib.sha256(data).hexdigest()})


class Host:
    def __init__(self, process):
        self.process = process
        self.calls = []
        self.hook = None
        self.booted = self.entry_ready = True
        self.held = False
        self.pid = process.pid
        self.mode = "wallet"
        self.captures = 0
        self.caption_stage = self.caption_observations = 0
        self.caption_baseline = None
        self.minimized = self.maximized = False
        self.window = [17, 23, 1240, 850]
        self.client = [1224, 811]
        self.original_window = self.snapshot()

    def snapshot(self):
        return {"window": list(self.window), "client": list(self.client),
                "physical": list(self.client), "devicePixelRatio": 1,
                "minimized": self.minimized, "maximized": self.maximized}

    def entry(self):
        return {"ok": True, "available": True, "nativeWindowReady": self.entry_ready,
                "startupReady": self.entry_ready, "welcomeReady": self.entry_ready,
                "held": self.held, "captures": self.captures}

    def caption_state(self):
        native = ({"minimized": self.minimized, "maximized": self.maximized}
                  if self.caption_stage in (1, 3) else self.snapshot())
        return {"ok": True, "captionVersion": 1, "stage": self.caption_stage,
                "observations": self.caption_observations, "original": True,
                "held": False, "pending": False, "settled": True, "window": native}

    def exchange(self, command, token, timeout):
        self.calls.append((copy.deepcopy(command), token, timeout))
        if self.hook:
            override = self.hook(command, token)
            if override is not None:
                return override
        if token != TOKEN:
            return reply({"ok": False, "error": "bad token"}, 400)
        name = command["cmd"]
        if name == "ping":
            return reply({"ok": True, "pid": self.pid, "booted": self.booted,
                          "harnessMode": self.mode})
        if name == "entry-state":
            return reply(self.entry())
        if name == "entry-caption":
            action = command["do"]
            if set(command) != {"cmd", "do"} or self.captures != 4:
                raise AssertionError("unexpected caption input")
            if action == "bind":
                self.caption_baseline = copy.deepcopy(self.snapshot())
                return reply(self.caption_state())
            if action == "observe":
                self.caption_observations = self.caption_stage
                return reply(self.caption_state())
            stage = {"maximize": 1, "restore": 2, "minimize": 3}[action]
            if self.caption_stage != stage - 1 or self.caption_observations != stage - 1:
                raise AssertionError("caption replay")
            self.caption_stage = stage
            self.maximized, self.minimized = stage == 1, stage == 3
            return reply({"ok": True, "captionVersion": 1, "stage": stage,
                          "admitted": True, "pendingObserved": True})
        if name == "window":
            extra = {}
            if "restoreState" in command:
                original = command["restoreState"]
                self.window, self.client = original["window"], original["client"]
                self.minimized, self.maximized = original["minimized"], original["maximized"]
                extra["restored"] = True
            elif command.get("do") == "show":
                self.window, self.client = [17, 23, 1296, 819], [1280, 780]
                extra["clientMatched"] = True
            elif command.get("do") == "restore":
                if self.caption_stage != 3 or self.caption_observations != 3:
                    raise AssertionError("restore before original minimize completion")
                self.caption_stage = 4
                self.minimized = self.maximized = False
            return reply({"ok": True, **self.snapshot(), **extra})
        if name == "entry-capture":
            if set(command) != {"cmd", "screen", "theme"}:
                raise AssertionError("unexpected capture keys")
            self.captures += 1
            return reply(capture_reply(command["screen"], command["theme"]))
        if name == "entry-check":
            return reply({**self.entry(), "frameReady": True, "restorationVerified": True})
        if name == "quit":
            self.process.close_requested = True
            return reply({"ok": True})
        raise AssertionError("unexpected command")


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.clock, self.process = Clock(), OriginalProcess()
        self.host = Host(self.process)
        self.drain, self.artifacts, self.report = Drain(), Artifacts(), smoke.Report()
        self.report.source_sha, self.report.source_tree = SOURCE, TREE
        self.report.run_id, self.report.run_attempt = "4001", "2"
        self.report.runner_sha256, self.report.dart_kernel_sha256 = "3" * 64, "4" * 64
        for name in ("environment", "source", "profile", "preflight", "payload_stable"):
            self.report.checks[name] = True

    def run_smoke(self):
        return smoke.EntrySmoke(self.process, self.host, TOKEN, self.drain, self.report,
                                artifacts=self.artifacts, limits=LIMITS,
                                clock=self.clock, sleep=self.clock.sleep).run()

    def commands(self, name=None):
        return [command for command, _, _ in self.host.calls
                if name is None or command["cmd"] == name]

    def test_caption_bind_retains_fixed_first_refusal_without_replaying_actions(self):
        for code in sorted(smoke.CAPTION_REFUSALS):
            with self.subTest(code=code):
                self.setUp()
                self.host.hook = lambda command, token: reply({
                    "ok": False, "error": code, "stack": TOKEN,
                }, 400) if command["cmd"] == "entry-caption" else None
                result = self.run_smoke()
                self.assertEqual(result["first_command_failure"], {
                    "phase": "caption_bind", "code": code, "http_status": 400,
                    "category": "REMOTE_ERROR", "resize": None})
                self.assertEqual(self.commands("entry-caption"), [
                    {"cmd": "entry-caption", "do": "bind"}])
                self.assertFalse(result["success"])
                self.assertFalse(result["checks"]["window_restored"])
                self.assertEqual(result["exit_code"], 0)
                self.assertNotIn(TOKEN, json.dumps(result))

    def test_unknown_caption_errors_cannot_enter_public_failure_codes(self):
        for error in (TOKEN, {"private": TOKEN}, [TOKEN], None):
            with self.subTest(error=error):
                self.setUp()
                self.host.hook = lambda command, token: reply({
                    "ok": False, "error": error, "stack": TOKEN,
                }, 400) if command["cmd"] == "entry-caption" else None
                result = self.run_smoke()
                self.assertEqual(result["first_command_failure"]["code"], "COMMAND_FAILED")
                self.assertNotIn(TOKEN, json.dumps(result))

    def test_caption_refusal_code_is_not_accepted_outside_caption_phases(self):
        self.host.hook = lambda command, token: reply({
            "ok": False, "error": "CAPTION_TREE_REFUSED",
        }, 400) if command["cmd"] == "entry-capture" else None
        result = self.run_smoke()
        self.assertEqual(result["first_command_failure"]["phase"], "capture_welcome_dark")
        self.assertEqual(result["first_command_failure"]["code"], "COMMAND_FAILED")

    def test_measured_slow_original_png_has_its_own_budget_without_capture_retry(self):
        original = self.host.exchange
        def exchange(command, token, timeout):
            if command["cmd"] == "entry-capture":
                elapsed = 21.451 if (command["screen"], command["theme"]) == ("welcome", "dark") else .01
                self.clock.sleep(min(elapsed, timeout))
                if elapsed >= timeout:
                    self.host.calls.append((copy.deepcopy(command), token, timeout))
                    raise TimeoutError("private-original-encoding")
            return original(command, token, timeout)
        self.host.exchange = exchange
        session = smoke.EntrySmoke(self.process, self.host, TOKEN, self.drain, self.report,
            artifacts=self.artifacts, limits=smoke.LIMITS,
            clock=self.clock, sleep=self.clock.sleep)
        result = session.run()
        self.assertTrue(result["success"])
        self.assertEqual(result["capture_count"], 4)
        self.assertEqual(self.commands("entry-capture"), [
            dict(cmd="entry-capture", screen=screen, theme=theme)
            for screen, theme in smoke.SCENES])
        self.assertTrue(all(timeout == 30 for command, _, timeout in self.host.calls
                            if command["cmd"] == "entry-capture"))
        self.assertTrue(all(timeout <= 20 for command, _, timeout in self.host.calls
                            if command["cmd"] != "entry-capture"))
        self.assertIs(session.limits, smoke.LIMITS)
        self.assertEqual((session.limits.total, session.limits.ready,
                          session.limits.request), (150, 45, 20))
        self.assertEqual(self.process.kill_count, 0)
        self.assertNotIn("private-original-encoding", json.dumps(result))

    def test_capture_budget_keeps_original_total_control_bounds_and_timeout_uncertainty(self):
        cases = (
            (dict(cmd="entry-capture", screen="welcome", theme="dark"),
             "capture_welcome_dark", 30.001, 0, 30),
            (dict(cmd="entry-state"), "entry_state", 20.001, 0, 20),
            (dict(cmd="entry-capture", screen="welcome", theme="dark"),
             "capture_welcome_dark", .75, 149.5, .5),
            (dict(cmd="ping"), "capture_welcome_dark", 20.001, 0, 20),
        )
        for command, phase, elapsed, start, cap in cases:
            with self.subTest(phase=phase, start=start):
                self.setUp()
                clock = self.clock
                class Delayed:
                    calls = []
                    def exchange(self, payload, token, timeout):
                        self.calls.append((copy.deepcopy(payload), timeout))
                        clock.sleep(min(elapsed, timeout))
                        if elapsed >= timeout:
                            raise TimeoutError("private-pending-image")
                        return reply({"ok": True})
                transport = Delayed()
                session = smoke.EntrySmoke(self.process, transport, TOKEN,
                    self.drain, self.report, artifacts=self.artifacts,
                    limits=smoke.LIMITS, clock=clock, sleep=clock.sleep)
                clock.now = start
                with self.assertRaises(smoke.bounded.SmokeFailure) as failure:
                    session._positive(command, phase=phase)
                self.assertEqual(failure.exception.code, "HTTP_FAILED")
                self.assertEqual(len(transport.calls), 1)
                self.assertLessEqual(transport.calls[0][1], cap)
                self.assertEqual(self.report.transport_failure,
                                 dict(phase=phase, kind="TIMEOUT"))
                self.assertIs(session.limits, smoke.LIMITS)
                self.assertEqual(session.limits.request, 20)
                self.assertEqual(self.artifacts.records, [])
                public = self.report.public()
                self.assertFalse(public["success"])
                self.assertEqual(public["status"], "UNKNOWN")
                self.assertNotIn("private-pending-image", json.dumps(public))

    def test_four_actual_byte_artifacts_outer_restore_then_original_zero_exit(self):
        result = self.run_smoke()
        self.assertTrue(result["success"])
        self.assertEqual(result["status"], "SUCCESS")
        self.assertEqual(result["schema"], 2)
        self.assertIsNone(result["first_command_failure"])
        self.assertEqual(result["cleanup_failures"], [])
        self.assertEqual(tuple(self.artifacts.writes), smoke.FILES)
        self.assertEqual([command for command in self.commands("entry-capture")], [
            {"cmd": "entry-capture", "screen": screen, "theme": theme}
            for screen, theme in smoke.SCENES])
        self.assertEqual(self.commands()[-3:][0]["restoreState"], self.host.original_window)
        self.assertEqual([item["cmd"] for item in self.commands()[-3:]],
                         ["window", "entry-check", "quit"])
        self.assertEqual(result["capture_count"], 4)
        self.assertEqual(result["exit_code"], 0)
        self.assertTrue(result["output_complete"])
        self.assertEqual(self.process.kill_count, 0)
        self.assertTrue(all(0 < timeout <= LIMITS.request for _, _, timeout in self.host.calls))

    def test_caption_extension_preserves_all_eighteen_checks_and_one_quit(self):
        self.assertEqual(smoke.CHECKS, (
            "environment", "source", "profile", "preflight", "identity", "auth",
            "entry_ready", "window_saved", "client_matched", "welcome_dark",
            "welcome_light", "import_dark", "import_light", "window_restored",
            "entry_restored", "close_ack", "exit", "payload_stable"))
        result = self.run_smoke()
        self.assertTrue(result["success"])
        self.assertTrue(all(result["checks"].values()))
        self.assertEqual(result["caption"], {"schema": 1, "observations": {
            name: True for name in smoke.CAPTION_CHECKS}})
        actions = [c["do"] for c in self.commands("entry-caption")]
        self.assertEqual(actions, ["bind", "maximize", "observe", "restore",
                                   "observe", "minimize", "observe", "observe"])
        self.assertEqual(len([c for c in self.commands("window")
                              if c.get("do") == "restore"]), 1)
        self.assertEqual(len(self.commands("quit")), 1)
        self.assertTrue(result["exit_observed"])
        self.assertEqual(result["exit_code"], 0)

    def test_old_check_pass_cannot_qualify_without_every_caption_observation(self):
        self.assertTrue(self.run_smoke()["success"])
        for name in smoke.CAPTION_CHECKS:
            with self.subTest(name=name):
                self.report.caption_checks[name] = False
                result = self.report.public()
                self.assertTrue(all(result["checks"].values()))
                self.assertFalse(result["complete"])
                self.assertEqual(result["status"], "UNKNOWN")
                self.report.caption_checks[name] = True

    def assert_caption_hold_cleanup(self, result):
        self.assertFalse(result["success"])
        self.assertEqual(result["capture_count"], 4)
        self.assertEqual(len(self.commands("quit")), 1)
        self.assertEqual(result["exit_code"], 0)
        self.assertFalse([c for c in self.commands("window") if "restoreState" in c])
        self.assertFalse(self.commands("entry-check"))
        self.assertFalse(result["checks"]["window_restored"])

    def test_pending_caption_polls_are_finite_and_never_replay_the_action(self):
        def pending(command, token):
            if command == {"cmd": "entry-caption", "do": "observe"}:
                return reply({**self.host.caption_state(), "settled": False,
                              "pending": True, "window": None})
        self.host.hook = pending
        result = self.run_smoke()
        self.assert_caption_hold_cleanup(result)
        self.assertIn("CAPTION_TIMEOUT", result["error_codes"])
        self.assertEqual(len([c for c in self.commands("entry-caption")
                              if c["do"] == "maximize"]), 1)
        self.assertLessEqual(len([c for c in self.commands("entry-caption")
                                  if c["do"] == "observe"]), 4)
        self.assertFalse([c for c in self.commands("window") if c.get("do") == "restore"])

    def test_lost_caption_tap_response_retains_images_and_forbids_geometry_cleanup(self):
        def lost(command, token):
            if command == {"cmd": "entry-caption", "do": "maximize"}:
                self.host.maximized = True
                raise TimeoutError(TOKEN + " original caption reply lost")
        self.host.hook = lost
        result = self.run_smoke()
        self.assert_caption_hold_cleanup(result)
        self.assertEqual([c["do"] for c in self.commands("entry-caption")],
                         ["bind", "maximize"])
        self.assertNotIn(TOKEN, json.dumps(result))
        self.assertEqual(self.process.kill_count, 0)

    def test_ack_without_immediate_original_pending_is_not_completion(self):
        self.host.hook = lambda c, t: reply({
            "ok": True, "captionVersion": 1, "stage": 1,
            "admitted": True, "pendingObserved": False,
        }) if c == {"cmd": "entry-caption", "do": "maximize"} else None
        result = self.run_smoke()
        self.assert_caption_hold_cleanup(result)
        self.assertIn("CAPTION_INVALID", result["error_codes"])
        self.assertFalse([c for c in self.commands("entry-caption") if c["do"] == "observe"])

    def test_caption_owner_replacement_or_hold_never_authorizes_another_action(self):
        for field, value in (("original", False), ("held", True)):
            with self.subTest(field=field):
                self.setUp()
                self.host.hook = lambda c, t: reply({
                    **self.host.caption_state(), "settled": False, field: value,
                }) if c == {"cmd": "entry-caption", "do": "observe"} else None
                result = self.run_smoke()
                self.assert_caption_hold_cleanup(result)
                self.assertIn("CAPTION_HELD", result["error_codes"])

    def test_duplicate_disabled_or_missing_pending_refusal_is_not_retried(self):
        for error in ("caption-control-changed", "caption-control-refused",
                      "caption-pending-unobserved"):
            with self.subTest(error=error):
                self.setUp()
                self.host.hook = lambda c, t: reply({"ok": False, "error": error}, 400) \
                    if c == {"cmd": "entry-caption", "do": "maximize"} else None
                result = self.run_smoke()
                self.assert_caption_hold_cleanup(result)
                self.assertEqual(len([c for c in self.commands("entry-caption")
                                      if c["do"] == "maximize"]), 1)

    def test_caption_settled_ack_cannot_substitute_for_native_mode(self):
        def wrong(command, token):
            if command == {"cmd": "entry-caption", "do": "observe"}:
                return reply({**self.host.caption_state(), "observations": 1,
                              "window": {"minimized": False, "maximized": False}})
        self.host.hook = wrong
        result = self.run_smoke()
        self.assert_caption_hold_cleanup(result)
        self.assertIn("CAPTION_NATIVE_MISMATCH", result["error_codes"])

    def test_caption_restore_requires_original_baseline_geometry(self):
        def wrong(command, token):
            if command == {"cmd": "entry-caption", "do": "observe"} and self.host.caption_stage == 2:
                window = self.host.snapshot()
                window["window"][0] += 1
                return reply({**self.host.caption_state(), "observations": 2, "window": window})
        self.host.hook = wrong
        result = self.run_smoke()
        self.assert_caption_hold_cleanup(result)
        self.assertTrue(result["caption"]["observations"]["maximized"])
        self.assertFalse(result["caption"]["observations"]["caption_restored"])

    def test_lost_ordinary_restore_response_preserves_three_prior_observations(self):
        def lost(command, token):
            if command == {"cmd": "window", "do": "restore"}:
                self.host.minimized = False
                raise TimeoutError("original restore reply lost")
        self.host.hook = lost
        result = self.run_smoke()
        self.assert_caption_hold_cleanup(result)
        self.assertEqual(result["caption"]["observations"], {
            "maximized": True, "caption_restored": True,
            "minimized": True, "native_restored": False})
        self.assertEqual(len([c for c in self.commands("window")
                              if c.get("do") == "restore"]), 1)

    def test_late_caption_response_does_not_reset_absolute_budget(self):
        def late(command, token):
            if command == {"cmd": "entry-caption", "do": "observe"}:
                self.clock.now += LIMITS.total + 1
                return reply(self.host.caption_state())
        self.host.hook = late
        result = self.run_smoke()
        self.assertFalse(result["success"])
        self.assertFalse(any(result["caption"]["observations"].values()))
        self.assertEqual(len([c for c in self.commands("entry-caption")
                              if c["do"] == "maximize"]), 1)
        self.assertFalse([c for c in self.commands("window") if "restoreState" in c])

    def test_native_restore_observation_cannot_adopt_wrong_mode(self):
        def wrong(command, token):
            if command == {"cmd": "entry-caption", "do": "observe"} and self.host.caption_stage == 4:
                return reply({**self.host.caption_state(), "observations": 4,
                              "window": {**self.host.snapshot(), "minimized": True}})
        self.host.hook = wrong
        result = self.run_smoke()
        self.assert_caption_hold_cleanup(result)
        self.assertFalse(result["caption"]["observations"]["native_restored"])

    def test_caption_projection_contains_only_fixed_boolean_observations(self):
        self.assertTrue(self.run_smoke()["success"])
        self.report.caption_checks[TOKEN] = TOKEN
        self.report.caption_checks["maximized"] = TOKEN
        result = self.report.public()
        self.assertEqual(set(result["caption"]), {"schema", "observations"})
        self.assertEqual(set(result["caption"]["observations"]), set(smoke.CAPTION_CHECKS))
        self.assertIs(result["caption"]["observations"]["maximized"], False)
        self.assertNotIn(TOKEN, json.dumps(result))
        self.assertFalse(result["success"])

    def test_original_identity_or_mode_failure_never_changes_a_window(self):
        for field, value, code in (("pid", 9191, "IDENTITY_REFUSED"),
                                   ("mode", "presentation", "MODE_REFUSED")):
            with self.subTest(field=field):
                self.setUp()
                setattr(self.host, field, value)
                result = self.run_smoke()
                self.assertIn(code, result["error_codes"])
                self.assertEqual(self.commands(), [{"cmd": "ping"}])
                self.assertEqual(self.process.kill_count, 1)

    def test_booted_is_not_positive_native_startup_evidence(self):
        self.host.entry_ready = False
        result = self.run_smoke()
        self.assertIn("READINESS_TIMEOUT", result["error_codes"])
        self.assertTrue(result["checks"]["identity"])
        self.assertFalse(result["checks"]["entry_ready"])
        self.assertFalse(self.commands("window"))
        self.assertLessEqual(len(self.commands("entry-state")), 4)
        self.assertEqual(len(self.commands("quit")), 1)

    def test_pending_ping_is_read_only_and_has_a_finite_deadline(self):
        self.host.booted = False
        result = self.run_smoke()
        self.assertIn("READINESS_TIMEOUT", result["error_codes"])
        self.assertLessEqual(len(self.commands()), 4)
        self.assertEqual({item["cmd"] for item in self.commands()}, {"ping"})

    def test_first_connection_refusal_only_polls_readiness(self):
        pending = [True]
        def first(command, token):
            if pending:
                pending.pop()
                raise ConnectionRefusedError()
        self.host.hook = first
        self.assertTrue(self.run_smoke()["success"])
        self.assertEqual(self.clock.now, LIMITS.poll)

    def test_held_or_unavailable_entry_does_not_retry_startup(self):
        for field, value, code in (("held", True, "ENTRY_HELD"),
                                   ("available", False, "ENTRY_UNAVAILABLE")):
            with self.subTest(field=field):
                self.setUp()
                self.host.hook = lambda command, token: reply({**self.host.entry(), field: value}) \
                    if command["cmd"] == "entry-state" else None
                result = self.run_smoke()
                self.assertIn(code, result["error_codes"])
                self.assertEqual(len(self.commands("entry-state")), 1)
                self.assertFalse(self.commands("entry-capture"))

    def test_forged_negative_auth_is_rejected_before_window_or_capture(self):
        self.host.hook = lambda command, token: reply({"ok": True}) if token != TOKEN else None
        result = self.run_smoke()
        self.assertIn("AUTH_REFUSAL_INVALID", result["error_codes"])
        self.assertFalse(self.commands("window"))
        self.assertFalse(self.commands("quit"))

    def test_invalid_json_or_duplicate_keys_are_not_readiness_retries(self):
        for body in (b"[]", b"not-json", b'{"ok":true,"ok":false}', b'{"ok":true,"n":NaN}'):
            with self.subTest(body=body):
                self.setUp()
                self.host.hook = lambda command, token: smoke.bounded.Reply(200, body)
                result = self.run_smoke()
                self.assertIn("RESPONSE_INVALID", result["error_codes"])
                self.assertEqual(self.commands(), [{"cmd": "ping"}])

    def test_client_match_claim_without_actual_client_dimensions_refuses(self):
        def outer_size_only(command, token):
            if command.get("do") == "show":
                return reply({"ok": True, **self.host.snapshot(), "clientMatched": True})
        self.host.hook = outer_size_only
        result = self.run_smoke()
        self.assertIn("WINDOW_INVALID", result["error_codes"])
        self.assertFalse(self.commands("entry-capture"))
        self.assertEqual(len([c for c in self.commands("window") if "restoreState" in c]), 1)
        self.assertEqual(result["first_command_failure"], {
            "phase": "window_show_resize", "code": "WINDOW_INVALID", "http_status": 200,
            "category": "GUARD_FAILED", "resize": None})

    def test_known_resize_rejections_keep_finite_facts_and_separate_cleanup_failure(self):
        for error, category in (
                ("the requested client area was not observed", "CLIENT_RESIZE_UNOBSERVED"),
                ("client dimensions changed before reporting", "CLIENT_METRICS_CHANGED")):
            with self.subTest(category=category):
                self.setUp()
                detail = resize_detail(private=TOKEN, window=[17, 23, 1280, 780],
                                       stack="private-profile-path")
                def refused(command, token):
                    if command.get("do") == "show":
                        return reply({"ok": False, "error": error, "detail": detail,
                                      "stack": TOKEN}, 400)
                    if command["cmd"] == "entry-check":
                        return reply({"ok": False, "error": TOKEN}, 400)
                self.host.hook = refused
                result = self.run_smoke()
                self.assertFalse(result["success"])
                self.assertEqual(result["capture_count"], 0)
                self.assertFalse(self.commands("entry-capture"))
                self.assertEqual(len([c for c in self.commands("window")
                                      if c.get("do") == "show"]), 1)
                self.assertEqual(result["first_command_failure"], {
                    "phase": "window_show_resize", "code": "COMMAND_FAILED", "http_status": 400,
                    "category": category, "resize": resize_detail()})
                self.assertEqual(result["cleanup_failures"], [{
                    "phase": "entry_verify", "code": "COMMAND_FAILED", "http_status": 400,
                    "category": "REMOTE_ERROR", "resize": None}])
                self.assertEqual(result["error_codes"], ["COMMAND_FAILED"])
                self.assertTrue(result["checks"]["window_restored"])
                self.assertTrue(result["checks"]["close_ack"])
                self.assertEqual(result["exit_code"], 0)
                self.assertEqual(self.process.kill_count, 0)
                self.assertNotIn(TOKEN, json.dumps(result))
                self.assertNotIn("private-profile-path", json.dumps(result))
                self.assertNotIn("stack", json.dumps(result))

    def test_unknown_remote_error_never_adopts_lookalike_resize_detail(self):
        def refused(command, token):
            if command.get("do") == "show":
                return reply({"ok": False, "error": {"private": TOKEN},
                              "detail": resize_detail(), "stack": TOKEN}, 500)
        self.host.hook = refused
        result = self.run_smoke()
        self.assertEqual(result["capture_count"], 0)
        self.assertFalse(self.commands("entry-capture"))
        self.assertEqual(result["first_command_failure"], {
            "phase": "window_show_resize", "code": "COMMAND_FAILED", "http_status": 500,
            "category": "REMOTE_ERROR", "resize": None})
        self.assertEqual(result["cleanup_failures"], [{
            "phase": "entry_verify", "code": "ENTRY_INVALID", "http_status": 200,
            "category": "GUARD_FAILED", "resize": None}])
        self.assertFalse(result["success"])
        self.assertNotIn(TOKEN, json.dumps(result))

    def test_lost_window_reply_is_unknown_and_is_never_retried(self):
        def lost(command, token):
            if command.get("do") == "show":
                raise TimeoutError(TOKEN)
        self.host.hook = lost
        result = self.run_smoke()
        self.assertIn("HTTP_FAILED", result["error_codes"])
        self.assertEqual(result["first_command_failure"], {
            "phase": "window_show_resize", "code": "HTTP_FAILED", "http_status": None,
            "category": "EXCHANGE_FAILED", "resize": None})
        self.assertEqual(len([c for c in self.commands("window") if c.get("do") == "show"]), 1)
        self.assertFalse(self.commands("entry-capture"))
        self.assertEqual(result["exit_code"], 0)
        self.assertFalse(result["success"])
        self.assertNotIn(TOKEN, json.dumps(result))

    def test_capture_refusal_preserves_prior_pngs_and_never_retries_capture(self):
        def refuse_second(command, token):
            if command["cmd"] == "entry-capture" and command["theme"] == "light":
                return reply({"ok": False, "error": TOKEN}, 400)
        self.host.hook = refuse_second
        result = self.run_smoke()
        self.assertFalse(result["success"])
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(result["capture_count"], 1)
        self.assertEqual(tuple(self.artifacts.writes), ("welcome-dark.png",))
        self.assertEqual(len(self.commands("entry-capture")), 2)
        self.assertEqual(len(self.commands("quit")), 1)

    def test_lost_capture_reply_is_unknown_even_if_original_exits_zero(self):
        def lost(command, token):
            if command["cmd"] == "entry-capture":
                raise TimeoutError(TOKEN)
        self.host.hook = lost
        result = self.run_smoke()
        self.assertIn("HTTP_FAILED", result["error_codes"])
        self.assertEqual(len(self.commands("entry-capture")), 1)
        self.assertEqual(result["exit_code"], 0)
        self.assertFalse(result["success"])

    def test_late_capture_cannot_extend_total_deadline_or_be_written(self):
        def late(command, token):
            if command["cmd"] == "entry-capture":
                self.clock.now += LIMITS.total
        self.host.hook = late
        result = self.run_smoke()
        self.assertIn("TOTAL_DEADLINE", result["error_codes"])
        self.assertEqual(result["capture_count"], 0)
        self.assertEqual(len(self.commands("entry-capture")), 1)
        self.assertEqual(self.process.kill_count, 1)

    def test_window_restore_requires_observed_original_geometry(self):
        def wrong_restore(command, token):
            if "restoreState" in command:
                return reply({"ok": True, **self.host.snapshot(), "restored": True})
        self.host.hook = wrong_restore
        result = self.run_smoke()
        self.assertIn("WINDOW_RESTORE_FAILED", result["error_codes"])
        self.assertFalse(result["checks"]["window_restored"])
        self.assertFalse(self.commands("entry-check"))
        self.assertEqual(len(self.commands("quit")), 1)
        self.assertEqual(result["first_command_failure"], {
            "phase": "window_restore", "code": "WINDOW_RESTORE_FAILED", "http_status": 200,
            "category": "GUARD_FAILED", "resize": None})
        self.assertEqual(result["cleanup_failures"], [result["first_command_failure"]])

    def test_fresh_frame_restoration_count_and_no_hold_are_all_required(self):
        for field, value in (("frameReady", False), ("restorationVerified", False),
                             ("captures", 3), ("held", True), ("startupReady", False)):
            with self.subTest(field=field):
                self.setUp()
                self.host.hook = lambda command, token: reply({
                    **self.host.entry(), "frameReady": True, "restorationVerified": True,
                    field: value}) if command["cmd"] == "entry-check" else None
                result = self.run_smoke()
                self.assertFalse(result["checks"]["entry_restored"])
                self.assertFalse(result["success"])
                self.assertEqual(len(self.commands("entry-check")), 1)

    def test_quit_ack_without_original_exit_cannot_succeed(self):
        unrelated = OriginalProcess()
        self.process.can_close = False
        result = self.run_smoke()
        self.assertIn("EXIT_TIMEOUT", result["error_codes"])
        self.assertTrue(result["forced_kill"])
        self.assertEqual(self.process.kill_count, 1)
        self.assertEqual(unrelated.kill_count, 0)
        self.assertEqual(len(self.commands("quit")), 1)

    def test_lost_quit_ack_and_nonzero_exit_are_failures(self):
        def lost_close(command, token):
            if command["cmd"] == "quit":
                self.process.close_requested = True
                raise TimeoutError(TOKEN)
        self.host.hook = lost_close
        result = self.run_smoke()
        self.assertIn("CLOSE_UNCERTAIN", result["error_codes"])
        self.assertEqual(result["first_command_failure"], {
            "phase": "close", "code": "HTTP_FAILED", "http_status": None,
            "category": "EXCHANGE_FAILED", "resize": None})
        self.assertEqual(result["cleanup_failures"], [{
            **result["first_command_failure"], "code": "CLOSE_UNCERTAIN"}])
        self.assertEqual(result["exit_code"], 0)
        self.assertFalse(result["success"])
        self.setUp()
        self.process.close_exit = 7
        result = self.run_smoke()
        self.assertIn("EXIT_FAILED", result["error_codes"])
        self.assertEqual(result["exit_code"], 7)

    def test_overflow_incomplete_drain_and_failed_owned_cleanup_remain_failures(self):
        for fault, code in (("overflow", "OUTPUT_OVERFLOW"),
                            ("incomplete", "OUTPUT_INCOMPLETE"), ("kill", "CLEANUP_FAILED")):
            with self.subTest(fault=fault):
                self.setUp()
                if fault == "overflow":
                    self.drain.overflow_on_finish = True
                elif fault == "incomplete":
                    self.drain.complete = False
                else:
                    self.host.mode = "presentation"
                    self.process.kill_error = OSError(TOKEN)
                result = self.run_smoke()
                self.assertIn(code, result["error_codes"])
                self.assertFalse(result["success"])

    def test_manifest_projection_cannot_publish_private_originals_or_unknown_codes(self):
        def private_failure(command, token):
            raise RuntimeError(TOKEN + " private-profile-path processInstance=opaque-owner")
        self.host.hook = private_failure
        self.report.fail("private-profile-path", TOKEN)
        self.report.captures.append({"file": "private-profile-path", "sha256": "5" * 64, "bytes": 1})
        result = self.run_smoke()
        encoded = json.dumps(result)
        for private in (TOKEN, "private-profile-path", "processInstance", "opaque-owner",
                        str(self.process.pid), "restoreState", "traceback"):
            self.assertNotIn(private, encoded)
        self.assertTrue(set(result["error_codes"]) <= smoke.CODES)
        self.assertEqual(set(result), {"schema", "source_sha", "source_tree", "run_id",
                         "run_attempt", "runner_sha256", "dart_kernel_sha256", "checks",
                         "captures", "capture_count", "exit_code", "exit_observed", "forced_kill",
                         "output_bytes", "output_complete", "output_overflow", "complete", "success",
                         "status", "error_codes", "first_command_failure", "cleanup_failures", "caption",
                         "transport_failure"})
        self.assertEqual(result["schema"], 2)
        self.assertEqual(result["transport_failure"],
                         {"phase": "readiness_ping", "kind": "OTHER"})
        self.assertEqual(result["first_command_failure"]["code"], "HTTP_FAILED")
        self.assertNotIn("capture_progress", result)


class DiagnosticProjectionTests(unittest.TestCase):
    def failure(self, detail=None):
        return smoke.command_failure(
            "window_show_resize", "COMMAND_FAILED", 400, category="REMOTE_ERROR",
            body={"error": "the requested client area was not observed",
                  "detail": resize_detail() if detail is None else detail})

    def test_diagnostic_keys_types_and_bounds_are_explicit(self):
        failure = self.failure()
        self.assertEqual(set(failure), {"phase", "code", "http_status", "category", "resize"})
        self.assertEqual(set(failure["resize"]), {
            "requestedClient", "client", "physical", "devicePixelRatio", "outer",
            "resizeAttempts", "clientMatched"})
        self.assertIs(type(failure["http_status"]), int)
        self.assertIs(type(failure["resize"]["resizeAttempts"]), int)
        self.assertIs(type(failure["resize"]["clientMatched"]), bool)
        self.assertTrue(all(type(failure[name]) is str for name in ("phase", "code", "category")))
        for name in ("requestedClient", "client", "physical", "outer"):
            self.assertIs(type(failure["resize"][name]), list)
            self.assertEqual(len(failure["resize"][name]), 2)
            self.assertTrue(all(type(item) in (int, float) for item in failure["resize"][name]))
        maximum = resize_detail(client=[32768, 32768], physical=[524288, 524288],
                                outer=[32768, 32768], devicePixelRatio=16)
        self.assertEqual(self.failure(maximum)["resize"], maximum)
        for attempts in (0, 5):
            self.assertEqual(self.failure(resize_detail(resizeAttempts=attempts))["resize"]
                             ["resizeAttempts"], attempts)

    def test_malformed_numeric_detail_is_omitted_without_losing_the_refusal(self):
        changes = (
            {"requestedClient": [1280, True]}, {"requestedClient": [1280, 781]},
            {"client": [0, 741]}, {"client": [32769, 741]}, {"client": "private-path"},
            {"physical": [524289, 1111.5]}, {"physical": [1896, 1112]},
            {"outer": [1280, float("inf")]}, {"outer": [32769, 780]},
            {"devicePixelRatio": True}, {"devicePixelRatio": 0},
            {"devicePixelRatio": 16.1}, {"devicePixelRatio": float("nan")},
            {"resizeAttempts": True}, {"resizeAttempts": 1.0},
            {"resizeAttempts": -1}, {"resizeAttempts": 6},
            {"clientMatched": 0}, {"clientMatched": True},
        )
        for change in changes:
            with self.subTest(change=change):
                failure = self.failure(resize_detail(**change))
                self.assertEqual(failure["code"], "COMMAND_FAILED")
                self.assertEqual(failure["category"], "CLIENT_RESIZE_UNOBSERVED")
                self.assertIsNone(failure["resize"])
                json.dumps(failure, allow_nan=False)
        self.assertIsNone(self.failure({})["resize"])
        self.assertIsNone(self.failure(TOKEN)["resize"])

    def test_unknown_shapes_and_private_fields_cannot_enter_public_diagnostics(self):
        valid = self.failure()
        for change in ({"phase": TOKEN}, {"phase": []}, {"code": TOKEN},
                       {"category": TOKEN}, {"category": True}, {"private": TOKEN}):
            with self.subTest(change=change):
                report = smoke.Report()
                report.first_command_failure = {**valid, **change}
                report.cleanup_failures = [{**valid, **change}]
                self.assertIsNone(report.public()["first_command_failure"])
                self.assertEqual(report.public()["cleanup_failures"], [])
                self.assertNotIn(TOKEN, json.dumps(report.public()))
        for status in (True, 400.0, "400", 99, 600, TOKEN):
            with self.subTest(status=status):
                self.assertIsNone(smoke.failure_projection({**valid, "http_status": status})
                                  ["http_status"])
        for status in (100, 400, 599):
            self.assertEqual(smoke.failure_projection({**valid, "http_status": status})
                             ["http_status"], status)
        detail = resize_detail(password=TOKEN, stack=TOKEN, path=TOKEN)
        self.assertEqual(self.failure(detail)["resize"], resize_detail())
        report = smoke.Report()
        report.first_command_failure = self.failure(detail)
        report.cleanup_failures = TOKEN
        public = report.public()
        self.assertEqual(public["cleanup_failures"], [])
        self.assertNotIn(TOKEN, json.dumps(public, allow_nan=False))
        self.assertFalse(public["success"])

    def test_cleanup_projection_is_finite_and_only_uses_cleanup_phases(self):
        report = smoke.Report()
        valid = {"phase": "window_restore", "code": "WINDOW_RESTORE_FAILED",
                 "http_status": 200, "category": "GUARD_FAILED", "resize": None}
        report.cleanup_failures = [valid, {**valid, "phase": "entry_verify"},
                                   {**valid, "phase": "close"}, {"private": TOKEN}]
        self.assertEqual(report.public()["cleanup_failures"], report.cleanup_failures[:2])
        report.cleanup_failures = [valid, valid]
        self.assertEqual(report.public()["cleanup_failures"], [valid])
        report.cleanup_failures = [{**valid, "phase": "window_observe"}]
        self.assertEqual(report.public()["cleanup_failures"], [])


class ParserTests(unittest.TestCase):
    def test_viewport_png_dimensions_are_explicit_bounded_and_private(self):
        for width, height in ((1280, 780), (1200, 600)):
            for colors, channels in ((2, 3), (6, 4)):
                header = struct.pack('>IIBBBBB', width, height, 8, colors, 0, 0, 0)
                rows = (b'\0' + bytes(width * channels)) * height
                def image(payload=rows):
                    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header)
                        + chunk(b'IDAT', zlib.compress(payload)) + chunk(b'IEND', b''))
                original = image()
                encoded = base64.b64encode(original).decode('ascii')
                self.assertEqual(smoke.png_bytes(encoded,
                    dimensions=(width, height)), original)
                if (width, height) == (1280, 780):
                    self.assertEqual(smoke.png_bytes(encoded), original)
                else:
                    with self.assertRaises(smoke.Failure) as caught:
                        smoke.png_bytes(encoded)
                    self.assertEqual(caught.exception.code, 'PNG_INVALID')
                for offered in (None, [], [width, height], (width,),
                    (True, height), (str(width), height), (width, float(height)),
                    (0, height), (16384, 16384),
                    (1200, 780), (1280, 600)):
                    with self.assertRaises(smoke.Failure) as caught:
                        smoke.png_bytes(encoded, dimensions=offered)
                    self.assertEqual(caught.exception.code, 'PNG_INVALID')
                other = (1200, 600) if width == 1280 else (1280, 780)
                with self.assertRaises(smoke.Failure):
                    smoke.png_bytes(encoded, dimensions=other)
                for invalid in (original[:-1] + bytes([original[-1] ^ 1]),
                    original[:33] + chunk(b'tEXt', b'private') + original[33:],
                    image(rows[:-(width * channels + 1)]),
                    image((b'\5' + bytes(width * channels)) * height)):
                    with self.assertRaises(smoke.Failure) as caught:
                        smoke.png_bytes(base64.b64encode(invalid).decode('ascii'),
                            dimensions=(width, height))
                    self.assertEqual(caught.exception.code, 'PNG_INVALID')

    def test_reference_artwork_requires_exact_original_kind_frame_and_time(self):
        for screen in ('welcome', 'import'):
            value = capture_reply(screen)
            self.assertEqual(smoke.capture_bytes(value, screen, 'dark'), PNG)
            for offered in (None, [], value['referenceArtwork'] * 2,
                            [dict(kind='entry_field', seconds=6.0)],
                            [dict(kind='entry_field', seconds='private')],
                            [dict(kind='entry_field', seconds=6, owner='private')]):
                with self.subTest(screen=screen, offered=offered), self.assertRaises(smoke.Failure):
                    smoke.capture_bytes(dict(value, referenceArtwork=offered), screen, 'dark')

    def test_welcome_frame_metadata_cannot_replace_wrong_mode_or_restore(self):
        value = capture_reply()
        for change in (dict(restorationVerified=False), dict(captureMode='presentation'),
                       dict(harnessMode='presentation')):
            with self.subTest(change=change), self.assertRaises(smoke.Failure):
                smoke.capture_bytes(dict(value, **change), 'welcome', 'dark')
        for change in (dict(frame=719), dict(frame=720.0), dict(frame_count=1799),
                       dict(kind='private'), dict(owner='private')):
            artwork = [dict(value['referenceArtwork'][0], **change),
                       value['referenceArtwork'][1]]
            with self.subTest(change=change), self.assertRaises(smoke.Failure):
                smoke.capture_bytes(dict(value, referenceArtwork=artwork), 'welcome', 'dark')

    def test_real_structured_png_and_logical_dimensions_are_admitted(self):
        self.assertEqual(smoke.png_bytes(ENCODED), PNG)
        self.assertEqual(smoke.capture_bytes(capture_reply(), "welcome", "dark"), PNG)

    def test_rgb_and_rgba_significant_bits_preserve_original_capture_png(self):
        for colors, significance in ((2, b"\x08\x08\x08"), (2, b"\x01\x01\x01"),
                                      (2, b"\x01\x04\x08"), (6, b"\x08\x08\x08\x08"),
                                      (6, b"\x01\x01\x01\x01"), (6, b"\x01\x03\x05\x08")):
            with self.subTest(colors=colors, significance=tuple(significance)):
                original = color_png(colors)
                data = original[:33] + chunk(b"sBIT", significance) + original[33:]
                encoded = base64.b64encode(data).decode("ascii")
                self.assertEqual(smoke.png_bytes(encoded), data)
                self.assertEqual(smoke.capture_bytes(
                    {**capture_reply(), "png": encoded}, "welcome", "dark"), data)

    def test_significant_bits_length_must_match_rgb_or_rgba_channels(self):
        for colors, channels in ((2, 3), (6, 4)):
            original = color_png(colors)
            for length in range(6):
                if length == channels:
                    continue
                with self.subTest(colors=colors, length=length):
                    data = original[:33] + chunk(b"sBIT", b"\x08" * length) + original[33:]
                    with self.assertRaises(smoke.Failure) as caught:
                        smoke.png_bytes(base64.b64encode(data).decode("ascii"))
                    self.assertEqual(caught.exception.code, "PNG_INVALID")

    def test_significant_bits_each_channel_requires_one_through_eight(self):
        for colors, channels in ((2, 3), (6, 4)):
            original = color_png(colors)
            for channel in range(channels):
                for value in (0, 9, 255):
                    with self.subTest(colors=colors, channel=channel, value=value):
                        significance = bytearray(b"\x08" * channels)
                        significance[channel] = value
                        data = original[:33] + chunk(b"sBIT", bytes(significance)) + original[33:]
                        with self.assertRaises(smoke.Failure) as caught:
                            smoke.png_bytes(base64.b64encode(data).decode("ascii"))
                        self.assertEqual(caught.exception.code, "PNG_INVALID")

    def test_significant_bits_duplicate_or_after_idat_is_refused(self):
        for colors, channels in ((2, 3), (6, 4)):
            original = color_png(colors)
            significance = chunk(b"sBIT", b"\x08" * channels)
            variants = (
                original[:33] + significance * 2 + original[33:],
                original[:33] + significance + chunk(b"sRGB", b"\0")
                + significance + original[33:],
                original[:-12] + significance + original[-12:],
            )
            for index, data in enumerate(variants):
                with self.subTest(colors=colors, variant=index):
                    with self.assertRaises(smoke.Failure) as caught:
                        smoke.png_bytes(base64.b64encode(data).decode("ascii"))
                    self.assertEqual(caught.exception.code, "PNG_INVALID")

    def test_significant_bits_cannot_bypass_its_original_chunk_crc(self):
        for colors, channels in ((2, 3), (6, 4)):
            with self.subTest(colors=colors):
                original = color_png(colors)
                significance = chunk(b"sBIT", b"\x08" * channels)
                broken = significance[:-1] + bytes([significance[-1] ^ 1])
                data = original[:33] + broken + original[33:]
                with self.assertRaises(smoke.Failure) as caught:
                    smoke.png_bytes(base64.b64encode(data).decode("ascii"))
                self.assertEqual(caught.exception.code, "PNG_INVALID")

    def test_significant_bits_does_not_admit_text_profiles_or_unknown_metadata(self):
        for colors, channels in ((2, 3), (6, 4)):
            original = color_png(colors)
            significance = chunk(b"sBIT", b"\x08" * channels)
            for kind in (b"tEXt", b"zTXt", b"iTXt", b"iCCP", b"zABC"):
                with self.subTest(colors=colors, kind=kind):
                    data = (original[:33] + significance
                            + chunk(kind, b"private-profile-data") + original[33:])
                    with self.assertRaises(smoke.Failure) as caught:
                        smoke.png_bytes(base64.b64encode(data).decode("ascii"))
                    self.assertEqual(caught.exception.code, "PNG_INVALID")

    def test_base64_must_be_strict_canonical_and_bounded(self):
        for encoded in ("", ENCODED + "\n", "????", ENCODED[:-1], 42):
            with self.subTest(encoded_type=type(encoded)):
                with self.assertRaises(smoke.Failure) as caught:
                    smoke.png_bytes(encoded)
                self.assertEqual(caught.exception.code, "PNG_INVALID")
        with patch.object(smoke, "MAX_BASE64", len(ENCODED) - 1):
            with self.assertRaises(smoke.Failure):
                smoke.png_bytes(ENCODED)

    def test_png_crc_truncation_trailing_bytes_and_dimension_lies_refuse(self):
        wrong = struct.pack(">IIBBBBB", 1279, 780, 8, 6, 0, 0, 0)
        variants = (PNG[:-1], PNG + b"trailing", PNG[:40] + bytes([PNG[40] ^ 1]) + PNG[41:],
                    PNG[:8] + chunk(b"IHDR", wrong) + PNG[33:])
        for data in variants:
            with self.subTest(size=len(data)):
                with self.assertRaises(smoke.Failure):
                    smoke.png_bytes(base64.b64encode(data).decode())

    def test_text_metadata_invalid_zlib_and_compression_bomb_are_not_artifacts(self):
        variants = (
            PNG[:33] + chunk(b"tEXt", b"private-profile-path") + PNG[33:],
            PNG[:33] + chunk(b"IDAT", b"not-zlib") + chunk(b"IEND", b""),
            PNG[:33] + chunk(b"IDAT", zlib.compress(PIXELS + b"overflow")) + chunk(b"IEND", b""),
            PNG[:33] + chunk(b"IDAT", zlib.compress(PIXELS) + zlib.compress(b"second"))
            + chunk(b"IEND", b""),
        )
        for data in variants:
            with self.subTest(size=len(data)):
                with self.assertRaises(smoke.Failure):
                    smoke.png_bytes(base64.b64encode(data).decode())

    def test_png_requires_idat_order_iend_and_valid_scanline_filters(self):
        invalid_pixels = b"\5" + PIXELS[1:]
        variants = (PNG[:33] + chunk(b"IEND", b""),
                    PNG[:33] + chunk(b"IDAT", zlib.compress(invalid_pixels)) + chunk(b"IEND", b""),
                    PNG[:33] + chunk(b"IDAT", zlib.compress(PIXELS)) + chunk(b"sRGB", b"\0")
                    + chunk(b"IEND", b""))
        for data in variants:
            with self.subTest(size=len(data)):
                with self.assertRaises(smoke.Failure):
                    smoke.png_bytes(base64.b64encode(data).decode())

    def test_capture_claims_require_exact_screen_mode_restoration_and_metrics(self):
        variants = (("screen", "import"), ("theme", "light"), ("width", True),
                    ("height", 779), ("scale", 2), ("client", [1296, 819]),
                    ("physical", [1280, 780]), ("devicePixelRatio", float("inf")),
                    ("restorationVerified", False), ("harnessMode", "presentation"),
                    ("captureMode", "covering"), ("privatePath", TOKEN))
        for key, value in variants:
            with self.subTest(key=key):
                body = {**capture_reply(), key: value}
                with self.assertRaises(smoke.Failure) as caught:
                    smoke.capture_bytes(body, "welcome", "dark")
                self.assertEqual(caught.exception.code, "CAPTURE_INVALID")


class AdmissionArtifactTests(unittest.TestCase):
    def parent(self):
        return {"GITHUB_ACTIONS": "true", "GITHUB_SHA": SOURCE, "RUNNER_OS": "Windows",
                "RUNNER_ENVIRONMENT": "github-hosted", "GITHUB_WORKSPACE": "checkout",
                "SystemRoot": r"C:\Windows", "GITHUB_RUN_ID": "4001", "GITHUB_RUN_ATTEMPT": "2"}

    def test_only_hosted_windows_exact_sha_and_anonymous_run_attempt_are_admitted(self):
        parent, expected = smoke.require_ci(self.parent(), None, platform="nt")
        self.assertEqual(expected, SOURCE)
        self.assertEqual(parent["SYSTEMROOT"], r"C:\Windows")
        for change in ({"RUNNER_ENVIRONMENT": "self-hosted"}, {"GITHUB_SHA": "bad"},
                       {"GITHUB_RUN_ID": "private-name"}, {"GITHUB_RUN_ATTEMPT": "0"}):
            with self.subTest(change=change):
                with self.assertRaises(smoke.bounded.SmokeFailure):
                    smoke.require_ci({**self.parent(), **change}, None, platform="nt")
        with self.assertRaises(smoke.bounded.SmokeFailure):
            smoke.require_ci(self.parent(), None, platform="posix")
        with self.assertRaises(smoke.bounded.SmokeFailure):
            smoke.require_ci(self.parent(), "5" * 40, platform="nt")

    def test_ordinary_profile_replaces_all_locations_and_inherited_harness_flags(self):
        parent = {key.lower(): "inherited-private" for key in smoke.bounded.REPLACED}
        parent.update({"SYRIUS_HARNESS_PRESENTATION": "welcome", "SYRIUS_HARNESS_SEED": TOKEN,
                       "GITHUB_TOKEN": TOKEN, "HTTP_PROXY": TOKEN, "Path": "runtime-path"})
        original = dict(parent)
        profile = PureWindowsPath(r"D:\checkout\.harness\ci-entry-smoke-new")
        env = smoke.child_environment(parent, profile, 32123, TOKEN)
        self.assertEqual(parent, original)
        self.assertTrue(smoke.bounded.REPLACED <= env.keys())
        self.assertEqual(env["PATH"], "runtime-path")
        self.assertEqual(env["XDG_CACHE_HOME"], str(profile / "Cache"))
        self.assertEqual(env["HOMEDRIVE"], "D:")
        self.assertNotIn("inherited-private", env.values())
        for key in ("GITHUB_TOKEN", "HTTP_PROXY", "SYRIUS_HARNESS_PRESENTATION", "SYRIUS_HARNESS_SEED"):
            self.assertNotIn(key, env)

    def test_preflight_diagnostics_stop_before_profile_or_wallet_launch(self):
        for code in ("PREFLIGHT_TIMEOUT", "PREFLIGHT_OUTPUT_REFUSED"):
            with self.subTest(code=code), tempfile.TemporaryDirectory() as location:
                repo = Path(location)
                parent = {"GITHUB_WORKSPACE": str(repo), "GITHUB_RUN_ID": "4001",
                          "GITHUB_RUN_ATTEMPT": "2"}
                with patch.object(smoke, "require_ci", return_value=(parent, SOURCE)), \
                        patch.object(smoke.Path, "cwd", return_value=repo), \
                        patch.object(smoke.bounded, "verify_source"), \
                        patch.object(smoke, "source_tree", return_value=TREE), \
                        patch.object(smoke.bounded, "binary_hash", return_value=(repo, "2" * 64, (1, 2, 3, 4))), \
                        patch.object(smoke.bounded, "check_no_existing", side_effect=smoke.bounded.SmokeFailure(code)), \
                        patch.object(smoke, "new_profile") as profile, \
                        patch.object(smoke.subprocess, "Popen") as launch, \
                        patch("sys.stdout", new_callable=io.StringIO) as output:
                    result = smoke.main([])
                self.assertEqual(result, 1)
                public = json.loads(output.getvalue())
                self.assertEqual(public["error_codes"], [code])
                self.assertFalse(public["success"])
                self.assertFalse(public["checks"]["preflight"])
                self.assertEqual(public["captures"], [])
                self.assertFalse(public["exit_observed"])
                profile.assert_not_called()
                launch.assert_not_called()
                self.assertNotIn(location, output.getvalue())
                self.assertNotIn(TOKEN, output.getvalue())
                manifest = json.loads((repo / smoke.OUTPUT / "manifest.json").read_bytes())
                self.assertEqual(manifest, public)

    def test_source_tree_is_exact_bounded_and_dirty_source_is_rejected(self):
        calls = []
        def fixed(arguments, **kwargs):
            calls.append((arguments, kwargs))
            return (0, (TREE + "\r\n").encode()) if "rev-parse" in arguments else (0, b"")
        self.assertEqual(smoke.source_tree(Path("checkout"), self.parent(), run=fixed), TREE)
        self.assertEqual(calls[0][1]["cap"], 128)
        self.assertIn("HEAD^{tree}", calls[0][0])
        for output in ((TREE + "\nprivate-path").encode(), b"not-a-tree\n"):
            with self.assertRaises(smoke.Failure):
                smoke.source_tree(Path("checkout"), {}, run=lambda *a, **kw: (0, output))
        with self.assertRaises(smoke.Failure):
            smoke.source_tree(Path("checkout"), {}, run=lambda args, **kw:
                              (0, (TREE + "\n").encode()) if "rev-parse" in args else (1, b""))

    def test_dirty_source_preserves_only_the_exact_observed_tree_before_refusal(self):
        report = smoke.Report()
        observations = []
        def observed(tree):
            observations.append(tree)
            report.source_tree = tree
        def dirty(arguments, **kwargs):
            if "rev-parse" in arguments:
                return 0, (TREE + "\n").encode()
            self.assertEqual(observations, [TREE])
            return 1, (TOKEN + " private-profile-path").encode()
        with self.assertRaises(smoke.Failure) as caught:
            smoke.source_tree(Path("checkout"), self.parent(), run=dirty, observe_tree=observed)
        self.assertEqual(caught.exception.code, "SOURCE_REFUSED")
        self.assertEqual(report.public()["source_tree"], TREE)
        self.assertFalse(report.public()["checks"]["source"])
        self.assertNotIn(TOKEN, json.dumps(report.public()))
        self.assertFalse(report.public()["success"])
        observations.clear()
        with self.assertRaises(smoke.Failure):
            smoke.source_tree(Path("checkout"), {}, observe_tree=observed,
                              run=lambda *args, **kwargs: (0, (TREE + "\nprivate-path").encode()))
        self.assertEqual(observations, [])

    def test_fresh_output_is_separate_from_profile_and_never_adopts_existing_output(self):
        with tempfile.TemporaryDirectory() as location:
            repo = Path(location)
            artifacts = smoke.Artifacts(repo)
            profile = smoke.new_profile(repo)
            self.assertNotEqual(profile, artifacts.root)
            self.assertNotIn(profile, artifacts.root.parents)
            artifacts.png("welcome-dark.png", PNG)
            with self.assertRaises(smoke.Failure) as caught:
                smoke.Artifacts(repo)
            self.assertEqual(caught.exception.code, "OUTPUT_REFUSED")
            report = smoke.Report()
            report.captures = artifacts.records
            artifacts.manifest(report.public())
            public = json.loads((artifacts.root / "manifest.json").read_bytes())
            self.assertFalse(public["success"])
            self.assertEqual(public["status"], "UNKNOWN")
            self.assertEqual(public["capture_count"], 1)
            self.assertEqual(set(path.name for path in artifacts.root.iterdir()),
                             {"welcome-dark.png", "manifest.json"})

    def test_exclusive_artifacts_keep_original_bytes_and_reject_unlisted_names(self):
        with tempfile.TemporaryDirectory() as location:
            artifacts = smoke.Artifacts(Path(location))
            artifacts.png("welcome-dark.png", PNG)
            for name in ("welcome-dark.png", "profile.zip", "../profile", "raw.log"):
                with self.subTest(name=name):
                    with self.assertRaises(smoke.Failure):
                        artifacts.png(name, b"private-data")
            self.assertEqual((artifacts.root / "welcome-dark.png").read_bytes(), PNG)
            artifacts.manifest(smoke.Report().public())
            with self.assertRaises(FileExistsError):
                artifacts.manifest(smoke.Report().public())

    def test_entry_lane_is_default_off_independent_and_uploads_five_explicit_files(self):
        workflow = (CONTROLLER.parents[2] / ".github/workflows/public-contribution-qualification.yml").read_text()
        self.assertIn("entry_capture_smoke:", workflow)
        option = workflow.split("      entry_capture_smoke:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertIn("default: false", option)
        tail = workflow.split("  windows-entry-capture:\n", 1)[1]
        lane = re.split(r"\n  [A-Za-z0-9_-]+:\n", tail, maxsplit=1)[0]
        self.assertIn("if: inputs.entry_capture_smoke", lane)
        self.assertIn("runs-on: windows-latest", lane)
        self.assertNotIn("needs:", lane)
        self.assertIn("--target harness/app/main.dart", lane)
        self.assertIn("--enforce-lockfile", lane)
        self.assertIn("compression-level: 0", lane)
        self.assertIn("always()", lane)
        upload = lane.split("path: |\n", 1)[1]
        self.assertEqual([line.strip() for line in upload.splitlines() if line.strip()],
                         [f".harness/ci-entry-capture/{name}" for name in (*smoke.FILES, "manifest.json")])



def progress_fixture():
    effect = dict(phase='original-native-frame', future='succeeded',
                  failed=False, milliseconds=21001)
    return dict(schema=1, screen='welcome', theme='dark', scopes=1,
        completedCaptures=1, effects=1, last=effect, slowest=dict(effect),
        artworkCount=2, imageCreated=True, restoring=True, restored=True, held=False)


def effect_trace_fixture(boundary='begin', **changes):
    value = dict(schema=1, screen='welcome', theme='dark', scopes=1, effects=1,
        phase='original-native-frame', boundary=boundary, failed=False,
        future='not_returned' if boundary == 'begin' else
            'succeeded' if boundary == 'ended' else 'pending',
        milliseconds={'begin': 0, 'returned': 1, 'ended': 2}[boundary])
    return dict(value, **changes)


def effect_trace_output(*values):
    return b''.join(smoke.EFFECT_TRACE_PREFIX + json.dumps(value).encode() + b'\n'
                    for value in values)


class EntryProgressTests(unittest.TestCase):
    def test_pipe_trace_keeps_last_admission_distinct_from_last_ended_effect(self):
        values = [effect_trace_fixture(boundary) for boundary in ('begin', 'returned', 'ended')]
        values += [effect_trace_fixture(boundary, effects=2,
            phase='original-renderer-image') for boundary in ('begin', 'returned')]
        raw = b'private unrelated process output\n' + effect_trace_output(*values)
        trace = smoke.effect_trace_from_output(raw, complete=True, overflow=False)
        self.assertEqual(trace['status'], 'OBSERVED')
        self.assertEqual(trace['events'], 5)
        self.assertEqual(trace['last']['phase'], 'original-renderer-image')
        self.assertEqual(trace['last']['future'], 'pending')
        self.assertEqual(trace['last_ended']['phase'], 'original-native-frame')
        values[-1]['phase'] = 'private'
        self.assertEqual(trace['last']['phase'], 'original-renderer-image')
        report = smoke.Report()
        report.effect_trace = trace
        report.errors = ['HTTP_FAILED']
        public = report.public()
        self.assertEqual(public['effect_trace'], trace)
        self.assertEqual(public['capture_count'], 0)
        self.assertFalse(public['success'])
        self.assertEqual(public['error_codes'], ['HTTP_FAILED'])
        self.assertNotIn('private', json.dumps(public))

    def test_pipe_trace_preserves_a_call_that_failed_before_returning_a_future(self):
        raw = effect_trace_output(effect_trace_fixture(),
            effect_trace_fixture('ended', future='not_returned', failed=True))
        trace = smoke.effect_trace_from_output(raw, complete=True, overflow=False)
        self.assertEqual(trace['status'], 'OBSERVED')
        self.assertEqual(trace['events'], 2)
        self.assertTrue(trace['last']['failed'])
        self.assertEqual(trace['last']['future'], 'not_returned')
        self.assertEqual(trace['last_ended'], trace['last'])

    def test_pipe_trace_refuses_private_fields_coercion_and_malformed_records(self):
        changes = [dict(schema=True), dict(screen='private'), dict(theme='private'),
            dict(scopes=True), dict(scopes=5), dict(effects=0), dict(effects=193),
            dict(phase='private'), dict(boundary='private'), dict(future='private'),
            dict(failed=1), dict(milliseconds=True), dict(milliseconds=-1),
            dict(milliseconds=0x80000000), dict(milliseconds=1.5),
            dict(error='private'), dict(boundary='returned'), dict(boundary='ended')]
        invalid = [effect_trace_output(dict(effect_trace_fixture(), **change))
                   for change in changes]
        valid = effect_trace_output(effect_trace_fixture())
        invalid += [valid[:-1], smoke.EFFECT_TRACE_PREFIX + b'\xff\n',
            valid.replace(b'"schema": 1', b'"schema":1,"schema":1'),
            smoke.EFFECT_TRACE_PREFIX + b'{"schema":true,"capped":true}\n',
            smoke.EFFECT_TRACE_PREFIX + b'x' * 513 + b'\n']
        for raw in invalid:
            with self.subTest(bytes=len(raw)):
                trace = smoke.effect_trace_from_output(raw, complete=True, overflow=False)
                self.assertEqual(trace, dict(schema=1, status='REFUSED',
                    events=0, last=None, last_ended=None))
                self.assertNotIn('private', json.dumps(trace))

    def test_pipe_trace_refuses_replays_gaps_and_inconsistent_effect_order(self):
        begin, returned, ended = [effect_trace_fixture(boundary)
                                 for boundary in ('begin', 'returned', 'ended')]
        invalid = [(returned,), (begin, begin), (begin, returned, returned),
            (begin, dict(returned, phase='original-renderer-image')),
            (dict(begin, milliseconds=5), returned),
            (begin, effect_trace_fixture(effects=2)), (begin, ended),
            (begin, returned, ended, effect_trace_fixture(effects=3)),
            (begin, returned, ended, effect_trace_fixture(scopes=2)),
            (begin, dict(schema=1, capped=True), returned)]
        for values in invalid:
            with self.subTest(records=len(values)):
                trace = smoke.effect_trace_from_output(
                    effect_trace_output(*values), complete=True, overflow=False)
                self.assertEqual(trace['status'], 'REFUSED')

    def test_pipe_trace_caps_and_original_output_limits_remain_explicit(self):
        raw = effect_trace_output(effect_trace_fixture(), dict(schema=1, capped=True))
        trace = smoke.effect_trace_from_output(raw, complete=True, overflow=False)
        self.assertEqual(trace['status'], 'CAPPED')
        self.assertEqual(trace['events'], 1)
        self.assertIsNone(trace['last_ended'])
        for complete, overflow in ((False, False), (True, True)):
            self.assertEqual(smoke.effect_trace_from_output(
                raw, complete=complete, overflow=overflow)['status'], 'REFUSED')
        self.assertIsNone(smoke.effect_trace_from_output(
            b'legacy private output\n', complete=True, overflow=False))
        self.assertEqual(smoke.effect_trace_from_output(
            b'x' * (smoke.LIMITS.output_bytes + 1),
            complete=True, overflow=False)['status'], 'REFUSED')
        self.assertEqual((smoke.LIMITS.total, smoke.LIMITS.ready, smoke.LIMITS.request,
                          smoke.LIMITS.capture_request, smoke.LIMITS.output_bytes),
                         (150, 45, 20, 30, 131072))
        env = smoke.child_environment({}, Path('isolated'), 1234, TOKEN)
        self.assertEqual(env['SYRIUS_CI_ENTRY_EFFECT_TRACE'], 'true')

    def test_original_failed_session_projects_its_existing_pipe_without_another_request(self):
        process, drain, report, clock = OriginalProcess(), Drain(), smoke.Report(), Clock()
        class TimedOutHost(Host):
            captures = 0
            def exchange(self, command, token, timeout):
                if command.get('cmd') == 'entry-capture':
                    self.captures += 1
                    raise TimeoutError('private original request')
                return super().exchange(command, token, timeout)
        host = TimedOutHost(process)
        drain.data = effect_trace_output(effect_trace_fixture())
        drain.count = len(drain.data)
        session = smoke.EntrySmoke(process, host, TOKEN, drain, report,
            artifacts=Artifacts(), limits=LIMITS, clock=clock, sleep=clock.sleep)
        public = session.run()
        self.assertEqual(host.captures, 1)
        self.assertEqual(public['effect_trace']['last']['boundary'], 'begin')
        self.assertEqual(public['capture_count'], 0)
        self.assertFalse(public['success'])
        self.assertIn('HTTP_FAILED', public['error_codes'])
        self.assertEqual(public['transport_failure'],
                         dict(phase='capture_welcome_dark', kind='TIMEOUT'))
        self.assertNotIn('private original request', json.dumps(public))

    def test_progress_copies_finite_receipts_and_keeps_host_counts_separate(self):
        original = progress_fixture()
        value = smoke.capture_progress_projection(original)
        self.assertEqual(value, original)
        original['last']['milliseconds'] = 1
        self.assertEqual(value['last']['milliseconds'], 21001)
        report = smoke.Report()
        report.capture_progress = value
        report.transport_failure = dict(phase='capture_welcome_dark', kind='TIMEOUT')
        report.errors = ['HTTP_FAILED']
        public = report.public()
        self.assertEqual(public['capture_progress']['completedCaptures'], 1)
        self.assertEqual(public['capture_count'], 0)
        self.assertEqual(public['captures'], [])
        self.assertFalse(public['success'])
        self.assertEqual(public['status'], 'UNKNOWN')
        self.assertEqual(public['error_codes'], ['HTTP_FAILED'])
        self.assertEqual(public['transport_failure']['kind'], 'TIMEOUT')

    def test_progress_refuses_private_fields_coercion_and_inconsistent_effects(self):
        base = progress_fixture()
        bad = [dict(base, schema=True), dict(base, scopes=True),
            dict(base, scopes=0), dict(base, scopes=17), dict(base, completedCaptures=2),
            dict(base, effects=193), dict(base, effects=False),
            dict(base, artworkCount=3), dict(base, imageCreated=1),
            dict(base, screen='private-input'), dict(base, theme='private-input'),
            dict(base, owner='private-input'), dict(base, slowest=None),
            dict(base, effects=0)]
        for field in ('last', 'slowest'):
            for change in (dict(phase='private-input'), dict(future='private-input'),
                    dict(failed=1), dict(milliseconds=True), dict(milliseconds=-1),
                    dict(milliseconds=0x80000000), dict(milliseconds=1.5),
                    dict(error='private-input')):
                bad.append(dict(base, **{field: dict(base[field], **change)}))
        for value in bad:
            with self.subTest(fields=len(value)):
                self.assertIsNone(smoke.capture_progress_projection(value))
        empty = dict(base, effects=0, last=None, slowest=None)
        self.assertEqual(smoke.capture_progress_projection(empty), empty)

    def test_http_exception_class_is_observed_without_message_or_capture_retry(self):
        class OpaqueError(Exception):
            def __str__(self):
                raise AssertionError('Private error must not be rendered')
        for error, kind in ((TimeoutError('private-context'), 'TIMEOUT'),
                (smoke.http.client.RemoteDisconnected('private-context'), 'DISCONNECTED'),
                (ConnectionResetError('private-context'), 'RESET'),
                (smoke.http.client.IncompleteRead(b'private-context', 17), 'INCOMPLETE'),
                (OSError('private-context'), 'IO_ERROR'), (OpaqueError(), 'OTHER')):
            self.assertEqual(smoke.http_failure_observation(error, 'capture_welcome_dark'),
                             dict(phase='capture_welcome_dark', kind=kind))
        self.assertIsNone(smoke.http_failure_observation(None, 'capture_welcome_dark'))
        self.assertIsNone(smoke.http_failure_observation(TimeoutError(), 'private-input'))
        error = TimeoutError('private-transport-context')
        class Transport:
            calls = 0
            def exchange(self, command, token, timeout):
                self.calls += 1
                raise error
        clock, report, transport = Clock(), smoke.Report(), Transport()
        session = smoke.EntrySmoke(OriginalProcess(), transport, TOKEN, Drain(), report,
            artifacts=Artifacts(), limits=LIMITS, clock=clock, sleep=clock.sleep)
        with self.assertRaises(smoke.bounded.SmokeFailure):
            session._positive(dict(cmd='entry-capture', screen='welcome', theme='dark'),
                              phase='capture_welcome_dark')
        self.assertEqual(transport.calls, 1)
        self.assertIs(report.original_errors[-1], error)
        self.assertEqual(report.transport_failure,
                         dict(phase='capture_welcome_dark', kind='TIMEOUT'))
        self.assertEqual(report.first_command_failure['code'], 'HTTP_FAILED')
        self.assertNotIn('private-transport-context', json.dumps(report.public()))

    def test_dart_phase_catalog_and_existing_reply_observation_remain_passive(self):
        root = CONTROLLER.parents[2]
        source = (root / 'harness/app/native_entry_capture.dart').read_text()
        model = (root / 'harness/app/entry_capture_progress.dart').read_text()
        phases = set(re.findall(r"effect(?:<[^>]+>)?\(\s*'([^']+)'", source))
        self.assertEqual(phases, smoke.ENTRY_EFFECT_PHASES)
        self.assertEqual(set(re.findall(r"'(original-[a-z-]+)'", model)), phases)
        progress = progress_fixture()
        class Transport:
            calls = 0
            def exchange(self, command, token, timeout):
                self.calls += 1
                return reply(dict(ok=True, captureProgress=progress))
        clock, report, transport = Clock(), smoke.Report(), Transport()
        session = smoke.EntrySmoke(OriginalProcess(), transport, TOKEN, Drain(), report,
            artifacts=Artifacts(), limits=LIMITS, clock=clock, sleep=clock.sleep)
        body = session._positive(dict(cmd='entry-check'), phase='entry_verify')
        self.assertEqual(body['captureProgress'], progress)
        self.assertEqual(report.capture_progress, progress)
        self.assertEqual(transport.calls, 1)
        self.assertEqual(report.public()['capture_count'], 0)
        self.assertFalse(report.public()['success'])


if __name__ == "__main__":
    unittest.main()
