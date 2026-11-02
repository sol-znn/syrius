"""Source/fake cases and optional AF_UNIX byte mechanics, never a lab launch.

No test opens a TCP listener, resolves a host, launches a service or runs a node.
Socketpair cases prove only local byte mechanics, not fixed-origin admission,
verified build/storage, producing chain 321, wallet ownership or checkpoint.
"""

from collections import deque
import errno
import importlib
import importlib.util
import socket
import time
import unittest
from unittest import mock

from tools.devnet.lab import owned_lab as policy
from tools.devnet.lab import socket_transport as transport


PRIVATE = "private-profile secret-token raw-native-diagnostic"


class Clock:
    def __init__(self):
        self.value, self.calls = 10.0, 0

    def __call__(self):
        self.calls += 1
        return self.value

    def advance(self, seconds):
        self.value += seconds


class FakeSocket:
    def __init__(self, descriptor=50):
        self.fd, self.family = descriptor, socket.AF_INET
        self.blocking = True
        self.kind, self.linger = int(socket.SOCK_STREAM), bytes(8)
        self.local, self.peer = ("0.0.0.0", 0), None
        self.bind_local = ("127.0.0.1", 55000 + descriptor)
        self.connect_peer, self.connect_result = None, 0
        self.so_errors = deque()
        self.socket_error_default = 0
        self.receives, self.sends = deque(), deque()
        self.sent, self.accepted = [], bytearray()
        self.events, self.hooks = [], {}
        self.connect_calls, self.close_calls = 0, 0
        self.close_error, self.close_stays_open = None, False
        self.oversized_read = False
        self._target = None

    def _event(self, name, *args):
        self.events.append((name,) + args)
        hook = self.hooks.get(name)
        if hook is not None:
            hook(self, *args)

    def fileno(self):
        self._event("fileno")
        return self.fd

    def setblocking(self, value):
        self._event("setblocking", value)
        self.blocking = value

    def getblocking(self):
        self._event("getblocking")
        return self.blocking

    def getsockopt(self, level, option, *args):
        self._event("getsockopt", level, option, *args)
        if option == socket.SO_TYPE:
            return self.kind
        if option == socket.SO_LINGER:
            return self.linger
        if option == socket.SO_ERROR:
            value = (self.so_errors.popleft() if self.so_errors
                     else self.socket_error_default)
            if value == 0:
                self.peer = self.connect_peer or self._target
            return value
        raise AssertionError("unexpected source fixture option")

    def getsockname(self):
        self._event("getsockname")
        return self.local

    def getpeername(self):
        self._event("getpeername")
        if self.peer is None:
            raise OSError(errno.ENOTCONN, PRIVATE)
        return self.peer

    def bind(self, endpoint):
        self._event("bind", endpoint)
        if endpoint != ("127.0.0.1", 0):
            raise AssertionError("unexpected source fixture binding")
        self.local = self.bind_local

    def connect_ex(self, endpoint):
        self.connect_calls += 1
        self._event("connect_ex", endpoint)
        self._target = endpoint
        if self.connect_result == 0:
            self.peer = self.connect_peer or endpoint
        return self.connect_result

    def recv(self, maximum):
        self._event("recv", maximum)
        action = self.receives.popleft() if self.receives else b""
        if isinstance(action, BaseException):
            raise action
        if callable(action):
            return action(self, maximum)
        if type(action) is bytes and len(action) > maximum and not self.oversized_read:
            self.receives.appendleft(action[maximum:])
            return action[:maximum]
        return action

    def send(self, data):
        data = bytes(data)
        self.sent.append(data)
        self._event("send", data)
        action = self.sends.popleft() if self.sends else len(data)
        if isinstance(action, BaseException):
            raise action
        count = action(self, data) if callable(action) else action
        if type(count) is int and 0 < count <= len(data):
            self.accepted.extend(data[:count])
        return count

    def close(self):
        self.close_calls += 1
        self._event("close")
        if self.close_error is not None:
            raise self.close_error
        if not self.close_stays_open:
            self.fd = -1


class Factory:
    def __init__(self, originals):
        self.originals, self.calls = deque(originals), []
        self.on_return = None

    def __call__(self, *args):
        self.calls.append(args)
        result = self.originals.popleft()
        if isinstance(result, BaseException):
            raise result
        if self.on_return is not None:
            self.on_return(result)
        return result


class Waiter:
    def __init__(self):
        self.calls, self.results = [], deque()

    def __call__(self, original, writing, seconds):
        self.calls.append((original, writing, seconds))
        result = self.results.popleft() if self.results else True
        if isinstance(result, BaseException):
            raise result
        return result(original, writing, seconds) if callable(result) else result


class SocketTransportPolicyTests(unittest.TestCase):
    def fixture(self, *originals):
        clock, waiter = Clock(), Waiter()
        factory = Factory(originals or (FakeSocket(), FakeSocket(51), FakeSocket(52)))
        http, ws = transport.make_transports(
            _socket_factory=factory, _waiter=waiter, _clock=clock)
        return clock, factory, waiter, http, ws

    def refused(self, code, method, *args):
        with self.assertRaises(policy.Refused) as caught:
            method(*args)
        error = caught.exception
        self.assertIs(type(error), policy.Refused)
        self.assertEqual(error.code, code)
        self.assertEqual(str(error), code)
        self.assertIn(code, policy.CODES)
        self.assertNotIn(PRIVATE, repr(error))
        self.assertIsNone(error.__cause__)
        return error

    def opened(self):
        fixture = self.fixture()
        clock, factory, waiter, http, ws = fixture
        wire = http.open(policy.HTTP_ORIGIN, clock() + 2)
        return fixture + (wire,)

    def test_canonical_policy_and_construction_have_no_native_calls(self):
        self.assertIs(transport.policy,
                      importlib.import_module("tools.devnet.lab.owned_lab"))
        clock, factory, waiter, http, ws = self.fixture()
        self.assertIsNot(http, ws)
        self.assertEqual((clock.calls, factory.calls, waiter.calls), (0, [], []))
        self.assertFalse(http.held)
        self.assertFalse(ws.held)

    def test_import_and_default_construction_do_not_allocate_wait_or_read_clock(self):
        spec = importlib.util.spec_from_file_location(
            "tools.devnet.lab.socket_transport_import_probe", transport.__file__)
        probe = importlib.util.module_from_spec(spec)
        with mock.patch.object(socket, "socket", side_effect=AssertionError("allocation")), \
                mock.patch.object(transport.select, "select",
                                  side_effect=AssertionError("wait")), \
                mock.patch.object(time, "monotonic", side_effect=AssertionError("clock")):
            spec.loader.exec_module(probe)
            http, ws = probe.make_transports()
        self.assertIsNot(http, ws)
        self.assertIs(probe.policy, policy)

    def test_exact_fixed_origins_refuse_before_allocation(self):
        for origin in ("http://localhost:45997", "http://127.0.0.1:45998",
                       "http://127.0.0.1:45997/", "http://127.0.0.1:45997?x=1",
                       "http://user@127.0.0.1:45997", "http://[::1]:45997",
                       policy.WS_ORIGIN, "HTTP://127.0.0.1:45997", None):
            with self.subTest(origin=origin):
                clock, factory, waiter, http, ws = self.fixture()
                self.refused("WIRE_REFUSED", http.open, origin, 12)
                self.assertEqual(factory.calls, [])
                self.assertTrue(http.held and ws.held)

    def test_invalid_or_expired_deadline_refuses_before_allocation(self):
        for end in (0, 9, 10, float("nan"), float("inf"), True, "12", None):
            with self.subTest(end=end):
                clock, factory, waiter, http, ws = self.fixture()
                self.refused("DEADLINE", http.open, policy.HTTP_ORIGIN, end)
                self.assertEqual(factory.calls, [])

    def test_original_retained_and_bound_before_exactly_one_connect(self):
        clock, factory, waiter, http, ws = self.fixture()
        original = factory.originals[0]

        def during_connect(raw, peer):
            self.assertIs(raw, original)
            self.assertIs(http._ledger._wires[0]._socket, original)
            self.assertIs(http._ledger._descriptors[raw.fd],
                          http._ledger._wires[0])
            self.assertFalse(raw.blocking)
            self.assertEqual(raw.local, raw.bind_local)
            self.assertEqual(peer, ("127.0.0.1", 45997))

        original.hooks["connect_ex"] = during_connect
        wire = http.open(policy.HTTP_ORIGIN, 12)
        self.assertEqual(factory.calls,
                         [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP)])
        self.assertEqual(original.connect_calls, 1)
        receipt = wire.close(11)
        self.assertIs(type(receipt), policy.Closed)
        self.assertIs(receipt.wire, wire)
        self.assertTrue(receipt.complete)
        self.assertFalse(receipt.forced)
        self.assertEqual(original.close_calls, 1)

    def test_http_and_ws_use_distinct_originals_and_exact_ports(self):
        clock, factory, waiter, http, ws = self.fixture()
        left = http.open(policy.HTTP_ORIGIN, 12)
        right = ws.open(policy.WS_ORIGIN, 12)
        self.assertIsNot(left, right)
        self.assertIsNot(left._socket, right._socket)
        self.assertEqual(left._peer, ("127.0.0.1", 45997))
        self.assertEqual(right._peer, ("127.0.0.1", 45998))
        self.assertIs(left.close(11).wire, left)
        self.assertIs(right.close(11).wire, right)

    def test_pending_connect_waits_on_original_without_repeating_connect(self):
        for pending in (errno.EINPROGRESS, errno.EWOULDBLOCK, errno.EINTR):
            with self.subTest(pending=pending):
                raw = FakeSocket()
                raw.connect_result = pending
                raw.so_errors.extend((errno.EINPROGRESS, 0))
                clock, factory, waiter, http, ws = self.fixture(raw)
                wire = http.open(policy.HTTP_ORIGIN, 1000)
                self.assertEqual(raw.connect_calls, 1)
                self.assertEqual(len(waiter.calls), 2)
                self.assertTrue(all(call[0] is raw and call[1] is True
                                    and 0 < call[2] <= 3 for call in waiter.calls))
                wire.close(11)

    def test_connect_refusal_closes_original_once_and_never_reopens(self):
        raw = FakeSocket()
        raw.connect_result = errno.ECONNREFUSED
        clock, factory, waiter, http, ws = self.fixture(raw)
        self.refused("WIRE_REFUSED", http.open, policy.HTTP_ORIGIN, 12)
        self.assertEqual((raw.connect_calls, raw.close_calls), (1, 1))
        self.refused("OWNER_HELD", ws.open, policy.WS_ORIGIN, 12)
        self.assertEqual(len(factory.calls), 1)

    def test_connected_return_with_kernel_error_is_not_positive_admission(self):
        raw = FakeSocket()
        raw.so_errors.append(errno.ECONNRESET)
        clock, factory, waiter, http, ws = self.fixture(raw)
        self.refused("WIRE_REFUSED", http.open, policy.HTTP_ORIGIN, 12)
        self.assertEqual((raw.connect_calls, raw.close_calls), (1, 1))
        self.assertTrue(http.held)

    def test_failed_open_with_unknown_close_is_retained_without_second_close(self):
        raw = FakeSocket()
        raw.connect_result = errno.ECONNREFUSED
        raw.close_error = OSError(errno.EIO, PRIVATE)
        clock, factory, waiter, http, ws = self.fixture(raw)
        self.refused("CLOSE_UNKNOWN", http.open, policy.HTTP_ORIGIN, 12)
        original_wire = http._ledger._wires[0]
        self.assertIs(original_wire._socket, raw)
        self.assertTrue(original_wire._close_attempted)
        self.assertFalse(original_wire._closed)
        self.assertEqual((raw.connect_calls, raw.close_calls), (1, 1))
        self.refused("CLOSE_UNKNOWN", original_wire.close, 11)
        self.refused("OWNER_HELD", ws.open, policy.WS_ORIGIN, 12)
        self.assertEqual((raw.close_calls, len(factory.calls)), (1, 1))

    def test_pending_connect_deadline_and_frozen_clock_spin_are_bounded(self):
        for timeout in (True, False):
            with self.subTest(timeout=timeout):
                raw = FakeSocket()
                raw.connect_result = errno.EINPROGRESS
                raw.socket_error_default = errno.EINPROGRESS
                clock, factory, waiter, http, ws = self.fixture(raw)
                if timeout:
                    waiter.results.append(False)
                code = "DEADLINE" if timeout else "WIRE_OVERFLOW"
                self.refused(code, http.open, policy.HTTP_ORIGIN, 12)
                self.assertEqual(raw.connect_calls, 1)
                self.assertEqual(raw.close_calls, 1)
                self.assertLessEqual(len(waiter.calls), transport._STEPS)

    def test_late_factory_retains_original_then_closes_under_new_bound(self):
        for origin in (policy.HTTP_ORIGIN, policy.WS_ORIGIN):
            with self.subTest(origin=origin):
                raw = FakeSocket()
                clock, factory, waiter, http, ws = self.fixture(raw)
                chosen = http if origin == policy.HTTP_ORIGIN else ws
                factory.on_return = lambda original: clock.advance(3)
                self.refused("DEADLINE", chosen.open, origin, 12)
                self.assertIs(chosen._ledger._wires[0]._socket, raw)
                self.assertTrue(chosen._ledger._wires[0]._closed)
                self.assertEqual((raw.connect_calls, raw.close_calls), (0, 1))
                self.assertFalse(raw.blocking)
                self.refused("OWNER_HELD", chosen.open, origin, 15)
                self.assertEqual(len(factory.calls), 1)

    def test_late_connect_and_wait_close_only_the_same_original(self):
        for stage in ("connect", "wait"):
            with self.subTest(stage=stage):
                raw = FakeSocket()
                clock, factory, waiter, http, ws = self.fixture(raw)
                if stage == "connect":
                    raw.hooks["connect_ex"] = lambda *args: clock.advance(3)
                else:
                    raw.connect_result = errno.EINPROGRESS
                    waiter.results.append(lambda *args: (clock.advance(3), True)[1])
                self.refused("DEADLINE", http.open, policy.HTTP_ORIGIN, 12)
                self.assertIs(http._ledger._wires[0]._socket, raw)
                self.assertEqual((raw.connect_calls, raw.close_calls), (1, 1))
                self.assertTrue(http.held)

    def test_initial_family_type_binding_or_connection_cannot_be_adopted(self):
        changes = (("family", socket.AF_UNIX if hasattr(socket, "AF_UNIX") else -1),
                   ("kind", int(socket.SOCK_DGRAM)),
                   ("kind", True), ("local", ("127.0.0.1", 55050)),
                   ("peer", ("127.0.0.1", 45997)))
        for field, value in changes:
            with self.subTest(field=field, value=value):
                raw = FakeSocket()
                setattr(raw, field, value)
                clock, factory, waiter, http, ws = self.fixture(raw)
                self.refused("WIRE_REFUSED", http.open, policy.HTTP_ORIGIN, 12)
                self.assertEqual(raw.connect_calls, 0)
                self.assertEqual(raw.close_calls, 1)

    def test_winsock_unbound_name_refusal_still_requires_one_loopback_bind(self):
        raw = FakeSocket()
        def unbound(original):
            if original.local == ("0.0.0.0", 0):
                raise OSError(10022, PRIVATE)
        raw.hooks["getsockname"] = unbound
        clock, factory, waiter, http, ws = self.fixture(raw)
        wire = http.open(policy.HTTP_ORIGIN, clock() + 2)
        self.assertEqual([event for event in raw.events if event[0] == "bind"],
                         [("bind", ("127.0.0.1", 0))])
        self.assertEqual(raw.connect_calls, 1)
        wire.close(clock() + 1)
        self.assertEqual(raw.close_calls, 1)

    def test_other_name_errors_or_an_already_bound_winsock_socket_are_refused(self):
        for code, already_bound in ((errno.EINVAL, False), (10022, True)):
            with self.subTest(code=code, already_bound=already_bound):
                raw = FakeSocket()
                raw.hooks["getsockname"] = lambda *args: (_ for _ in ()).throw(OSError(code, PRIVATE))
                if already_bound:
                    raw.local = ("0.0.0.0", 55050)
                    raw.hooks["bind"] = lambda *args: (_ for _ in ()).throw(OSError(10022, PRIVATE))
                clock, factory, waiter, http, ws = self.fixture(raw)
                self.refused("WIRE_REFUSED", http.open, policy.HTTP_ORIGIN, clock() + 2)
                self.assertEqual(raw.connect_calls, 0)
                self.assertEqual(raw.close_calls, 1)

    def test_translated_winsock_name_error_uses_the_native_status(self):
        raw = FakeSocket()
        def unbound(original):
            if original.local == ("0.0.0.0", 0):
                error = OSError(errno.EINVAL, PRIVATE)
                error.winerror = 10022
                raise error
        raw.hooks["getsockname"] = unbound
        clock, factory, waiter, http, ws = self.fixture(raw)
        wire = http.open(policy.HTTP_ORIGIN, clock() + 2)
        self.assertEqual(raw.connect_calls, 1)
        wire.close(clock() + 1)
        self.assertEqual(raw.close_calls, 1)

    def test_conflicting_native_status_cannot_use_the_errno_exception(self):
        raw = FakeSocket()
        def denied(*args):
            error = OSError(10022, PRIVATE)
            error.winerror = 5
            raise error
        raw.hooks["getsockname"] = denied
        clock, factory, waiter, http, ws = self.fixture(raw)
        self.refused("WIRE_REFUSED", http.open, policy.HTTP_ORIGIN, clock() + 2)
        self.assertEqual(raw.connect_calls, 0)
        self.assertEqual(raw.close_calls, 1)

    def test_exact_local_and_peer_endpoint_validation(self):
        cases = (("bind_local", ("0.0.0.0", 55050)),
                 ("bind_local", ("127.0.0.2", 55050)),
                 ("bind_local", ("127.0.0.1", 0)),
                 ("bind_local", ("127.0.0.1", True)),
                 ("bind_local", ("127.0.0.1", 45997)),
                 ("connect_peer", ("127.0.0.1", 45998)),
                 ("connect_peer", ("127.0.0.2", 45997)))
        for field, value in cases:
            with self.subTest(field=field, value=value):
                raw = FakeSocket()
                setattr(raw, field, value)
                clock, factory, waiter, http, ws = self.fixture(raw)
                self.refused("WIRE_REFUSED", http.open, policy.HTTP_ORIGIN, 12)
                self.assertEqual(raw.close_calls, 1)

    def test_same_socket_object_is_never_reused_or_closed_as_second_owner(self):
        for already_closed in (False, True):
            with self.subTest(already_closed=already_closed):
                raw = FakeSocket()
                clock, factory, waiter, http, ws = self.fixture(raw, raw)
                first = http.open(policy.HTTP_ORIGIN, 12)
                if already_closed:
                    first.close(11)
                self.refused("WIRE_REFUSED", ws.open, policy.WS_ORIGIN, 12)
                if not already_closed:
                    first.close(11)
                self.assertEqual(raw.close_calls, 1)

    def test_active_descriptor_collision_is_held_without_closing_candidate(self):
        first, candidate = FakeSocket(), FakeSocket()
        clock, factory, waiter, http, ws = self.fixture(first, candidate)
        wire = http.open(policy.HTTP_ORIGIN, 12)
        self.refused("WIRE_REFUSED", ws.open, policy.WS_ORIGIN, 12)
        self.assertEqual(candidate.close_calls, 0)
        self.assertIs(http._ledger._descriptors[first.fd], wire)
        wire.close(11)
        self.assertEqual(first.close_calls, 1)
        self.assertTrue(http.held)

    def test_descriptor_number_can_recur_only_after_positive_original_close(self):
        first, second = FakeSocket(), FakeSocket()
        clock, factory, waiter, http, ws = self.fixture(first, second)
        one = http.open(policy.HTTP_ORIGIN, 12)
        one.close(11)
        two = http.open(policy.HTTP_ORIGIN, 12)
        self.assertIsNot(one._socket, two._socket)
        self.assertEqual(one._descriptor_id, two._descriptor_id)
        two.close(11)
        self.assertEqual((first.close_calls, second.close_calls), (1, 1))

    def test_ws_never_reconnects_after_positive_close(self):
        clock, factory, waiter, http, ws = self.fixture()
        wire = ws.open(policy.WS_ORIGIN, 12)
        wire.close(11)
        self.refused("WIRE_REFUSED", ws.open, policy.WS_ORIGIN, 12)
        self.assertEqual(len(factory.calls), 1)

    def test_http_allocation_count_is_finite(self):
        clock, factory, waiter, http, ws = self.fixture()
        http._attempts = 128
        self.refused("WIRE_REFUSED", http.open, policy.HTTP_ORIGIN, 12)
        self.assertEqual(factory.calls, [])

    def test_identity_change_blocks_io_and_descriptor_replacement_blocks_close(self):
        changes = (("fd", 900), ("fd", -1), ("family", -1),
                   ("local", ("127.0.0.1", 55051)),
                   ("peer", ("127.0.0.1", 45998)), ("blocking", True),
                   ("kind", int(socket.SOCK_DGRAM)))
        for field, value in changes:
            with self.subTest(field=field, value=value):
                clock, factory, waiter, http, ws, wire = self.opened()
                raw = wire._socket
                setattr(raw, field, value)
                self.refused("WIRE_REFUSED", wire.read, 1, 12)
                self.assertEqual(waiter.calls, [])
                if field != "blocking":
                    self.refused("CLOSE_UNKNOWN", wire.close, 11)
                    self.assertEqual(raw.close_calls, 0)
                else:
                    wire.close(11)
                    self.assertEqual(raw.close_calls, 1)
                self.assertTrue(http.held)

    def test_enabled_linger_is_held_without_possibly_blocking_close(self):
        clock, factory, waiter, http, ws, wire = self.opened()
        wire._socket.linger = b"\1" + bytes(7)
        self.refused("WIRE_REFUSED", wire.read, 1, 12)
        self.refused("CLOSE_UNKNOWN", wire.close, 11)
        self.assertEqual(wire._socket.close_calls, 0)
        self.refused("CLOSE_UNKNOWN", wire.close, 11)
        self.assertEqual(wire._socket.close_calls, 0)

    def test_partial_reads_obey_requested_maximum_and_preserve_remainder(self):
        clock, factory, waiter, http, ws, wire = self.opened()
        wire._socket.receives.append(b"abcdef")
        self.assertEqual(wire.read(2, 12), b"ab")
        self.assertEqual(wire.read(3, 12), b"cde")
        self.assertEqual(wire.read(1, 12), b"f")
        self.assertEqual(wire._read_bytes, 6)
        wire.close(11)

    def test_partial_writes_advance_only_accepted_prefix(self):
        clock, factory, waiter, http, ws, wire = self.opened()
        wire._socket.sends.extend((2, 1, 3))
        self.assertIsNone(wire.write(b"abcdef", 12))
        self.assertEqual(wire._socket.sent, [b"abcdef", b"cdef", b"def"])
        self.assertEqual(bytes(wire._socket.accepted), b"abcdef")
        self.assertEqual(wire._write_bytes, 6)
        self.assertEqual(wire._socket.connect_calls, 1)
        wire.close(11)

    def test_same_operation_eintr_and_eagain_do_not_repeat_connect_or_prefix(self):
        clock, factory, waiter, http, ws, wire = self.opened()
        wire._socket.receives.extend((InterruptedError(errno.EINTR, PRIVATE),
                                     BlockingIOError(errno.EAGAIN, PRIVATE), b"x"))
        waiter.results.append(InterruptedError(errno.EINTR, PRIVATE))
        self.assertEqual(wire.read(1, 12), b"x")
        wire._socket.sends.extend((InterruptedError(errno.EINTR, PRIVATE), 2,
                                  BlockingIOError(errno.EAGAIN, PRIVATE), 1))
        wire.write(b"abc", 12)
        self.assertEqual(bytes(wire._socket.accepted), b"abc")
        self.assertEqual(wire._socket.sent, [b"abc", b"abc", b"c", b"c"])
        self.assertEqual(wire._socket.connect_calls, 1)
        wire.close(11)

    def test_zero_recv_or_send_is_terminal_eof_without_reconnect(self):
        for reading in (True, False):
            with self.subTest(reading=reading):
                clock, factory, waiter, http, ws, wire = self.opened()
                if reading:
                    wire._socket.receives.append(b"")
                    self.refused("WIRE_EOF", wire.read, 1, 12)
                else:
                    wire._socket.sends.append(0)
                    self.refused("WIRE_EOF", wire.write, b"x", 12)
                self.refused("OWNER_HELD", http.open, policy.HTTP_ORIGIN, 12)
                self.assertEqual(len(factory.calls), 1)
                wire.close(11)

    def test_invalid_io_sizes_and_types_are_finite_before_native_io(self):
        cases = ((True, 0), (True, -1), (True, True), (True, 4097),
                 (True, "1"), (False, b""), (False, bytearray(b"x")),
                 (False, b"x" * (transport._WRITE_MAX + 1)))
        for reading, value in cases:
            with self.subTest(reading=reading, kind=type(value).__name__):
                clock, factory, waiter, http, ws, wire = self.opened()
                self.refused("WIRE_OVERFLOW", wire.read if reading else wire.write,
                             value, 12)
                self.assertEqual(waiter.calls, [])
                wire.close(11)

    def test_malformed_native_read_and_write_results_refuse(self):
        for result, reading in ((b"xx", True), (bytearray(b"x"), True),
                                (-1, False), (2, False), (True, False)):
            with self.subTest(reading=reading, kind=type(result).__name__):
                clock, factory, waiter, http, ws, wire = self.opened()
                if reading:
                    wire._socket.oversized_read = True
                    wire._socket.receives.append(result)
                    self.refused("WIRE_OVERFLOW", wire.read, 1, 12)
                else:
                    wire._socket.sends.append(result)
                    self.refused("WIRE_REFUSED", wire.write, b"x", 12)
                wire.close(11)

    def test_per_wire_count_and_byte_limits_precede_io(self):
        for name, maximum, reading in (("_read_calls", transport._CALLS_MAX, True),
                                       ("_read_bytes", transport._BYTES_MAX, True),
                                       ("_write_calls", transport._CALLS_MAX, False),
                                       ("_write_bytes", transport._BYTES_MAX, False)):
            with self.subTest(name=name):
                clock, factory, waiter, http, ws, wire = self.opened()
                setattr(wire, name, maximum)
                self.refused("WIRE_OVERFLOW", wire.read if reading else wire.write,
                             1 if reading else b"x", 12)
                self.assertEqual(waiter.calls, [])
                wire.close(11)

    def test_frozen_clock_transient_io_has_finite_syscall_budget(self):
        for reading in (True, False):
            with self.subTest(reading=reading):
                clock, factory, waiter, http, ws, wire = self.opened()
                actions = wire._socket.receives if reading else wire._socket.sends
                actions.extend(BlockingIOError(errno.EAGAIN, PRIVATE)
                               for _ in range(transport._STEPS))
                self.refused("WIRE_OVERFLOW", wire.read if reading else wire.write,
                             1 if reading else b"x", 12)
                self.assertEqual(len(waiter.calls), transport._STEPS)
                self.assertEqual(wire._socket.connect_calls, 1)
                wire.close(11)

    def test_timeout_and_late_read_never_return_bytes_or_retry(self):
        for late in (False, True):
            with self.subTest(late=late):
                clock, factory, waiter, http, ws, wire = self.opened()
                if late:
                    wire._socket.receives.append(
                        lambda raw, size: (clock.advance(3), b"x")[1])
                else:
                    waiter.results.append(False)
                self.refused("DEADLINE", wire.read, 1, 12)
                self.assertLessEqual(len(waiter.calls), 1)
                self.assertEqual(len(factory.calls), 1)
                wire.close(clock() + 1)

    def test_late_partial_send_records_progress_without_retry(self):
        clock, factory, waiter, http, ws, wire = self.opened()
        wire._socket.sends.append(lambda raw, data: (clock.advance(3), 2)[1])
        self.refused("DEADLINE", wire.write, b"abcdef", 12)
        self.assertEqual(wire._write_bytes, 2)
        self.assertEqual(bytes(wire._socket.accepted), b"ab")
        self.refused("OWNER_HELD", wire.write, b"abcdef", 15)
        self.assertEqual(wire._socket.sent, [b"abcdef"])
        wire.close(14)

    def test_supplied_absolute_request_deadline_is_not_reset_after_progress(self):
        clock, factory, waiter, http, ws, wire = self.opened()
        waiter.results.extend((lambda *args: (clock.advance(.75), True)[1],
                               lambda *args: (clock.advance(.3), True)[1]))
        wire._socket.sends.extend((1, 1))
        self.refused("DEADLINE", wire.write, b"ab", 11)
        self.assertEqual(bytes(wire._socket.accepted), b"a")
        self.assertEqual(len(waiter.calls), 2)
        self.assertAlmostEqual(waiter.calls[0][2], 1)
        self.assertAlmostEqual(waiter.calls[1][2], .25)
        wire.close(clock() + 1)

    def test_session_expiry_refuses_new_open_but_allows_independent_close(self):
        clock, factory, waiter, http, ws, wire = self.opened()
        clock.advance(241)
        self.refused("DEADLINE", ws.open, policy.WS_ORIGIN, clock() + 2)
        self.assertEqual(len(factory.calls), 1)
        self.assertTrue(wire.close(clock() + 1).complete)

    def test_clock_regression_is_held_and_does_not_reconstruct_clock_or_socket(self):
        clock, factory, waiter, http, ws, wire = self.opened()
        clock.value = 9
        self.refused("DEADLINE", wire.read, 1, 12)
        self.refused("CLOSE_UNKNOWN", wire.close, 12)
        self.assertEqual(wire._socket.close_calls, 0)
        self.assertEqual(len(factory.calls), 1)

    def test_close_unknown_is_terminal_and_only_original_close_is_issued_once(self):
        for mode in ("error", "late", "stays_open", "float_closed", "expired"):
            with self.subTest(mode=mode):
                clock, factory, waiter, http, ws, wire = self.opened()
                raw = wire._socket
                end = 11
                if mode == "error":
                    raw.close_error = OSError(errno.EIO, PRIVATE)
                elif mode == "late":
                    raw.hooks["close"] = lambda *args: clock.advance(1.1)
                elif mode == "stays_open":
                    raw.close_stays_open = True
                elif mode == "float_closed":
                    def malformed_descriptor(original):
                        if original.close_calls:
                            original.fd = -1.0
                    raw.hooks["fileno"] = malformed_descriptor
                else:
                    end = 10
                self.refused("CLOSE_UNKNOWN", wire.close, end)
                self.refused("CLOSE_UNKNOWN", wire.close, clock() + 1)
                self.assertEqual(raw.close_calls, 0 if mode == "expired" else 1)
                self.assertTrue(http.held)
                self.assertTrue(ws.held)
                self.assertFalse(wire._closed)
                if mode == "float_closed":
                    self.assertIs(type(raw.fd), float)

    def test_successful_close_cannot_be_issued_again_or_reused_for_io(self):
        clock, factory, waiter, http, ws, wire = self.opened()
        receipt = wire.close(11)
        self.assertIs(receipt.wire, wire)
        self.refused("CLOSE_UNKNOWN", wire.close, 11)
        self.refused("OWNER_HELD", wire.read, 1, 12)
        self.assertEqual(wire._socket.close_calls, 1)

    def test_raw_factory_and_io_errors_are_private_finite_public_exceptions(self):
        raw_error = OSError(errno.EIO, PRIVATE)
        clock, factory, waiter, http, ws = self.fixture(raw_error)
        self.refused("WIRE_REFUSED", http.open, policy.HTTP_ORIGIN, 12)
        self.assertTrue(any(error is raw_error for error in http._ledger._errors))
        clock, factory, waiter, http, ws, wire = self.opened()
        wire._socket.receives.append(raw_error)
        self.refused("WIRE_REFUSED", wire.read, 1, 12)
        self.assertTrue(any(error is raw_error for error in http._ledger._errors))
        wire.close(11)

    def test_transport_does_not_grant_build_storage_wallet_or_seed_admission(self):
        clock, factory, waiter, http, ws = self.fixture()
        digest = lambda value: "%064x" % value
        pins = policy.Pins(
            application_sha="1" * 40, application_tree="2" * 40, node_tree="3" * 40,
            image_id="sha256:" + digest(4), genesis_sha256=digest(5),
            genesis_momentum_hash=digest(6), assets_sha256=digest(7),
            configs_sha256=tuple(digest(value) for value in range(8, 13)),
            build_context_sha256=digest(13), dockerfile_sha256=digest(14),
            base_image_ids=("sha256:" + digest(15),))
        supervisor = policy.Supervisor(http_transport=http, ws_transport=ws, clock=clock)
        self.assertIsNone(supervisor.launch(pins))
        report = supervisor.public()
        self.assertEqual(report["provenance"], "UNKNOWN")
        self.assertEqual(report["error_codes"], ["BUILD_UNKNOWN"])
        self.assertFalse(report["seed_admitted"])
        self.assertFalse(report["success"])
        self.assertEqual(factory.calls, [])


@unittest.skipUnless(hasattr(socket, "socketpair") and hasattr(socket, "AF_UNIX"),
                     "AF_UNIX socketpair unavailable")
class SocketpairMechanicsTests(unittest.TestCase):
    def pair(self):
        try:
            left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
        except (OSError, ValueError):
            self.skipTest("AF_UNIX socketpair unavailable")
        ledger = transport._Ledger(None, transport._wait, time.monotonic)
        core = ledger.retain(left, transport._SocketIO)
        self.addCleanup(right.close)
        self.addCleanup(self.finish, core)
        core._prime(time.monotonic() + 1)
        return core, right

    def finish(self, core):
        if not core._close_attempted:
            self.assertTrue(core.close(time.monotonic() + 1).complete)

    def test_local_bytes_obey_read_limit_and_write_exact_payload(self):
        core, peer = self.pair()
        peer.settimeout(1)
        peer.sendall(b"abcdef")
        end = time.monotonic() + 1
        self.assertEqual(core.read(2, end), b"ab")
        self.assertEqual(core.read(4, end), b"cdef")
        core.write(b"response", end)
        received, receive_end = bytearray(), time.monotonic() + 1
        for _ in range(8):
            remaining = receive_end - time.monotonic()
            self.assertGreater(remaining, 0)
            peer.settimeout(remaining)
            chunk = peer.recv(8 - len(received))
            self.assertTrue(chunk)
            received.extend(chunk)
            if len(received) == 8:
                break
        self.assertEqual(bytes(received), b"response")
        receipt = core.close(time.monotonic() + 1)
        self.assertIs(type(receipt), policy.Closed)
        self.assertIs(receipt.wire, core)
        self.assertEqual(core._socket.fileno(), -1)

    def test_local_eof_holds_original_without_reconnect(self):
        core, peer = self.pair()
        peer.close()
        with self.assertRaises(policy.Refused) as caught:
            core.read(1, time.monotonic() + 1)
        self.assertEqual(caught.exception.code, "WIRE_EOF")
        self.assertTrue(core._ledger.held)
        self.assertTrue(core.close(time.monotonic() + 1).complete)

    def test_local_empty_read_has_independent_finite_deadline(self):
        core, peer = self.pair()
        with self.assertRaises(policy.Refused) as caught:
            core.read(1, time.monotonic() + .02)
        self.assertEqual(caught.exception.code, "DEADLINE")
        self.assertTrue(core._ledger.held)
        self.assertTrue(core.close(time.monotonic() + 1).complete)
