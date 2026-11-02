"""Finite Flutter-tool protocol checks; no process or runtime admission.

The caller retains original private output. This module exposes no URL, app
identifier, source path or diagnostic text through its public projection.
Protocol reference: Flutter 3.47.7 packages/flutter_tools/doc/daemon.md.
"""

import json
import re
import urllib.parse


MAX_LINE = 256 * 1024
MAX_TOTAL = 8 * 1024**2
MAX_LINES = 10000
CODES = frozenset(("FRAME_REFUSED", "EVENT_REFUSED", "RESPONSE_REFUSED",
    "SESSION_CHANGED", "COMMAND_REFUSED", "COMMAND_UNCERTAIN", "ENDPOINT_REFUSED",
    "SEQUENCE_REFUSED", "OUTPUT_REFUSED"))
EVENTS = frozenset(("daemon.connected", "daemon.log", "daemon.logMessage",
    "app.start", "app.debugPort", "app.started", "app.log", "app.progress",
    "app.stop", "app.devTools", "app.dtd", "app.warning"))


class Refused(Exception):
    def __init__(self, code):
        self.code = code if code in CODES else "FRAME_REFUSED"
        super().__init__(self.code)


def need(value, code):
    if not value:
        raise Refused(code)


def opaque(value):
    return type(value) is str and 0 < len(value) <= 256 and all(32 <= ord(c) < 127 for c in value)


def loopback_uri(value, scheme):
    need(type(value) is str and 0 < len(value) <= 4096 and value.isascii()
         and not any(ord(c) <= 32 or ord(c) == 127 for c in value), "ENDPOINT_REFUSED")
    try:
        uri = urllib.parse.urlsplit(value)
        need(uri.scheme == scheme and uri.hostname == "127.0.0.1"
             and uri.username is None and uri.password is None
             and type(uri.port) is int and 1024 <= uri.port <= 65535
             and uri.netloc == "127.0.0.1:" + str(uri.port), "ENDPOINT_REFUSED")
    except ValueError:
        raise Refused("ENDPOINT_REFUSED") from None
    return uri


def vm_uri(value):
    uri = loopback_uri(value, "ws")
    path = urllib.parse.unquote(uri.path)
    need(not uri.query and not uri.fragment
         and re.fullmatch(r"/[A-Za-z0-9_=-]{1,256}/ws", path), "ENDPOINT_REFUSED")
    return value


def devtools_uri(value, service):
    uri = loopback_uri(value, "http")
    vm = urllib.parse.urlsplit(vm_uri(service))
    fields = urllib.parse.parse_qs(uri.query)
    fragment = urllib.parse.parse_qs(uri.fragment.partition("?")[2])
    targets = fields.get("uri", []) + fragment.get("uri", [])
    need(len(targets) == 1, "ENDPOINT_REFUSED")
    try:
        target = urllib.parse.urlsplit(targets[0])
        need(target.scheme in ("http", "ws") and target.hostname == "127.0.0.1"
             and target.port == vm.port and target.username is None and target.password is None
             and not target.query and not target.fragment, "ENDPOINT_REFUSED")
        expected = vm.path if target.scheme == "ws" else vm.path[:-2]
        need(urllib.parse.unquote(target.path).rstrip("/") ==
             urllib.parse.unquote(expected).rstrip("/"), "ENDPOINT_REFUSED")
    except ValueError:
        raise Refused("ENDPOINT_REFUSED") from None
    return value


class DaemonTranscript:
    """One tool session; an uncertain command cannot be issued again."""

    def __init__(self):
        self._app = self._service = self._devtools = None
        self._started = self._stopped = self._held = False
        self._pending = {}
        self._next = 1
        self._bytes = self._lines = self._completed = 0

    def _current(self):
        need(not self._held, "COMMAND_UNCERTAIN")

    def reserve(self, method, *, full_restart=None):
        try:
            self._current()
            need(not self._pending and self._next <= 64, "SEQUENCE_REFUSED")
            need(method in ("daemon.version", "daemon.shutdown", "app.restart", "app.stop"), "COMMAND_REFUSED")
            params = {}
            if method.startswith("app."):
                need(self._app is not None and self._started and not self._stopped, "SEQUENCE_REFUSED")
                params["appId"] = self._app
            if method == "app.restart":
                need(type(full_restart) is bool, "COMMAND_REFUSED")
                params.update(fullRestart=full_restart, pause=False, debounce=False, reason="ci-debug-loop")
            else:
                need(full_restart is None, "COMMAND_REFUSED")
            if method == "daemon.shutdown":
                need(self._stopped, "SEQUENCE_REFUSED")
            identifier = self._next
            self._next += 1
            self._pending[identifier] = method
            return dict(id=identifier, method=method, params=params)
        except Refused:
            self._held = True
            raise

    def uncertain(self, identifier):
        self._held = True
        need(type(identifier) is int and identifier in self._pending, "RESPONSE_REFUSED")
        raise Refused("COMMAND_UNCERTAIN")

    def feed(self, raw):
        try:
            self._current()
            need(type(raw) is bytes and len(raw) <= MAX_LINE, "OUTPUT_REFUSED")
            self._bytes += len(raw)
            self._lines += 1
            need(self._bytes <= MAX_TOTAL and self._lines <= MAX_LINES, "OUTPUT_REFUSED")
            value = raw.strip()
            if not value.startswith(b"[") or not value[1:].lstrip().startswith(b"{"):
                return
            try:
                messages = json.loads(value)
            except (ValueError, UnicodeError):
                raise Refused("FRAME_REFUSED") from None
            need(type(messages) is list and 0 < len(messages) <= 16, "FRAME_REFUSED")
            for message in messages:
                self._message(message)
        except Refused:
            self._held = True
            raise

    def _message(self, message):
        need(type(message) is dict, "FRAME_REFUSED")
        if "id" in message:
            identifier = message["id"]
            need(type(identifier) is int and identifier in self._pending
                 and (("result" in message) != ("error" in message)), "RESPONSE_REFUSED")
            need("error" not in message, "COMMAND_REFUSED")
            method, result = self._pending[identifier], message["result"]
            if method == "daemon.version":
                need(type(result) is str and re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", result), "RESPONSE_REFUSED")
            elif method == "app.restart":
                need(type(result) is dict and type(result.get("code")) is int and result["code"] == 0,
                     "COMMAND_REFUSED")
            elif method == "app.stop":
                need(result is True, "COMMAND_REFUSED")
            else:
                need(result is None or result is True, "RESPONSE_REFUSED")
            del self._pending[identifier]
            self._completed += 1
            return
        event, params = message.get("event"), message.get("params")
        need(type(event) is str and event in EVENTS and type(params) is dict, "EVENT_REFUSED")
        if event == "app.start":
            need(self._app is None and opaque(params.get("appId"))
                 and params.get("deviceId") == "windows" and params.get("supportsRestart") is True,
                 "SESSION_CHANGED")
            self._app = params["appId"]
        elif event.startswith("app."):
            need(self._app is not None and not self._stopped
                 and params.get("appId", self._app) == self._app, "SESSION_CHANGED")
            if event == "app.debugPort":
                service = vm_uri(params.get("wsUri"))
                need(type(params.get("port")) is int and params["port"] == urllib.parse.urlsplit(service).port
                     and self._service in (None, service), "SESSION_CHANGED")
                self._service = service
            elif event == "app.devTools":
                need(self._service is not None, "SEQUENCE_REFUSED")
                address = devtools_uri(params.get("uri"), self._service)
                need(self._devtools in (None, address), "SESSION_CHANGED")
                self._devtools = address
            elif event == "app.started":
                need(self._service is not None, "SEQUENCE_REFUSED")
                self._started = True
            elif event == "app.stop":
                self._stopped = True

    def public(self):
        return dict(scope="flutter_tool_protocol_only", app_started=self._started,
            app_stopped=self._stopped, vm_uri_seen=self._service is not None,
            devtools_uri_seen=self._devtools is not None, held=self._held,
            pending_commands=len(self._pending), completed_commands=self._completed,
            runtime_qualified=False, debug_loop_qualified=False)
