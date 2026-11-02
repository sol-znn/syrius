"""Injected diagnostic cases; no process, socket, thread or disk scratch."""

from pathlib import Path
import subprocess
import hashlib
import unittest
from unittest import mock

from tool.ci import hosted_chain321 as lab
from tool.ci import native_stack_probe as probe


def stack():
    return (b"goroutine 10 [select]:\nnet/http.(*Server).Shutdown(0xprivate)\n"
            b"private-path.go:1\ngithub.com/zenon-network/go-zenon/node.(*httpServer).doStop(0xprivate)\n"
            + probe.OWNER + b"0xprivate)\nprivate-path.go:2\n\n"
            b"goroutine 11 [select]:\nprivate-owner()\nprivate-path.go:3\n")


class StackProbeTests(unittest.TestCase):
    @staticmethod
    def syncer_worker(path=b"/private/root/protocol/downloader/downloader.go", line=321, header=b"chan receive, 1 minutes"):
        return (b"goroutine 20 [" + header + b"]:\n"
            b"github.com/zenon-network/go-zenon/protocol/downloader.(*Downloader).cancel(0xprivate)\n"
            + path + b":" + str(line).encode() + b" +0xprivate\n"
            b"github.com/zenon-network/go-zenon/protocol.(*ProtocolManager).Start.func1()\n"
            b"/private/root/protocol/handler.go:160 +0xprivate\n")

    def test_syncer_site_contains_only_public_path_digest_and_finite_facts(self):
        result = probe.project(stack() + b"\n" + self.syncer_worker())
        workers = result["protocol_workers"]
        self.assertEqual(workers["status"], "CAPTURED")
        self.assertEqual(workers["count"], 1)
        self.assertEqual(workers["items"], [dict(kind="SYNCER", state="CHAN_RECEIVE",
            package="protocol/downloader", source_path_sha256=hashlib.sha256(
                b"protocol/downloader/downloader.go").hexdigest(), line=321)])
        self.assertNotIn("private", str(result))

    def test_windows_prefix_cannot_change_the_public_source_path_digest(self):
        windows = self.syncer_worker(path=b"D:\\private\\root\\protocol\\downloader\\downloader.go")
        self.assertEqual(probe.protocol_workers(windows), probe.protocol_workers(self.syncer_worker()))

    def test_duplicate_worker_sites_keep_actual_count_and_bounded_unique_sites(self):
        raw = b"\n".join([self.syncer_worker()] * 2 + [self.syncer_worker(line=line) for line in range(400, 410)])
        result = probe.protocol_workers(raw)
        self.assertEqual(result["count"], 12)
        self.assertEqual(len(result["items"]), 4)

    def test_unknown_worker_source_or_header_refuses_all_partial_worker_facts(self):
        for raw in (self.syncer_worker(header=b"private] bad"),
                    self.syncer_worker(path=b"/private/root/other/downloader.go"),
                    self.syncer_worker(line=0), b"x" * (probe.MAX_BYTES + 1)):
            self.assertEqual(probe.protocol_workers(raw), dict(status="REFUSED", count=None, items=[]))

    def test_unrelated_frames_and_creation_notes_do_not_create_joined_worker_evidence(self):
        raw = (b"goroutine 20 [select]:\nprivate(0xprivate)\n"
            b"created by github.com/zenon-network/go-zenon/protocol.(*ProtocolManager).Start.func1()\n")
        self.assertEqual(probe.protocol_workers(raw), dict(status="EMPTY", count=0, items=[]))
        self.assertNotIn("protocol_workers", probe.project(self.syncer_worker()))

    def test_message_handler_has_its_own_kind_and_unknown_wait_is_not_echoed(self):
        raw = (b"goroutine 21 [private wait]:\n"
            b"github.com/zenon-network/go-zenon/protocol.(*ProtocolManager).handleMsg(0xprivate)\n"
            b"/private/root/protocol/handler.go:509 +0xprivate\n")
        result = probe.protocol_workers(raw)
        self.assertEqual(result["items"][0]["kind"], "MESSAGE_HANDLER")
        self.assertEqual(result["items"][0]["state"], "OTHER")
        self.assertNotIn("private", str(result))

    def test_pillar_shutdown_frames_remain_finite_without_other_goroutines(self):
        raw = (b"goroutine 10 [select]:\n"
            b"github.com/zenon-network/go-zenon/pillar.(*worker).Stop(0xprivate)\nprivate.go:1\n"
            b"github.com/zenon-network/go-zenon/pillar.(*manager).Stop(0xprivate)\nprivate.go:2\n"
            + probe.OWNER + b"0xprivate)\nprivate.go:3\n")
        value = probe.project(raw)
        self.assertEqual(value["frames"], ["PILLAR_WORKER_STOP", "PILLAR_MANAGER_STOP", "NODE_STOP"])
        self.assertNotIn("private", str(value))

    def test_changed_role_or_port_is_refused_before_any_connection(self):
        with mock.patch.object(probe.http.client, "HTTPConnection") as connection:
            for role, port in (("pillar2", probe.PORT), ("private", 46001), ("rpc", True), ("rpc", 80)):
                owner = mock.Mock(stack_debug=True, stack_role=role, stack_port=port,
                    process=mock.Mock(poll=mock.Mock(return_value=None)))
                self.assertEqual(probe.capture(owner)["status"], "REFUSED")
            connection.assert_not_called()

    def test_each_original_uses_only_its_preassigned_loopback_port(self):
        for role, port in probe.PORTS.items():
            response = mock.Mock(status=200)
            response.getheader.return_value = "identity"
            response.read1.side_effect = [stack(), b""]
            connection = mock.Mock()
            connection.getresponse.return_value = response
            owner = mock.Mock(stack_debug=True, stack_role=role, stack_port=port,
                process=mock.Mock(poll=mock.Mock(return_value=None)))
            with mock.patch.object(probe.http.client, "HTTPConnection", return_value=connection) as factory:
                self.assertEqual(probe.capture(owner)["status"], "CAPTURED")
            factory.assert_called_once_with("127.0.0.1", port, timeout=1)
            connection.close.assert_called_once()

    def test_all_diagnostic_ports_are_preflighted_and_original_sockets_close(self):
        ports = {45997, 45998, *lab.NATIVE_PORTS.values(), *probe.PORTS.values()}
        sockets = [mock.Mock() for _ in ports]
        with mock.patch.object(lab.socket, "socket", side_effect=sockets):
            lab.preflight_ports("native", stack_debug=True)
        self.assertEqual({item.bind.call_args.args[0] for item in sockets},
                         {("127.0.0.1", port) for port in ports})
        for item in sockets:
            item.close.assert_called_once()

    def test_only_actual_shutdown_block_has_allowlisted_frames(self):
        result = probe.project(stack())
        self.assertEqual(result["status"], "CAPTURED")
        self.assertEqual(result["frames"], ["HTTP_SERVER_SHUTDOWN", "NODE_HTTP_DO_STOP", "NODE_STOP"])
        self.assertNotIn("private", str(result))

    def test_unrelated_or_ambiguous_goroutines_cannot_become_original_shutdown(self):
        self.assertEqual(probe.project(b"goroutine 1 [select]:\nprivate()\n")["status"], "NO_SHUTDOWN_STACK")
        self.assertEqual(probe.project(stack() + b"\n" + stack())["status"], "AMBIGUOUS")
        self.assertEqual(probe.project(b"bad header\n" + probe.OWNER + b"0)")["status"], "REFUSED")

    def test_oversized_bytes_are_refused_before_parsing(self):
        self.assertEqual(probe.project(b"x" * (probe.MAX_BYTES + 1))["status"], "REFUSED")

    def test_disabled_or_exited_original_never_opens_a_connection(self):
        with mock.patch.object(probe.http.client, "HTTPConnection") as connection:
            for enabled, code in ((False, None), (True, 0)):
                owner = mock.Mock(stack_debug=enabled, process=mock.Mock(poll=mock.Mock(return_value=code)))
                self.assertEqual(probe.capture(owner)["status"], "UNAVAILABLE")
            connection.assert_not_called()

    def test_one_fixed_loopback_request_and_original_connection_close(self):
        response = mock.Mock(status=200)
        response.getheader.return_value = "identity"
        response.read1.side_effect = [stack(), b""]
        connection = mock.Mock()
        connection.getresponse.return_value = response
        owner = mock.Mock(stack_debug=True, stack_role="rpc", stack_port=probe.PORT, process=mock.Mock(poll=mock.Mock(return_value=None)))
        with mock.patch.object(probe.http.client, "HTTPConnection", return_value=connection) as factory:
            result = probe.capture(owner)
        factory.assert_called_once_with("127.0.0.1", 45999, timeout=1)
        connection.request.assert_called_once_with("GET", "/debug/pprof/goroutine?debug=2",
            headers={"Connection": "close", "Accept-Encoding": "identity"})
        connection.close.assert_called_once_with()
        self.assertEqual(result["status"], "CAPTURED")

    def test_redirect_is_not_followed_and_original_exit_during_read_is_unavailable(self):
        for status, polls in ((302, [None]), (200, [None, 0])):
            response = mock.Mock(status=status)
            response.getheader.return_value = "identity"
            response.read1.side_effect = [stack(), b""]
            connection = mock.Mock()
            connection.getresponse.return_value = response
            owner = mock.Mock(stack_debug=True, stack_role="rpc", stack_port=probe.PORT, process=mock.Mock(poll=mock.Mock(side_effect=polls)))
            with mock.patch.object(probe.http.client, "HTTPConnection", return_value=connection):
                result = probe.capture(owner)
            self.assertNotEqual(result["status"], "CAPTURED")
            connection.close.assert_called_once_with()
            connection.request.assert_called_once()

    def test_close_failure_cannot_leave_a_positive_probe(self):
        response = mock.Mock(status=200)
        response.getheader.return_value = "identity"
        response.read1.side_effect = [stack(), b""]
        connection = mock.Mock()
        connection.getresponse.return_value = response
        connection.close.side_effect = OSError("private")
        owner = mock.Mock(stack_debug=True, stack_role="rpc", stack_port=probe.PORT, process=mock.Mock(poll=mock.Mock(return_value=None)))
        with mock.patch.object(probe.http.client, "HTTPConnection", return_value=connection):
            result = probe.capture(owner)
        self.assertEqual(result["status"], "REFUSED")
        self.assertEqual(result["frames"], [])

    def test_diagnostic_flags_are_default_off_and_bind_each_original_role(self):
        for enabled in (False, True):
            runtime = lab.Native(mock.Mock(env={}), Path("fixture/znnd"),
                {role: Path("fixture") / role for role in lab.ROLES}, stack_debug=enabled)
            originals = [mock.Mock() for _ in lab.ROLES]
            with mock.patch.object(lab, "Original", side_effect=originals) as factory:
                runtime.start()
            calls = factory.call_args_list
            self.assertEqual(len(calls), 5)
            for role, original, call in zip(lab.ROLES, originals, calls):
                self.assertEqual("--pprof" in call.args[0], enabled)
                self.assertEqual(original.stack_debug, enabled)
                if enabled:
                    self.assertEqual(call.args[0][-4:], ["--pprof.addr", "127.0.0.1", "--pprof.port", str(probe.PORTS[role])])
                    self.assertEqual((original.stack_role, original.stack_port), (role, probe.PORTS[role]))

    def test_probe_error_cannot_prevent_forced_original_cleanup_or_create_success(self):
        owner = object.__new__(lab.Original)
        owner.process = mock.Mock()
        owner.process.poll.side_effect = [None, None]
        owner.process.wait.side_effect = [subprocess.TimeoutExpired("fixture", 30), None]
        owner.receipt, owner.forced, owner.stack_debug = None, False, True
        owner.finish = mock.Mock()
        with mock.patch.object(probe, "capture", side_effect=ValueError("private")):
            owner.stop()
        owner.process.kill.assert_called_once_with()
        self.assertTrue(owner.forced)
        self.assertEqual(owner.stop_code, "WAIT_TIMEOUT")
        self.assertEqual(owner.stack_probe["status"], "UNAVAILABLE")
