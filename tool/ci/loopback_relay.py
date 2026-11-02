"""Owned loopback byte relays to the one RPC node on the internal lab bridge.

There is no CLI, DNS lookup, saved descriptor or configurable destination.
Importing this module allocates nothing. Only original sockets and threads
created by one Relay may be stopped; a saved summary is never an owner.
"""

from __future__ import annotations

import select
import socket
import threading
import time


PAIRS = ((45997, 35997), (45998, 35998))
TARGET = "172.37.0.11"
BUFFER = 32768
MAX_BYTES = 2 * 1024**2


class RelayError(Exception):
    pass


def need(value):
    if not value:
        raise RelayError("RELAY_REFUSED")


def pump(left, right, stopped, *, _select=select.select, _clock=time.monotonic):
    """Bound both directions, preserve unsent prefixes and propagate EOF."""
    sockets = (left, right)
    peer = {left: right, right: left}
    readers, pending, ended = set(sockets), {left: bytearray(), right: bytearray()}, set()
    total, end = 0, _clock() + 300
    for item in sockets:
        item.setblocking(False)
    while readers or any(pending.values()):
        if stopped.is_set():
            return total
        need(_clock() < end)
        for item in sockets:
            if item not in readers and not pending[peer[item]] and item not in ended:
                try:
                    peer[item].shutdown(socket.SHUT_WR)
                except OSError:
                    pass
                ended.add(item)
        ready_read, ready_write, errors = _select(
            [item for item in readers if len(pending[peer[item]]) < BUFFER],
            [item for item in sockets if pending[item]], list(sockets), 0.1)
        need(not errors)
        for item in ready_read:
            try:
                data = item.recv(min(16384, BUFFER - len(pending[peer[item]])))
            except (BlockingIOError, InterruptedError):
                continue
            need(type(data) is bytes)
            if not data:
                readers.remove(item)
                continue
            total += len(data)
            need(total <= MAX_BYTES)
            pending[peer[item]].extend(data)
        for item in ready_write:
            try:
                count = item.send(pending[item])
            except (BlockingIOError, InterruptedError):
                continue
            need(type(count) is int and 0 < count <= len(pending[item]))
            del pending[item][:count]
    return total


class Relay:
    def __init__(self):
        self.stopped = threading.Event()
        self.lock = threading.Lock()
        self.listeners, self.threads, self.active = [], [], []
        self.accepted, self.completed, self.bytes = 0, 0, 0
        self.started = self.closed = False
        self.stop_attempted = False

    def start(self):
        need(not self.started and not self.closed and not self.listeners)
        try:
            for local, target in PAIRS:
                original = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self.listeners.append(original)
                original.settimeout(0.2)
                original.bind(("127.0.0.1", local))
                need(original.getsockname() == ("127.0.0.1", local))
                original.listen(4)
                worker = threading.Thread(target=self._accept, args=(original, target), daemon=True)
                self.threads.append(worker)
                worker.start()
            self.started = True
        except BaseException:
            self.stop()
            raise

    def _accept(self, original, target):
        attempts = 0
        while not self.stopped.is_set():
            try:
                client, address = original.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            with self.lock:
                if self.stopped.is_set() or address[0] != "127.0.0.1" or len(self.active) >= 4 or attempts >= 128:
                    client.close()
                    continue
                attempts += 1
                self.accepted += 1
                pair = [client]
                self.active.append(pair)
                worker = threading.Thread(target=self._serve, args=(pair, target), daemon=True)
                self.threads.append(worker)
                worker.start()

    def _serve(self, pair, target):
        count = 0
        try:
            upstream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            with self.lock:
                pair.append(upstream)
            upstream.settimeout(1)
            upstream.connect((TARGET, target))
            need(upstream.getpeername() == (TARGET, target))
            count = pump(pair[0], upstream, self.stopped)
        except (OSError, RelayError):
            pass
        finally:
            for original in pair:
                original.close()
            with self.lock:
                self.bytes += count
                self.completed += 1
                self.active.remove(pair)

    def stop(self):
        if self.stop_attempted:
            need(self.closed)
            return
        self.stop_attempted = True
        self.stopped.set()
        for original in self.listeners:
            original.close()
        with self.lock:
            active = [original for pair in self.active for original in pair]
        for original in active:
            try:
                original.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        # An accept worker can append one final owned worker before seeing stop.
        end = time.monotonic() + 3
        for worker in tuple(self.threads):
            if worker.ident is not None:
                worker.join(max(0, end - time.monotonic()))
        for worker in tuple(self.threads):
            if worker.is_alive():
                worker.join(max(0, end - time.monotonic()))
        need(not any(worker.is_alive() for worker in self.threads) and not self.active
             and all(original.fileno() == -1 for original in self.listeners))
        self.closed = True

    def summary(self):
        return dict(started=self.started, closed=self.closed, listeners=len(self.listeners),
                    accepted=self.accepted, completed=self.completed, bytes=self.bytes,
                    active=len(self.active), workers_alive=sum(worker.is_alive() for worker in self.threads))
