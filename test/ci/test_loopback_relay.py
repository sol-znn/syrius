"""Injected byte and lifecycle cases; no real listener, thread or node."""

from collections import deque
import importlib.util
import socket
import threading
import unittest
from unittest import mock

from tool.ci import loopback_relay as relay


class Stream:
    def __init__(self, data):
        self.data = deque(data)
        self.output = bytearray()
        self.shutdowns = []
        self.limit = 2

    def setblocking(self, value):
        self.blocking = value

    def recv(self, maximum):
        value = self.data.popleft() if self.data else b""
        if len(value) > maximum:
            self.data.appendleft(value[maximum:])
        return value[:maximum]

    def send(self, data):
        count = min(self.limit, len(data))
        self.output.extend(data[:count])
        return count

    def shutdown(self, direction):
        self.shutdowns.append(direction)


def ready(readers, writers, errors, seconds):
    return readers, writers, []


def listener():
    item = mock.Mock()
    item.fileno.return_value = 50
    item.bind.side_effect = lambda address: setattr(item, "bound", address)
    item.getsockname.side_effect = lambda: item.bound
    item.close.side_effect = lambda: setattr(item.fileno, "return_value", -1)
    return item


def worker():
    item = mock.Mock()
    item.ident = 100
    item.is_alive.return_value = False
    return item


class RelayTests(unittest.TestCase):
    def test_partial_writes_preserve_both_original_streams(self):
        left, right = Stream([b"request", b""]), Stream([b"reply", b""])
        total = relay.pump(left, right, threading.Event(), _select=ready, _clock=lambda: 1)
        self.assertEqual(bytes(left.output), b"reply")
        self.assertEqual(bytes(right.output), b"request")
        self.assertEqual(total, 12)

    def test_stop_admits_no_further_read_or_write(self):
        left, right = mock.Mock(), mock.Mock()
        stopped = threading.Event()
        stopped.set()
        self.assertEqual(relay.pump(left, right, stopped, _select=ready, _clock=lambda: 1), 0)
        left.recv.assert_not_called()
        right.send.assert_not_called()

    def test_zero_write_cannot_be_treated_as_forwarded_bytes(self):
        left, right = Stream([b"request", b""]), Stream([b""])
        right.limit = 0
        with self.assertRaises(relay.RelayError):
            relay.pump(left, right, threading.Event(), _select=ready, _clock=lambda: 1)

    def test_byte_limit_refuses_before_forwarding_an_oversized_prefix(self):
        left, right = Stream([b"four"]), Stream([b""])
        with mock.patch.object(relay, "MAX_BYTES", 3), self.assertRaises(relay.RelayError):
            relay.pump(left, right, threading.Event(), _select=ready, _clock=lambda: 1)
        self.assertEqual(bytes(right.output), b"")

    def test_start_binds_only_loopback_and_stop_closes_each_original_once(self):
        originals, workers = [listener(), listener()], [worker(), worker()]
        with mock.patch.object(relay.socket, "socket", side_effect=originals), \
                mock.patch.object(relay.threading, "Thread", side_effect=workers):
            owner = relay.Relay()
            owner.start()
        self.assertEqual([item.bound for item in originals], [("127.0.0.1", 45997), ("127.0.0.1", 45998)])
        owner.stop()
        owner.stop()
        for item in originals:
            item.close.assert_called_once_with()
        self.assertTrue(owner.summary()["closed"])

    def test_second_bind_failure_closes_only_the_two_created_originals(self):
        originals, foreign = [listener(), listener()], listener()
        originals[1].bind.side_effect = OSError("fixture bind refusal")
        with mock.patch.object(relay.socket, "socket", side_effect=originals), \
                mock.patch.object(relay.threading, "Thread", return_value=worker()), \
                self.assertRaises(OSError):
            relay.Relay().start()
        for item in originals:
            item.close.assert_called_once_with()
        foreign.close.assert_not_called()

    def test_unknown_stop_is_terminal_and_never_reissues_close_or_join(self):
        owner = relay.Relay()
        item = worker()
        item.is_alive.return_value = True
        owner.threads.append(item)
        with self.assertRaises(relay.RelayError):
            owner.stop()
        before = item.join.call_count
        with self.assertRaises(relay.RelayError):
            owner.stop()
        self.assertEqual(item.join.call_count, before)
        self.assertFalse(owner.closed)

    def test_import_has_no_socket_or_thread_side_effect(self):
        spec = importlib.util.spec_from_file_location("relay_import_probe", relay.__file__)
        module = importlib.util.module_from_spec(spec)
        with mock.patch.object(socket, "socket", side_effect=AssertionError("socket allocation")), \
                mock.patch.object(threading, "Thread", side_effect=AssertionError("thread allocation")):
            spec.loader.exec_module(module)
        self.assertEqual(module.TARGET, "172.37.0.11")


if __name__ == "__main__":
    unittest.main()
