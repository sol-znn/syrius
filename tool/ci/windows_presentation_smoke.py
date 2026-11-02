"""Bounded CI-only presentation smoke; never a wallet or capture qualifier.

Build the separate harness Debug target before invoking this controller.
GITHUB_SHA is the default source pin; ``--source-sha`` can explicitly select
that same exact checked-out GitHub Actions SHA. The controller
does not build, download, package, upload, remove profiles, or adopt a process.
Its only Git invocation is a fixed, bounded, read-only HEAD identity query.
Public output is one allowlisted JSON summary; original exceptions and child
output are never printed. A retained original process is the only kill target.
"""

from __future__ import annotations

import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import socket
import stat
import subprocess
import sys
import threading
import time
from dataclasses import dataclass


BINARY = Path("build/windows/x64/runner/Debug/syrius.exe")
KERNEL = BINARY.parent / "data/flutter_assets/kernel_blob.bin"
BLOCKED = (
    "tap", "type", "key", "scroll", "drop", "seed", "clipboard",
    "shot", "screens", "import", "unlock", "chain",
)
CHECKS = (
    "environment", "source", "profile", "preflight", "identity", "auth",
    "welcome_dark", "welcome_light", "import_dark", "import_light",
    "state", "refusals", "close_ack", "exit",
)
CODES = frozenset((
    "ARGUMENTS_REFUSED", "ENVIRONMENT_REFUSED", "SOURCE_REFUSED",
    "BINARY_REFUSED", "PROFILE_REFUSED", "PREFLIGHT_FAILED",
    "PREFLIGHT_TIMEOUT", "PREFLIGHT_OUTPUT_REFUSED",
    "EXISTING_PROCESS", "LAUNCH_FAILED", "READINESS_TIMEOUT",
    "PROCESS_EXITED", "IDENTITY_REFUSED", "MODE_REFUSED",
    "HTTP_FAILED", "RESPONSE_INVALID", "AUTH_REFUSAL_INVALID",
    "COMMAND_FAILED", "STATE_INVALID", "THEME_INVALID",
    "VISIBILITY_INVALID", "REFUSAL_INVALID", "CLOSE_FAILED",
    "CLOSE_UNCERTAIN", "EXIT_TIMEOUT", "EXIT_FAILED", "TOTAL_DEADLINE",
    "FORCED_TERMINATION", "CLEANUP_FAILED", "OUTPUT_OVERFLOW",
    "OUTPUT_INCOMPLETE", "INTERNAL_ERROR",
))
REFUSED = "read-only presentation refuses this command"
REPLACED = frozenset((
    "APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "HOME", "USERPROFILE",
    "HOMEDRIVE", "HOMEPATH", "XDG_CONFIG_HOME", "XDG_DATA_HOME",
    "XDG_CACHE_HOME",
))
RUNTIME_ENV = frozenset((
    "SYSTEMROOT", "WINDIR", "SYSTEMDRIVE", "PATH", "PATHEXT", "COMSPEC",
    "OS", "PROCESSOR_ARCHITECTURE", "NUMBER_OF_PROCESSORS",
))


@dataclass(frozen=True)
class Limits:
    total: float = 90.0
    ready: float = 30.0
    request: float = 5.0
    poll: float = 0.1
    exit: float = 10.0
    cleanup: float = 5.0
    drain: float = 1.0
    response_bytes: int = 65536
    output_bytes: int = 131072


class SmokeFailure(Exception):
    def __init__(self, code):
        self.code = code if code in CODES else "INTERNAL_ERROR"
        super().__init__(self.code)


class Report:
    """Only this explicit projection may reach public stdout."""

    def __init__(self):
        self.source_sha = None
        self.runner_sha256 = None
        self.dart_kernel_sha256 = None
        self.checks = dict.fromkeys(CHECKS, False)
        self.errors = []
        self.original_errors = []
        self.exit_code = None
        self.exit_observed = False
        self.forced_kill = False
        self.output_complete = False
        self.output_overflow = False

    def fail(self, code, original=None):
        code = code if code in CODES else "INTERNAL_ERROR"
        if code not in self.errors:
            self.errors.append(code)
        if original is not None:
            self.original_errors.append(original)

    def public(self):
        complete = (
            all(self.checks[name] is True for name in CHECKS)
            and self.exit_observed and self.exit_code == 0
            and self.output_complete and not self.output_overflow
            and not self.forced_kill and not self.errors
        )
        return {
            "schema": 1,
            "source_sha": self.source_sha if valid_sha(self.source_sha) else None,
            "runner_sha256": safe_digest(self.runner_sha256),
            "dart_kernel_sha256": safe_digest(self.dart_kernel_sha256),
            "checks": {name: self.checks[name] is True for name in CHECKS},
            "exit_code": self.exit_code if type(self.exit_code) is int else None,
            "exit_observed": self.exit_observed is True,
            "forced_kill": self.forced_kill is True,
            "output_complete": self.output_complete is True,
            "output_overflow": self.output_overflow is True,
            "complete": complete,
            "success": complete,
            "error_codes": [code for code in self.errors if code in CODES],
        }


class OutputDrain:
    """Drain one original pipe continuously, retaining at most the byte cap."""

    def __init__(self, pipe, cap, *, retain=False):
        self.pipe = pipe
        self.cap = cap
        self.retain = retain
        self.data = bytearray()
        self.count = 0
        self.overflow = threading.Event()
        self.done = threading.Event()
        self.error = None
        self.thread = threading.Thread(target=self._read, daemon=True)
        self.thread.start()

    def _read(self):
        try:
            while chunk := self.pipe.read(4096):
                if not isinstance(chunk, bytes):
                    raise SmokeFailure("OUTPUT_INCOMPLETE")
                available = max(0, self.cap - self.count)
                self.count += len(chunk)
                if self.retain:
                    self.data.extend(chunk[:available])
                if self.count > self.cap:
                    self.overflow.set()
        except Exception as error:
            self.error = error
        finally:
            self.done.set()

    def finish(self, timeout):
        self.thread.join(timeout)
        if self.thread.is_alive() or self.error is not None:
            return False
        try:
            self.pipe.close()
        except Exception as error:
            self.error = error
            return False
        return True


@dataclass(frozen=True)
class Reply:
    status: int
    body: bytes
    content_type: str = "application/json"


class LoopbackTransport:
    """No proxy, redirects or discovery; each request owns its original socket."""

    def __init__(self, port, cap):
        self.port = port
        self.cap = cap

    def exchange(self, command, token, timeout):
        deadline = time.monotonic() + timeout
        connection = http.client.HTTPConnection(
            "127.0.0.1", self.port, timeout=timeout,
        )
        timer = None
        expired = threading.Event()
        try:
            connection.connect()
            original_socket = connection.sock

            def expire():
                expired.set()
                try:
                    original_socket.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass

            # A socket timeout alone allows indefinitely trickling headers.
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError()
            timer = threading.Timer(remaining, expire)
            timer.daemon = True
            timer.start()
            connection.request(
                "POST", "/", json.dumps(command).encode("utf-8"),
                {"Content-Type": "application/json", "x-harness-token": token},
            )
            response = connection.getresponse()
            body = response.read(self.cap + 1)
            if expired.is_set() or time.monotonic() >= deadline:
                raise TimeoutError()
            if len(body) > self.cap:
                raise SmokeFailure("RESPONSE_INVALID")
            return Reply(response.status, body, response.getheader("Content-Type", ""))
        finally:
            if timer is not None:
                timer.cancel()
            connection.close()


def valid_sha(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}", value) is not None


def safe_digest(value):
    return value if isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) else None


def decode_reply(reply, cap):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError()
            result[key] = value
        return result

    def invalid_constant(_):
        raise ValueError()

    try:
        if len(reply.body) > cap or reply.content_type.split(";")[0] != "application/json":
            raise ValueError()
        body = json.loads(
            reply.body.decode("utf-8"), object_pairs_hook=unique,
            parse_constant=invalid_constant,
        )
        if not isinstance(body, dict) or type(body.get("ok")) is not bool:
            raise ValueError()
        return body
    except (ValueError, TypeError, AttributeError, UnicodeError, RecursionError):
        raise SmokeFailure("RESPONSE_INVALID") from None


def finish_original(process, drain, report, limits, *, grace=0):
    """Never resolve a process from its PID, name, or another launcher."""
    try:
        if grace > 0 and process.poll() is None:
            try:
                process.wait(timeout=grace)
            except subprocess.TimeoutExpired:
                pass
        if process.poll() is None:
            report.forced_kill = True
            report.fail("FORCED_TERMINATION")
            process.kill()
        code = process.wait(timeout=limits.cleanup)
        if type(code) is not int:
            raise SmokeFailure("CLEANUP_FAILED")
        report.exit_code = code
        report.exit_observed = True
    except Exception as error:
        report.fail("CLEANUP_FAILED", error)
    if drain is None:
        report.fail("OUTPUT_INCOMPLETE")
        return
    report.output_overflow = drain.overflow.is_set()
    try:
        report.output_complete = drain.finish(limits.drain)
    except Exception as error:
        report.output_complete = False
        report.fail("CLEANUP_FAILED", error)
    # Observe again after joining: the final chunk can cross the cap.
    report.output_overflow = drain.overflow.is_set()
    if report.output_overflow:
        report.fail("OUTPUT_OVERFLOW")
    if not report.output_complete:
        report.fail("OUTPUT_INCOMPLETE", drain.error)


class PresentationSmoke:
    """Serial, finite protocol checks against exactly one admitted process."""

    def __init__(self, process, transport, token, drain, report, *,
                 limits=Limits(), clock=time.monotonic, sleep=time.sleep):
        self.process = process
        self.transport = transport
        self.token = token
        self.drain = drain
        self.report = report
        self.limits = limits
        self.clock = clock
        self.sleep = sleep
        self.deadline = clock() + limits.total
        self.surface = "welcome"
        self.theme = "dark"
        self.quit_sent = False

    def _health(self, *, allow_exit=False):
        if self.drain.overflow.is_set():
            raise SmokeFailure("OUTPUT_OVERFLOW")
        if self.drain.error is not None:
            raise SmokeFailure("OUTPUT_INCOMPLETE")
        remaining = self.deadline - self.clock()
        if remaining <= 0:
            raise SmokeFailure("TOTAL_DEADLINE")
        if not allow_exit and self.process.poll() is not None:
            raise SmokeFailure("PROCESS_EXITED")
        return remaining

    def _exchange(self, command, *, token=None, allow_exit=False, until=None):
        remaining = self._health(allow_exit=allow_exit)
        if until is not None:
            remaining = min(remaining, until - self.clock())
            if remaining <= 0:
                raise SmokeFailure("READINESS_TIMEOUT")
        try:
            reply = self.transport.exchange(
                command, self.token if token is None else token,
                min(self.limits.request, remaining),
            )
        except ConnectionRefusedError:
            raise
        except SmokeFailure:
            raise
        except Exception as error:
            self.report.original_errors.append(error)
            raise SmokeFailure("HTTP_FAILED") from None
        self._health(allow_exit=allow_exit)
        if until is not None and self.clock() >= until:
            raise SmokeFailure("READINESS_TIMEOUT")
        return reply.status, decode_reply(reply, self.limits.response_bytes)

    def _positive(self, command, *, surface=None, allow_exit=False):
        status, body = self._exchange(command, allow_exit=allow_exit)
        if status != 200 or body["ok"] is not True:
            raise SmokeFailure("COMMAND_FAILED")
        if (body.get("harnessMode") != "presentation"
                or body.get("presentationScreen") != (surface or self.surface)
                or body.get("readOnly") is not True):
            raise SmokeFailure("MODE_REFUSED")
        return body

    def _ready(self):
        deadline = min(self.deadline, self.clock() + self.limits.ready)
        while self.clock() < deadline:
            try:
                status, body = self._exchange({"cmd": "ping"}, until=deadline)
            except ConnectionRefusedError:
                body = None
            if body is not None:
                if status != 200 or body["ok"] is not True:
                    raise SmokeFailure("COMMAND_FAILED")
                if type(body.get("pid")) is not int or body["pid"] != self.process.pid:
                    raise SmokeFailure("IDENTITY_REFUSED")
                if (body.get("harnessMode") != "presentation"
                        or body.get("presentationScreen") != "welcome"):
                    raise SmokeFailure("MODE_REFUSED")
                if type(body.get("booted")) is not bool:
                    raise SmokeFailure("RESPONSE_INVALID")
                if body["booted"]:
                    self.report.checks["identity"] = True
                    return
            self.sleep(min(self.limits.poll, max(0, deadline - self.clock())))
        raise SmokeFailure("READINESS_TIMEOUT")

    def _state(self):
        body = self._positive({"cmd": "state"})
        expected = {
            "ok": True, "presentation": True, "readOnly": True,
            "surface": self.surface, "theme": self.theme,
            "actualCapture": False, "walletOwnerMounted": False,
            "harnessMode": "presentation", "presentationScreen": self.surface,
            "booted": True, "walletUnlocked": False,
            "walletInitCompleted": False, "tabs": [],
        }
        if body.keys() != expected.keys() or any(
            type(body[key]) is not type(value) or body[key] != value
            for key, value in expected.items()
        ):
            raise SmokeFailure("STATE_INVALID")
        self.report.checks["state"] = True
        return body

    def _visible(self, key, *, empty=False):
        body = self._positive({"cmd": "assert", "key": key})
        target = body.get("target")
        if (body.get("asserted") is not True
                or body.get("presentationOnly") is not True
                or body.get("actualCapture") is not False
                or not isinstance(target, dict) or target.get("key") != key
                or empty and (target.get("kind") != "field" or target.get("value") != "")):
            raise SmokeFailure("VISIBILITY_INVALID")

    def _observed_theme(self, body):
        if (body.get("mode") != self.theme or body.get("brightness") != self.theme
                or body.get("surface") != self.surface
                or body.get("theme") != self.theme
                or body.get("presentation") is not True
                or body.get("readOnly") is not True
                or body.get("actualCapture") is not False
                or body.get("walletOwnerMounted") is not False):
            raise SmokeFailure("THEME_INVALID")

    def _scenes(self):
        for surface in ("welcome", "import"):
            if surface != self.surface:
                body = self._positive(
                    {"cmd": "presentation", "surface": surface}, surface=surface,
                )
                self.surface = surface
                self._observed_theme(body)
            for theme in ("dark", "light"):
                body = self._positive({"cmd": "theme", "mode": theme})
                self.theme = theme
                self._observed_theme(body)
                self._visible("harness_presentation_banner")
                key = "welcome_create" if surface == "welcome" else "import_seed_field"
                self._visible(key, empty=surface == "import")
                self._state()
                self.report.checks[f"{surface}_{theme}"] = True

    def _refusals(self):
        before = self._state()
        for name in BLOCKED:
            status, body = self._exchange({"cmd": name})
            if status != 400 or body != {"ok": False, "error": REFUSED}:
                raise SmokeFailure("REFUSAL_INVALID")
            if self._state() != before:
                raise SmokeFailure("REFUSAL_INVALID")
        # State does not contain draft text. Re-observe the original empty field.
        self._visible("import_seed_field", empty=True)
        self.report.checks["refusals"] = True

    def _quit(self):
        self.quit_sent = True
        try:
            status, body = self._exchange({"cmd": "quit"}, allow_exit=True)
        except Exception as error:
            self.report.original_errors.append(error)
            raise SmokeFailure("CLOSE_UNCERTAIN") from None
        if status != 200 or body["ok"] is not True:
            raise SmokeFailure("CLOSE_FAILED")
        if (body.get("harnessMode") != "presentation"
                or body.get("presentationScreen") != self.surface
                or body.get("readOnly") is not True):
            raise SmokeFailure("CLOSE_FAILED")
        close = body.get("close")
        phases = {"queued": (True, False, False), "admitted": (False, True, False),
                  "completed": (False, True, True)}
        if not isinstance(close, dict) or close.get("status") not in phases:
            raise SmokeFailure("CLOSE_FAILED")
        expected = dict(zip(("queued", "admitted", "completed"), phases[close["status"]]))
        if (close.keys() != {"status", "queued", "admitted", "completed", "exitProved"}
                or close.get("exitProved") is not False
                or any(close.get(key) is not value for key, value in expected.items())):
            raise SmokeFailure("CLOSE_FAILED")
        self.report.checks["close_ack"] = True
        try:
            code = self.process.wait(timeout=min(self.limits.exit, self._health(allow_exit=True)))
        except subprocess.TimeoutExpired:
            raise SmokeFailure("EXIT_TIMEOUT") from None
        self.report.exit_code = code
        self.report.exit_observed = type(code) is int
        if type(code) is not int or code != 0:
            raise SmokeFailure("EXIT_FAILED")
        self.report.checks["exit"] = True

    def run(self):
        try:
            self._ready()
            status, body = self._exchange(
                {"cmd": "ping"}, token="invalid-presentation-smoke-token",
            )
            if status != 400 or body != {"ok": False, "error": "bad token"}:
                raise SmokeFailure("AUTH_REFUSAL_INVALID")
            self.report.checks["auth"] = True
            self._scenes()
            self._refusals()
            self._quit()
        except SmokeFailure as error:
            self.report.fail(error.code, error)
        except (Exception, KeyboardInterrupt) as error:
            self.report.fail("INTERNAL_ERROR", error)
        finally:
            grace = min(self.limits.exit, max(0, self.deadline - self.clock())) if self.quit_sent else 0
            finish_original(self.process, self.drain, self.report, self.limits, grace=grace)
        return self.report.public()


def fixed_command(arguments, *, cwd, env, cap=0, timeout=5):
    """Bounded admission helpers also retain their own original Popen handles."""
    process = drain = None
    try:
        process = subprocess.Popen(
            arguments, cwd=cwd, env=env, shell=False, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE if cap else subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        drain = OutputDrain(process.stdout, cap, retain=True) if cap else None
        code = process.wait(timeout=timeout)
        if drain is not None and (not drain.finish(1) or drain.overflow.is_set()):
            raise SmokeFailure("PREFLIGHT_OUTPUT_REFUSED")
        return code, bytes(drain.data) if drain is not None else b""
    except (Exception, KeyboardInterrupt) as error:
        failure = (error.code if isinstance(error, SmokeFailure)
                   else "PREFLIGHT_TIMEOUT" if isinstance(error, subprocess.TimeoutExpired)
                   else "PREFLIGHT_FAILED")
        if process is not None:
            try:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)
            except Exception:
                raise SmokeFailure("CLEANUP_FAILED") from None
        if drain is not None and not drain.finish(1):
            raise SmokeFailure("CLEANUP_FAILED") from None
        raise SmokeFailure(failure) from None


def verify_source(repo, expected, parent, *, run=fixed_command):
    # rev-parse handles both ordinary Actions branch and detached checkouts.
    env = {key: value for key, value in parent.items() if not key.upper().startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    code, output = run(
        ["git", "-C", str(repo), "rev-parse", "HEAD"], cwd=repo, env=env, cap=128,
    )
    if code != 0 or output not in ((expected + "\n").encode(), (expected + "\r\n").encode()):
        raise SmokeFailure("SOURCE_REFUSED")


def require_ci(parent, expected, *, platform):
    # A copied Windows environment no longer has os.environ's case folding.
    normalized = {}
    for key, value in parent.items():
        upper = key.upper()
        if upper in normalized and normalized[upper] != value:
            raise SmokeFailure("ENVIRONMENT_REFUSED")
        normalized[upper] = value
    expected = normalized.get("GITHUB_SHA") if expected is None else expected
    if (platform != "nt" or normalized.get("GITHUB_ACTIONS") != "true"
            or normalized.get("RUNNER_OS") != "Windows"
            or normalized.get("RUNNER_ENVIRONMENT") != "github-hosted"
            or not valid_sha(expected) or normalized.get("GITHUB_SHA") != expected
            or not normalized.get("GITHUB_WORKSPACE") or not normalized.get("SYSTEMROOT")):
        raise SmokeFailure("ENVIRONMENT_REFUSED")
    return normalized, expected


def check_no_existing(repo, parent, *, run=fixed_command):
    helper = Path(__file__).absolute().with_name('windows_process_preflight.py')
    if not stat.S_ISREG(plain(helper).st_mode):
        raise SmokeFailure("PREFLIGHT_FAILED")
    env = {key: value for key, value in parent.items() if key.upper() in RUNTIME_ENV}
    code, _ = run(
        [sys.executable, '-I', '-S', '-B', str(helper)],
        # Keep the original deadline and retained Popen handle; no shell startup.
        cwd=repo, env=env, timeout=15,
    )
    if code == 23:
        raise SmokeFailure("EXISTING_PROCESS")
    if code != 0:
        raise SmokeFailure("PREFLIGHT_FAILED")


def child_environment(parent, profile, port, token):
    # Do not pass inherited CI credentials, proxies or harness control flags.
    env = {key.upper(): value for key, value in parent.items()
           if key.upper() in RUNTIME_ENV and key.upper() not in REPLACED
           and not key.upper().startswith("SYRIUS_HARNESS_")}
    env.update({
        "APPDATA": str(profile / "AppData" / "Roaming"),
        "LOCALAPPDATA": str(profile / "AppData" / "Local"),
        "TEMP": str(profile / "Temp"), "TMP": str(profile / "Temp"),
        "HOME": str(profile), "USERPROFILE": str(profile),
        "SYRIUS_HARNESS_HOME": str(profile), "SYRIUS_HARNESS_PORT": str(port),
        "SYRIUS_HARNESS_TOKEN": token, "SYRIUS_HARNESS_PRESENTATION": "welcome",
    })
    if profile.drive:
        env.update(HOMEDRIVE=profile.drive, HOMEPATH=str(profile)[len(profile.drive):])
    return env


def plain(path):
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
        raise SmokeFailure("PROFILE_REFUSED")
    return info


def new_profile(repo):
    root = repo / ".harness"
    if not root.exists():
        root.mkdir(mode=0o700)
    if not stat.S_ISDIR(plain(root).st_mode):
        raise SmokeFailure("PROFILE_REFUSED")
    profile = root / ("ci-presentation-smoke-" + secrets.token_hex(12))
    profile.mkdir(mode=0o700)  # An existing directory is always a refusal.
    for relative in ("AppData/Roaming", "AppData/Local", "Temp"):
        (profile / relative).mkdir(parents=True, mode=0o700)
    plain(profile)
    return profile


def binary_hash(repo, relative=BINARY):
    current = repo
    for part in relative.parts:
        current = current / part
        plain(current)
    digest = hashlib.sha256()
    with current.open("rb") as original:
        before = os.fstat(original.fileno())
        if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= 268435456:
            raise SmokeFailure("BINARY_REFUSED")
        received = 0
        while chunk := original.read(1048576):
            received += len(chunk)
            if received > 268435456:
                raise SmokeFailure("BINARY_REFUSED")
            digest.update(chunk)
        after = os.fstat(original.fileno())
    identity = lambda info: (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)
    if identity(before) != identity(after) or identity(after) != identity(current.stat()):
        raise SmokeFailure("BINARY_REFUSED")
    return current, digest.hexdigest(), identity(after)


def main(arguments=None):
    report = Report()
    process = drain = None
    limits = Limits()
    try:
        arguments = sys.argv[1:] if arguments is None else arguments
        if arguments and (len(arguments) != 2 or arguments[0] != "--source-sha" or not valid_sha(arguments[1])):
            raise SmokeFailure("ARGUMENTS_REFUSED")
        parent, expected = require_ci(
            os.environ, arguments[1] if arguments else None, platform=os.name,
        )
        repo = Path(parent["GITHUB_WORKSPACE"])
        plain(repo)
        if repo.resolve() != Path.cwd().resolve():
            raise SmokeFailure("ENVIRONMENT_REFUSED")
        report.checks["environment"] = True
        verify_source(repo, expected, parent)
        report.source_sha = expected
        report.checks["source"] = True
        binary, report.runner_sha256, identity = binary_hash(repo)
        kernel, report.dart_kernel_sha256, kernel_identity = binary_hash(repo, KERNEL)
        check_no_existing(repo, parent)
        report.checks["preflight"] = True
        profile = new_profile(repo)
        report.checks["profile"] = True
        token = secrets.token_urlsafe(32)
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        # Closing this reservation has a race; exact token/PID/mode must win.
        env = child_environment(parent, profile, port, token)
        # These are the selected runner and Dart payload, not a bundle digest
        # or proof of the Flutter build target. The workflow owns that build.
        for selected, original in ((binary, identity), (kernel, kernel_identity)):
            check = plain(selected)
            if (check.st_dev, check.st_ino, check.st_size, check.st_mtime_ns) != original:
                raise SmokeFailure("BINARY_REFUSED")
        try:
            process = subprocess.Popen(
                [str(binary)], cwd=binary.parent, env=env, shell=False,
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, bufsize=0,
            )
        except Exception as error:
            report.fail("LAUNCH_FAILED", error)
            raise SmokeFailure("LAUNCH_FAILED") from None
        drain = OutputDrain(process.stdout, limits.output_bytes)
        session = PresentationSmoke(
            process, LoopbackTransport(port, limits.response_bytes), token,
            drain, report, limits=limits,
        )
        process = None  # Transfer the original object before its owned cleanup.
        session.run()
    except SmokeFailure as error:
        report.fail(error.code, error)
    except (Exception, KeyboardInterrupt) as error:
        report.fail("INTERNAL_ERROR", error)
    finally:
        if process is not None:
            finish_original(process, drain, report, limits)
    public = report.public()
    print(json.dumps(public, sort_keys=True, separators=(",", ":")))
    return 0 if public["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
