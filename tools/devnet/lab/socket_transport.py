"""Finite direct-loopback byte transports for the owned lab policy.

Only make_transports is an integration entry point. It allocates nothing until
open; there is no CLI, resolver, proxy, reconnect, listener or import-time I/O.
The underscored injections are trusted implementation/test seams, not caller
claims or permission to adopt an existing socket. They must allocate fresh
original sockets. This module does not establish build, storage or lab ownership.
"""

from __future__ import annotations

import errno
import math
import select
import socket
import time

from tools.devnet.lab import owned_lab as policy


_MAX_SECONDS = 3.0
_CLOSE_SECONDS = 1.0
_SESSION_SECONDS = 240.0
_STEPS = 64
_READ_MAX = 4096
_WRITE_MAX = 65543
_CALLS_MAX = 32768
_BYTES_MAX = 1048576
_PENDING = frozenset((errno.EINPROGRESS, errno.EWOULDBLOCK, errno.EALREADY,
                      errno.EINTR, 10035, 10036, 10037, 10004))
_TRANSIENT = frozenset((errno.EINTR, errno.EAGAIN, errno.EWOULDBLOCK,
                        10004, 10035))
_NOT_CONNECTED = frozenset((errno.ENOTCONN, 10057))


def _require(condition, code="WIRE_REFUSED"):
    if not condition:
        raise policy.Refused(code)


def _wait(original, writing, seconds):
    """select receives only this original nonblocking socket and a finite bound."""
    read, write, errors = select.select(
        [] if writing else [original], [original] if writing else [],
        [original], seconds)
    return bool(read or write or errors)


def _endpoint(value, port=None):
    return (type(value) is tuple and len(value) == 2
            and value[0] == "127.0.0.1" and type(value[1]) is int
            and 0 < value[1] <= 65535 and (port is None or value[1] == port))


class _Ledger:
    def __init__(self, factory, waiter, clock):
        self.factory, self.waiter, self.clock = factory, waiter, clock
        self.held = False
        self._last_time = self._session_end = None
        self._wires, self._descriptors, self._errors = [], {}, []
        self._last_error = None

    def now(self):
        value = self.clock()
        _require(type(value) in (int, float) and math.isfinite(value)
                 and (self._last_time is None or value >= self._last_time),
                 "DEADLINE")
        self._last_time = value
        return value

    def deadline(self, supplied, cleanup=False):
        now = self.now()
        _require(type(supplied) in (int, float) and math.isfinite(supplied)
                 and now < supplied, "DEADLINE")
        if cleanup:
            return min(supplied, now + _CLOSE_SECONDS)
        _require(not self.held, "OWNER_HELD")
        if self._session_end is None:
            self._session_end = now + _SESSION_SECONDS
        end = min(supplied, now + _MAX_SECONDS, self._session_end)
        _require(now < end, "DEADLINE")
        return end

    def hold(self, error):
        self.held = True
        # Original exceptions stay in memory only; no raw diagnostic projection.
        self._last_error = error
        if len(self._errors) < 32 and all(error is not old for old in self._errors):
            self._errors.append(error)

    def fail(self, error, fallback="WIRE_REFUSED"):
        self.hold(error)
        if not isinstance(error, Exception):
            raise error
        code = error.code if isinstance(error, policy.Refused) else fallback
        raise policy.Refused(code) from None

    def retain(self, original, wire_type):
        _require(original is not None and len(self._wires) < 129)
        _require(all(original is not old._socket for old in self._wires))
        wire = wire_type(self, original)
        # Retain the exact returned original before descriptor/timing checks.
        self._wires.append(wire)
        descriptor = original.fileno()
        _require(type(descriptor) is int and descriptor >= 0)
        # Never close a second object referring to another active original FD.
        _require(descriptor not in self._descriptors)
        wire._descriptor_id = descriptor
        self._descriptors[descriptor] = wire
        return wire


class _SocketIO:
    """Private nonblocking mechanics; this alone is not a loopback Transport."""

    def __init__(self, ledger, original):
        self._ledger, self._socket = ledger, original
        self._descriptor_id = None
        self._close_attempted = self._closed = False
        self._read_calls = self._write_calls = 0
        self._read_bytes = self._write_bytes = 0

    def _remaining(self, end):
        remaining = end - self._ledger.now()
        _require(remaining > 0, "DEADLINE")
        return remaining

    def _call(self, end, method, *args):
        self._remaining(end)
        result = method(*args)
        self._remaining(end)
        return result

    def _descriptor(self, end):
        descriptor = self._call(end, self._socket.fileno)
        _require(self._descriptor_id is not None
                 and type(descriptor) is int and descriptor == self._descriptor_id
                 and self._ledger._descriptors.get(descriptor) is self)

    def _linger(self, end):
        linger = self._call(end, self._socket.getsockopt,
                            socket.SOL_SOCKET, socket.SO_LINGER, 8)
        # Fresh sockets have disabled linger. Both native struct widths are
        # accepted; enabled/stale settings never authorize a possibly blocking close.
        _require(type(linger) is bytes and len(linger) in (4, 8)
                 and not any(linger))

    def _prime(self, end):
        self._call(end, self._socket.setblocking, False)
        self._descriptor(end)
        _require(self._call(end, self._socket.getblocking) is False)
        kind = self._call(end, self._socket.getsockopt,
                          socket.SOL_SOCKET, socket.SO_TYPE)
        _require(type(kind) is int and kind == socket.SOCK_STREAM)
        self._linger(end)

    def _identity(self, end):
        self._descriptor(end)
        _require(not self._close_attempted and not self._closed)
        _require(self._call(end, self._socket.getblocking) is False)
        kind = self._call(end, self._socket.getsockopt,
                          socket.SOL_SOCKET, socket.SO_TYPE)
        _require(type(kind) is int and kind == socket.SOCK_STREAM)
        self._linger(end)

    def _ready(self, end, writing):
        self._identity(end)
        remaining = self._remaining(end)
        ready = self._ledger.waiter(self._socket, writing, remaining)
        self._remaining(end)
        _require(type(ready) is bool)
        _require(ready, "DEADLINE")
        self._identity(end)

    def read(self, maximum, deadline):
        try:
            end = self._ledger.deadline(deadline)
            _require(type(maximum) is int and 0 < maximum <= _READ_MAX,
                     "WIRE_OVERFLOW")
            self._read_calls += 1
            _require(self._read_calls <= _CALLS_MAX
                     and self._read_bytes < _BYTES_MAX, "WIRE_OVERFLOW")
            maximum = min(maximum, _BYTES_MAX - self._read_bytes)
            for _ in range(_STEPS):
                try:
                    self._ready(end, False)
                    data = self._socket.recv(maximum)
                except OSError as error:
                    if error.errno in _TRANSIENT:
                        continue
                    raise
                _require(type(data) is bytes and len(data) <= maximum,
                         "WIRE_OVERFLOW")
                self._read_bytes += len(data)
                self._remaining(end)
                self._identity(end)
                _require(self._read_bytes <= _BYTES_MAX, "WIRE_OVERFLOW")
                _require(bool(data), "WIRE_EOF")
                return data
            raise policy.Refused("WIRE_OVERFLOW")
        except BaseException as error:
            self._ledger.fail(error)

    def write(self, data, deadline):
        try:
            end = self._ledger.deadline(deadline)
            _require(type(data) is bytes and 0 < len(data) <= _WRITE_MAX,
                     "WIRE_OVERFLOW")
            self._write_calls += 1
            _require(self._write_calls <= _CALLS_MAX
                     and self._write_bytes + len(data) <= _BYTES_MAX,
                     "WIRE_OVERFLOW")
            offset = 0
            for _ in range(_STEPS):
                try:
                    self._ready(end, True)
                    count = self._socket.send(memoryview(data)[offset:])
                except OSError as error:
                    if error.errno in _TRANSIENT:
                        continue
                    raise
                _require(type(count) is int and 0 <= count <= len(data) - offset)
                _require(count > 0, "WIRE_EOF")
                # Preserve actual progress before a late-return check. Never
                # resend a completed prefix, even after a partial failure.
                offset += count
                self._write_bytes += count
                self._remaining(end)
                self._identity(end)
                _require(self._write_bytes <= _BYTES_MAX, "WIRE_OVERFLOW")
                if offset == len(data):
                    return None
            raise policy.Refused("WIRE_OVERFLOW")
        except BaseException as error:
            self._ledger.fail(error)

    def _closing_identity(self, end):
        self._descriptor(end)

    def close(self, deadline):
        # A failed/late close is terminal. No second close, detach or FD lookup.
        if self._close_attempted:
            self._ledger.fail(policy.Refused("CLOSE_UNKNOWN"), "CLOSE_UNKNOWN")
        self._close_attempted = True
        try:
            end = self._ledger.deadline(deadline, cleanup=True)
            self._closing_identity(end)
            # A late factory return may precede _prime. Make this retained
            # original nonblocking under the independent cleanup deadline.
            self._call(end, self._socket.setblocking, False)
            _require(self._call(end, self._socket.getblocking) is False,
                     "CLOSE_UNKNOWN")
            self._linger(end)
            self._descriptor(end)
            self._call(end, self._socket.close)
            descriptor = self._call(end, self._socket.fileno)
            _require(type(descriptor) is int and descriptor == -1,
                     "CLOSE_UNKNOWN")
            self._closed = True
            del self._ledger._descriptors[self._descriptor_id]
            return policy.Closed(self, True, False)
        except BaseException as error:
            self._ledger.hold(error)
            if not isinstance(error, Exception):
                raise
            raise policy.Refused("CLOSE_UNKNOWN") from None


class _SocketWire(_SocketIO):
    def __init__(self, ledger, original):
        super().__init__(ledger, original)
        self._local = self._peer = None

    def _identity(self, end):
        super()._identity(end)
        _require(self._socket.family == socket.AF_INET)
        if self._local is not None:
            local = self._call(end, self._socket.getsockname)
            _require(_endpoint(local) and local == self._local)
        if self._peer is not None:
            peer = self._call(end, self._socket.getpeername)
            _require(_endpoint(peer, self._peer[1]) and peer == self._peer)

    def _closing_identity(self, end):
        super()._closing_identity(end)
        if self._local is not None:
            _require(self._socket.family == socket.AF_INET)
            local = self._call(end, self._socket.getsockname)
            _require(_endpoint(local) and local == self._local)
        if self._peer is not None:
            kind = self._call(end, self._socket.getsockopt,
                              socket.SOL_SOCKET, socket.SO_TYPE)
            _require(type(kind) is int and kind == socket.SOCK_STREAM)
            peer = self._call(end, self._socket.getpeername)
            _require(_endpoint(peer, self._peer[1]) and peer == self._peer)

    def connect(self, peer, end):
        self._prime(end)
        _require(self._socket.family == socket.AF_INET)
        try:
            initial = self._call(end, self._socket.getsockname)
        except OSError as error:
            # Winsock reports WSAEINVAL before bind. Only that exact status
            # may proceed to the one explicit bind below; another existing
            # binding still makes bind fail and can never be adopted.
            native = getattr(error, "winerror", None)
            _require(native == 10022 or (native is None and error.errno == 10022))
            self._remaining(end)
        else:
            _require(type(initial) is tuple and initial == ("0.0.0.0", 0)
                     and type(initial[1]) is int)
        try:
            self._call(end, self._socket.getpeername)
        except OSError as error:
            _require(error.errno in _NOT_CONNECTED)
            self._remaining(end)
        else:
            raise policy.Refused("WIRE_REFUSED")
        self._call(end, self._socket.bind, ("127.0.0.1", 0))
        local = self._call(end, self._socket.getsockname)
        _require(_endpoint(local) and local != peer)
        self._local = local
        # The original is already retained and nonblocking before the one
        # connect_ex. EINTR/pending waits inspect this attempt, never repeat it.
        self._identity(end)
        result = self._call(end, self._socket.connect_ex, peer)
        _require(type(result) is int)
        if result != 0:
            if result not in _PENDING:
                raise OSError(result, "original connect refused")
            for _ in range(_STEPS):
                try:
                    self._ready(end, True)
                    result = self._call(end, self._socket.getsockopt,
                                        socket.SOL_SOCKET, socket.SO_ERROR)
                except OSError as error:
                    if error.errno in _TRANSIENT:
                        continue
                    raise
                _require(type(result) is int)
                if result == 0:
                    break
                if result not in _PENDING:
                    raise OSError(result, "original connect refused")
            else:
                raise policy.Refused("WIRE_OVERFLOW")
        result = self._call(end, self._socket.getsockopt,
                            socket.SOL_SOCKET, socket.SO_ERROR)
        _require(type(result) is int)
        if result != 0:
            raise OSError(result, "original connection unproven")
        actual_peer = self._call(end, self._socket.getpeername)
        _require(_endpoint(actual_peer, peer[1]) and actual_peer == peer)
        self._peer = actual_peer
        self._identity(end)


class _Transport:
    def __init__(self, ledger, origin, port, attempts):
        self._ledger, self._origin = ledger, origin
        self._peer, self._limit, self._attempts = ("127.0.0.1", port), attempts, 0

    @property
    def held(self):
        return self._ledger.held

    def open(self, origin, deadline):
        wire = None
        try:
            _require(type(origin) is str and origin == self._origin)
            end = self._ledger.deadline(deadline)
            _require(self._attempts < self._limit)
            self._attempts += 1
            original = self._ledger.factory(
                socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP)
            # retain may itself refuse a duplicated original/active descriptor.
            # Such a candidate is preserved and never closed as a foreign owner.
            wire = self._ledger.retain(original, _SocketWire)
            wire._remaining(end)
            wire.connect(self._peer, end)
            return wire
        except BaseException as error:
            self._ledger.hold(error)
            failure = error
            if wire is not None:
                try:
                    wire.close(self._ledger.now() + _CLOSE_SECONDS)
                except BaseException as close_error:
                    self._ledger.hold(close_error)
                    if not isinstance(close_error, Exception):
                        raise
                    if isinstance(error, Exception):
                        failure = policy.Refused("CLOSE_UNKNOWN")
            self._ledger.fail(failure)


def make_transports(*, _socket_factory=None, _waiter=None, _clock=None):
    """Return distinct fixed HTTP/WS transports, without allocating a socket.

    Injections are trusted source-level seams. They are never read from lab
    reports, environment flags, RPC input or a saved descriptor. Integrations
    must import owned_lab by this canonical package path as well.
    """
    ledger = _Ledger(_socket_factory if _socket_factory is not None else socket.socket,
                     _waiter if _waiter is not None else _wait,
                     _clock if _clock is not None else time.monotonic)
    return (_Transport(ledger, policy.HTTP_ORIGIN, 45997, 128),
            _Transport(ledger, policy.WS_ORIGIN, 45998, 1))
