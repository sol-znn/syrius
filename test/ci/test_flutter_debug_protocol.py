"""Pure protocol cases; no process, socket, private profile or disk scratch."""

import json
import unittest
import urllib.parse
from unittest import mock

from tool.ci import flutter_debug_protocol as protocol


VM = "ws://127.0.0.1:43432/fixture-token=/ws"
DEVTOOLS = "http://127.0.0.1:9100/?uri=" + urllib.parse.quote(VM.replace("ws:", "http:")[:-2], safe="")


def frame(value):
    return json.dumps([value]).encode()


def event(name, **params):
    return frame(dict(event=name, params=params))


def started():
    session = protocol.DaemonTranscript()
    session.feed(event("app.start", appId="private-app", deviceId="windows", supportsRestart=True,
                       directory="private-source-path"))
    session.feed(event("app.debugPort", appId="private-app", port=43432, wsUri=VM))
    session.feed(event("app.started", appId="private-app"))
    return session


class EndpointTests(unittest.TestCase):
    def test_vm_auth_bytes_are_preserved_after_finite_validation(self):
        for value in (VM, VM.replace("fixture-token=", "fixture%3D")):
            self.assertEqual(protocol.vm_uri(value), value)

    def test_vm_refuses_alias_remote_credentials_redirect_and_unbound_paths(self):
        values = [VM.replace("127.0.0.1", "localhost"), VM.replace("127.0.0.1", "example.invalid"),
            VM.replace("127.0.0.1", "user@127.0.0.1"), VM.replace(":43432", ":80"),
            VM.replace("/fixture-token=/", "/"), VM + "?private=value", VM + "#private",
            VM.replace("fixture-token=", ".."), VM.replace("fixture-token=", "bad%2Fpath"), VM + "\n"]
        for value in values:
            with self.subTest(value=value), self.assertRaises(protocol.Refused):
                protocol.vm_uri(value)

    def test_devtools_links_only_the_original_service(self):
        self.assertEqual(protocol.devtools_uri(DEVTOOLS, VM), DEVTOOLS)
        fragment = "http://127.0.0.1:9100/#/debugger?uri=" + urllib.parse.quote(VM, safe="")
        self.assertEqual(protocol.devtools_uri(fragment, VM), fragment)

    def test_devtools_refuses_changed_service_and_duplicate_bindings(self):
        for value in (DEVTOOLS.replace(":9100", ":80"), DEVTOOLS.replace("43432", "43433"),
                      DEVTOOLS.replace("fixture-token", "changed"), DEVTOOLS + "&uri=" + urllib.parse.quote(VM, safe=""),
                      "http://example.invalid/?uri=" + urllib.parse.quote(VM, safe="")):
            with self.subTest(value=value), self.assertRaises(protocol.Refused):
                protocol.devtools_uri(value, VM)


class TranscriptTests(unittest.TestCase):
    def test_version_request_and_reply_keep_the_original_identifier(self):
        session = protocol.DaemonTranscript()
        command = session.reserve("daemon.version")
        self.assertEqual(command, dict(id=1, method="daemon.version", params={}))
        session.feed(frame(dict(id=1, result="0.6.1")))
        self.assertEqual(session.public()["completed_commands"], 1)

    def test_reload_and_restart_are_distinct_serial_commands(self):
        session = started()
        for identifier, full in ((1, False), (2, True)):
            command = session.reserve("app.restart", full_restart=full)
            self.assertEqual(command["id"], identifier)
            self.assertEqual(command["params"], dict(appId="private-app", fullRestart=full,
                pause=False, debounce=False, reason="ci-debug-loop"))
            session.feed(frame(dict(id=identifier, result=dict(code=0, message="private detail"))))
        self.assertEqual(session.public()["completed_commands"], 2)
        self.assertFalse(session.public()["debug_loop_qualified"])

    def test_pending_command_cannot_be_reissued_or_recovered_by_a_late_reply(self):
        session = started()
        session.reserve("app.restart", full_restart=False)
        with self.assertRaises(protocol.Refused):
            session.reserve("app.restart", full_restart=False)
        with self.assertRaises(protocol.Refused):
            session.feed(frame(dict(id=1, result=dict(code=0))))
        self.assertTrue(session.public()["held"])
        self.assertEqual(session.public()["pending_commands"], 1)

    def test_uncertain_delivery_keeps_the_original_reservation(self):
        session = started()
        session.reserve("app.restart", full_restart=True)
        with self.assertRaises(protocol.Refused) as raised:
            session.uncertain(1)
        self.assertEqual(raised.exception.code, "COMMAND_UNCERTAIN")
        self.assertEqual(session.public()["pending_commands"], 1)
        with self.assertRaises(protocol.Refused):
            session.reserve("app.stop")

    def test_unknown_or_boolean_reply_id_cannot_complete_a_command(self):
        for identifier in (True, 2, "1"):
            session = started()
            session.reserve("app.restart", full_restart=False)
            with self.subTest(identifier=identifier), self.assertRaises(protocol.Refused):
                session.feed(frame(dict(id=identifier, result=dict(code=0))))
            self.assertEqual(session.public()["completed_commands"], 0)

    def test_original_command_error_and_false_zero_stay_failed_without_raw_text(self):
        for reply in (dict(error="private token and source path"), dict(result=dict(code=False)),
                      dict(result=dict(code=1, message="private diagnostics"))):
            session = started()
            session.reserve("app.restart", full_restart=False)
            with self.subTest(reply=reply), self.assertRaises(protocol.Refused) as raised:
                session.feed(frame(dict(id=1, **reply)))
            self.assertNotIn("private", str(raised.exception))
            self.assertTrue(session.public()["held"])

    def test_replaced_application_or_service_keeps_the_session_held(self):
        changes = [event("app.start", appId="replacement", deviceId="windows", supportsRestart=True),
            event("app.log", appId="replacement", log="private"),
            event("app.debugPort", appId="private-app", port=43433, wsUri=VM.replace("43432", "43433"))]
        for change in changes:
            session = started()
            with self.assertRaises(protocol.Refused):
                session.feed(change)
            self.assertTrue(session.public()["held"])

    def test_devtools_availability_never_claims_attachment_or_runtime(self):
        session = started()
        session.feed(event("app.devTools", uri=DEVTOOLS))
        view = session.public()
        self.assertTrue(view["devtools_uri_seen"])
        self.assertFalse(view["runtime_qualified"])
        self.assertFalse(view["debug_loop_qualified"])
        self.assertNotIn("private", json.dumps(view))
        self.assertNotIn("127.0.0.1", json.dumps(view))

    def test_build_noise_and_private_logs_are_not_public_protocol_facts(self):
        session = started()
        session.feed(b"[1/5] Building private-source-path\n")
        session.feed(event("app.log", appId="private-app", log="private auth URL"))
        session.feed(event("daemon.logMessage", level="error", message="private path", stackTrace="private stack"))
        self.assertNotIn("private", json.dumps(session.public()))

    def test_malformed_protocol_and_output_caps_hold_without_a_fake_completion(self):
        session = started()
        with self.assertRaises(protocol.Refused):
            session.feed(b'[{"event":')
        self.assertTrue(session.public()["held"])
        for name, limit, chunks in (("MAX_LINE", 4, [b"12345"]),
                                    ("MAX_TOTAL", 6, [b"1234", b"5678"]),
                                    ("MAX_LINES", 1, [b"one", b"two"])):
            session = protocol.DaemonTranscript()
            with mock.patch.object(protocol, name, limit), self.assertRaises(protocol.Refused):
                for chunk in chunks:
                    session.feed(chunk)
            self.assertTrue(session.public()["held"])

    def test_stop_reply_event_and_shutdown_have_separate_facts(self):
        session = started()
        command = session.reserve("app.stop")
        session.feed(event("app.stop", appId="private-app"))
        session.feed(frame(dict(id=command["id"], result=True)))
        shutdown = session.reserve("daemon.shutdown")
        session.feed(frame(dict(id=shutdown["id"], result=None)))
        self.assertTrue(session.public()["app_stopped"])
        self.assertEqual(session.public()["completed_commands"], 2)
        self.assertFalse(session.public()["runtime_qualified"])

    def test_unknown_commands_and_non_windows_start_cannot_be_admitted(self):
        session = protocol.DaemonTranscript()
        with self.assertRaises(protocol.Refused):
            session.reserve("app.evaluate")
        session = protocol.DaemonTranscript()
        with self.assertRaises(protocol.Refused):
            session.feed(event("app.start", appId="private", deviceId="linux", supportsRestart=True))
