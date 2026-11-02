"""Injected, fresh-only chain-321 supervisor policy; no native adapters or CLI.

Importing this module performs no I/O. A trusted integration must implement the
build, managed-storage, runtime and two wire-transport contracts below. Expected
pins, Docker labels and saved reports are data, never ownership capabilities.
The only capability is the original in-memory Owner minted by one Supervisor.
No wallet/checkpoint adapter is connected; seed admission is always false.
"""

from __future__ import annotations

import base64
from dataclasses import dataclass, field
import hashlib
import json
import math
import re
import secrets
import time
from typing import Optional, Protocol, Tuple


NODE_SHA = "590f43ca7a24dccd8e883bc8903a0cb02e54528a"
HTTP_ORIGIN = "http://127.0.0.1:45997"
WS_ORIGIN = "ws://127.0.0.1:45998"
ROLES = ("pillar", "pillar2", "pillar3", "observer", "rpc")
IPS = ("172.37.0.10", "172.37.0.12", "172.37.0.13", "172.37.0.14", "172.37.0.11")
SUBNET = "172.37.0.0/24"
PORTS = (("127.0.0.1", 45997, 35997), ("127.0.0.1", 45998, 35998))
CHECKS = ("build", "storage", "preflight", "created", "started", "identity",
          "http", "ws", "genesis", "cross_hash", "advancing", "stop", "exit")
CODES = frozenset((
    "PINS_REFUSED", "LIMITS_REFUSED", "BUILD_UNKNOWN", "BUILD_REFUSED",
    "STORAGE_REFUSED", "PREFLIGHT_REFUSED", "CREATE_UNKNOWN", "START_UNKNOWN",
    "COMMAND_UNPROVEN", "OUTPUT_OVERFLOW", "RESOURCE_CHANGED", "OWNER_REFUSED",
    "OWNER_HELD", "ALREADY_ATTEMPTED", "DEADLINE", "WIRE_REFUSED", "WIRE_EOF",
    "WIRE_OVERFLOW", "HTTP_REFUSED", "WS_REFUSED", "RPC_REFUSED",
    "FRONTIER_REFUSED", "FRONTIER_REGRESSED", "GENESIS_MISMATCH",
    "ENDPOINTS_DISAGREE", "PRODUCTION_UNPROVEN", "CLOSE_UNKNOWN",
    "STOP_UNKNOWN", "EXIT_UNPROVEN", "INTERNAL_ERROR",
))
CONFLICTS = frozenset(("container", "network", "volume", "port", "subnet", "mount"))
_SEAL = object()


class Refused(Exception):
    def __init__(self, code):
        self.code = code if code in CODES else "INTERNAL_ERROR"
        super().__init__(self.code)


def _require(condition, code):
    if not condition:
        raise Refused(code)


def _hex(value, size):
    return (type(value) is str and len(value) == size
            and re.fullmatch(r"[0-9a-f]+", value) is not None
            and any(c != "0" for c in value))


def _image(value):
    return type(value) is str and value.startswith("sha256:") and _hex(value[7:], 64)


def _opaque(value):
    return (type(value) is str
            and re.fullmatch(r"[A-Za-z0-9:_.+\-]{1,128}", value) is not None)


def _digest(value):
    return hashlib.sha256(value.encode("ascii")).hexdigest()


@dataclass(frozen=True)
class Limits:
    total: float = 240.0
    request: float = 3.0
    command: float = 20.0
    close: float = 1.0
    stop: float = 30.0
    poll: float = 5.0
    samples: int = 36
    exit_polls: int = 12
    header_bytes: int = 16384
    response_bytes: int = 262144
    frame_bytes: int = 262144
    frames: int = 8
    reads: int = 4096
    command_bytes: int = 131072

    def validate(self):
        for name in ("total", "request", "command", "close", "stop", "poll"):
            value = getattr(self, name)
            _require(type(value) in (int, float) and math.isfinite(value)
                     and 0 < value <= 600, "LIMITS_REFUSED")
        for name, maximum in (("samples", 48), ("exit_polls", 30),
                              ("header_bytes", 16384), ("response_bytes", 262144),
                              ("frame_bytes", 262144), ("frames", 16),
                              ("reads", 32768), ("command_bytes", 131072)):
            value = getattr(self, name)
            _require(type(value) is int and 0 < value <= maximum, "LIMITS_REFUSED")


@dataclass(frozen=True)
class Pins:
    application_sha: str
    application_tree: str
    node_tree: str
    image_id: str
    genesis_sha256: str
    genesis_momentum_hash: str
    assets_sha256: str
    configs_sha256: Tuple[str, ...]
    build_context_sha256: str
    dockerfile_sha256: str
    base_image_ids: Tuple[str, ...]
    node_sha: str = NODE_SHA
    platform: str = "linux/amd64"

    def validate(self):
        _require(self.node_sha == NODE_SHA and self.platform == "linux/amd64",
                 "PINS_REFUSED")
        _require(all(_hex(v, 40) for v in
                     (self.application_sha, self.application_tree, self.node_tree)),
                 "PINS_REFUSED")
        _require(_image(self.image_id), "PINS_REFUSED")
        _require(type(self.base_image_ids) is tuple and 0 < len(self.base_image_ids) <= 8
                 and all(_image(v) for v in self.base_image_ids), "PINS_REFUSED")
        _require(type(self.configs_sha256) is tuple and len(self.configs_sha256) == 5,
                 "PINS_REFUSED")
        _require(all(_hex(v, 64) for v in (
            self.genesis_sha256, self.genesis_momentum_hash, self.assets_sha256,
            self.build_context_sha256, self.dockerfile_sha256, *self.configs_sha256)),
            "PINS_REFUSED")


@dataclass(frozen=True)
class CommandReceipt:
    """Original command handle retained by the trusted adapter, never a PID lookup."""
    original: object
    exit_code: Optional[int]
    exit_observed: bool
    output_complete: bool
    output_bytes: int = 0
    overflow: bool = False
    forced: bool = False


@dataclass(frozen=True)
class BuildWitness:
    """Returned only by the injected verifier of an actual retained source build."""
    pins: Pins
    original_build: object


@dataclass(frozen=True)
class StorageReceipt:
    """Fresh manager reservation and five distinct directory-identity handles."""
    original_reservation: object
    roles: Tuple[object, ...]
    fresh: bool


@dataclass(frozen=True)
class Plan:
    name: str
    pins: Pins
    storage: StorageReceipt
    subnet: str = SUBNET
    ports: tuple = PORTS
    roles: tuple = ROLES


@dataclass(frozen=True)
class Preflight:
    daemon: str
    conflicts: Tuple[str, ...] = ()


@dataclass(frozen=True)
class NetworkSpec:
    name: str
    subnet: str = SUBNET


@dataclass(frozen=True)
class ContainerSpec:
    role: str
    name: str
    network_id: str
    ip: str
    image_id: str
    storage: object
    genesis_sha256: str
    config_sha256: str
    ports: tuple
    restart_policy: str = "no"
    log_bytes: int = 1048576
    log_files: int = 2


@dataclass(frozen=True)
class Created:
    request: object
    resource_id: str
    daemon: str
    command: CommandReceipt


@dataclass(frozen=True)
class Started:
    created: Created
    start_id: str
    command: CommandReceipt


@dataclass(frozen=True)
class NetworkState:
    resource_id: str
    daemon: str
    name: str
    subnet: str
    members: Tuple[str, ...]


@dataclass(frozen=True)
class ContainerState:
    resource_id: str
    daemon: str
    image_id: str
    network_id: str
    ip: str
    storage: object
    ports: tuple
    start_id: str
    running: bool
    restart_count: int
    exit_code: Optional[int] = None
    finished_id: Optional[str] = None
    forced: bool = False
    mounts: tuple = ()
    restart_policy: str = "no"


@dataclass(frozen=True)
class Closed:
    wire: object
    complete: bool
    forced: bool = False


class BuildAuthority(Protocol):
    def verify(self, pins: Pins, deadline: float) -> Optional[BuildWitness]: ...
    def current(self, witness: BuildWitness, deadline: float) -> bool: ...


class ManagedStorage(Protocol):
    def reserve(self, pins: Pins, deadline: float) -> StorageReceipt: ...
    def current(self, receipt: StorageReceipt, deadline: float) -> bool: ...


class Runtime(Protocol):
    def preflight(self, plan: Plan, deadline: float) -> Preflight: ...
    def create_network(self, spec: NetworkSpec, deadline: float) -> Created: ...
    def create_container(self, spec: ContainerSpec, deadline: float) -> Created: ...
    def start(self, created: Created, deadline: float) -> Started: ...
    def inspect_network(self, created: Created, deadline: float) -> NetworkState: ...
    def inspect_container(self, started: Started, deadline: float) -> ContainerState: ...
    def request_stop(self, started: Started, deadline: float) -> CommandReceipt: ...


class Wire(Protocol):
    def read(self, maximum: int, deadline: float) -> bytes: ...
    def write(self, data: bytes, deadline: float) -> None: ...
    def close(self, deadline: float) -> Closed: ...


class Transport(Protocol):
    def open(self, origin: str, deadline: float) -> Wire: ...


class _Deadline:
    def __init__(self, clock, end):
        self.clock, self.end = clock, end

    def check(self):
        _require(self.clock() < self.end, "DEADLINE")

    def child(self, seconds):
        self.check()
        return _Deadline(self.clock, min(self.end, self.clock() + seconds))

    def call(self, function, *args):
        self.check()
        result = function(*args, self.end)
        self.check()
        return result


class _Reader:
    def __init__(self, wire, limits, deadline):
        self.wire, self.limits, self.deadline = wire, limits, deadline
        self.buffer = bytearray()
        self.reads = 0

    def exact(self, size):
        _require(type(size) is int and 0 <= size <= self.limits.response_bytes,
                 "WIRE_OVERFLOW")
        while len(self.buffer) < size:
            self.reads += 1
            _require(self.reads <= self.limits.reads, "WIRE_OVERFLOW")
            maximum = min(4096, max(1, size - len(self.buffer)))
            chunk = self.deadline.call(self.wire.read, maximum)
            _require(type(chunk) is bytes and len(chunk) <= maximum, "WIRE_OVERFLOW")
            _require(bool(chunk), "WIRE_EOF")
            self.buffer.extend(chunk)
        result = bytes(self.buffer[:size])
        del self.buffer[:size]
        return result

    def until(self, marker, maximum):
        result = bytearray()
        while not result.endswith(marker):
            _require(len(result) < maximum, "WIRE_OVERFLOW")
            result.extend(self.exact(1))
        return bytes(result[:-len(marker)])

    def headers(self):
        raw = self.until(b"\r\n\r\n", self.limits.header_bytes)
        try:
            lines = raw.decode("ascii").split("\r\n")
        except UnicodeError:
            raise Refused("HTTP_REFUSED") from None
        _require(1 <= len(lines) <= 65, "HTTP_REFUSED")
        match = re.fullmatch(r"HTTP/1\.[01] ([0-9]{3})(?: [\x20-\x7e]*)?", lines[0])
        _require(match is not None, "HTTP_REFUSED")
        headers = {}
        for line in lines[1:]:
            name, sep, value = line.partition(":")
            _require(sep and re.fullmatch(r"[A-Za-z0-9-]+", name) is not None
                     and len(value) <= 4096
                     and all(32 <= ord(c) <= 126 for c in value), "HTTP_REFUSED")
            name = name.lower()
            _require(name not in headers, "HTTP_REFUSED")
            headers[name] = value.strip()
        return int(match.group(1)), headers

    def body(self, headers):
        length, encoding = headers.get("content-length"), headers.get("transfer-encoding")
        _require(headers.get("content-encoding", "identity").lower() == "identity",
                 "HTTP_REFUSED")
        _require(not (length is not None and encoding is not None), "HTTP_REFUSED")
        if length is not None:
            _require(re.fullmatch(r"0|[1-9][0-9]{0,8}", length) is not None,
                     "HTTP_REFUSED")
            return self.exact(int(length))
        _require(encoding is not None and encoding.lower() == "chunked", "HTTP_REFUSED")
        result = bytearray()
        for _ in range(256):
            line = self.until(b"\r\n", 32)
            _require(re.fullmatch(rb"[0-9A-Fa-f]{1,8}", line) is not None, "HTTP_REFUSED")
            size = int(line, 16)
            _require(len(result) + size <= self.limits.response_bytes, "WIRE_OVERFLOW")
            if size == 0:
                _require(self.exact(2) == b"\r\n", "HTTP_REFUSED")
                return bytes(result)
            result.extend(self.exact(size))
            _require(self.exact(2) == b"\r\n", "HTTP_REFUSED")
        raise Refused("WIRE_OVERFLOW")


def _json(raw, expected_id, limits):
    _require(type(raw) is bytes and len(raw) <= limits.response_bytes, "WIRE_OVERFLOW")

    def number(value):
        _require(len(value) <= 20, "RPC_REFUSED")
        return int(value)

    def invalid(_):
        raise Refused("RPC_REFUSED")

    def pairs(values):
        result = {}
        for key, value in values:
            _require(key not in result, "RPC_REFUSED")
            result[key] = value
        return result

    try:
        value = json.loads(raw.decode("utf-8"), parse_int=number, parse_float=invalid,
                           parse_constant=invalid, object_pairs_hook=pairs)
    except (ValueError, UnicodeError, RecursionError):
        raise Refused("RPC_REFUSED") from None
    pending, count = [(value, 0)], 0
    while pending:
        item, depth = pending.pop()
        count += 1
        _require(count <= 4096 and depth <= 24, "RPC_REFUSED")
        if type(item) is dict:
            pending.extend((child, depth + 1) for child in item.values())
        elif type(item) is list:
            pending.extend((child, depth + 1) for child in item)
    _require(type(value) is dict and value.get("jsonrpc") == "2.0"
             and type(value.get("id")) is int and value["id"] == expected_id
             and value.get("error") is None and "result" in value
             and set(value) <= {"jsonrpc", "id", "result", "error"}, "RPC_REFUSED")
    return value["result"]


class _Rpc:
    def __init__(self, transport, limits, deadline, entropy, seen_wires=None):
        self.transport, self.limits = transport, limits
        self.deadline, self.entropy = deadline, entropy
        self.next_id = 0
        self.held_wires = []
        self.seen_wires = seen_wires if seen_wires is not None else []

    def _open(self, origin, deadline):
        deadline.check()
        wire = self.transport.open(origin, deadline.end)
        _require(wire is not None and all(wire is not old for old in self.seen_wires),
                 "WIRE_REFUSED")
        self.held_wires.append(wire)
        self.seen_wires.append(wire)
        # A late return still created this original wire. Retain it before
        # refusing admission so finalization can close it exactly once.
        deadline.check()
        return wire

    def _close(self, wire):
        _require(any(old is wire for old in self.held_wires), "CLOSE_UNKNOWN")
        # A close with an unknown outcome is retained, never issued again.
        self.held_wires[:] = [old for old in self.held_wires if old is not wire]
        deadline = _Deadline(self.deadline.clock,
                             self.deadline.clock() + self.limits.close)
        result = deadline.call(wire.close)
        _require(type(result) is Closed and result.wire is wire
                 and result.complete is True and result.forced is False, "CLOSE_UNKNOWN")

    def close(self):
        failure = None
        for wire in tuple(self.held_wires):
            try:
                self._close(wire)
            except Exception:
                failure = Refused("CLOSE_UNKNOWN")
        if failure is not None:
            raise failure

    def _height_allowed(self, height):
        return height == 1

    def _payload(self, method, params):
        _require(type(method) is str and method in (
                            "ledger.getFrontierMomentum", "ledger.getMomentumsByHeight",
                            "ledger.getMomentumByHash"), "RPC_REFUSED")
        _require(type(params) is list, "RPC_REFUSED")
        if method == "ledger.getFrontierMomentum":
            _require(not params, "RPC_REFUSED")
        elif method == "ledger.getMomentumsByHeight":
            _require(len(params) == 2 and type(params[0]) is int
                     and self._height_allowed(params[0])
                     and type(params[1]) is int and params[1] == 1, "RPC_REFUSED")
        else:
            _require(len(params) == 1 and _hex(params[0], 64), "RPC_REFUSED")
        _require(self.next_id < 256, "RPC_REFUSED")
        self.next_id += 1
        return json.dumps({"jsonrpc": "2.0", "id": self.next_id,
                           "method": method, "params": params}, separators=(",", ":")).encode()


class HttpRpc(_Rpc):
    def __init__(self, transport, limits, deadline, entropy, seen_wires=None, *,
                 retained_momentum=None):
        _require(retained_momentum is None or
                 type(retained_momentum) is Momentum
                 and all(type(value) is int and 0 < value < 2 ** 63
                         for value in (retained_momentum.height, retained_momentum.timestamp))
                 and _hex(retained_momentum.hash, 64), "RPC_REFUSED")
        super().__init__(transport, limits, deadline, entropy, seen_wires)
        # The optional original parsed momentum admits only its one height.
        self._retained_height = None if retained_momentum is None else retained_momentum.height

    def _height_allowed(self, height):
        return super()._height_allowed(height) or height == self._retained_height

    def call(self, method, params):
        deadline = self.deadline.child(self.limits.request)
        body = self._payload(method, params)
        wire = self._open(HTTP_ORIGIN, deadline)
        try:
            request = (b"POST / HTTP/1.1\r\nHost: 127.0.0.1:45997\r\n"
                       b"Content-Type: application/json\r\nConnection: close\r\n"
                       + ("Content-Length: %d\r\n\r\n" % len(body)).encode() + body)
            deadline.call(wire.write, request)
            reader = _Reader(wire, self.limits, deadline)
            status, headers = reader.headers()
            _require(status == 200 and headers.get("content-type", "").split(";", 1)[0]
                     .strip().lower() == "application/json", "HTTP_REFUSED")
            result = _json(reader.body(headers), self.next_id, self.limits)
            deadline.check()
            return result
        finally:
            self._close(wire)


class WsRpc(_Rpc):
    def connect(self):
        deadline = self.deadline.child(self.limits.request)
        self.wire = self._open(WS_ORIGIN, deadline)
        nonce = self.entropy(16)
        _require(type(nonce) is bytes and len(nonce) == 16, "WS_REFUSED")
        key = base64.b64encode(nonce).decode("ascii")
        request = ("GET / HTTP/1.1\r\nHost: 127.0.0.1:45998\r\nUpgrade: websocket\r\n"
                   "Connection: Upgrade\r\nSec-WebSocket-Version: 13\r\n"
                   "Sec-WebSocket-Key: " + key + "\r\n\r\n").encode("ascii")
        deadline.call(self.wire.write, request)
        self.reader = _Reader(self.wire, self.limits, deadline)
        status, headers = self.reader.headers()
        accept = base64.b64encode(hashlib.sha1(
            (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()).decode()
        _require(status == 101 and headers.get("upgrade", "").lower() == "websocket"
                 and "upgrade" in {part.strip() for part in
                                    headers.get("connection", "").lower().split(",")}
                 and headers.get("sec-websocket-accept") == accept
                 and "sec-websocket-extensions" not in headers
                 and "sec-websocket-protocol" not in headers
                 and "transfer-encoding" not in headers
                 and headers.get("content-length", "0") == "0", "WS_REFUSED")

    def _write(self, opcode, payload, deadline):
        mask = self.entropy(4)
        _require(type(mask) is bytes and len(mask) == 4 and len(payload) <= 65535,
                 "WS_REFUSED")
        prefix = bytes((128 | opcode, 128 | len(payload))) if len(payload) < 126 else (
            bytes((128 | opcode, 128 | 126)) + len(payload).to_bytes(2, "big"))
        deadline.call(self.wire.write, prefix + mask + bytes(
            value ^ mask[index % 4] for index, value in enumerate(payload)))

    def call(self, method, params):
        deadline = self.deadline.child(self.limits.request)
        self.reader.deadline, self.reader.reads = deadline, 0
        self._write(1, self._payload(method, params), deadline)
        result, fragmented, controls = bytearray(), False, 0
        for _ in range(self.limits.frames):
            first, second = self.reader.exact(2)
            final, opcode, size = bool(first & 128), first & 15, second & 127
            _require(first & 112 == 0 and second & 128 == 0, "WS_REFUSED")
            if size == 126:
                size = int.from_bytes(self.reader.exact(2), "big")
                _require(size >= 126, "WS_REFUSED")
            elif size == 127:
                size = int.from_bytes(self.reader.exact(8), "big")
                _require(65536 <= size < 2 ** 63, "WS_REFUSED")
            _require(size <= self.limits.frame_bytes, "WIRE_OVERFLOW")
            if opcode >= 8:
                controls += 1
                _require(final and size <= 125 and opcode in (9, 10) and controls <= 2,
                         "WS_REFUSED")
                payload = self.reader.exact(size)
                if opcode == 9:
                    self._write(10, payload, deadline)
                continue
            _require(opcode == (0 if fragmented else 1), "WS_REFUSED")
            _require(len(result) + size <= self.limits.response_bytes, "WIRE_OVERFLOW")
            result.extend(self.reader.exact(size))
            if final:
                value = _json(bytes(result), self.next_id, self.limits)
                deadline.check()
                return value
            fragmented = True
        raise Refused("WIRE_OVERFLOW")


@dataclass(frozen=True)
class Momentum:
    height: int
    timestamp: int
    hash: str

    @classmethod
    def parse(cls, value):
        _require(type(value) is dict and type(value.get("chainIdentifier")) is int
                 and value["chainIdentifier"] == 321, "FRONTIER_REFUSED")
        _require(all(type(value.get(key)) is int and 0 < value[key] < 2 ** 63
                     for key in ("height", "timestamp")) and _hex(value.get("hash"), 64),
                 "FRONTIER_REFUSED")
        return cls(value["height"], value["timestamp"], value["hash"])

    def follows(self, previous):
        _require(self.height >= previous.height, "FRONTIER_REGRESSED")
        if self.height == previous.height:
            _require(self == previous, "FRONTIER_REGRESSED")
        else:
            _require(self.timestamp > previous.timestamp and self.hash != previous.hash,
                     "FRONTIER_REGRESSED")


@dataclass
class _OwnerState:
    network: Optional[Created] = None
    created: list = field(default_factory=list)
    started: list = field(default_factory=list)
    stopped: list = field(default_factory=list)
    held: bool = False
    observed: bool = False
    probe_attempted: bool = False
    stop_attempted: bool = False
    closed: bool = False


class Owner:
    """Read-only public views; identity and issuer are checked at every entry."""
    __slots__ = ("_issuer", "plan", "witness", "daemon", "_state")

    def __init__(self, seal, issuer, plan, witness, daemon):
        _require(seal is _SEAL, "OWNER_REFUSED")
        for name, value in (("_issuer", issuer), ("plan", plan), ("witness", witness),
                            ("daemon", daemon), ("_state", _OwnerState())):
            object.__setattr__(self, name, value)

    def __setattr__(self, name, value):
        raise AttributeError("owner views are read only")

    @property
    def network(self):
        return self._state.network

    @property
    def created(self):
        return tuple(self._state.created)

    @property
    def started(self):
        return tuple(self._state.started)

    @property
    def stopped(self):
        return tuple(self._state.stopped)

    @property
    def held(self):
        return self._state.held

    @property
    def observed(self):
        return self._state.observed

    @property
    def probe_attempted(self):
        return self._state.probe_attempted

    @property
    def stop_attempted(self):
        return self._state.stop_attempted

    @property
    def closed(self):
        return self._state.closed

    @property
    def seed_admitted(self):
        return False


class Supervisor:
    def __init__(self, *, build=None, storage=None, runtime=None,
                 http_transport=None, ws_transport=None, limits=Limits(),
                 clock=time.monotonic, sleep=time.sleep, entropy=secrets.token_bytes):
        limits.validate()
        self.build, self.storage, self.runtime = build, storage, runtime
        self.http_transport, self.ws_transport = http_transport, ws_transport
        self.limits, self.clock, self.sleep, self.entropy = limits, clock, sleep, entropy
        self.owner, self.pins, self.attempted = None, None, False
        self.checks = dict.fromkeys(CHECKS, False)
        self.codes, self._private_failures, self._commands = [], [], []
        self._attempts, self._returned, self._seen_wires = [], [], []
        self._storage_receipt = self._build_witness = None
        self._revoked = False
        self.provenance = "UNKNOWN"
        self.samples = 0
        self._issuer = object()
        self._deadline = None

    def _hold(self, error, fallback="INTERNAL_ERROR"):
        code = error.code if isinstance(error, Refused) else fallback
        code = code if code in CODES else "INTERNAL_ERROR"
        if code not in self.codes:
            self.codes.append(code)
            self._private_failures.append(error)
        if code == "BUILD_UNKNOWN":
            self.provenance = "UNKNOWN"
        if self.owner is not None:
            self._revoked = True
            self.owner._state.held = True

    def _command(self, receipt):
        _require(type(receipt) is CommandReceipt and receipt.original is not None
                 and all(receipt.original is not prior for prior in self._commands),
                 "COMMAND_UNPROVEN")
        self._commands.append(receipt.original)
        _require(type(receipt.output_bytes) is int and 0 <= receipt.output_bytes
                 <= self.limits.command_bytes and receipt.overflow is False,
                 "OUTPUT_OVERFLOW")
        _require(receipt.exit_observed is True and type(receipt.exit_code) is int
                 and receipt.exit_code == 0 and receipt.output_complete is True
                 and receipt.forced is False, "COMMAND_UNPROVEN")

    def _mutation(self, function, request, deadline):
        """Retain even a late return before refusing its timing/identity proof."""
        self._attempts.append(request)
        bounded = deadline.child(self.limits.command)
        bounded.check()
        result = function(request, bounded.end)
        self._returned.append(result)
        bounded.check()
        return result

    def _owner(self, owner, active=True):
        _require(type(owner) is Owner and owner is self.owner
                 and owner._issuer is self._issuer, "OWNER_REFUSED")
        if active:
            _require(not self._revoked and not owner.held and not owner.closed
                     and not owner.stop_attempted,
                     "OWNER_HELD")

    def _created(self, value, spec, daemon):
        _require(type(value) is Created and value.request is spec
                 and value.daemon == daemon and _hex(value.resource_id, 64), "CREATE_UNKNOWN")
        self._command(value.command)
        known = ([self.owner.network] if self.owner.network is not None else [])
        _require(all(value.resource_id != old.resource_id
                     for old in known + list(self.owner.created)), "CREATE_UNKNOWN")

    def _network(self, owner, deadline, all_members):
        state = deadline.call(self.runtime.inspect_network, owner.network)
        spec = owner.network.request
        _require(type(state) is NetworkState and state.resource_id == owner.network.resource_id
                 and state.daemon == owner.daemon and state.name == spec.name
                 and state.subnet == SUBNET and type(state.members) is tuple
                 and len(state.members) == len(set(state.members)), "RESOURCE_CHANGED")
        expected = {value.resource_id for value in owner.created}
        _require(set(state.members) <= expected
                 and (not all_members or set(state.members) == expected), "RESOURCE_CHANGED")

    def _container(self, owner, started, state):
        spec = started.created.request
        _require(type(state) is ContainerState
                 and state.resource_id == started.created.resource_id
                 and state.daemon == owner.daemon and state.image_id == spec.image_id
                 and state.network_id == spec.network_id and state.ip == spec.ip
                 and state.storage is spec.storage and state.ports == spec.ports
                 and type(state.mounts) is tuple and len(state.mounts) == 1
                 and state.mounts[0] is spec.storage
                 and state.restart_policy == spec.restart_policy
                 and state.start_id == started.start_id
                 and type(state.restart_count) is int and state.restart_count == 0
                 and state.forced is False, "RESOURCE_CHANGED")

    def current(self, owner):
        try:
            self._owner(owner)
            deadline = self._deadline.child(self.limits.command)
            _require(deadline.call(self.build.current, owner.witness) is True, "BUILD_UNKNOWN")
            _require(deadline.call(self.storage.current, owner.plan.storage) is True,
                     "STORAGE_REFUSED")
            self._network(owner, deadline, True)
            for started in owner.started:
                state = deadline.call(self.runtime.inspect_container, started)
                self._container(owner, started, state)
                _require(state.running is True and state.exit_code is None
                         and state.finished_id is None, "RESOURCE_CHANGED")
            self.checks["identity"] = True
            return True
        except BaseException as error:
            self._hold(error)
            if not isinstance(error, Exception):
                raise
            return False

    def launch(self, pins):
        try:
            _require(not self.attempted, "ALREADY_ATTEMPTED")
            self.attempted = True
            _require(type(pins) is Pins, "PINS_REFUSED")
            pins.validate()
            self.pins = pins
            self._deadline = _Deadline(self.clock, self.clock() + self.limits.total)
            _require(self.build is not None and callable(getattr(self.build, "verify", None))
                     and callable(getattr(self.build, "current", None)), "BUILD_UNKNOWN")
            witness = self._deadline.child(self.limits.command).call(self.build.verify, pins)
            self._build_witness = witness
            _require(type(witness) is BuildWitness and witness.original_build is not None,
                     "BUILD_UNKNOWN")
            _require(witness.pins == pins, "BUILD_REFUSED")
            _require(self._deadline.child(self.limits.command).call(
                self.build.current, witness) is True, "BUILD_UNKNOWN")
            self.provenance, self.checks["build"] = "VERIFIED", True
            _require(self.storage is not None and self.runtime is not None, "STORAGE_REFUSED")
            storage = self._mutation(self.storage.reserve, pins, self._deadline)
            self._storage_receipt = storage
            _require(type(storage) is StorageReceipt and storage.original_reservation is not None
                     and storage.fresh is True and type(storage.roles) is tuple
                     and len(storage.roles) == 5 and all(value is not None for value in storage.roles)
                     and len({id(value) for value in storage.roles}) == 5, "STORAGE_REFUSED")
            _require(self._deadline.child(self.limits.command).call(
                self.storage.current, storage) is True, "STORAGE_REFUSED")
            self.checks["storage"] = True
            nonce = self.entropy(12)
            _require(type(nonce) is bytes and len(nonce) == 12, "PREFLIGHT_REFUSED")
            plan = Plan("syrius-owned-" + nonce.hex(), pins, storage)
            preflight = self._deadline.child(self.limits.command).call(self.runtime.preflight, plan)
            _require(type(preflight) is Preflight and _opaque(preflight.daemon)
                     and type(preflight.conflicts) is tuple and not preflight.conflicts,
                     "PREFLIGHT_REFUSED")
            self.checks["preflight"] = True
            owner = Owner(_SEAL, self._issuer, plan, witness, preflight.daemon)
            self.owner = owner
            spec = NetworkSpec(plan.name + "-network")
            network = self._mutation(self.runtime.create_network, spec, self._deadline)
            self._created(network, spec, owner.daemon)
            owner._state.network = network
            self._network(owner, self._deadline, False)
            for index, role in enumerate(ROLES):
                spec = ContainerSpec(role, plan.name + "-" + role, network.resource_id,
                                     IPS[index], pins.image_id, storage.roles[index],
                                     pins.genesis_sha256, pins.configs_sha256[index],
                                     PORTS if role == "rpc" else ())
                created = self._mutation(self.runtime.create_container, spec, self._deadline)
                self._created(created, spec, owner.daemon)
                owner._state.created.append(created)
                started = self._mutation(self.runtime.start, created, self._deadline)
                _require(type(started) is Started and started.created is created
                         and _opaque(started.start_id), "START_UNKNOWN")
                self._command(started.command)
                owner._state.started.append(started)
            self.checks["created"] = self.checks["started"] = True
            _require(self.current(owner), "OWNER_HELD")
            return owner
        except BaseException as error:
            self._hold(error, "CREATE_UNKNOWN" if self.owner is not None else "INTERNAL_ERROR")
            if not isinstance(error, Exception):
                raise
            return None

    def _genesis(self, rpc):
        value = rpc.call("ledger.getMomentumsByHeight", [1, 1])
        _require(type(value) is dict and type(value.get("list")) is list
                 and len(value["list"]) == 1 and type(value.get("count")) is int
                 and value["count"] >= 1, "GENESIS_MISMATCH")
        momentum = Momentum.parse(value["list"][0])
        _require(momentum.height == 1 and momentum.hash == self.pins.genesis_momentum_hash,
                 "GENESIS_MISMATCH")
        return momentum

    def _snapshot(self, http, ws):
        left = Momentum.parse(http.call("ledger.getFrontierMomentum", []))
        right = Momentum.parse(ws.call("ledger.getFrontierMomentum", []))
        _require(Momentum.parse(ws.call("ledger.getMomentumByHash", [left.hash])) == left
                 and Momentum.parse(http.call("ledger.getMomentumByHash", [right.hash])) == right,
                 "ENDPOINTS_DISAGREE")
        self.samples += 1
        self.checks["http"] = self.checks["ws"] = self.checks["cross_hash"] = True
        return left, right

    def probe(self, owner):
        http = ws = None
        passed = False
        try:
            self._owner(owner)
            _require(not owner.probe_attempted, "ALREADY_ATTEMPTED")
            owner._state.probe_attempted = True
            _require(self.http_transport is not None and self.ws_transport is not None
                     and self.http_transport is not self.ws_transport, "WIRE_REFUSED")
            _require(self.current(owner), "OWNER_HELD")
            http = HttpRpc(self.http_transport, self.limits, self._deadline,
                           self.entropy, self._seen_wires)
            ws = WsRpc(self.ws_transport, self.limits, self._deadline,
                       self.entropy, self._seen_wires)
            ws.connect()
            _require(self._genesis(http) == self._genesis(ws), "GENESIS_MISMATCH")
            self.checks["genesis"] = True
            first = previous = self._snapshot(http, ws)
            for _ in range(self.limits.samples):
                self._deadline.check()
                self.sleep(min(self.limits.poll, self._deadline.end - self.clock()))
                _require(self.current(owner), "OWNER_HELD")
                latest = self._snapshot(http, ws)
                for value, old in zip(latest, previous):
                    value.follows(old)
                if all(value.height > old.height and value.timestamp > old.timestamp
                       and value.hash != old.hash for value, old in zip(latest, first)):
                    _require(self.current(owner), "OWNER_HELD")
                    self.checks["advancing"] = True
                    owner._state.observed = True
                    passed = True
                    break
                previous = latest
            if not passed:
                raise Refused("PRODUCTION_UNPROVEN")
        except BaseException as error:
            self._hold(error, "WIRE_REFUSED")
            if not isinstance(error, Exception):
                raise
        finally:
            for rpc in (http, ws):
                if rpc is not None:
                    try:
                        rpc.close()
                    except BaseException as error:
                        self._hold(error, "CLOSE_UNKNOWN")
                        if not isinstance(error, Exception):
                            raise
        if passed and owner is self.owner and not owner.held:
            return self.current(owner)
        return False

    def stop(self, owner):
        try:
            self._owner(owner, active=False)
            _require(not owner.stop_attempted, "ALREADY_ATTEMPTED")
            owner._state.stop_attempted = True
        except Exception as error:
            self._hold(error)
            return False
        deadline = _Deadline(self.clock, self.clock() + self.limits.stop)
        for started in reversed(owner.started):
            try:
                self._network(owner, deadline, False)
                state = deadline.call(self.runtime.inspect_container, started)
                self._container(owner, started, state)
                _require(state.running is True and state.exit_code is None
                         and state.finished_id is None, "EXIT_UNPROVEN")
                receipt = self._mutation(self.runtime.request_stop, started, deadline)
                self._command(receipt)
                exited = False
                for _ in range(self.limits.exit_polls):
                    state = deadline.call(self.runtime.inspect_container, started)
                    self._container(owner, started, state)
                    if state.running is False:
                        _require(type(state.exit_code) is int and state.exit_code == 0
                                 and _opaque(state.finished_id)
                                 and state.finished_id != started.start_id, "EXIT_UNPROVEN")
                        exited = True
                        break
                    _require(state.running is True and state.exit_code is None
                             and state.finished_id is None, "EXIT_UNPROVEN")
                    deadline.check()
                    self.sleep(min(0.1, deadline.end - self.clock()))
                _require(exited, "EXIT_UNPROVEN")
                owner._state.stopped.append(started)
            except BaseException as error:
                self._hold(error, "STOP_UNKNOWN")
                if not isinstance(error, Exception):
                    raise
        try:
            self._network(owner, deadline, False)
        except Exception as error:
            self._hold(error, "STOP_UNKNOWN")
        owner._state.closed = len(owner.started) == len(owner.stopped) == 5
        self.checks["stop"] = self.checks["exit"] = owner.closed
        return owner.closed and not owner.held

    def public(self):
        """Historical evidence projection only; this mapping authorizes nothing."""
        pins, owner = self.pins, self.owner
        complete = (self.provenance == "VERIFIED" and all(self.checks.values())
                    and owner is not None and owner.observed and owner.closed
                    and not owner.held and not self.codes)
        return {
            "schema": 1,
            "evidence": "injected-source-policy",
            "provenance": self.provenance,
            "node_sha": NODE_SHA,
            "application_sha": pins.application_sha if pins is not None else None,
            "application_tree": pins.application_tree if pins is not None else None,
            "node_tree": pins.node_tree if pins is not None else None,
            "platform": "linux/amd64",
            "image_id": pins.image_id if pins is not None else None,
            "genesis_sha256": pins.genesis_sha256 if pins is not None else None,
            "genesis_momentum_hash": pins.genesis_momentum_hash if pins is not None else None,
            "assets_sha256": pins.assets_sha256 if pins is not None else None,
            "configs_sha256": list(pins.configs_sha256) if pins is not None else [],
            "build_context_sha256": pins.build_context_sha256 if pins is not None else None,
            "dockerfile_sha256": pins.dockerfile_sha256 if pins is not None else None,
            "base_image_ids": list(pins.base_image_ids) if pins is not None else [],
            "daemon_sha256": _digest(owner.daemon) if owner is not None else None,
            "resource_sha256": ([_digest(value.resource_id) for value in
                                 ([owner.network] if owner.network is not None else [])
                                 + list(owner.created)] if owner is not None else []),
            "start_sha256": ([_digest(value.start_id) for value in owner.started]
                             if owner is not None else []),
            "checks": {name: self.checks[name] is True for name in CHECKS},
            "containers_created": len(owner.created) if owner is not None else 0,
            "containers_started": len(owner.started) if owner is not None else 0,
            "original_exits_zero": len(owner.stopped) if owner is not None else 0,
            "samples": self.samples,
            "held": owner.held if owner is not None else bool(self.codes),
            "resources_retained": True,
            "seed_admitted": False,
            "complete": bool(complete),
            "success": bool(complete),
            "error_codes": [code for code in self.codes if code in CODES],
        }
