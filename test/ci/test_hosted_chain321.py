"""Finite regression cases; no node, Docker, wallet or network is started."""

import copy
import json
import os
from pathlib import Path, PureWindowsPath
import struct
import tempfile
import unittest
from unittest import mock

from tool.ci import hosted_chain321 as lab
from tool.ci import restored_lab_paths


class _WindowsLexicalPath(PureWindowsPath):
    """Absolute Windows names without consulting the host filesystem."""

    def absolute(self):
        return self


def node_config():
    return dict(DataPath="/root/.znn", GenesisFile="/root/.znn/genesis.json",
        WalletPath="/root/.znn/wallet", Producer=dict(Address="fixture", Index=0),
        Net=dict(BootstrapPeers=["/ip4/172.30.0.12/tcp/35995/p2p/" + "a" * 40],
                 Seeders=["enode://" + "b" * 128 + "@172.30.0.13:35995"],
                 ListenHost="0.0.0.0", ListenPort=35995, MinConnectedPeers=3, MinPeers=0),
        RPC=dict(EnableHTTP=True, EnableWS=True, HTTPHost="0.0.0.0",
                 WSHost="0.0.0.0", HTTPPort=35997, WSPort=35998))


class ClosedCheckpointAuthorityTests(unittest.TestCase):
    def originals(self):
        runtime = lab.Native(mock.Mock(), Path('/fixture/binary'),
                             {role: Path('/fixture') / role for role in lab.ROLES})
        runtime.stop_attempted, runtime.stop_order = True, list(lab.ROLES)
        runtime.originals = [mock.Mock(process=mock.Mock(poll=mock.Mock(return_value=0)),
            receipt=dict(exit_code=0, output_complete=True, forced=False)) for _ in lab.ROLES]
        return runtime, mock.Mock(closed=mock.Mock(return_value=True),
                                  quiescent=mock.Mock(return_value=True))

    def test_a_saved_public_report_never_authorizes_a_checkpoint(self):
        wallet = mock.Mock()
        self.assertFalse(lab.checkpoint_closed(dict(stopped=True), wallet))
        wallet.closed.assert_not_called()

    def test_all_original_handles_and_the_closed_wallet_are_required(self):
        runtime, wallet = self.originals()
        self.assertTrue(lab.checkpoint_closed(runtime, wallet))
        wallet.closed.assert_called_once()
        self.assertTrue(all(original.process.poll.called for original in runtime.originals))

    def test_receipts_cannot_heal_live_failed_incomplete_or_forced_originals(self):
        for poll in (None, 1, False):
            runtime, wallet = self.originals()
            runtime.originals[-1].process.poll.return_value = poll
            self.assertFalse(lab.checkpoint_closed(runtime, wallet))
        for key, value in (('exit_code', None), ('exit_code', False),
                           ('output_complete', False), ('forced', True)):
            runtime, wallet = self.originals()
            runtime.originals[-1].receipt[key] = value
            self.assertFalse(lab.checkpoint_closed(runtime, wallet))

    def test_partial_or_reordered_runtime_closure_is_not_reusable(self):
        for field, value in (('stop_attempted', False), ('stop_attempted', 1),
                             ('stop_order', list(reversed(lab.ROLES))), ('originals', []),
                             ('configs', {})):
            runtime, wallet = self.originals()
            setattr(runtime, field, value)
            self.assertFalse(lab.checkpoint_closed(runtime, wallet))

    def test_wallet_closure_requires_positive_identity_and_normal_exit(self):
        for value in (False, None, 1, {'closed': True}):
            runtime, wallet = self.originals()
            wallet.closed.return_value = value
            self.assertFalse(lab.checkpoint_closed(runtime, wallet))

    def test_unobservable_originals_hold_the_checkpoint_without_private_details(self):
        runtime, wallet = self.originals()
        runtime.originals[-1].process.poll.side_effect = OSError('synthetic private diagnostic')
        self.assertFalse(lab.checkpoint_closed(runtime, wallet))

    def test_normal_original_exits_cannot_replace_positive_quiescence(self):
        for value in (False, None, 1, {'complete': True}):
            runtime, wallet = self.originals()
            wallet.quiescent.return_value = value
            self.assertFalse(lab.checkpoint_closed(runtime, wallet))


class AssetGenerationTests(unittest.TestCase):
    def test_original_helper_success_keeps_the_same_timeout_and_complete_phase(self):
        raw = b''.join(lab.lab_asset_progress.PREFIX + phase.encode() + b'\n'
                       for phase in lab.lab_asset_progress.PHASES)
        commands = mock.Mock(originals=[])
        def run(*args, **kwargs):
            commands.originals.append(mock.Mock(drains=[mock.Mock(), mock.Mock(data=raw)]))
        commands.run.side_effect = run
        report = {}
        lab.make_assets(commands, Path('fixture/repo'), Path('fixture/source'), Path('fixture/out'), report)
        commands.run.assert_called_once_with(['node', str(Path('fixture/repo/tools/devnet/lab/make-assets.js')),
            str(Path('fixture/source/docker/devnet')), str(Path('fixture/out')), '--progress'],
            cwd=Path('fixture/repo'), timeout=20)
        self.assertTrue(report['asset_generation']['script_complete'])

    def test_original_timeout_is_preserved_without_retry_or_a_longer_deadline(self):
        commands = mock.Mock(originals=[])
        failure = lab.Failure('COMMAND_TIMEOUT')
        def run(*args, **kwargs):
            raw = lab.lab_asset_progress.PREFIX + b'STARTED\n'
            commands.originals.append(mock.Mock(drains=[mock.Mock(), mock.Mock(data=raw)]))
            raise failure
        commands.run.side_effect = run
        report = {}
        with self.assertRaises(lab.Failure) as raised:
            lab.make_assets(commands, Path('fixture/repo'), Path('fixture/source'), Path('fixture/out'), report)
        self.assertIs(raised.exception, failure)
        commands.run.assert_called_once()
        self.assertEqual(commands.run.call_args.kwargs['timeout'], 20)
        self.assertEqual(report['asset_generation']['phase'], 'STARTED')
        self.assertFalse(report['asset_generation']['script_complete'])


class CompilerDiagnosticTests(unittest.TestCase):
    def test_version_requirement_and_locked_modules_have_distinct_codes(self):
        self.assertEqual(lab.compiler_diagnostics(b"dependency requires go >= 1.24.0"),
                         [dict(code="GO_VERSION_REQUIRED")])
        self.assertEqual(lab.compiler_diagnostics(b"go: updates to go.mod needed"),
                         [dict(code="LOCKED_MODULE_CHANGED")])

    def test_linker_reference_retains_only_the_public_symbol(self):
        for symbol in ("runtime.stopTheWorld", "crypto/tls.cipherSuiteTLS13"):
            value = lab.compiler_diagnostics(("/fixture/private/compiler/link: invalid reference to " + symbol + "\n").encode())
            self.assertEqual(value, [dict(code="GO_LINKNAME_REFUSED", symbol=symbol)])
            self.assertNotIn("/fixture/", json.dumps(value))

    def test_unclassified_private_text_is_never_echoed(self):
        value = lab.compiler_diagnostics(b"/fixture/private/value: an unrecognized diagnostic\n")
        self.assertEqual(value, [dict(code="UNCLASSIFIED_BUILD_FAILURE")])
        self.assertNotIn("private", json.dumps(value))


class NodeSourceTests(unittest.TestCase):
    def test_reconnect_failure_classifies_the_public_assertion_without_socket_details(self):
        for error, suffix in (
            ("read tcp private-endpoint: wsarecv: An existing connection was forcibly closed", "RESET"),
            ("write tcp private-endpoint: An established connection was aborted", "ABORTED"),
            ("EOF", "EOF"), ("read tcp private-endpoint: i/o timeout", "TIMEOUT"),
            ("write error: private detail", "WRITE"), ("too many peers", "REASON"),
            ("read tcp private-eof-endpoint: private detail", "UNCLASSIFIED"),
            ("private unknown detail", "UNCLASSIFIED"),
        ):
            with self.subTest(suffix=suffix):
                result = lab.reconnect_failure_code(
                    "private-path/shutdown_test.go:381: second attempt rejected with " + error + ", want already connected\n")
                self.assertEqual(result, "GO_RECONNECT_" + suffix)
                self.assertNotIn("private", result)

    def test_reconnect_failure_requires_the_exact_public_assertion(self):
        for output in ("private EOF", "shutdown_test.go:380: second attempt rejected with EOF, want already connected",
                       "shutdown_test.go:381: another assertion EOF"):
            self.assertIsNone(lab.reconnect_failure_code(output))

    def test_reconnect_category_requires_the_original_named_parent_failure(self):
        name = "TestSameIdentityReconnectDuringGatedCleanup"
        output = "shutdown_test.go:381: second attempt rejected with EOF, want already connected\n"
        rows = [dict(Action="output", Package="github.com/zenon-network/go-zenon/p2p/legacy", Test=name, Output=output)]
        receipt = dict(exit_code=1, output_complete=True, forced=False)
        encode = lambda: b"\n".join(json.dumps(row).encode() for row in rows)
        self.assertNotIn("GO_RECONNECT_EOF", lab.shutdown_failure_observation(encode(), receipt)["codes"])
        rows.append(dict(Action="fail", Package="github.com/zenon-network/go-zenon/p2p/legacy", Test=name))
        self.assertIn("GO_RECONNECT_EOF", lab.shutdown_failure_observation(encode(), receipt)["codes"])

    def test_failed_go_test_keeps_named_facts_without_private_output(self):
        name = lab.SHUTDOWN_TESTS[0]
        events = [dict(Action="run", Package="github.com/zenon-network/go-zenon/p2p/legacy", Test=name),
            dict(Action="output", Package="github.com/zenon-network/go-zenon/p2p/legacy", Test=name,
                 Output="private-path/shutdown_test.go:123: private failure\n"),
            dict(Action="fail", Package="github.com/zenon-network/go-zenon/p2p/legacy", Test=name)]
        raw = b"\n".join(json.dumps(event).encode() for event in events)
        result = lab.shutdown_failure_observation(raw, dict(exit_code=1, output_complete=True, forced=False))
        self.assertEqual(result["status"], "COMPLETE")
        self.assertEqual(result["failed"], [name])
        self.assertEqual(result["locations"], [123])
        self.assertEqual(result["codes"], ["GO_TEST_ASSERTION"])
        self.assertNotIn("private", json.dumps(result))

    def test_go_timeout_keeps_the_active_parent_and_actual_forced_state(self):
        name = lab.SHUTDOWN_TESTS[1]
        rows = [dict(Action="run", Package="github.com/zenon-network/go-zenon/p2p/legacy", Test=name),
            dict(Action="output", Package="github.com/zenon-network/go-zenon/p2p/legacy",
                 Output="panic: test timed out after 30s\nC:\\private\\shutdown_test.go:81 +0x123\n")]
        result = lab.shutdown_failure_observation(b"\n".join(json.dumps(row).encode() for row in rows),
            dict(exit_code=1, output_complete=True, forced=True))
        self.assertEqual(result["status"], "PARTIAL")
        self.assertEqual(result["active"], [name])
        self.assertEqual(result["locations"], [81])
        self.assertTrue(result["forced"])
        self.assertIn("GO_TEST_TIMEOUT", result["codes"])

    def test_malformed_go_output_cannot_create_named_test_evidence(self):
        for raw in (b"private raw text", b'{"Action":[]}', b"x" * (lab.MIB + 1)):
            value = lab.shutdown_failure_observation(raw, dict(exit_code=1, output_complete=True, forced=False))
            self.assertEqual(value["status"], "REFUSED")
            self.assertEqual(value["passed"], [])
            self.assertEqual(value["failed"], [])

    def test_failed_go_command_is_preserved_and_never_retried_by_observation(self):
        name = lab.SHUTDOWN_TESTS[0]
        raw = json.dumps(dict(Action="fail", Package="github.com/zenon-network/go-zenon/p2p/legacy", Test=name)).encode()
        original = mock.Mock(receipt=dict(exit_code=1, output_complete=True, forced=False),
            drains=[mock.Mock(data=bytearray(raw)), mock.Mock(data=bytearray())])
        commands = mock.Mock(originals=[])
        failure = lab.Failure("COMMAND_FAILED")
        def run(*args, **kwargs):
            commands.originals.append(original)
            raise failure
        commands.run.side_effect = run
        report = {}
        with self.assertRaises(lab.Failure) as raised:
            lab.run_shutdown_tests(commands, Path("fixture"), report)
        self.assertIs(raised.exception, failure)
        commands.run.assert_called_once()
        self.assertEqual(original.receipt["exit_code"], 1)
        self.assertEqual(report["upstream_stop_failure"]["failed"], [name])

    def test_only_explicit_source_choices_are_admitted(self):
        self.assertEqual(lab.selected_node_source("original")[0], lab.NODE_SHA)
        self.assertEqual(lab.selected_node_source("upstream")[0], lab.UPSTREAM_NODE_SHA)
        self.assertEqual(lab.selected_node_source("lab-fix"), lab.NODE_SOURCES["upstream"])
        for offered in ("dev", "master", "https://example.invalid", "a" * 40, None):
            with self.subTest(offered=offered), self.assertRaises(lab.Failure):
                lab.selected_node_source(offered)

    @staticmethod
    def events():
        package = "github.com/zenon-network/go-zenon/p2p/legacy"
        return [dict(Action="pass", Package=package, Test=name) for name in lab.SHUTDOWN_TESTS] + [dict(Action="pass", Package=package)]

    def test_all_seven_original_go_tests_and_package_pass_are_required(self):
        raw = b"\n".join(json.dumps(event).encode() for event in self.events())
        result = lab.shutdown_test_result(raw)
        self.assertEqual(result, dict(passed=True, tests=list(lab.SHUTDOWN_TESTS), skips=0))

    def test_empty_missing_duplicate_skipped_or_failed_go_results_are_refused(self):
        events = self.events()
        invalid = [[], events[1:], events[:-1], events + [events[0]],
            events + [dict(Action="skip")], events + [dict(Action="fail")]]
        for offered in invalid:
            raw = b"\n".join(json.dumps(event).encode() for event in offered)
            with self.subTest(events=len(offered)), self.assertRaises(lab.Failure):
                lab.shutdown_test_result(raw)
        with self.assertRaises(lab.Failure):
            lab.shutdown_test_result(b"private-path: not a Go JSON event")

    def test_raw_test_output_is_ignored_in_the_finite_projection(self):
        events = [dict(Action="output", Output="private-path and private-input")] + self.events()
        result = lab.shutdown_test_result(b"\n".join(json.dumps(event).encode() for event in events))
        self.assertNotIn("private", json.dumps(result))


class RuntimeDiagnosticTests(unittest.TestCase):
    def test_shutdown_projection_keeps_only_finite_stage_codes(self):
        raw = (b'private-path msg="Stopping znnd ..."\n'
               b'msg="stopping p2p server ..."\nmsg="HTTP server stopped" endpoint=private\n'
               b'msg="releasing dataDir lock ..."\nmsg="Failed to stop node" reason=private')
        result = lab.node_diagnostics(raw)
        self.assertEqual(set(result), {"NODE_STOP_REQUESTED", "NODE_P2P_STOP_REQUESTED",
            "NODE_HTTP_STOPPED", "NODE_DATA_LOCK_RELEASE_REQUESTED", "NODE_STOP_FAILED"})
        self.assertNotIn("private", json.dumps(result))

    def test_owned_log_files_are_bounded_and_never_returned_as_text(self):
        calls = []
        def read(path):
            calls.append(path)
            return b'private-path msg="stopping p2p server ..."'
        with mock.patch.object(lab, "directories"), mock.patch.object(lab, "regular", side_effect=read):
            result = lab.native_log_projection(Path("fixture"))
        self.assertEqual(calls, [Path("fixture/log/zenon.log"), Path("fixture/log/error/zenon.error.log")])
        self.assertEqual(result["status"], "READ")
        self.assertEqual(result["codes"], ["NODE_P2P_STOP_REQUESTED"])
        self.assertNotIn("private", json.dumps(result))
        self.assertTrue(all(set(item) == {"kind", "bytes", "sha256"} for item in result["files"]))

    def test_missing_and_refused_logs_keep_honest_distinct_status(self):
        for error, status in ((FileNotFoundError(), "MISSING"), (lab.Failure("STORAGE_REFUSED"), "REFUSED")):
            with mock.patch.object(lab, "directories"), mock.patch.object(lab, "regular", side_effect=error):
                result = lab.native_log_projection(Path("fixture"))
            self.assertEqual(result["status"], status)
            self.assertEqual(result["codes"], [])

    def test_original_wire_codes_are_preserved_without_exception_text(self):
        for code in ("HTTP_REFUSED", "WS_REFUSED", "FRONTIER_REFUSED", "CLOSE_UNKNOWN"):
            self.assertEqual(lab.failure_code(lab.wire_policy.Refused(code)), code)
        self.assertEqual(lab.failure_code(ValueError("/fixture/private/value")), "INTERNAL_ERROR")

    def test_node_log_projection_keeps_categories_and_omits_private_text(self):
        result = lab.node_diagnostics(b"/fixture/private/value: permission denied\npanic: fixture")
        self.assertEqual(set(result), {"NODE_STORAGE_REFUSED", "NODE_PANIC"})
        self.assertNotIn("private", json.dumps(result))
        self.assertEqual(lab.node_diagnostics(b"using key file /fixture/private/value"), [])

    def test_docker_state_requires_an_original_created_resource(self):
        runtime = lab.Docker(mock.Mock(), Path("fixture"), {}, "fixture")
        runtime.created = ["fixture-original"]
        item = dict(Id="fixture-original", State=dict(Running=False, ExitCode=1, OOMKilled=False))
        runtime.record_state(item, "before_stop")
        self.assertEqual(runtime.states, [dict(phase="before_stop", role="pillar", running=False,
                                               exit_code=1, oom_killed=False)])
        item["Id"] = "unowned"
        with self.assertRaises(lab.Failure):
            runtime.record_state(item, "before_stop")

    def test_wire_cleanup_cannot_replace_the_first_observed_failure(self):
        http, ws = mock.Mock(), mock.Mock()
        ws.connect.side_effect = lab.wire_policy.Refused("WS_REFUSED")
        ws.close.side_effect = lab.wire_policy.Refused("CLOSE_UNKNOWN")
        report = dict(error_codes=[])
        with mock.patch.object(lab.socket, "create_connection", return_value=mock.MagicMock()), \
                mock.patch.object(lab, "make_transports", return_value=(object(), object())), \
                mock.patch.object(lab.wire_policy, "HttpRpc", return_value=http), \
                mock.patch.object(lab.wire_policy, "WsRpc", return_value=ws), \
                self.assertRaises(lab.wire_policy.Refused) as result:
            lab.observe(mock.Mock(), Path("fixture"), report)
        self.assertEqual(result.exception.code, "WS_REFUSED")
        self.assertEqual(report["error_codes"], ["CLOSE_UNKNOWN"])
        http.close.assert_called_once_with()
        ws.close.assert_called_once_with()


class StaticBinaryTests(unittest.TestCase):
    @staticmethod
    def elf(kinds=(1, 7)):
        raw = bytearray(64 + 56 * len(kinds))
        raw[:7] = b"\x7fELF\x02\x01\x01"
        struct.pack_into("<HHI", raw, 16, 2, 62, 1)
        struct.pack_into("<Q", raw, 32, 64)
        struct.pack_into("<HH", raw, 54, 56, len(kinds))
        for index, kind in enumerate(kinds):
            struct.pack_into("<I", raw, 64 + 56 * index, kind)
        return bytes(raw)

    def test_static_amd64_executable_is_accepted_without_execution(self):
        self.assertTrue(lab.static_linux_binary(self.elf()))

    def test_interpreter_or_dynamic_section_cannot_enter_scratch_image(self):
        for kind in (2, 3):
            with self.subTest(kind=kind), self.assertRaises(lab.Failure):
                lab.static_linux_binary(self.elf((1, kind)))

    def test_wrong_architecture_or_shared_object_is_refused(self):
        for offset, value in ((16, 3), (18, 183)):
            raw = bytearray(self.elf())
            struct.pack_into("<H", raw, offset, value)
            with self.assertRaises(lab.Failure):
                lab.static_linux_binary(bytes(raw))

    def test_truncated_or_unbounded_program_headers_are_refused(self):
        raw = bytearray(self.elf())
        struct.pack_into("<H", raw, 56, 65535)
        for value in (bytes(raw), self.elf()[:-1], b"MZ" + b"\0" * 70):
            with self.assertRaises(lab.Failure):
                lab.static_linux_binary(value)


class KeyfileDeploymentTests(unittest.TestCase):
    @staticmethod
    def source():
        name = "z1" + "a" * 38
        value = dict(Path="/root/.znn/wallet/" + name, baseAddress=name, version=1, timestamp=1,
            crypto=dict(cipherName="aes-256-gcm", kdf="argon2.IDKey", cipherData="0xabcdef",
                        nonce="0x123456", argon2Params=dict(salt="0x789abc")))
        return name, value

    def test_only_embedded_path_moves_and_crypto_bytes_remain_equal(self):
        name, value = self.source()
        raw = json.dumps(value).encode()
        for parent in ("/data/wallet/", "C:\\fixture\\pillar\\wallet\\"):
            result = json.loads(lab.relocated_keyfile(raw, name, parent + name))
            self.assertEqual(result["Path"], parent + name)
            self.assertEqual({k: v for k, v in result.items() if k != "Path"},
                             {k: v for k, v in value.items() if k != "Path"})
            self.assertEqual(json.dumps(value).encode(), raw)

    def test_another_profile_address_or_unknown_field_cannot_be_adopted(self):
        name, value = self.source()
        for field, changed in (("Path", "/fixture/private/wallet/" + name),
                               ("baseAddress", "/fixture/private/value"), ("extra", "fixture")):
            source = dict(value)
            source[field] = changed
            with self.assertRaises(lab.Failure):
                lab.relocated_keyfile(json.dumps(source).encode(), name, "/data/wallet/" + name)

    def test_committed_filename_can_differ_from_the_preserved_base_address(self):
        name, value = self.source()
        value["baseAddress"] = "z1" + "b" * 38
        result = json.loads(lab.relocated_keyfile(json.dumps(value).encode(), name, "/data/wallet/" + name))
        self.assertEqual(result["baseAddress"], value["baseAddress"])
        self.assertEqual(result["crypto"], value["crypto"])
        self.assertEqual(result["Path"], "/data/wallet/" + name)

    def test_malformed_fixture_or_changed_version_is_refused(self):
        name, value = self.source()
        value["version"] = 2
        for raw in (b"not-json", json.dumps(value).encode()):
            with self.assertRaises(lab.Failure):
                lab.relocated_keyfile(raw, name, "/data/wallet/" + name)


class ConfigurationTests(unittest.TestCase):
    def test_native_bootstrap_and_seeder_remain_on_loopback(self):
        result = lab.configuration(node_config(), "pillar", Path("fixture"), "native")
        self.assertIn("/ip4/127.0.0.1/tcp/45992/p2p/", result["Net"]["BootstrapPeers"][0])
        self.assertTrue(result["Net"]["Seeders"][0].endswith("@127.0.0.1:45993"))
        self.assertNotIn("172.30.0.", json.dumps(result))
        self.assertEqual(result["Net"]["MinConnectedPeers"], 3)
        self.assertEqual(result["Producer"], node_config()["Producer"])

    def test_each_native_role_has_a_distinct_loopback_port(self):
        ports = {lab.configuration(node_config(), role, Path("fixture"), "native")["Net"]["ListenPort"]
                 for role in lab.ROLES}
        self.assertEqual(len(ports), 5)
        for role in lab.ROLES:
            cfg = lab.configuration(node_config(), role, Path("fixture"), "native")
            self.assertEqual(cfg["Net"]["ListenHost"], "127.0.0.1")
            self.assertEqual(cfg["RPC"]["HTTPHost"], "127.0.0.1" if role == "rpc" else "")
            self.assertEqual(cfg["RPC"]["WSHost"], "127.0.0.1" if role == "rpc" else "")

    def test_only_rpc_role_exposes_http_and_websocket(self):
        for backend in ("native", "docker"):
            for role in lab.ROLES:
                cfg = lab.configuration(node_config(), role, Path("fixture"), backend)
                self.assertIs(cfg["RPC"]["EnableHTTP"], role == "rpc")
                self.assertIs(cfg["RPC"]["EnableWS"], role == "rpc")
                self.assertEqual(bool(cfg["RPC"]["HTTPHost"]), role == "rpc")
                self.assertEqual(bool(cfg["RPC"]["WSHost"]), role == "rpc")

    def test_docker_keeps_its_internal_ports_and_moves_the_subnet(self):
        cfg = lab.configuration(node_config(), "rpc", Path("fixture"), "docker")
        self.assertIn("172.37.0.12/tcp/35995", cfg["Net"]["BootstrapPeers"][0])
        self.assertEqual((cfg["RPC"]["HTTPPort"], cfg["RPC"]["WSPort"]), (35997, 35998))
        self.assertEqual(cfg["GenesisFile"], "/data/genesis.json")

    def test_windows_native_configs_round_trip_through_the_actual_copy_binder(self):
        fields = ('DataPath', 'GenesisFile', 'WalletPath')
        with mock.patch.object(restored_lab_paths, 'Path', _WindowsLexicalPath):
            for role in lab.ROLES:
                with self.subTest(role=role):
                    original = _WindowsLexicalPath('C:/synthetic/original') / role
                    restored = _WindowsLexicalPath('C:/synthetic/restored') / role
                    deployed = lab.configuration(node_config(), role, original, 'native')
                    raw = json.dumps(deployed).encode('ascii')
                    result = json.loads(restored_lab_paths.config_bytes(raw, original, restored))
                    self.assertEqual(tuple(result[field] for field in fields),
                        (str(restored), str(restored / 'genesis.json'), str(restored / 'wallet')))
                    self.assertEqual({k: v for k, v in result.items() if k not in fields},
                        {k: v for k, v in deployed.items() if k not in fields})
                    self.assertEqual(json.loads(raw), deployed)

    def test_docker_paths_stay_posix_with_a_windows_checkout_path(self):
        cfg = lab.configuration(node_config(), 'rpc',
            _WindowsLexicalPath('C:/synthetic/checkout'), 'docker')
        self.assertEqual((cfg['DataPath'], cfg['GenesisFile'], cfg['WalletPath']),
            ('/data', '/data/genesis.json', '/data/wallet'))

    def test_input_configuration_is_not_mutated(self):
        source = node_config()
        before = copy.deepcopy(source)
        lab.configuration(source, "rpc", Path("fixture"), "native")
        self.assertEqual(source, before)

    def test_public_dns_alias_or_additional_path_is_refused(self):
        candidates = ["https://example.invalid/172.30.0.12/tcp/35995/p2p/" + "a" * 40,
                      "/dns4/example.invalid/tcp/35995/p2p/" + "a" * 40,
                      "/ip4/172.30.0.12/tcp/35995/p2p/" + "a" * 40 + "/extra"]
        for peer in candidates:
            source = node_config()
            source["Net"]["BootstrapPeers"] = [peer]
            for backend in ("native", "docker"):
                with self.subTest(peer=peer, backend=backend), self.assertRaises(lab.Failure):
                    lab.configuration(source, "rpc", Path("fixture"), backend)

    def test_foreign_subnet_or_wrong_port_is_refused(self):
        for old, new in (("172.30.0.12", "172.31.0.12"), ("35995", "35996")):
            source = node_config()
            source["Net"]["BootstrapPeers"][0] = source["Net"]["BootstrapPeers"][0].replace(old, new)
            with self.assertRaises(lab.Failure):
                lab.configuration(source, "rpc", Path("fixture"), "native")

    def test_non_original_seeder_is_refused(self):
        source = node_config()
        source["Net"]["Seeders"] = ["enode://" + "b" * 128 + "@example.invalid:35995"]
        with self.assertRaises(lab.Failure):
            lab.configuration(source, "rpc", Path("fixture"), "native")


class DockerShutdownTests(unittest.TestCase):
    def runtime(self, *, changed=None, exit_137=False, command_failed=False, receipt=None):
        commands = mock.Mock(originals=[])
        runtime = lab.Docker(commands, Path("fixture/znnd"), {}, "fixture")
        runtime.image = "original-image"
        runtime.created = [format(index + 1, "064x") for index in range(5)]
        runtime.started = list(runtime.created)
        events, stopped = [], False
        def inspect(kind, identifier):
            events.append(("inspect", identifier, stopped))
            return dict(Id=identifier, Image="changed-image" if identifier == changed else runtime.image,
                Config=dict(Labels={"org.zenon.ci321.owner": runtime.owner}),
                State=dict(Running=not stopped, ExitCode=137 if exit_137 and identifier == runtime.created[-1] else 0,
                           OOMKilled=False))
        def call(*args, **kwargs):
            nonlocal stopped
            events.append((args[0], args, kwargs))
            terminal = dict(exit_code=1 if command_failed else 0, output_complete=True, forced=False)
            if receipt is not None and args[0] == "stop":
                terminal.update(receipt)
            commands.originals.append(mock.Mock(receipt=terminal,
                drains=[mock.Mock(data=bytearray()), mock.Mock(data=bytearray())]))
            if args[0] == "stop":
                stopped = True
                if command_failed:
                    raise lab.Failure("COMMAND_FAILED")
            return b""
        runtime.inspect, runtime.call = inspect, call
        return runtime, events

    def test_every_original_is_verified_before_one_stop_command_with_unchanged_limits(self):
        runtime, events = self.runtime()
        runtime.stop()
        stop = next(index for index, event in enumerate(events) if event[0] == "stop")
        self.assertEqual([event[1] for event in events[:stop] if event[0] == "inspect"], list(reversed(runtime.created)))
        self.assertEqual(events[stop], ("stop", ("stop", "--time", "20", *reversed(runtime.created)), dict(timeout=30)))
        self.assertEqual(sum(event[0] == "stop" for event in events), 1)
        self.assertEqual(len([event for event in events[stop + 1:] if event[0] == "inspect"]), 5)
        self.assertEqual(runtime.shutdown, dict(mode="single_verified_stop_command", roles=list(reversed(lab.ROLES)),
            exit_code=0, output_complete=True, forced=False))

    def test_original_exit_137_stays_failed_and_a_second_stop_is_refused(self):
        runtime, events = self.runtime(exit_137=True)
        for _ in range(2):
            with self.assertRaises(lab.Failure):
                runtime.stop()
        self.assertEqual(sum(event[0] == "stop" for event in events), 1)
        self.assertIn(137, [item["exit_code"] for item in runtime.states if item["phase"] == "after_stop"])

    def test_changed_resource_is_excluded_from_the_batch_and_keeps_failure(self):
        changed = format(5, "064x")
        runtime, events = self.runtime(changed=changed)
        with self.assertRaises(lab.Failure):
            runtime.stop()
        stop = next(event for event in events if event[0] == "stop")
        self.assertNotIn(changed, stop[1])
        self.assertEqual(len(runtime.shutdown["roles"]), 4)

    def test_failed_stop_command_keeps_its_receipt_and_still_observes_each_original(self):
        runtime, events = self.runtime(command_failed=True)
        with self.assertRaises(lab.Failure):
            runtime.stop()
        self.assertEqual(runtime.shutdown["exit_code"], 1)
        self.assertEqual(sum(item["phase"] == "after_stop" for item in runtime.states), 5)
        self.assertEqual(sum(event[0] == "stop" for event in events), 1)

    def test_incomplete_or_forced_command_cannot_qualify_five_zero_exits(self):
        for receipt in (dict(output_complete=False), dict(forced=True)):
            runtime, _ = self.runtime(receipt=receipt)
            with self.subTest(receipt=receipt), self.assertRaises(lab.Failure):
                runtime.stop()


class OriginalHandleTests(unittest.TestCase):
    def test_panic_observation_cannot_turn_original_exit_two_into_success(self):
        runtime = lab.Native(mock.Mock(), Path("fixture"), {})
        runtime.originals = [mock.Mock(receipt=dict(exit_code=0, output_complete=True, forced=False), drains=[])
                             for _ in lab.ROLES]
        original = runtime.originals[1]
        original.receipt["exit_code"] = 2
        original.drains = [self.drain(b"panic: private failure\n\ngoroutine 1 [running]:\n"
            b"\tgithub.com/zenon-network/go-zenon/wallet/manager.go:257 +0x123\n")]
        with self.assertRaises(lab.Failure):
            runtime.stop()
        self.assertEqual(original.receipt["node_panic"]["status"], "CAPTURED")
        self.assertEqual(original.receipt["exit_code"], 2)
        self.assertNotIn("private", json.dumps(original.receipt["node_panic"]))
        for item in runtime.originals:
            item.stop.assert_called_once_with()

    def test_failed_original_signal_is_retained_and_never_reissued(self):
        process = mock.Mock()
        process.poll.side_effect = [None, 0]
        process.send_signal.side_effect = OSError(5, "fixture signal refusal")
        original = self.original(process, [self.drain(), self.drain()])
        with self.assertRaises(OSError):
            original.request_stop()
        with self.assertRaises(lab.Failure):
            original.stop()
        process.send_signal.assert_called_once()
        process.kill.assert_called_once_with()
        self.assertEqual(original.receipt["stop_code"], "SIGNAL_OS_ERROR")
        self.assertTrue(original.receipt["forced"])

    def test_native_requests_all_joining_peers_before_waiting_for_any(self):
        events = []
        originals = []
        for index in range(5):
            item = mock.Mock(receipt=dict(exit_code=0, output_complete=True, forced=False), drains=[])
            item.request_stop.side_effect = lambda index=index: events.append(("request", index))
            def finish(index=index):
                self.assertEqual(sum(kind == "request" for kind, _ in events), 5)
                events.append(("wait", index))
            item.stop.side_effect = finish
            originals.append(item)
        runtime = lab.Native(mock.Mock(), Path("fixture"), {})
        runtime.originals = originals
        runtime.stop()
        self.assertEqual(events, [("request", i) for i in range(5)] + [("wait", i) for i in range(5)])
        self.assertEqual(runtime.stop_order, list(lab.ROLES))
        for item in originals:
            item.request_stop.assert_called_once_with()

    def test_native_stop_is_one_attempt_even_after_all_originals_exit_zero(self):
        runtime = lab.Native(mock.Mock(), Path("fixture"), {})
        runtime.originals = [mock.Mock(receipt=dict(exit_code=0, output_complete=True, forced=False), drains=[])
                             for _ in lab.ROLES]
        runtime.stop()
        with self.assertRaises(lab.Failure):
            runtime.stop()
        for item in runtime.originals:
            item.stop.assert_called_once_with()

    def original(self, process, drains):
        value = object.__new__(lab.Original)
        value.process, value.drains = process, drains
        value.forced, value.receipt = False, None
        return value

    def drain(self, data=b"", finish=True):
        value = mock.Mock(data=bytearray(data), count=len(data), error=None)
        value.overflow.is_set.return_value = False
        value.finish.return_value = finish
        return value

    def test_both_drains_are_finished_after_one_reports_incomplete(self):
        drains = [self.drain(finish=False), self.drain()]
        original = self.original(mock.Mock(poll=mock.Mock(return_value=0)), drains)
        with self.assertRaises(lab.Failure):
            original.finish()
        for drain in drains:
            drain.finish.assert_called_once_with(3)
        self.assertFalse(original.receipt["output_complete"])

    def test_forced_exit_cannot_be_successful_even_with_zero_exit(self):
        original = self.original(mock.Mock(poll=mock.Mock(return_value=0)), [self.drain(), self.drain()])
        original.forced = True
        with self.assertRaises(lab.Failure):
            original.finish()

    def test_terminal_failure_is_not_replaced_by_a_second_stop(self):
        original = self.original(mock.Mock(poll=mock.Mock(return_value=7)), [self.drain(), self.drain()])
        with self.assertRaises(lab.Failure):
            original.finish()
        original.stop()
        original.process.send_signal.assert_not_called()
        self.assertEqual(original.receipt["exit_code"], 7)

    def test_overflow_refuses_native_process_admission(self):
        drain = self.drain()
        drain.overflow.is_set.return_value = True
        original = self.original(mock.Mock(), [drain, self.drain()])
        with self.assertRaises(lab.Failure):
            original.healthy()

    def test_native_stop_attempts_every_original_after_one_failure(self):
        runtime = lab.Native(mock.Mock(), Path("fixture"), {})
        runtime.originals = [mock.Mock() for _ in lab.ROLES]
        runtime.originals[2].stop.side_effect = lab.Failure("STOP_UNKNOWN")
        with self.assertRaises(lab.Failure):
            runtime.stop()
        for original in runtime.originals:
            original.stop.assert_called_once_with()

    def test_running_native_process_cannot_replace_a_missing_fifth_owner(self):
        runtime = lab.Native(mock.Mock(), Path("fixture"), {})
        runtime.originals = [mock.Mock() for _ in range(4)]
        with self.assertRaises(lab.Failure):
            runtime.healthy()

    def test_prior_terminal_failure_cannot_become_success_on_a_second_stop(self):
        runtime = lab.Native(mock.Mock(), Path("fixture"), {})
        runtime.originals = [mock.Mock(receipt=dict(exit_code=0, output_complete=True, forced=False))
                             for _ in lab.ROLES]
        runtime.originals[0].receipt["exit_code"] = 7
        with self.assertRaises(lab.Failure):
            runtime.stop()


class IsolationTests(unittest.TestCase):
    def test_child_environment_excludes_tokens_and_original_profiles(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            result = lab.child_environment(root, dict(PATH="tools", GITHUB_TOKEN="private",
                ACTIONS_ID_TOKEN_REQUEST_TOKEN="private", HOME="original", USERPROFILE="original"))
            self.assertNotIn("GITHUB_TOKEN", result)
            self.assertNotIn("ACTIONS_ID_TOKEN_REQUEST_TOKEN", result)
            self.assertNotIn("original", result.values())
            self.assertEqual(result["CGO_ENABLED"], "1")
            self.assertEqual(result["CC"], "gcc")
            for field in ("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "TMP", "TEMP"):
                self.assertTrue(Path(result[field]).is_relative_to(root))

    def test_regular_input_refuses_a_hard_link(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "first").write_bytes(b"fixture")
            try:
                os.link(root / "first", root / "second")
            except (OSError, NotImplementedError):
                self.skipTest("Hard links unavailable")
            with self.assertRaises(lab.Failure):
                lab.regular(root / "first")

    def test_real_wallet_or_non_actions_run_is_refused_before_any_launch(self):
        with mock.patch.dict(lab.os.environ, {}, clear=True), mock.patch.object(lab, "Original") as launch:
            with self.assertRaises(lab.Failure):
                lab.run("native")
            launch.assert_not_called()

    def test_self_hosted_runner_cannot_use_the_lower_fixture_floor(self):
        parent = dict(GITHUB_ACTIONS="true", GITHUB_EVENT_NAME="workflow_dispatch",
            GITHUB_REPOSITORY="edgepillar/syrius", GITHUB_SHA="a" * 40,
            SYRIUS_HOSTED_RUNNER="self-hosted")
        with mock.patch.dict(lab.os.environ, parent, clear=True), mock.patch.object(lab, "Original") as launch:
            with self.assertRaises(lab.Failure) as result:
                lab.run("native")
            self.assertEqual(result.exception.code, "ENVIRONMENT_REFUSED")
            launch.assert_not_called()

    def test_port_preflight_closes_all_originals_after_a_conflict(self):
        sockets = [mock.Mock(), mock.Mock()]
        sockets[1].bind.side_effect = OSError("fixture")
        with mock.patch.object(lab.socket, "socket", side_effect=sockets), self.assertRaises(lab.Failure):
            lab.preflight_ports("native")
        for original in sockets:
            original.close.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
