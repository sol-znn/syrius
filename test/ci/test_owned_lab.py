"""Finite injected source-policy cases; no Docker, network, process or wallet.

These fixtures deliberately are not native evidence or source-build provenance.
"""

import base64
from dataclasses import replace
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import unittest


SOURCE = Path(__file__).resolve().parents[2] / "tools/devnet/lab/owned_lab.py"
SPEC = importlib.util.spec_from_file_location("owned_lab", SOURCE)
lab = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = lab
SPEC.loader.exec_module(lab)


def digest(number):
    return "%064x" % number


PINS = lab.Pins(
    application_sha="1" * 40, application_tree="2" * 40, node_tree="3" * 40,
    image_id="sha256:" + digest(4), genesis_sha256=digest(5),
    genesis_momentum_hash=digest(6), assets_sha256=digest(7),
    configs_sha256=tuple(digest(value) for value in range(8, 13)),
    build_context_sha256=digest(13), dockerfile_sha256=digest(14),
    base_image_ids=("sha256:" + digest(15),),
)
LIMITS = lab.Limits(total=30, request=1, command=2, close=.2, stop=2,
                    poll=.1, samples=3, exit_polls=2)
PRIVATE = "/private/owner/profile secret-token private-raw-error"


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


def command(**changes):
    return replace(lab.CommandReceipt(object(), 0, True, True), **changes)


class Build:
    def __init__(self):
        self.result = "witness"
        self.ok = True
        self.calls = []

    def verify(self, pins, deadline):
        self.calls.append(("verify", deadline))
        if self.result == "witness":
            return lab.BuildWitness(pins, object())
        return self.result

    def current(self, witness, deadline):
        self.calls.append(("current", deadline))
        return self.ok


class Storage:
    def __init__(self):
        self.receipt = lab.StorageReceipt(object(), tuple(object() for _ in range(5)), True)
        self.ok = True
        self.reservations = 0

    def reserve(self, pins, deadline):
        self.reservations += 1
        return self.receipt

    def current(self, receipt, deadline):
        return receipt is self.receipt and self.ok


class Runtime:
    def __init__(self):
        self.daemon = "private-original-daemon"
        self.conflicts = ()
        self.network = None
        self.created = []
        self.started = []
        self.states = {}
        self.calls = []
        self.network_hook = None
        self.create_hook = None
        self.start_hook = None
        self.inspect_hook = None
        self.stop_hook = None

    def preflight(self, plan, deadline):
        self.plan = plan
        self.calls.append(("preflight", plan))
        return lab.Preflight(self.daemon, self.conflicts)

    def create_network(self, spec, deadline):
        self.calls.append(("network", spec))
        self.network = lab.Created(spec, digest(101), self.daemon, command())
        return self.network

    def inspect_network(self, created, deadline):
        members = tuple(value.created.resource_id for value in self.started
                        if self.states[value.created.resource_id].running)
        state = lab.NetworkState(self.network.resource_id, self.daemon,
                                 self.network.request.name, lab.SUBNET, members)
        return self.network_hook(state) if self.network_hook else state

    def create_container(self, spec, deadline):
        self.calls.append(("create", spec))
        value = lab.Created(spec, digest(102 + len(self.created)), self.daemon, command())
        self.created.append(value)
        return self.create_hook(value) if self.create_hook else value

    def start(self, created, deadline):
        self.calls.append(("start", created))
        spec = created.request
        value = lab.Started(created, "private-start-" + spec.role, command())
        self.started.append(value)
        self.states[created.resource_id] = lab.ContainerState(
            created.resource_id, self.daemon, spec.image_id, spec.network_id,
            spec.ip, spec.storage, spec.ports, value.start_id, True, 0,
            mounts=(spec.storage,),
        )
        return self.start_hook(value) if self.start_hook else value

    def inspect_container(self, started, deadline):
        state = self.states[started.created.resource_id]
        return self.inspect_hook(started, state) if self.inspect_hook else state

    def request_stop(self, started, deadline):
        self.calls.append(("stop", started))
        if self.stop_hook:
            return self.stop_hook(started)
        self.states[started.created.resource_id] = replace(
            self.states[started.created.resource_id], running=False, exit_code=0,
            finished_id="private-finished-" + started.created.request.role,
        )
        return command()


def momentum(height, timestamp=None, chain=321, hash_value=None):
    return {"chainIdentifier": chain, "height": height,
            "timestamp": timestamp if timestamp is not None else height + 100,
            "hash": hash_value if hash_value is not None else digest(height + 1000)}


GENESIS = momentum(1, hash_value=PINS.genesis_momentum_hash)


def frame(payload, opcode=1, final=True):
    size = len(payload)
    first = (128 if final else 0) | opcode
    if size < 126:
        header = bytes((first, size))
    elif size < 65536:
        header = bytes((first, 126)) + size.to_bytes(2, "big")
    else:
        header = bytes((first, 127)) + size.to_bytes(8, "big")
    return header + payload


class Server:
    def __init__(self, canonical):
        self.canonical = canonical
        self.frontiers = [momentum(10), momentum(11)]
        self.index = 0
        self.genesis = GENESIS
        self.hook = None
        self.calls = []

    def reply(self, request):
        self.calls.append(request)
        method, params = request["method"], request["params"]
        if method == "ledger.getMomentumsByHeight":
            result = {"count": 1, "list": [self.genesis]}
        elif method == "ledger.getFrontierMomentum":
            result = self.frontiers[min(self.index, len(self.frontiers) - 1)]
            self.index += 1
        elif method == "ledger.getMomentumByHash":
            result = self.canonical.get(params[0])
        else:
            raise AssertionError("unexpected RPC")
        reply = {"jsonrpc": "2.0", "id": request["id"], "result": result}
        return self.hook(request, reply) if self.hook else reply


class Wire:
    def __init__(self, transport):
        self.transport = transport
        self.incoming = bytearray()
        self.writes = []
        self.close_count = 0
        self.close_deadlines = []
        self.closed = False

    def write(self, data, deadline):
        self.writes.append(data)
        if not self.transport.ws:
            request = json.loads(data.split(b"\r\n\r\n", 1)[1])
            body = json.dumps(self.transport.server.reply(request), separators=(",", ":")).encode()
            if self.transport.http_body_hook:
                body = self.transport.http_body_hook(body)
            if self.transport.chunked:
                response = (b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                            b"Transfer-Encoding: chunked\r\n\r\n" +
                            ("%x\r\n" % len(body)).encode() + body + b"\r\n0\r\n\r\n")
            else:
                response = (b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                            + ("Content-Length: %d\r\n\r\n" % len(body)).encode() + body)
            self.incoming.extend(self.transport.http_hook(response)
                                 if self.transport.http_hook else response)
        elif data.startswith(b"GET "):
            key = next(line.split(b": ", 1)[1] for line in data.split(b"\r\n")
                       if line.startswith(b"Sec-WebSocket-Key:"))
            accept = base64.b64encode(hashlib.sha1(
                key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest())
            response = (b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                        b"Connection: keep-alive, Upgrade\r\nSec-WebSocket-Accept: "
                        + accept + b"\r\n\r\n")
            self.incoming.extend(self.transport.upgrade_hook(response)
                                 if self.transport.upgrade_hook else response)
        else:
            self.assert_client_frame(data)
            size, offset = data[1] & 127, 2
            if size == 126:
                size, offset = int.from_bytes(data[2:4], "big"), 4
            mask, payload = data[offset:offset + 4], data[offset + 4:]
            payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
            if data[0] & 15 == 10:
                return
            if len(payload) != size:
                raise AssertionError("bad client frame size")
            request = json.loads(payload)
            body = json.dumps(self.transport.server.reply(request), separators=(",", ":")).encode()
            self.incoming.extend(self.transport.frame_hook(body)
                                 if self.transport.frame_hook else frame(body))

    @staticmethod
    def assert_client_frame(data):
        if not (data[0] & 128 and data[1] & 128):
            raise AssertionError("client text/control frames must be final and masked")

    def read(self, maximum, deadline):
        if self.transport.read_hook:
            return self.transport.read_hook(self, maximum, deadline)
        if not self.incoming:
            raise TimeoutError(PRIVATE)
        result = bytes(self.incoming[:maximum])
        del self.incoming[:maximum]
        return result

    def close(self, deadline):
        self.close_count += 1
        self.close_deadlines.append(deadline)
        self.closed = True
        if self.transport.close_hook:
            return self.transport.close_hook(self)
        return lab.Closed(self, True)


class Transport:
    def __init__(self, server, ws=False):
        self.server, self.ws = server, ws
        self.wires, self.origins = [], []
        self.http_hook = self.http_body_hook = self.upgrade_hook = None
        self.frame_hook = self.read_hook = self.close_hook = self.open_hook = None
        self.chunked = False

    def open(self, origin, deadline):
        self.origins.append(origin)
        wire = self.open_hook(origin) if self.open_hook else Wire(self)
        self.wires.append(wire)
        return wire


class Fixture:
    def __init__(self, limits=LIMITS):
        self.clock, self.build, self.storage, self.runtime = Clock(), Build(), Storage(), Runtime()
        canonical = {value["hash"]: value for value in
                     (GENESIS, momentum(10), momentum(11), momentum(12))}
        self.http_server, self.ws_server = Server(canonical), Server(canonical)
        self.http, self.ws = Transport(self.http_server), Transport(self.ws_server, ws=True)
        self.supervisor = lab.Supervisor(
            build=self.build, storage=self.storage, runtime=self.runtime,
            http_transport=self.http, ws_transport=self.ws, limits=limits,
            clock=self.clock, sleep=self.clock.sleep, entropy=lambda size: b"a" * size,
        )

    def launch(self):
        owner = self.supervisor.launch(PINS)
        if owner is None:
            raise AssertionError(self.supervisor.public()["error_codes"])
        return owner


class AdmissionTests(unittest.TestCase):
    def assertHeld(self, fixture, code=None):
        report = fixture.supervisor.public()
        self.assertTrue(report["held"])
        self.assertFalse(report["success"])
        self.assertFalse(report["seed_admitted"])
        if code:
            self.assertIn(code, report["error_codes"])

    def test_positive_fake_lifecycle_requires_observation_and_all_original_exits(self):
        f = Fixture()
        owner = f.launch()
        self.assertFalse(f.supervisor.public()["success"])
        self.assertTrue(f.supervisor.probe(owner))
        self.assertFalse(f.supervisor.public()["success"])
        self.assertTrue(f.supervisor.stop(owner))
        report = f.supervisor.public()
        self.assertTrue(report["success"])
        self.assertEqual(report["evidence"], "injected-source-policy")
        self.assertEqual(report["original_exits_zero"], 5)
        self.assertFalse(owner.seed_admitted)
        self.assertFalse(report["seed_admitted"])
        self.assertEqual(set(f.http.origins), {lab.HTTP_ORIGIN})
        self.assertEqual(set(f.ws.origins), {lab.WS_ORIGIN})
        stopped = [value for action, value in f.runtime.calls if action == "stop"]
        self.assertEqual(stopped, list(reversed(owner.started)))
        self.assertTrue(all(wire.close_count == 1 for wire in f.http.wires + f.ws.wires))

    def test_default_missing_build_authority_is_unknown_and_allocates_nothing(self):
        f = Fixture()
        f.supervisor.build = None
        self.assertIsNone(f.supervisor.launch(PINS))
        self.assertEqual(f.supervisor.public()["provenance"], "UNKNOWN")
        self.assertEqual(f.storage.reservations, 0)
        self.assertEqual(f.runtime.calls, [])
        self.assertHeld(f, "BUILD_UNKNOWN")

    def test_caller_mapping_is_not_a_build_authority(self):
        f = Fixture()
        f.supervisor.build = {"verified": True, "image_id": PINS.image_id}
        self.assertIsNone(f.supervisor.launch(PINS))
        self.assertEqual(f.storage.reservations, 0)
        self.assertHeld(f, "BUILD_UNKNOWN")

    def test_json_labels_booleans_and_missing_original_build_are_not_witnesses(self):
        for result in (None, True, {"verified": True, "image_id": PINS.image_id},
                       lab.BuildWitness(PINS, None)):
            with self.subTest(result=type(result).__name__):
                f = Fixture()
                f.build.result = result
                self.assertIsNone(f.supervisor.launch(PINS))
                self.assertEqual(f.runtime.calls, [])
                self.assertHeld(f, "BUILD_UNKNOWN")

    def test_full_pins_are_checked_before_any_authority_or_mutation(self):
        changes = ({"node_sha": "590f43c"}, {"node_sha": "f" * 40},
                   {"application_sha": PRIVATE}, {"application_tree": "0" * 40},
                   {"image_id": "syrius-lab:latest"}, {"platform": "windows/amd64"},
                   {"genesis_sha256": True}, {"genesis_momentum_hash": "0" * 64},
                   {"configs_sha256": (digest(1),)}, {"base_image_ids": ()},
                   {"assets_sha256": "f" * 63}, {"build_context_sha256": PRIVATE})
        for change in changes:
            with self.subTest(change=list(change)):
                f = Fixture()
                self.assertIsNone(f.supervisor.launch(replace(PINS, **change)))
                self.assertEqual(f.build.calls, [])
                self.assertEqual(f.storage.reservations, 0)
                self.assertHeld(f, "PINS_REFUSED")
                self.assertNotIn(PRIVATE, json.dumps(f.supervisor.public()))

    def test_verified_build_for_a_different_image_or_genesis_refuses(self):
        for change in ({"image_id": "sha256:" + digest(90)},
                       {"genesis_sha256": digest(90)}, {"node_tree": "9" * 40}):
            f = Fixture()
            f.build.result = lab.BuildWitness(replace(PINS, **change), object())
            self.assertIsNone(f.supervisor.launch(PINS))
            self.assertEqual(f.storage.reservations, 0)
            self.assertHeld(f, "BUILD_REFUSED")

    def test_storage_must_be_fresh_current_and_have_five_distinct_original_handles(self):
        receipts = (lab.StorageReceipt(object(), tuple(object() for _ in range(5)), False),
                    lab.StorageReceipt(None, tuple(object() for _ in range(5)), True),
                    lab.StorageReceipt(object(), (object(),) * 5, True),
                    lab.StorageReceipt(object(), (None,) * 5, True))
        for receipt in receipts:
            f = Fixture()
            f.storage.receipt = receipt
            self.assertIsNone(f.supervisor.launch(PINS))
            self.assertEqual(f.runtime.calls, [])
            self.assertHeld(f, "STORAGE_REFUSED")

    def test_existing_resources_ports_subnets_or_mounts_never_reach_create(self):
        for conflict in lab.CONFLICTS:
            f = Fixture()
            f.runtime.conflicts = (conflict,)
            self.assertIsNone(f.supervisor.launch(PINS))
            self.assertEqual([action for action, _ in f.runtime.calls], ["preflight"])
            self.assertHeld(f, "PREFLIGHT_REFUSED")

    def test_created_ids_requests_daemon_and_original_command_must_match(self):
        hooks = (lambda value: replace(value, resource_id="short"),
                 lambda value: replace(value, resource_id=digest(101)),
                 lambda value: replace(value, request=replace(value.request)),
                 lambda value: replace(value, daemon="foreign-daemon"),
                 lambda value: replace(value, command=command(exit_observed=False)),
                 lambda value: replace(value, command=command(output_complete=False)),
                 lambda value: replace(value, command=command(forced=True)),
                 lambda value: replace(value, command=command(output_bytes=131073)))
        for hook in hooks:
            f = Fixture()
            f.runtime.create_hook = hook
            self.assertIsNone(f.supervisor.launch(PINS))
            self.assertEqual(len(f.runtime.created), 1)
            self.assertEqual(f.runtime.started, [])
            self.assertHeld(f)
            self.assertGreaterEqual(len(f.supervisor._returned), 2)

    def test_partial_or_ambiguous_launch_is_retained_and_never_retried(self):
        f = Fixture()

        def uncertain(value):
            if value.request.role == "pillar3":
                raise RuntimeError(PRIVATE)
            return value

        f.runtime.create_hook = uncertain
        self.assertIsNone(f.supervisor.launch(PINS))
        owner = f.supervisor.owner
        self.assertEqual(len(owner.started), 2)
        before = len(f.runtime.calls)
        self.assertIsNone(f.supervisor.launch(PINS))
        self.assertEqual(len(f.runtime.calls), before)
        self.assertFalse(f.supervisor.stop(owner))
        self.assertEqual(len(owner.stopped), 2)
        self.assertEqual(len(f.runtime.created), 3)
        self.assertHeld(f, "CREATE_UNKNOWN")

    def test_unproven_start_is_not_reconstructed_from_inspection(self):
        f = Fixture()
        f.runtime.start_hook = lambda value: replace(value, created=replace(value.created))
        self.assertIsNone(f.supervisor.launch(PINS))
        self.assertEqual(f.supervisor.owner.started, ())
        self.assertFalse(f.supervisor.stop(f.supervisor.owner))
        self.assertEqual([v for a, v in f.runtime.calls if a == "stop"], [])
        self.assertHeld(f, "START_UNKNOWN")

    def test_one_original_command_handle_cannot_receipt_two_mutations(self):
        f = Fixture()
        f.runtime.create_hook = lambda value: replace(
            value, command=f.runtime.network.command)
        self.assertIsNone(f.supervisor.launch(PINS))
        self.assertEqual(f.runtime.started, [])
        self.assertHeld(f, "COMMAND_UNPROVEN")

    def test_foreign_report_and_capability_cannot_authorize_an_owner(self):
        for forged in ({"owned": True, "seed_admitted": True}, True, None):
            f = Fixture()
            owner = f.launch()
            self.assertFalse(f.supervisor.probe(forged))
            self.assertTrue(owner.held)
            self.assertEqual(f.http.origins + f.ws.origins, [])
        left, right = Fixture(), Fixture()
        foreign, original = left.launch(), right.launch()
        self.assertFalse(right.supervisor.probe(foreign))
        self.assertTrue(original.held)
        with self.assertRaises(lab.Refused):
            lab.Owner(object(), object(), None, None, "claimed")
        with self.assertRaises(AttributeError):
            original.held = False

    def test_resource_loss_is_permanent_even_if_original_values_return(self):
        changes = ({"resource_id": digest(900)}, {"daemon": "foreign"},
                   {"image_id": "sha256:" + digest(901)}, {"network_id": digest(902)},
                   {"ip": "172.37.0.99"}, {"storage": object()},
                   {"ports": (("0.0.0.0", 45997, 35997),)},
                   {"start_id": "replacement-start"}, {"restart_count": 1},
                   {"restart_policy": "always"}, {"mounts": (object(),)},
                   {"forced": True}, {"running": False, "exit_code": 0})
        for change in changes:
            f = Fixture()
            owner = f.launch()
            f.runtime.inspect_hook = lambda started, state: replace(state, **change)
            self.assertFalse(f.supervisor.current(owner))
            f.runtime.inspect_hook = None
            self.assertFalse(f.supervisor.current(owner))
            self.assertHeld(f, "RESOURCE_CHANGED")

    def test_network_outsider_and_build_or_storage_revocation_hold_before_wire_io(self):
        for changed in ("network", "build", "storage"):
            f = Fixture()
            owner = f.launch()
            if changed == "network":
                f.runtime.network_hook = lambda state: replace(
                    state, members=state.members + (digest(999),))
            elif changed == "build":
                f.build.ok = False
            else:
                f.storage.ok = False
            self.assertFalse(f.supervisor.probe(owner))
            self.assertEqual(f.http.origins + f.ws.origins, [])
            self.assertHeld(f)

    def test_command_deadline_is_passed_and_late_return_cannot_admit(self):
        f = Fixture()
        original = f.runtime.create_network

        def late(spec, deadline):
            self.assertLessEqual(deadline - f.clock(), LIMITS.command)
            result = original(spec, deadline)
            f.clock.now = deadline
            return result

        f.runtime.create_network = late
        self.assertIsNone(f.supervisor.launch(PINS))
        self.assertEqual(f.runtime.created, [])
        self.assertIn(f.runtime.network, f.supervisor._returned)
        self.assertIsNone(f.supervisor.owner.network)
        self.assertHeld(f, "DEADLINE")

    def test_interrupted_mutation_preserves_held_owner_without_recovery(self):
        f = Fixture()

        def interrupted(value):
            raise KeyboardInterrupt()

        f.runtime.create_hook = interrupted
        with self.assertRaises(KeyboardInterrupt):
            f.supervisor.launch(PINS)
        self.assertIsNotNone(f.supervisor.owner.network)
        self.assertEqual(len(f.runtime.created), 1)
        self.assertEqual(f.runtime.started, [])
        self.assertHeld(f, "CREATE_UNKNOWN")
        self.assertIsNone(f.supervisor.launch(PINS))
        self.assertEqual(len(f.runtime.created), 1)

    def test_both_transports_need_positive_chain_321_and_expected_genesis(self):
        for endpoint in ("http_server", "ws_server"):
            for bad in (momentum(1, chain=69), momentum(1, hash_value=digest(999)),
                        momentum(2, hash_value=PINS.genesis_momentum_hash)):
                f = Fixture()
                owner = f.launch()
                getattr(f, endpoint).genesis = bad
                self.assertFalse(f.supervisor.probe(owner))
                self.assertEqual(f.supervisor.samples, 0)
                self.assertHeld(f)

    def test_frontiers_require_both_advance_and_exact_cross_hash_lookup(self):
        for changed in ("http", "ws", "cross_hash"):
            f = Fixture()
            owner = f.launch()
            if changed == "http":
                f.http_server.frontiers = [momentum(10)]
            elif changed == "ws":
                f.ws_server.frontiers = [momentum(10)]
            else:
                f.ws_server.hook = lambda request, reply: (
                    dict(reply, result=momentum(12))
                    if request["method"] == "ledger.getMomentumByHash" else reply)
            self.assertFalse(f.supervisor.probe(owner))
            self.assertHeld(f, "ENDPOINTS_DISAGREE" if changed == "cross_hash"
                            else "PRODUCTION_UNPROVEN")
            self.assertLessEqual(f.supervisor.samples, LIMITS.samples + 1)

    def test_height_timestamp_hash_and_json_integer_types_are_independent(self):
        values = (momentum(10, timestamp=999), momentum(9),
                  momentum(11, timestamp=110), momentum(11, hash_value=momentum(10)["hash"]),
                  momentum(True), momentum(11, chain=True),
                  momentum(11, timestamp=True), momentum(11, hash_value="0" * 64))
        for bad in values:
            f = Fixture()
            owner = f.launch()
            f.http_server.frontiers = [momentum(10), bad]
            f.http_server.canonical[bad["hash"]] = bad
            self.assertFalse(f.supervisor.probe(owner))
            self.assertHeld(f)

    def test_current_owner_is_rechecked_between_samples(self):
        f = Fixture()
        owner = f.launch()

        def revoke(seconds):
            f.clock.sleep(seconds)
            f.storage.ok = False

        f.supervisor.sleep = revoke
        self.assertFalse(f.supervisor.probe(owner))
        self.assertEqual(f.supervisor.samples, 1)
        self.assertHeld(f, "STORAGE_REFUSED")

    def test_probe_cannot_be_retried_or_replaced_after_refusal(self):
        f = Fixture()
        owner = f.launch()
        f.http_server.genesis = momentum(1, chain=69)
        self.assertFalse(f.supervisor.probe(owner))
        before = (len(f.http.origins), len(f.ws.origins))
        f.http_server.genesis = GENESIS
        self.assertFalse(f.supervisor.probe(owner))
        self.assertEqual(before, (len(f.http.origins), len(f.ws.origins)))
        self.assertHeld(f)

    def test_stop_ack_and_command_zero_do_not_establish_original_process_exit(self):
        for change in (None, {"running": False, "exit_code": 137,
                             "finished_id": "private-finished"},
                       {"running": False, "exit_code": 0, "finished_id": None}):
            f = Fixture()
            owner = f.launch()
            self.assertTrue(f.supervisor.probe(owner))

            def stop_without_proof(started):
                if change is not None:
                    f.runtime.states[started.created.resource_id] = replace(
                        f.runtime.states[started.created.resource_id], **change)
                return command()

            f.runtime.stop_hook = stop_without_proof
            self.assertFalse(f.supervisor.stop(owner))
            self.assertEqual(owner.stopped, ())
            self.assertHeld(f, "EXIT_UNPROVEN")
            self.assertEqual(len([a for a, _ in f.runtime.calls if a == "stop"]), 5)

    def test_changed_start_is_never_a_stop_target_and_no_stop_is_reissued(self):
        f = Fixture()
        owner = f.launch()
        replaced = owner.started[-1]
        f.runtime.states[replaced.created.resource_id] = replace(
            f.runtime.states[replaced.created.resource_id], start_id="foreign-start")
        self.assertFalse(f.supervisor.stop(owner))
        stopped = [value for action, value in f.runtime.calls if action == "stop"]
        self.assertNotIn(replaced, stopped)
        self.assertEqual(len(stopped), 4)
        before = len(f.runtime.calls)
        self.assertFalse(f.supervisor.stop(owner))
        self.assertEqual(before, len(f.runtime.calls))
        self.assertHeld(f, "RESOURCE_CHANGED")

    def test_changed_daemon_cannot_receive_stop_requests_for_old_resources(self):
        f = Fixture()
        owner = f.launch()
        f.runtime.daemon = "replacement-daemon"
        self.assertFalse(f.supervisor.stop(owner))
        self.assertEqual([value for action, value in f.runtime.calls if action == "stop"], [])
        self.assertHeld(f, "RESOURCE_CHANGED")

    def test_successful_saved_projection_is_still_not_an_owner_or_seed_capability(self):
        f = Fixture()
        owner = f.launch()
        self.assertTrue(f.supervisor.probe(owner))
        self.assertTrue(f.supervisor.stop(owner))
        saved = json.loads(json.dumps(f.supervisor.public()))
        self.assertTrue(saved["success"])
        other = Fixture()
        original = other.launch()
        self.assertFalse(other.supervisor.probe(saved))
        self.assertTrue(original.held)
        self.assertEqual(other.http.wires + other.ws.wires, [])
        self.assertFalse(saved["seed_admitted"])
        with self.assertRaises(AttributeError):
            owner.seed_admitted = True

    def test_failed_original_command_receipt_is_not_replaced_or_forced(self):
        for changes in ({"exit_code": 1}, {"output_complete": False},
                        {"forced": True}, {"overflow": True}):
            f = Fixture()
            owner = f.launch()
            f.runtime.stop_hook = lambda started: command(**changes)
            self.assertFalse(f.supervisor.stop(owner))
            self.assertEqual(owner.stopped, ())
            self.assertHeld(f)
            self.assertTrue(all(a in {"preflight", "network", "create", "start", "stop"}
                                for a, _ in f.runtime.calls))

    def test_public_projection_keeps_only_fixed_codes_hashes_counts_and_booleans(self):
        f = Fixture()
        owner = f.launch()
        f.http.open_hook = lambda origin: (_ for _ in ()).throw(RuntimeError(PRIVATE))
        self.assertFalse(f.supervisor.probe(owner))
        report = json.loads(json.dumps(f.supervisor.public()))
        rendered = json.dumps(report)
        for forbidden in (PRIVATE, "secret-token", "private-original-daemon", "private-start",
                          "private-finished", "syrius-owned-", "172.37.0."):
            self.assertNotIn(forbidden, rendered)
        self.assertTrue(set(report["error_codes"]) <= lab.CODES)
        self.assertEqual(set(report["checks"]), set(lab.CHECKS))
        self.assertTrue(report["resources_retained"])
        self.assertFalse(report["seed_admitted"])


class WirePolicyTests(unittest.TestCase):
    def test_retained_http_scope_adds_only_its_one_height_to_genesis_reads(self):
        f = Fixture()
        retained = lab.Momentum.parse(momentum(10))
        def reply(request, response):
            if request['method'] == 'ledger.getMomentumsByHeight' and request['params'] == [10, 1]:
                return dict(response, result=dict(count=1, list=[momentum(10)]))
            return response
        f.http.server.hook = reply
        rpc = lab.HttpRpc(f.http, LIMITS, lab._Deadline(f.clock, 10),
            lambda size: b'a' * size, retained_momentum=retained)
        self.assertEqual(rpc.call('ledger.getMomentumsByHeight', [10, 1])['list'], [momentum(10)])
        self.assertEqual(rpc.call('ledger.getMomentumsByHeight', [1, 1])['list'], [GENESIS])
        for method, params in (('ledger.getMomentumsByHeight', [11, 1]),
                ('ledger.getMomentumsByHeight', [10, 2]),
                ('ledger.getMomentumsByHeight', [True, 1]),
                ('ledger.publishRawTransaction', [])):
            with self.subTest(method=method, params=params), self.assertRaises(lab.Refused):
                rpc.call(method, params)
        self.assertEqual(len(f.http.wires), 2)
        self.assertTrue(all(wire.close_count == 1 for wire in f.http.wires))
        rpc.next_id = 256
        with self.assertRaises(lab.Refused):
            rpc.call('ledger.getMomentumsByHeight', [10, 1])
        self.assertEqual(len(f.http.wires), 2)

    def test_default_http_and_ws_keep_the_original_genesis_only_scope(self):
        f = Fixture()
        for cls, transport in ((lab.HttpRpc, f.http), (lab.WsRpc, f.ws)):
            rpc = cls(transport, LIMITS, lab._Deadline(f.clock, 10), lambda size: b'a' * size)
            self.assertIsInstance(rpc._payload('ledger.getMomentumsByHeight', [1, 1]), bytes)
            with self.assertRaises(lab.Refused):
                rpc._payload('ledger.getMomentumsByHeight', [10, 1])
        self.assertEqual(f.http.wires, [])
        self.assertEqual(f.ws.wires, [])
        with self.assertRaises(TypeError):
            lab.WsRpc(f.ws, LIMITS, lab._Deadline(f.clock, 10), lambda size: b'a' * size,
                retained_momentum=lab.Momentum.parse(momentum(10)))

    def test_retained_http_scope_requires_an_exact_valid_parsed_momentum(self):
        f = Fixture()
        valid = lab.Momentum.parse(momentum(10))
        for value in (True, 10, dict(height=10), object(),
                replace(valid, height=True), replace(valid, height=0),
                replace(valid, height=2 ** 63), replace(valid, timestamp=0),
                replace(valid, timestamp=True), replace(valid, hash='private')):
            with self.subTest(kind=type(value).__name__), self.assertRaises(lab.Refused):
                lab.HttpRpc(f.http, LIMITS, lab._Deadline(f.clock, 10), lambda size: b'a' * size,
                    retained_momentum=value)
        self.assertEqual(f.http.wires, [])

    def test_retained_http_scope_keeps_response_and_close_failure_refusals(self):
        for failure in ('response', 'close'):
            f = Fixture()
            if failure == 'response':
                f.http.http_hook = lambda raw: raw.replace(b'200 OK', b'302 Found', 1)
            else:
                f.http.close_hook = lambda wire: lab.Closed(wire, False)
            rpc = lab.HttpRpc(f.http, LIMITS, lab._Deadline(f.clock, 10), lambda size: b'a' * size,
                retained_momentum=lab.Momentum.parse(momentum(10)))
            with self.subTest(failure=failure), self.assertRaises(lab.Refused):
                rpc.call('ledger.getMomentumsByHeight', [10, 1])
            self.assertEqual(len(f.http.wires), 1)
            self.assertEqual(f.http.wires[0].close_count, 1)

    def refused_probe(self, configure, code=None, limits=LIMITS):
        f = Fixture(limits)
        owner = f.launch()
        configure(f)
        self.assertFalse(f.supervisor.probe(owner))
        self.assertTrue(owner.held)
        self.assertFalse(f.supervisor.public()["success"])
        if code:
            self.assertIn(code, f.supervisor.public()["error_codes"])
        return f

    def test_chunked_http_and_fragmented_ws_remain_bounded_positive_inputs(self):
        f = Fixture()
        f.http.chunked = True
        f.ws.frame_hook = lambda body: (frame(body[:17], final=False)
                                       + frame(b"ok", opcode=9)
                                       + frame(body[17:], opcode=0))
        owner = f.launch()
        self.assertTrue(f.supervisor.probe(owner))
        self.assertTrue(f.supervisor.stop(owner))

    def test_only_fixed_bounded_read_requests_can_open_http_wires(self):
        f = Fixture()
        deadline = lab._Deadline(f.clock, 10)
        rpc = lab.HttpRpc(f.http, LIMITS, deadline, lambda size: b"a" * size)
        for method, params in (("ledger.publishRawTransaction", []),
                               ("ledger.getFrontierMomentum", [PRIVATE]),
                               ("ledger.getMomentumsByHeight", [True, 1]),
                               ("ledger.getMomentumsByHeight", [1, 999]),
                               ("ledger.getMomentumByHash", ["x" * 100000]),
                               ("ledger.getMomentumByHash", ["0" * 64])):
            with self.assertRaises(lab.Refused):
                rpc.call(method, params)
        self.assertEqual(f.http.wires, [])

    def test_http_redirect_compression_ambiguous_length_and_unbounded_body_refuse(self):
        hooks = (
            lambda raw: raw.replace(b"200 OK", b"302 Found", 1),
            lambda raw: raw.replace(b"Content-Type:", b"Content-Encoding: gzip\r\nContent-Type:", 1),
            lambda raw: raw.replace(b"Content-Length:", b"Transfer-Encoding: chunked\r\nContent-Length:", 1),
            lambda raw: raw.replace(b"Content-Length:", b"Content-Length: 1\r\nContent-Length:", 1),
            lambda raw: b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 262145\r\n\r\n",
            lambda raw: b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{}",
            lambda raw: b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n40001\r\n",
        )
        for hook in hooks:
            self.refused_probe(lambda f: setattr(f.http, "http_hook", hook))

    def test_http_header_body_and_read_call_caps_have_finite_refusals(self):
        self.refused_probe(lambda f: setattr(f.http, "http_hook", lambda raw:
                           b"HTTP/1.1 200 OK\r\nX: " + b"x" * 16384), "WIRE_OVERFLOW")
        self.refused_probe(lambda f: setattr(f.http, "read_hook", lambda wire, maximum, deadline:
                           b"x" * (maximum + 1)), "WIRE_OVERFLOW")
        self.refused_probe(lambda f: setattr(f.http, "read_hook", lambda *args: b""), "WIRE_EOF")
        self.refused_probe(lambda f: None, "WIRE_OVERFLOW", replace(LIMITS, reads=1))

    def test_rpc_envelope_duplicate_keys_constants_depth_and_large_integer_refuse(self):
        bodies = (
            b'{"jsonrpc":"2.0","id":true,"result":{}}',
            b'{"jsonrpc":"2.0","id":999,"result":{}}',
            b'{"jsonrpc":"2.0","id":1,"id":1,"result":{}}',
            b'{"jsonrpc":"2.0","id":1,"error":{"message":"private"}}',
            b'{"jsonrpc":"2.0","id":1,"result":NaN}',
            b'{"jsonrpc":"2.0","id":1,"result":1.2}',
            b'{"jsonrpc":"2.0","id":1,"result":' + b"9" * 100 + b'}',
            b'{"jsonrpc":"2.0","id":1,"result":' + b"[" * 26 + b"0" + b"]" * 26 + b'}',
            b'{"jsonrpc":"2.0","id":1,"result":[' + b"0," * 5000 + b"0]}",
            b"\xff",
        )
        for body in bodies:
            self.refused_probe(lambda f: setattr(f.http, "http_body_hook", lambda raw: body),
                               "RPC_REFUSED")

    def test_ws_upgrade_requires_exact_accept_and_no_unrequested_features(self):
        hooks = (
            lambda raw: raw.replace(b"101 Switching Protocols", b"200 OK", 1),
            lambda raw: raw.replace(b"Sec-WebSocket-Accept:", b"X-Wrong-Accept:", 1),
            lambda raw: raw.replace(b"Upgrade: websocket", b"Upgrade: other", 1),
            lambda raw: raw.replace(b"\r\n\r\n", b"\r\nSec-WebSocket-Extensions: permessage-deflate\r\n\r\n"),
            lambda raw: raw.replace(b"\r\n\r\n", b"\r\nSec-WebSocket-Protocol: other\r\n\r\n"),
        )
        for hook in hooks:
            self.refused_probe(lambda f: setattr(f.ws, "upgrade_hook", hook), "WS_REFUSED")

    def test_ws_invalid_mask_opcode_fragment_control_lengths_and_frame_floods_refuse(self):
        hooks = (
            lambda body: b"\x81\x80" + b"aaaa",
            lambda body: frame(body, opcode=2),
            lambda body: frame(body, opcode=0),
            lambda body: frame(b"ping", opcode=9, final=False),
            lambda body: frame(b"x" * 126, opcode=9),
            lambda body: frame(b"", opcode=8),
            lambda body: b"\xc1\x00",
            lambda body: b"\x81\x7e\x00\x01x",
            lambda body: b"\x81\x7f" + (2 ** 63).to_bytes(8, "big"),
            lambda body: b"\x81\x7f" + (262145).to_bytes(8, "big"),
            lambda body: frame(b"a", opcode=9) * 3 + frame(body),
            lambda body: frame(b"x", final=False) + frame(b"x", opcode=0, final=False) * 8,
        )
        for hook in hooks:
            self.refused_probe(lambda f: setattr(f.ws, "frame_hook", hook))

    def test_ws_fragment_aggregate_cap_applies_before_json(self):
        self.refused_probe(lambda f: setattr(f.ws, "frame_hook", lambda body:
                           frame(b"x" * 150000, final=False)
                           + frame(b"x" * 150000, opcode=0)), "WIRE_OVERFLOW")

    def test_independent_transports_cannot_return_the_same_original_wire(self):
        f = Fixture()
        owner = f.launch()
        f.http.open_hook = lambda origin: f.ws.wires[0]
        self.assertFalse(f.supervisor.probe(owner))
        self.assertIn("WIRE_REFUSED", f.supervisor.public()["error_codes"])
        self.assertEqual(f.ws.wires[0].close_count, 1)

    def test_timeout_and_late_reads_do_not_reconnect_or_retry(self):
        for late in (False, True):
            def configure(f):
                def failed(wire, maximum, deadline):
                    if late:
                        f.clock.now = deadline
                        return b"H"
                    raise TimeoutError(PRIVATE)
                f.ws.read_hook = failed
            f = self.refused_probe(configure)
            self.assertEqual(len(f.ws.wires), 1)
            self.assertEqual(f.http.wires, [])

    def test_late_http_and_ws_open_retain_and_close_the_exact_original_once(self):
        for endpoint in ("http", "ws"):
            with self.subTest(endpoint=endpoint):
                f = Fixture()
                owner = f.launch()
                transport = getattr(f, endpoint)
                original_open = transport.open
                returned = []
                close_observations = []

                def late_open(origin, deadline):
                    wire = original_open(origin, deadline)
                    returned.append(wire)
                    f.clock.now = deadline
                    return wire

                def observe_close(wire):
                    close_observations.append(wire)
                    self.assertIs(wire, returned[0])
                    self.assertAlmostEqual(wire.close_deadlines[-1] - f.clock(),
                                           LIMITS.close)
                    return lab.Closed(wire, True)

                transport.open = late_open
                transport.close_hook = observe_close
                self.assertFalse(f.supervisor.probe(owner))
                self.assertTrue(owner.held)
                self.assertIn("DEADLINE", f.supervisor.public()["error_codes"])
                self.assertEqual(len(returned), 1)
                self.assertIs(transport.wires[0], returned[0])
                self.assertEqual(close_observations, returned)
                self.assertTrue(any(wire is returned[0]
                                    for wire in f.supervisor._seen_wires))
                self.assertEqual(returned[0].writes, [])
                self.assertEqual(returned[0].close_count, 1)
                before = (len(f.http.wires), len(f.ws.wires))
                self.assertFalse(f.supervisor.probe(owner))
                self.assertEqual(before, (len(f.http.wires), len(f.ws.wires)))
                self.assertEqual(returned[0].close_count, 1)

    def test_unknown_close_never_retries_or_turns_positive_observation_into_success(self):
        for endpoint in ("http", "ws"):
            def configure(f):
                getattr(f, endpoint).close_hook = lambda wire: lab.Closed(object(), True)
            f = self.refused_probe(configure, "CLOSE_UNKNOWN")
            self.assertTrue(all(wire.close_count == 1 for wire in f.http.wires + f.ws.wires))

    def test_limits_reject_bool_nonfinite_zero_and_unbounded_inputs(self):
        for change in ({"total": float("inf")}, {"request": 0}, {"samples": True},
                       {"samples": 49}, {"response_bytes": 262145}, {"reads": 0},
                       {"frames": 17}, {"stop": 601}):
            with self.assertRaises(lab.Refused):
                lab.Supervisor(limits=replace(LIMITS, **change))


if __name__ == "__main__":
    unittest.main()
