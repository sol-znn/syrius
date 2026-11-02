"""Bounded hosted-Windows evidence for ordinary Welcome and empty Import only.

The workflow builds the Debug harness first. One new process gets an isolated
profile, ordinary wallet mode and a private token. Public output and the five
explicit artifacts contain only allowlisted identities and finite outcomes.
This does not qualify the launch film, Ready, a wallet, chain 321 or mockups.
"""

from __future__ import annotations

import base64
from dataclasses import dataclass, replace
import binascii
import hashlib
import http.client
import json
import math
import os
from pathlib import Path
import re
import secrets
import socket
import stat
import struct
import subprocess
import sys
import zlib

try:
    from . import windows_presentation_smoke as bounded
except ImportError:
    import windows_presentation_smoke as bounded


MAX_PNG = 8 * 1024 * 1024
MAX_BASE64 = 4 * ((MAX_PNG + 2) // 3)
OUTPUT = Path(".harness/ci-entry-capture")
SCENES = tuple((screen, theme) for screen in ("welcome", "import")
               for theme in ("dark", "light"))
FILES = tuple(f"{screen}-{theme}.png" for screen, theme in SCENES)
CHECKS = (
    "environment", "source", "profile", "preflight", "identity", "auth",
    "entry_ready", "window_saved", "client_matched", "welcome_dark",
    "welcome_light", "import_dark", "import_light", "window_restored",
    "entry_restored", "close_ack", "exit", "payload_stable",
)
CAPTION_CHECKS = ("maximized", "caption_restored", "minimized", "native_restored")
CAPTION_REFUSALS = frozenset((
    "CAPTION_BASELINE_REFUSED", "CAPTION_CONTROL_CHANGED", "CAPTION_CONTROL_REFUSED",
    "CAPTION_ENTRY_REFUSED", "CAPTION_NATIVE_INVALID", "CAPTION_NATIVE_PENDING",
    "CAPTION_ORIGINAL_CHANGED", "CAPTION_PENDING", "CAPTION_PENDING_UNOBSERVED",
    "CAPTION_REPLAY_REFUSED", "CAPTION_RESTORE_REFUSED", "CAPTION_TIMEOUT",
    "CAPTION_TREE_REFUSED", "CAPTION_UNAVAILABLE", "CAPTION_HELD",
    "CAPTION_TREE_CAPACITY_REFUSED", "CAPTION_TREE_UNMOUNTED",
))
CAPTURE_PHASES = frozenset(f"capture_{screen}_{theme}" for screen, theme in SCENES)
CAPTION_PHASES = frozenset((
    "caption_bind", "caption_maximize", "caption_restore", "caption_minimize",
    "caption_observe", "caption_native_restore", "window_restore",
))
CODES = bounded.CODES | frozenset((
    "OUTPUT_REFUSED", "ARTIFACT_FAILED", "ENTRY_UNAVAILABLE", "ENTRY_HELD",
    "ENTRY_INVALID", "WINDOW_INVALID", "WINDOW_RESTORE_FAILED",
    "CAPTURE_INVALID", "PNG_INVALID", "RESTORATION_INVALID",
    "CAPTION_INVALID", "CAPTION_HELD", "CAPTION_TIMEOUT", "CAPTION_NATIVE_MISMATCH",
)) | CAPTION_REFUSALS
@dataclass(frozen=True)
class EntryLimits(bounded.Limits):
    # Original raster encoding is a bounded capture operation, separate from
    # ordinary control requests and the unchanged total process deadline.
    capture_request: float = 30.0


LIMITS = EntryLimits(total=150, ready=45, request=20,
                        response_bytes=MAX_BASE64 + 65536)
CLEANUP_PHASES = frozenset(("window_restore", "entry_verify", "close"))
COMMAND_PHASES = (frozenset(("readiness_ping", "auth_refusal", "entry_state",
                            "window_observe", "window_show_resize"))
                  | CLEANUP_PHASES
                  | frozenset(("caption_bind", "caption_maximize", "caption_restore",
                               "caption_minimize", "caption_observe", "caption_native_restore"))
                  | frozenset(f"capture_{screen}_{theme}" for screen, theme in SCENES))
RESIZE_ERRORS = {
    "the requested client area was not observed": "CLIENT_RESIZE_UNOBSERVED",
    "client dimensions changed before reporting": "CLIENT_METRICS_CHANGED",
}
FAILURE_CATEGORIES = (frozenset(("REMOTE_ERROR", "EXCHANGE_FAILED", "GUARD_FAILED"))
                      | frozenset(RESIZE_ERRORS.values()))


ENTRY_EFFECT_PHASES = frozenset((
    'original-entry-artwork-ready', 'original-image-release',
    'original-import-controller-end', 'original-import-navigation-end',
    'original-import-route-end', 'original-incomplete-import-input',
    'original-native-frame', 'original-png-encoding', 'original-renderer-image',
    'original-restored-window-position', 'original-restored-window-size',
    'original-restored-window-visibility', 'original-route-frame',
    'original-route-transition', 'original-theme-flush', 'original-theme-frame',
    'original-theme-write', 'original-welcome-import', 'original-window-position',
    'original-window-size', 'original-window-visibility',
))
ENTRY_FUTURE_STATES = frozenset(('not_returned', 'pending', 'succeeded', 'failed'))
EFFECT_TRACE_PREFIX = b'SYRIUS_ENTRY_EFFECT:'
EFFECT_TRACE_MAX_EVENTS = 384
EFFECT_TRACE_MAX_BYTES = 98304
HTTP_FAILURE_KINDS = frozenset((
    'TIMEOUT', 'DISCONNECTED', 'RESET', 'INCOMPLETE', 'IO_ERROR', 'OTHER',
))


def _entry_effect_projection(value):
    if (type(value) is not dict
            or set(value) != {'phase', 'future', 'failed', 'milliseconds'}
            or type(value['phase']) is not str or value['phase'] not in ENTRY_EFFECT_PHASES
            or type(value['future']) is not str or value['future'] not in ENTRY_FUTURE_STATES
            or type(value['failed']) is not bool
            or type(value['milliseconds']) is not int
            or not 0 <= value['milliseconds'] <= 0x7fffffff):
        return None
    return {key: value[key] for key in ('phase', 'future', 'failed', 'milliseconds')}


def _effect_trace_event(value):
    fields = ('schema', 'screen', 'theme', 'scopes', 'effects', 'phase',
              'boundary', 'future', 'failed', 'milliseconds')
    if (type(value) is not dict or set(value) != set(fields)
            or type(value['schema']) is not int or value['schema'] != 1
            or type(value['scopes']) is not int or not 1 <= value['scopes'] <= 4
            or type(value['effects']) is not int or not 1 <= value['effects'] <= 192
            or type(value['screen']) is not str or type(value['theme']) is not str
            or (value['screen'], value['theme']) != SCENES[value['scopes'] - 1]
            or type(value['boundary']) is not str
            or value['boundary'] not in ('begin', 'returned', 'ended')
            or _entry_effect_projection({key: value[key] for key in
                ('phase', 'future', 'failed', 'milliseconds')}) is None):
        return None
    boundary, future, failed = value['boundary'], value['future'], value['failed']
    if (boundary == 'begin' and (future != 'not_returned' or failed)
            or boundary == 'returned' and (future == 'not_returned' or failed)
            or boundary == 'ended' and future == 'not_returned' and not failed):
        return None
    return {key: value[key] for key in fields}


def effect_trace_projection(value):
    """A trace observes its original process; it never supplies a capture."""
    fields = {'schema', 'status', 'events', 'last', 'last_ended'}
    if (type(value) is not dict or set(value) != fields
            or type(value['schema']) is not int or value['schema'] != 1
            or type(value['status']) is not str
            or value['status'] not in ('OBSERVED', 'CAPPED', 'REFUSED')
            or type(value['events']) is not int
            or not 0 <= value['events'] <= EFFECT_TRACE_MAX_EVENTS):
        return None
    if value['status'] == 'REFUSED':
        return (dict(schema=1, status='REFUSED', events=0, last=None, last_ended=None)
                if value['events'] == 0 and value['last'] is None
                and value['last_ended'] is None else None)
    last = _effect_trace_event(value['last'])
    ended = _effect_trace_event(value['last_ended']) if value['last_ended'] is not None else None
    if (not value['events'] or last is None
            or value['last_ended'] is not None and (ended is None or ended['boundary'] != 'ended')
            or last['boundary'] == 'ended' and ended != last):
        return None
    if ended is None:
        expected = {'begin': 1, 'returned': 2}
        if (last['boundary'] not in expected or value['events'] != expected[last['boundary']]
                or (last['scopes'], last['effects']) != (1, 1)):
            return None
    elif last['boundary'] != 'ended':
        position = (last['scopes'], last['effects'])
        if position not in ((ended['scopes'], ended['effects'] + 1),
                            (ended['scopes'] + 1, 1)):
            return None
    return dict(schema=1, status=value['status'], events=value['events'],
                last=last, last_ended=ended)


def effect_trace_from_output(data, *, complete, overflow):
    """Project only fixed complete lines from the already-owned output pipe."""
    refused = dict(schema=1, status='REFUSED', events=0, last=None, last_ended=None)
    if (type(data) not in (bytes, bytearray) or type(complete) is not bool
            or type(overflow) is not bool or len(data) > LIMITS.output_bytes):
        return refused
    lines = bytes(data).splitlines(keepends=True)
    selected = [line for line in lines if line.startswith(EFFECT_TRACE_PREFIX)]
    if not selected:
        return None
    if not complete or overflow:
        return refused
    previous = ended = None
    events = size = 0
    capped = False

    def unique(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError()
            value[key] = item
        return value

    try:
        for line in selected:
            if capped or not line.endswith(b'\n') or len(line) > 512:
                return refused
            size += len(line)
            if size > EFFECT_TRACE_MAX_BYTES + 128:
                return refused
            value = json.loads(line[len(EFFECT_TRACE_PREFIX):].decode('ascii'),
                               object_pairs_hook=unique)
            if value == {'schema': 1, 'capped': True}:
                if (type(value.get('schema')) is not int or not events
                        or type(value.get('capped')) is not bool):
                    return refused
                capped = True
                continue
            value = _effect_trace_event(value)
            if value is None or events >= EFFECT_TRACE_MAX_EVENTS:
                return refused
            position = (value['scopes'], value['effects'])
            if previous is None:
                valid = position == (1, 1) and value['boundary'] == 'begin'
            elif position == (previous['scopes'], previous['effects']):
                allowed = {'begin': ('returned', 'ended'), 'returned': ('ended',), 'ended': ()}
                valid = (value['phase'] == previous['phase']
                    and value['boundary'] in allowed[previous['boundary']]
                    and value['milliseconds'] >= previous['milliseconds']
                    and (previous['boundary'] != 'returned' or value['future'] != 'not_returned')
                    and (previous['boundary'] != 'begin' or value['boundary'] != 'ended'
                         or value['future'] == 'not_returned' and value['failed']))
            else:
                valid = (previous['boundary'] == 'ended' and value['boundary'] == 'begin'
                    and (position == (previous['scopes'], previous['effects'] + 1)
                         or position == (previous['scopes'] + 1, 1)))
            if not valid:
                return refused
            events += 1
            previous = value
            if value['boundary'] == 'ended':
                ended = value
    except (ValueError, UnicodeError, TypeError, KeyError):
        return refused
    result = dict(schema=1, status='CAPPED' if capped else 'OBSERVED',
                  events=events, last=previous, last_ended=ended)
    return effect_trace_projection(result) or refused


def capture_progress_projection(value):
    """Only existing finite receipts are observations; no owner is invoked."""
    fields = {'schema', 'screen', 'theme', 'scopes', 'completedCaptures', 'effects',
              'last', 'slowest', 'artworkCount', 'imageCreated', 'restoring', 'restored', 'held'}
    if (type(value) is not dict or set(value) != fields
            or type(value['schema']) is not int or value['schema'] != 1
            or type(value['screen']) is not str or value['screen'] not in ('welcome', 'import')
            or type(value['theme']) is not str or value['theme'] not in ('dark', 'light')
            or type(value['scopes']) is not int or not 1 <= value['scopes'] <= 16
            or type(value['completedCaptures']) is not int
            or not 0 <= value['completedCaptures'] <= value['scopes']
            or type(value['effects']) is not int or not 0 <= value['effects'] <= 192
            or type(value['artworkCount']) is not int or not 0 <= value['artworkCount'] <= 2
            or any(type(value[key]) is not bool for key in
                   ('imageCreated', 'restoring', 'restored', 'held'))):
        return None
    last, slowest = value['last'], value['slowest']
    if value['effects'] == 0:
        if last is not None or slowest is not None:
            return None
    else:
        last, slowest = _entry_effect_projection(last), _entry_effect_projection(slowest)
        if (last is None or slowest is None
                or slowest['milliseconds'] < last['milliseconds']
                or value['effects'] == 1 and last != slowest):
            return None
    result = dict(value)
    result.update(last=last, slowest=slowest)
    return result


def transport_failure_projection(value):
    if (type(value) is not dict or set(value) != {'phase', 'kind'}
            or type(value['phase']) is not str or value['phase'] not in COMMAND_PHASES
            or type(value['kind']) is not str or value['kind'] not in HTTP_FAILURE_KINDS):
        return None
    return dict(value)


def http_failure_observation(error, phase):
    """Classify the actual exception without reading its message or arguments."""
    if not isinstance(error, Exception):
        return None
    if isinstance(error, TimeoutError):
        kind = 'TIMEOUT'
    elif isinstance(error, http.client.RemoteDisconnected):
        kind = 'DISCONNECTED'
    elif isinstance(error, ConnectionResetError):
        kind = 'RESET'
    elif isinstance(error, http.client.IncompleteRead):
        kind = 'INCOMPLETE'
    elif isinstance(error, OSError):
        kind = 'IO_ERROR'
    else:
        kind = 'OTHER'
    return transport_failure_projection(dict(phase=phase, kind=kind))


class Failure(bounded.SmokeFailure):
    def __init__(self, code):
        self.code = code if code in CODES else "INTERNAL_ERROR"
        Exception.__init__(self, self.code)


class Report(bounded.Report):
    def __init__(self):
        super().__init__()
        self.source_tree = self.run_id = self.run_attempt = None
        self.checks = dict.fromkeys(CHECKS, False)
        self.captures = []
        self.caption_checks = dict.fromkeys(CAPTION_CHECKS, False)
        self.output_bytes = 0
        self.first_command_failure = None
        self.cleanup_failures = []
        self.capture_progress = None
        self.effect_trace = None
        self.transport_failure = None

    def fail(self, code, original=None):
        code = code if code in CODES else "INTERNAL_ERROR"
        if code not in self.errors:
            self.errors.append(code)
        if original is not None:
            self.original_errors.append(original)

    def command_failed(self, failure, *, cleanup=False):
        failure = failure_projection(failure)
        if failure is None:
            return
        if self.first_command_failure is None:
            self.first_command_failure = failure
        if cleanup and failure["phase"] in CLEANUP_PHASES and len(self.cleanup_failures) < 2:
            self.cleanup_failures.append(failure)

    def public(self):
        first_failure = failure_projection(self.first_command_failure)
        cleanup_failures = []
        seen = set()
        if isinstance(self.cleanup_failures, list):
            for failure in self.cleanup_failures[:2]:
                failure = failure_projection(failure)
                if (failure is not None and failure["phase"] in CLEANUP_PHASES
                        and failure["phase"] not in seen):
                    seen.add(failure["phase"])
                    cleanup_failures.append(failure)
        captures = []
        for name in FILES:
            for item in self.captures:
                if (item.get("file") == name and bounded.safe_digest(item.get("sha256"))
                        and type(item.get("bytes")) is int and 0 < item["bytes"] <= MAX_PNG):
                    captures.append({"file": name, "sha256": item["sha256"],
                                     "bytes": item["bytes"], "width": 1280, "height": 780})
                    break
        capture_progress = capture_progress_projection(self.capture_progress)
        effect_trace = effect_trace_projection(self.effect_trace)
        transport_failure = transport_failure_projection(self.transport_failure)
        complete = (
            all(self.checks.get(name) is True for name in CHECKS)
            and all(self.caption_checks.get(name) is True for name in CAPTION_CHECKS)
            and len(captures) == 4 and self.exit_observed and self.exit_code == 0
            and self.output_complete and not self.output_overflow
            and not self.forced_kill and not self.errors
            and first_failure is None and not cleanup_failures
        )
        return {
            "schema": 2,
            "source_sha": self.source_sha if bounded.valid_sha(self.source_sha) else None,
            "source_tree": self.source_tree if bounded.valid_sha(self.source_tree) else None,
            "run_id": anonymous_number(self.run_id),
            "run_attempt": anonymous_number(self.run_attempt, 6),
            "runner_sha256": bounded.safe_digest(self.runner_sha256),
            "dart_kernel_sha256": bounded.safe_digest(self.dart_kernel_sha256),
            "checks": {name: self.checks.get(name) is True for name in CHECKS},
            "caption": {"schema": 1, "observations": {
                name: self.caption_checks.get(name) is True for name in CAPTION_CHECKS}},
            "captures": captures, "capture_count": len(captures),
            "exit_code": self.exit_code if type(self.exit_code) is int else None,
            "exit_observed": self.exit_observed is True,
            "forced_kill": self.forced_kill is True,
            "output_bytes": self.output_bytes if type(self.output_bytes) is int
                            and 0 <= self.output_bytes < 2 ** 63 else None,
            "output_complete": self.output_complete is True,
            "output_overflow": self.output_overflow is True,
            "complete": complete, "success": complete,
            "status": "SUCCESS" if complete else "UNKNOWN",
            "error_codes": [code for code in self.errors if code in CODES],
            "first_command_failure": first_failure,
            "cleanup_failures": cleanup_failures,
            **({'capture_progress': capture_progress} if capture_progress is not None else {}),
            **({'effect_trace': effect_trace} if effect_trace is not None else {}),
            **({'transport_failure': transport_failure} if transport_failure is not None else {}),
        }


def anonymous_number(value, digits=20):
    return value if isinstance(value, str) and re.fullmatch(
        rf"[1-9][0-9]{{0,{digits - 1}}}", value,
    ) else None


def require_ci(parent, expected, *, platform):
    parent, expected = bounded.require_ci(parent, expected, platform=platform)
    if (anonymous_number(parent.get("GITHUB_RUN_ID")) is None
            or anonymous_number(parent.get("GITHUB_RUN_ATTEMPT"), 6) is None):
        raise Failure("ENVIRONMENT_REFUSED")
    return parent, expected


def source_tree(repo, parent, *, run=bounded.fixed_command, observe_tree=None):
    env = {key: value for key, value in parent.items() if not key.upper().startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    code, output = run(["git", "-C", str(repo), "rev-parse", "HEAD^{tree}"],
                       cwd=repo, env=env, cap=128)
    try:
        tree = output.decode("ascii").rstrip("\r\n")
    except UnicodeError:
        raise Failure("SOURCE_REFUSED") from None
    if code != 0 or not bounded.valid_sha(tree) or output not in (
        (tree + "\n").encode(), (tree + "\r\n").encode(),
    ):
        raise Failure("SOURCE_REFUSED")
    if observe_tree is not None:
        observe_tree(tree)  # The observed commit tree does not assert a clean worktree.
    code, _ = run(["git", "-C", str(repo), "diff", "--quiet", "HEAD", "--"],
                  cwd=repo, env=env)
    if code != 0:
        raise Failure("SOURCE_REFUSED")
    return tree


def private_root(repo):
    root = repo / ".harness"
    if not root.exists():
        root.mkdir(mode=0o700)
    if not stat.S_ISDIR(bounded.plain(root).st_mode):
        raise Failure("PROFILE_REFUSED")
    return root


def new_profile(repo):
    profile = private_root(repo) / ("ci-entry-smoke-" + secrets.token_hex(12))
    profile.mkdir(mode=0o700)
    for name in ("AppData/Roaming", "AppData/Local", "Temp", "Config", "Data", "Cache"):
        (profile / name).mkdir(parents=True, mode=0o700)
    bounded.plain(profile)
    return profile


def child_environment(parent, profile, port, token):
    env = {key.upper(): value for key, value in parent.items()
           if key.upper() in bounded.RUNTIME_ENV}
    env.update({
        "APPDATA": str(profile / "AppData/Roaming"),
        "LOCALAPPDATA": str(profile / "AppData/Local"),
        "TEMP": str(profile / "Temp"), "TMP": str(profile / "Temp"),
        "HOME": str(profile), "USERPROFILE": str(profile),
        "XDG_CONFIG_HOME": str(profile / "Config"),
        "XDG_DATA_HOME": str(profile / "Data"),
        "XDG_CACHE_HOME": str(profile / "Cache"),
        "SYRIUS_HARNESS_HOME": str(profile),
        "SYRIUS_HARNESS_PORT": str(port), "SYRIUS_HARNESS_TOKEN": token,
        "SYRIUS_CI_ENTRY_EFFECT_TRACE": "true",
    })
    if profile.drive:
        env.update(HOMEDRIVE=profile.drive, HOMEPATH=str(profile)[len(profile.drive):])
    return env


def png_bytes(encoded, *, dimensions=(1280, 780)):
    """Admit bounded screenshot pixels, never textual/private PNG metadata."""
    try:
        if (type(dimensions) is not tuple or len(dimensions) != 2
                or any(type(value) is not int for value in dimensions)
                or dimensions not in ((1280, 780), (1200, 600))):
            raise ValueError()
        if not isinstance(encoded, str) or not 0 < len(encoded) <= MAX_BASE64:
            raise ValueError()
        data = base64.b64decode(encoded, validate=True)
        if not 0 < len(data) <= MAX_PNG or base64.b64encode(data).decode("ascii") != encoded:
            raise ValueError()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError()
        offset, chunks, colors, ended, idat = 8, 0, None, False, False
        compressed = bytearray()
        seen = set()
        while offset < len(data):
            chunks += 1
            if chunks > 4096 or len(data) - offset < 12 or ended:
                raise ValueError()
            length, kind = struct.unpack_from(">I4s", data, offset)
            if length > MAX_PNG or offset + 12 + length > len(data):
                raise ValueError()
            payload = data[offset + 8:offset + 8 + length]
            crc, = struct.unpack_from(">I", data, offset + 8 + length)
            if crc != zlib.crc32(kind + payload) & 0xffffffff:
                raise ValueError()
            if chunks == 1:
                if kind != b"IHDR" or length != 13:
                    raise ValueError()
                width, height, depth, colors, comp, filt, interlace = struct.unpack(
                    ">IIBBBBB", payload,
                )
                if (width, height, depth, comp, filt, interlace) != (*dimensions, 8, 0, 0, 0):
                    raise ValueError()
                if colors not in (2, 6):
                    raise ValueError()
            elif kind == b"IDAT":
                idat = True
                compressed.extend(payload)
            elif kind == b"IEND":
                if length or not compressed:
                    raise ValueError()
                ended = True
            # Skia emits this fixed-size channel precision before pixel data.
            elif kind == b"sBIT" and not idat and kind not in seen:
                if (length != (4 if colors == 6 else 3)
                        or any(value < 1 or value > 8 for value in payload)):
                    raise ValueError()
            elif (kind in (b"sRGB", b"gAMA", b"cHRM") and not idat
                  and kind not in seen):
                if (kind == b"sRGB" and (length != 1 or payload[0] > 3)
                        or kind == b"gAMA" and (length != 4 or payload == b"\0" * 4)
                        or kind == b"cHRM" and length != 32):
                    raise ValueError()
            else:
                raise ValueError()
            seen.add(kind)
            offset += length + 12
        if not ended or offset != len(data):
            raise ValueError()
        stride = width * (4 if colors == 6 else 3) + 1
        expected = stride * height
        decoder = zlib.decompressobj()
        pixels = decoder.decompress(compressed, expected + 1)
        if (len(pixels) != expected or not decoder.eof
                or decoder.unused_data or decoder.unconsumed_tail
                or any(pixels[row * stride] > 4 for row in range(height))):
            raise ValueError()
        return data
    except (ValueError, TypeError, UnicodeError, binascii.Error, struct.error, zlib.error):
        raise Failure("PNG_INVALID") from None


def number(value, *, positive=False):
    return (type(value) in (int, float) and abs(value) <= 10000000
            and math.isfinite(value) and (not positive or value > 0))


def vector(value, length, *, positive=False):
    return (isinstance(value, list) and len(value) == length
            and all(number(item, positive=positive) for item in value))


def resize_projection(value):
    """Project only the known resize reply's finite numeric facts, never raw detail."""
    if not isinstance(value, dict):
        return None
    result = {}
    for name, maximum in (("requestedClient", 16384), ("client", 32768),
                          ("physical", 524288), ("outer", 32768)):
        items = value.get(name)
        if not vector(items, 2, positive=True) or any(item > maximum for item in items):
            return None
        result[name] = list(items)
    ratio, attempts, matched = (value.get(name) for name in (
        "devicePixelRatio", "resizeAttempts", "clientMatched"))
    if (not number(ratio, positive=True) or ratio > 16
            or type(attempts) is not int or not 0 <= attempts <= 5
            or type(matched) is not bool
            or result["requestedClient"] != [1280, 780]
            or any(abs(physical - logical * ratio) >= .01
                   for physical, logical in zip(result["physical"], result["client"]))
            or matched is not all(abs(actual - expected) < .01 for actual, expected
                                  in zip(result["client"], result["requestedClient"]))):
        return None
    result.update(devicePixelRatio=ratio, resizeAttempts=attempts, clientMatched=matched)
    return result


def failure_projection(value):
    """The only failure shape allowed into the manifest; no error text survives."""
    if (not isinstance(value, dict)
            or set(value) != {"phase", "code", "http_status", "category", "resize"}
            or any(type(value[name]) is not str for name in ("phase", "code", "category"))
            or value["phase"] not in COMMAND_PHASES or value["code"] not in CODES
            or value["category"] not in FAILURE_CATEGORIES):
        return None
    category = value["category"]
    known_resize = category in RESIZE_ERRORS.values()
    if known_resize and value["phase"] != "window_show_resize":
        return None
    status = value["http_status"]
    status = status if type(status) is int and 100 <= status <= 599 else None
    return {"phase": value["phase"], "code": value["code"], "http_status": status,
            "category": category,
            "resize": resize_projection(value["resize"]) if known_resize else None}


def command_failure(phase, code, status, *, category, body=None):
    error = body.get("error") if isinstance(body, dict) else None
    if category == "REMOTE_ERROR" and phase == "window_show_resize" and type(error) is str:
        category = RESIZE_ERRORS.get(error, category)
    return failure_projection({
        "phase": phase, "code": code, "http_status": status, "category": category,
        "resize": body.get("detail") if isinstance(body, dict)
                  and category in RESIZE_ERRORS.values() else None,
    })


def reference_artwork(value, screen):
    if type(value) is not list or screen not in ('welcome', 'import'):
        return False
    expected = ([dict(kind='welcome_globe', frame=720, frame_count=1800)]
                if screen == 'welcome' else [])
    expected.append(dict(kind='entry_field', seconds=6))
    return (value == expected and len(value) == len(expected)
            and all(type(item) is dict and set(item) == set(original)
                    and all(type(item[key]) is type(original[key]) for key in original)
                    for item, original in zip(value, expected)))


def capture_bytes(body, screen, theme):
    keys = {"ok", "screen", "theme", "width", "height", "scale", "client",
            "physical", "devicePixelRatio", "png", "harnessMode", "captureMode",
            "restorationVerified", "referenceArtwork"}
    if (body.keys() != keys or body.get("harnessMode") != "wallet"
            or body.get("captureMode") != "entry" or body.get("screen") != screen
            or body.get("theme") != theme or body.get("restorationVerified") is not True
            or not reference_artwork(body.get("referenceArtwork"), screen)
            or type(body.get("width")) is not int or body["width"] != 1280
            or type(body.get("height")) is not int or body["height"] != 780
            or not number(body.get("scale"), positive=True) or body["scale"] != 1
            or not vector(body.get("client"), 2, positive=True)
            or any(abs(a - b) >= .01 for a, b in zip(body["client"], (1280, 780)))
            or not number(body.get("devicePixelRatio"), positive=True)
            or not vector(body.get("physical"), 2, positive=True)
            or any(abs(a - b * body["devicePixelRatio"]) >= .01
                   for a, b in zip(body["physical"], body["client"]))):
        raise Failure("CAPTURE_INVALID")
    return png_bytes(body["png"])


class Artifacts:
    def __init__(self, repo):
        private_root(repo)
        self.root = repo / OUTPUT
        try:
            self.root.mkdir(mode=0o700)  # Existing or linked output is never adopted.
        except OSError:
            raise Failure("OUTPUT_REFUSED") from None
        self.identity = self._identity()
        self.records = []

    def _identity(self):
        info = bounded.plain(self.root)
        if not stat.S_ISDIR(info.st_mode):
            raise Failure("OUTPUT_REFUSED")
        return info.st_dev, info.st_ino

    def _write(self, name, data):
        if self._identity() != self.identity:
            raise Failure("OUTPUT_REFUSED")
        with (self.root / name).open("xb") as original:
            if original.write(data) != len(data):
                raise Failure("ARTIFACT_FAILED")
            original.flush()
            os.fsync(original.fileno())
        if self._identity() != self.identity or bounded.plain(self.root / name).st_size != len(data):
            raise Failure("ARTIFACT_FAILED")

    def png(self, name, data):
        if name not in FILES or any(item["file"] == name for item in self.records):
            raise Failure("OUTPUT_REFUSED")
        if not 0 < len(data) <= MAX_PNG:
            raise Failure("PNG_INVALID")
        self._write(name, data)
        self.records.append({"file": name, "sha256": hashlib.sha256(data).hexdigest(),
                             "bytes": len(data)})

    def manifest(self, public):
        # Publish only after the complete sanitized bytes have been flushed.
        # Windows rename refuses an existing destination. The explicit check
        # also keeps the finite portable fixture from replacing its own file.
        final = self.root / "manifest.json"
        if final.exists() or final.is_symlink():
            raise FileExistsError()
        self._write("manifest.pending", json.dumps(
            public, sort_keys=True, separators=(",", ":"),
        ).encode("ascii") + b"\n")
        (self.root / "manifest.pending").rename(final)


class EntrySmoke(bounded.PresentationSmoke):
    """Reuse only bounded transport/health primitives; ordinary protocol below."""

    def __init__(self, *args, artifacts, **kwargs):
        super().__init__(*args, **kwargs)
        self.artifacts = artifacts
        self.original_window = None
        self.window_changed = self.authenticated = False
        self.caption_attempted = self.caption_complete = False
        self.caption_baseline = None
        self._command_phase = self._command_status = self._command_failure = None

    def _retain_failure(self, code, *, category="GUARD_FAILED", body=None, cleanup=False):
        failure = self._command_failure
        if failure is None:
            failure = command_failure(self._command_phase, code, self._command_status,
                                      category=category, body=body)
        else:
            failure = {**failure, "code": code}
        self._command_failure = failure
        self.report.command_failed(failure, cleanup=cleanup)

    def _exchange_at(self, phase, command, *, allow_exit=False, until=None,
                     poll_refused=False):
        self._command_phase, self._command_status, self._command_failure = phase, None, None
        original_limits = self.limits
        try:
            if (isinstance(original_limits, EntryLimits) and phase in CAPTURE_PHASES
                    and command.get("cmd") == "entry-capture"
                    and phase == f"capture_{command.get('screen')}_{command.get('theme')}"):
                self.limits = replace(original_limits, request=original_limits.capture_request)
            try:
                status, body = self._exchange(command, allow_exit=allow_exit, until=until)
            finally:
                self.limits = original_limits
        except ConnectionRefusedError:
            if not poll_refused:
                self._retain_failure("INTERNAL_ERROR", category="EXCHANGE_FAILED")
            raise
        except bounded.SmokeFailure as error:
            if (error.code == "HTTP_FAILED" and self.report.original_errors
                    and self.report.transport_failure is None):
                self.report.transport_failure = http_failure_observation(
                    self.report.original_errors[-1], phase)
            self._retain_failure(error.code, category="EXCHANGE_FAILED")
            raise
        except (Exception, KeyboardInterrupt):
            self._retain_failure("INTERNAL_ERROR", category="EXCHANGE_FAILED")
            raise
        self._command_status = status
        return status, body

    def _positive(self, command, *, phase, allow_exit=False, until=None,
                  poll_refused=False):
        status, body = self._exchange_at(phase, command, allow_exit=allow_exit,
                                         until=until, poll_refused=poll_refused)
        if phase in ("entry_state", "entry_verify") and "captureProgress" in body:
            self.report.capture_progress = capture_progress_projection(body["captureProgress"])
        if status != 200 or body["ok"] is not True:
            # Retain the first finite refusal instead of collapsing every bind
            # failure. Never echo arbitrary remote errors, paths or stacks.
            remote = body.get("error")
            code = (remote if phase in CAPTION_PHASES and type(remote) is str
                    and remote in CAPTION_REFUSALS else "COMMAND_FAILED")
            self._retain_failure(code, category="REMOTE_ERROR", body=body)
            raise Failure(code)
        return body

    def _entry(self, body, *, count):
        if body.get("available") is not True:
            raise Failure("ENTRY_UNAVAILABLE")
        if body.get("held") is not False:
            raise Failure("ENTRY_HELD")
        if (type(body.get("captures")) is not int or body["captures"] != count
                or any(type(body.get(name)) is not bool for name in (
                    "nativeWindowReady", "startupReady", "welcomeReady"))):
            raise Failure("ENTRY_INVALID")
        return all(body[name] for name in ("nativeWindowReady", "startupReady", "welcomeReady"))

    def _ready(self):
        until = min(self.deadline, self.clock() + self.limits.ready)
        while self.clock() < until:
            try:
                body = self._positive({"cmd": "ping"}, phase="readiness_ping", until=until,
                                      poll_refused=True)
            except ConnectionRefusedError:
                body = None
            if body is not None:
                if type(body.get("pid")) is not int or body["pid"] != self.process.pid:
                    raise Failure("IDENTITY_REFUSED")
                if body.get("harnessMode") != "wallet":
                    raise Failure("MODE_REFUSED")
                if type(body.get("booted")) is not bool:
                    raise Failure("RESPONSE_INVALID")
                if body["booted"]:
                    self.report.checks["identity"] = True
                    break
            self.sleep(min(self.limits.poll, max(0, until - self.clock())))
        else:
            raise Failure("READINESS_TIMEOUT")
        self._command_phase, self._command_status, self._command_failure = "auth_refusal", None, None
        try:
            status, body = self._exchange({"cmd": "ping"}, token="invalid-entry-smoke-token", until=until)
        except bounded.SmokeFailure as error:
            self._retain_failure(error.code, category="EXCHANGE_FAILED")
            raise
        except (Exception, KeyboardInterrupt):
            self._retain_failure("INTERNAL_ERROR", category="EXCHANGE_FAILED")
            raise
        self._command_status = status
        if status != 400 or body != {"ok": False, "error": "bad token"}:
            raise Failure("AUTH_REFUSAL_INVALID")
        self.authenticated = self.report.checks["auth"] = True
        while self.clock() < until:
            body = self._positive({"cmd": "entry-state"}, phase="entry_state", until=until)
            if self._entry(body, count=0):
                self.report.checks["entry_ready"] = True
                return
            self.sleep(min(self.limits.poll, max(0, until - self.clock())))
        raise Failure("READINESS_TIMEOUT")

    def _window(self, body):
        if (not vector(body.get("window"), 4)
                or any(value <= 0 for value in body["window"][2:])
                or not vector(body.get("client"), 2, positive=True)
                or not vector(body.get("physical"), 2, positive=True)
                or not number(body.get("devicePixelRatio"), positive=True)
                or type(body.get("minimized")) is not bool
                or type(body.get("maximized")) is not bool):
            raise Failure("WINDOW_INVALID")
        return {name: body[name] for name in (
            "window", "client", "physical", "devicePixelRatio", "minimized", "maximized",
        )}

    @staticmethod
    def _same_window(actual, expected):
        return all(
            all(abs(a - b) < .01 for a, b in zip(actual[key], value))
            if isinstance(value, list) else actual[key] == value
            for key, value in expected.items()
        )

    def _caption_state(self, body, stage):
        keys = {"ok", "captionVersion", "stage", "observations", "original",
                "held", "pending", "settled", "window"}
        if (set(body) != keys or type(body.get("captionVersion")) is not int
                or body["captionVersion"] != 1 or type(body.get("stage")) is not int
                or body["stage"] != stage or type(body.get("observations")) is not int
                or not max(0, stage - 1) <= body["observations"] <= stage
                or any(type(body.get(name)) is not bool for name in (
                    "original", "held", "pending", "settled"))):
            raise Failure("CAPTION_INVALID")
        if body["original"] is not True or body["held"] is not False:
            raise Failure("CAPTION_HELD")
        if not body["settled"]:
            return False
        if body["pending"] or body["observations"] != stage or not isinstance(body["window"], dict):
            raise Failure("CAPTION_INVALID")
        if stage in (1, 3):
            actual = body["window"]
            if (set(actual) != {"minimized", "maximized"}
                    or any(type(actual.get(name)) is not bool
                           for name in ("minimized", "maximized"))):
                raise Failure("CAPTION_INVALID")
        else:
            actual = self._window(body["window"])
        if actual["maximized"] != (stage == 1) or actual["minimized"] != (stage == 3):
            raise Failure("CAPTION_NATIVE_MISMATCH")
        if stage in (2, 4) and (self.caption_baseline is None
                                or not self._same_window(actual, self.caption_baseline)):
            raise Failure("CAPTION_NATIVE_MISMATCH")
        return True

    def _caption_poll(self, stage, until):
        while self.clock() < until:
            body = self._positive({"cmd": "entry-caption", "do": "observe"},
                                  phase="caption_observe", until=until)
            if self._caption_state(body, stage):
                return
            self.sleep(min(self.limits.poll, max(0, until - self.clock())))
        raise Failure("CAPTION_TIMEOUT")

    def _caption(self):
        # Reserve before bind/tap: a lost response never authorizes geometry cleanup.
        self.caption_attempted = True
        until = min(self.deadline, self.clock() + min(20, self.limits.ready))
        body = self._positive({"cmd": "entry-caption", "do": "bind"},
                              phase="caption_bind", until=until)
        if not self._caption_state(body, 0):
            raise Failure("CAPTION_INVALID")
        self.caption_baseline = self._window(body["window"])
        if any(abs(a - b) >= .01 for a, b in zip(
                self.caption_baseline["client"], (1280, 780))):
            raise Failure("CAPTION_NATIVE_MISMATCH")
        for stage, action, check in ((1, "maximize", "maximized"),
                                     (2, "restore", "caption_restored"),
                                     (3, "minimize", "minimized")):
            body = self._positive({"cmd": "entry-caption", "do": action},
                                  phase=f"caption_{action}", until=until)
            if (set(body) != {"ok", "captionVersion", "stage", "admitted", "pendingObserved"}
                    or type(body.get("captionVersion")) is not int or body["captionVersion"] != 1
                    or type(body.get("stage")) is not int or body["stage"] != stage
                    or body.get("admitted") is not True or body.get("pendingObserved") is not True):
                raise Failure("CAPTION_INVALID")
            self._caption_poll(stage, until)
            self.report.caption_checks[check] = True
        self._positive({"cmd": "window", "do": "restore"},
                       phase="caption_native_restore", until=until)
        self._caption_poll(4, until)
        self.report.caption_checks["native_restored"] = True
        self.caption_complete = True

    def _restore(self):
        if self.caption_attempted and not self.caption_complete:
            self._command_phase, self._command_status, self._command_failure = "window_restore", None, None
            raise Failure("CAPTION_HELD")
        if self.window_changed:
            restored = self._positive({"cmd": "window", "restoreState": self.original_window},
                                      phase="window_restore")
            actual = self._window(restored)
            if restored.get("restored") is not True:
                raise Failure("WINDOW_RESTORE_FAILED")
            for key, expected in self.original_window.items():
                value = actual[key]
                same = (all(abs(a - b) < .01 for a, b in zip(value, expected))
                        if isinstance(expected, list) else value == expected)
                if not same:
                    raise Failure("WINDOW_RESTORE_FAILED")
            self.report.checks["window_restored"] = True
            body = self._positive({"cmd": "entry-check"}, phase="entry_verify")
            if (not self._entry(body, count=4) or body.get("frameReady") is not True
                    or body.get("restorationVerified") is not True):
                raise Failure("RESTORATION_INVALID")
            self.report.checks["entry_restored"] = True

    def _quit(self):
        self.quit_sent = True
        try:
            body = self._positive({"cmd": "quit"}, phase="close", allow_exit=True)
        except Exception as error:
            self.report.original_errors.append(error)
            raise Failure("CLOSE_UNCERTAIN") from None
        if body != {"ok": True}:
            raise Failure("CLOSE_FAILED")
        self.report.checks["close_ack"] = True
        try:
            code = self.process.wait(timeout=min(self.limits.exit, self._health(allow_exit=True)))
        except subprocess.TimeoutExpired:
            raise Failure("EXIT_TIMEOUT") from None
        self.report.exit_code, self.report.exit_observed = code, type(code) is int
        if type(code) is not int or code != 0:
            raise Failure("EXIT_FAILED")
        self.report.checks["exit"] = True

    def _record(self, action, *, cleanup=False):
        try:
            action()
        except bounded.SmokeFailure as error:
            self._retain_failure(error.code, cleanup=cleanup)
            self.report.fail(error.code, error)
        except (Exception, KeyboardInterrupt) as error:
            self._retain_failure("INTERNAL_ERROR", cleanup=cleanup)
            self.report.fail("INTERNAL_ERROR", error)

    def run(self):
        def capture():
            self._ready()
            self.original_window = self._window(self._positive(
                {"cmd": "window"}, phase="window_observe"))
            self.report.checks["window_saved"] = True
            self.window_changed = True  # Reserve before the mutating RPC.
            body = self._positive({"cmd": "window", "do": "show", "width": 1280, "height": 780},
                                  phase="window_show_resize")
            actual = self._window(body)
            if (body.get("clientMatched") is not True or actual["minimized"]
                    or actual["maximized"] or any(abs(a - b) >= .01 for a, b in zip(
                        actual["client"], (1280, 780)))):
                raise Failure("WINDOW_INVALID")
            self.report.checks["client_matched"] = True
            for screen, theme in SCENES:
                body = self._positive({"cmd": "entry-capture", "screen": screen, "theme": theme},
                                      phase=f"capture_{screen}_{theme}")
                self.artifacts.png(f"{screen}-{theme}.png", capture_bytes(body, screen, theme))
                self.report.checks[f"{screen}_{theme}"] = True
            self._caption()
        try:
            self._record(capture)
        finally:
            if self.authenticated and self.process.poll() is None:
                self._record(self._restore, cleanup=True)
                self._record(self._quit, cleanup=True)
            grace = min(self.limits.exit, max(0, self.deadline - self.clock())) if self.quit_sent else 0
            bounded.finish_original(self.process, self.drain, self.report, self.limits, grace=grace)
            self.report.output_bytes = getattr(self.drain, "count", 0)
            self.report.effect_trace = effect_trace_from_output(
                getattr(self.drain, "data", b""), complete=self.report.output_complete,
                overflow=self.report.output_overflow)
            self.report.captures = self.artifacts.records
        return self.report.public()


def main(arguments=None):
    report = Report()
    process = drain = artifacts = None
    try:
        arguments = sys.argv[1:] if arguments is None else arguments
        if arguments and (len(arguments) != 2 or arguments[0] != "--source-sha"
                          or not bounded.valid_sha(arguments[1])):
            raise Failure("ARGUMENTS_REFUSED")
        parent, expected = require_ci(os.environ, arguments[1] if arguments else None, platform=os.name)
        repo = Path(parent["GITHUB_WORKSPACE"])
        bounded.plain(repo)
        if repo.resolve() != Path.cwd().resolve():
            raise Failure("ENVIRONMENT_REFUSED")
        report.checks["environment"] = True
        report.source_sha, report.run_id = expected, parent["GITHUB_RUN_ID"]
        report.run_attempt = parent["GITHUB_RUN_ATTEMPT"]
        artifacts = Artifacts(repo)
        bounded.verify_source(repo, expected, parent)
        report.source_tree = source_tree(
            repo, parent, observe_tree=lambda tree: setattr(report, "source_tree", tree))
        report.checks["source"] = True
        binary, report.runner_sha256, identity = bounded.binary_hash(repo)
        kernel, report.dart_kernel_sha256, kernel_identity = bounded.binary_hash(repo, bounded.KERNEL)
        bounded.check_no_existing(repo, parent)
        report.checks["preflight"] = True
        profile = new_profile(repo)
        report.checks["profile"] = True
        token = secrets.token_urlsafe(32)
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        env = child_environment(parent, profile, port, token)
        for selected, original in ((binary, identity), (kernel, kernel_identity)):
            info = bounded.plain(selected)
            if (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns) != original:
                raise Failure("BINARY_REFUSED")
        try:
            process = subprocess.Popen([str(binary)], cwd=binary.parent, env=env,
                                       shell=False, stdin=subprocess.DEVNULL,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
        except Exception as error:
            report.fail("LAUNCH_FAILED", error)
            raise Failure("LAUNCH_FAILED") from None
        drain = bounded.OutputDrain(process.stdout, LIMITS.output_bytes, retain=True)
        session = EntrySmoke(process, bounded.LoopbackTransport(port, LIMITS.response_bytes),
                             token, drain, report, artifacts=artifacts, limits=LIMITS)
        process = None  # The session now owns the retained original object.
        session.run()
        for relative, digest, original in (
            (bounded.BINARY, report.runner_sha256, identity),
            (bounded.KERNEL, report.dart_kernel_sha256, kernel_identity),
        ):
            _, observed, current = bounded.binary_hash(repo, relative)
            if observed != digest or current != original:
                raise Failure("BINARY_REFUSED")
        bounded.verify_source(repo, expected, parent)
        if source_tree(repo, parent) != report.source_tree:
            raise Failure("SOURCE_REFUSED")
        report.checks["payload_stable"] = True
    except bounded.SmokeFailure as error:
        report.fail(error.code, error)
    except (Exception, KeyboardInterrupt) as error:
        report.fail("INTERNAL_ERROR", error)
    finally:
        if process is not None:
            bounded.finish_original(process, drain, report, LIMITS)
        if artifacts is not None:
            report.captures = artifacts.records
            try:
                artifacts.manifest(report.public())
            except (Exception, KeyboardInterrupt) as error:
                report.fail("ARTIFACT_FAILED", error)
    public = report.public()
    print(json.dumps(public, sort_keys=True, separators=(",", ":")))
    return 0 if public["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
