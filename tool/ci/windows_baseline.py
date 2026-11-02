"""Hosted Windows baseline with bounded private output and no wallet startup.

The tooling receives a fresh isolated profile. Each DLL probe gets a separate
fresh profile. Profiles are preserved, never adopted or removed. Raw doctor,
analyzer, compiler and test output stays in capped memory and is never uploaded.
Only the explicit public projection is printed. A DLL can execute initialization
while being mapped; that behavior remains outside the map/export lookup proof.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import secrets
import shutil
import stat
import subprocess
import sys
import time
from dataclasses import dataclass

try:
    from . import dart_test_failure
    from .windows_presentation_smoke import (
        OutputDrain, RUNTIME_ENV, SmokeFailure, binary_hash, plain, require_ci,
        valid_sha,
    )
except ImportError:
    import dart_test_failure
    from windows_presentation_smoke import (
        OutputDrain, RUNTIME_ENV, SmokeFailure, binary_hash, plain, require_ci,
        valid_sha,
    )


VERSION = re.compile(r"[0-9]+(?:\.[0-9]+){1,3}")
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
STAGES = frozenset((
    "source_head", "source_tree", "source_clean_before", "source_clean_restored",
    "source_clean_generated", "source_clean_after",
    "inventory_windows", "inventory_git", "inventory_git_bash", "inventory_cmake",
    "inventory_flutter", "inventory_dart", "inventory_python", "inventory_pillow",
    "inventory_node", "inventory_docker_client", "inventory_docker_daemon",
    "enable_windows", "doctor", "restore_application", "restore_vendored",
    "analyze_vendored", "analyze_root", "unit_widget_tests", "generate_sources",
    "format_integration", "generate_localizations", "generate_metadata",
    "build_debug", "build_release", "map_source", "map_debug", "map_release",
))
CODES = frozenset((
    "ARGUMENTS_REFUSED", "ENVIRONMENT_REFUSED", "SOURCE_REFUSED",
    "PROFILE_REFUSED", "REQUIRED_TOOL_MISSING", "COMMAND_REFUSED",
    "LAUNCH_FAILED", "COMMAND_TIMEOUT", "OUTPUT_OVERFLOW",
    "OUTPUT_INCOMPLETE", "CLEANUP_FAILED", "REQUIRED_COMMAND_FAILED",
    "DOCTOR_UNPROVEN", "ANALYSIS_INVALID", "ANALYSIS_FAILED", "INVENTORY_INCOMPLETE",
    "INVENTORY_REPORT_FAILED",
    "TEST_EVENTS_INVALID", "TESTS_FAILED", "SOURCE_CHANGED",
    "LIBRARY_CHANGED", "LIBRARY_PROBE_INVALID", "INTERNAL_ERROR",
))
INVENTORY = frozenset((
    "windows", "architecture", "git", "git_bash", "msvc",
    "native_desktop_workload", "cmake", "windows_sdk", "flutter", "dart",
    "python", "pillow", "node", "chrome", "edge", "docker_desktop",
    "docker_client", "docker_daemon", "developer_mode",
))
SCOPES = frozenset(("platform", "path", "git_install", "metadata", "standard_install", "registry"))
STATUSES = frozenset(("present", "absent", "unknown", "enabled", "disabled"))
LIBRARIES = {
    "source": Path("lib/embedded_node/blobs/libznn.dll"),
    "debug": Path("build/windows/x64/runner/Debug/libznn.dll"),
    "release": Path("build/windows/x64/runner/Release/libznn.dll"),
}
CHECKS = (
    "source", "locked_restoration", "windows_doctor", "vendored_analysis",
    "root_analysis", "unit_widget_tests", "generated_correspondence",
    "debug_build", "release_build", "library_hash_correspondence",
    "library_map_exports", "source_unchanged",
)
EXTRA_ENV = frozenset((
    "FLUTTER_ROOT", "PUB_CACHE", "JAVA_HOME", "ANDROID_HOME", "ANDROID_SDK_ROOT",
    "PROGRAMFILES", "PROGRAMFILES(X86)", "PROGRAMW6432",
))
HOSTED_INVENTORY_PROFILE_ENV = frozenset((
    'APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'HOME', 'USERPROFILE', 'HOMEDRIVE', 'HOMEPATH',
))

# Read installed versions only. Paths and PowerShell diagnostics remain private.
WINDOWS_INVENTORY = r"""
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$result = @{}
function Mark-Inventory($value) {
  [Console]::Out.WriteLine('SYRIUS_INVENTORY_STAGE:' + $value)
  [Console]::Out.Flush()
}
Mark-Inventory 'entry'
function Put-Version($key, $value, $scope) {
  $status = if ([string]::IsNullOrWhiteSpace($value)) { 'unknown' } else { 'present' }
  $result[$key] = @{ status = $status; version = $value; scope = $scope }
}
Mark-Inventory 'visual_studio'
$vswhere = [IO.Path]::Combine(${env:ProgramFiles(x86)}, 'Microsoft Visual Studio\Installer\vswhere.exe')
try {
  if ([IO.File]::Exists($vswhere)) {
    Mark-Inventory 'vswhere_installation'
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0) { throw 'query failed' }
    if ($vs) {
      Mark-Inventory 'msvc_version'
      $tools = [IO.Path]::Combine($vs, 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt')
      Put-Version 'msvc' ([IO.File]::ReadAllText($tools)).Trim() 'standard_install'
      Mark-Inventory 'vswhere_workload'
      $workloads = & $vswhere -latest -products '*' -requiresAny -requires Microsoft.VisualStudio.Workload.NativeDesktop Microsoft.VisualStudio.Workload.VCTools -property installationVersion
      if ($LASTEXITCODE -ne 0) { throw 'query failed' }
      $state = if ($workloads) { 'present' } else { 'absent' }
      $result['native_desktop_workload'] = @{status=$state; version=$workloads; scope='standard_install'}
    } else {
      $result['msvc'] = @{status='absent'; version=$null; scope='standard_install'}
      $result['native_desktop_workload'] = @{status='absent'; version=$null; scope='standard_install'}
    }
  }
} catch {}
Mark-Inventory 'windows_sdk'
try {
  $roots = @()
  foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
    $base = $null; $key = $null
    try {
      $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
      $key = $base.OpenSubKey('SOFTWARE\Microsoft\Windows Kits\Installed Roots')
      if ($key) {
        $kits = $key.GetValue('KitsRoot10', $null)
        if ($kits -and $roots -notcontains $kits) { $roots += $kits }
      }
    } finally { if ($key) { $key.Dispose() }; if ($base) { $base.Dispose() } }
  }
  $best = $null
  foreach ($kits in $roots) {
    $include = [IO.Path]::Combine($kits, 'Include')
    if ([IO.Directory]::Exists($include)) {
      $directories = [IO.Directory]::GetDirectories($include)
      if ($directories.Length -gt 128) { throw 'SDK inventory bound' }
      foreach ($directory in $directories) {
        $name = [IO.Path]::GetFileName($directory)
        if ($name -match '^\d+\.\d+\.\d+\.\d+$' -and (!$best -or [version]$name -gt [version]$best)) { $best = $name }
      }
    }
  }
  if ($best) { Put-Version 'windows_sdk' $best 'registry' }
  else { $result['windows_sdk'] = @{status='absent'; version=$null; scope='registry'} }
} catch {}
Mark-Inventory 'browsers'
foreach ($item in @(
  @('chrome', 'Google\Chrome\Application\chrome.exe'),
  @('edge', 'Microsoft\Edge\Application\msedge.exe'),
  @('docker_desktop', 'Docker\Docker\Docker Desktop.exe')
)) {
  try {
    $found = $null
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
      if ($root) {
        $candidate = [IO.Path]::Combine($root, $item[1])
        if ([IO.File]::Exists($candidate)) { $found = $candidate; break }
      }
    }
    if ($found) {
      Put-Version $item[0] ([Diagnostics.FileVersionInfo]::GetVersionInfo($found)).ProductVersion 'standard_install'
    } else {
      $result[$item[0]] = @{status='absent'; version=$null; scope='standard_install'}
    }
  } catch {}
}
Mark-Inventory 'developer_mode'
try {
  $mode = [Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock', 'AllowDevelopmentWithoutDevLicense', $null)
  $state = if ($null -eq $mode) { 'absent' } elseif ($mode -eq 1) { 'enabled' }
    elseif ($mode -eq 0) { 'disabled' } else { 'unknown' }
  $result['developer_mode'] = @{status=$state; version=$null; scope='registry'}
} catch {}
Mark-Inventory 'complete'
$parts = @()
foreach ($key in @('msvc', 'native_desktop_workload', 'windows_sdk', 'chrome', 'edge', 'docker_desktop', 'developer_mode')) {
  $row = $result[$key]
  $state = [string]$row.status
  if ($state -notmatch '^(present|absent|unknown|enabled|disabled)$') { $state = 'unknown' }
  $scope = [string]$row.scope
  if ($scope -notmatch '^(standard_install|registry)$') { $scope = 'standard_install' }
  $version = $row.version
  if (($version -is [string]) -and $version -match '^[0-9]+(?:\.[0-9]+){1,3}$') { $version = '"' + $version + '"' }
  else { $version = 'null'; if ($state -eq 'present') { $state = 'unknown' } }
  $parts += '"' + $key + '":{"status":"' + $state + '","version":' + $version + ',"scope":"' + $scope + '"}'
}
[Console]::Out.WriteLine('SYRIUS_INVENTORY_JSON:{' + [string]::Join(',', [string[]]$parts) + '}')
[Console]::Out.Flush()
"""
NATIVE_INVENTORY_STAGES = ('entry', 'visual_studio', 'windows_sdk', 'browsers',
                           'developer_mode', 'complete')
NATIVE_INVENTORY_DETAILS = ('vswhere_installation', 'msvc_version', 'vswhere_workload')


class BaselineFailure(Exception):
    def __init__(self, code):
        self.code = code if code in CODES else "INTERNAL_ERROR"
        super().__init__(self.code)


@dataclass
class Outcome:
    output: bytes = b""
    exit_code: int | None = None
    exit_observed: bool = False
    forced_kill: bool = False
    output_complete: bool = False
    output_overflow: bool = False
    output_bytes: int = 0
    seconds: float = 0.0
    errors: tuple = ()

    @property
    def transport_complete(self):
        return (self.exit_observed and self.output_complete
                and not self.forced_kill and not self.output_overflow
                and not self.errors)

    @property
    def success(self):
        return self.transport_complete and self.exit_code == 0

    def public(self):
        return {
            "exit_code": self.exit_code if type(self.exit_code) is int else None,
            "exit_observed": self.exit_observed is True,
            "forced_kill": self.forced_kill is True,
            "output_complete": self.output_complete is True,
            "output_overflow": self.output_overflow is True,
            "output_bytes": self.output_bytes, "seconds": round(self.seconds, 3),
            "success": self.success,
            "error_codes": [code for code in self.errors if code in CODES],
        }


def run_bounded(arguments, *, cwd, env, timeout=30, cap=262144,
                spawn=None, drain_factory=None, clock=None):
    """Retain the original handle; timeout, overflow or forced exit cannot pass."""
    spawn = subprocess.Popen if spawn is None else spawn
    drain_factory = OutputDrain if drain_factory is None else drain_factory
    clock = time.monotonic if clock is None else clock
    started = clock()
    outcome = Outcome()
    errors = []
    process = drain = None
    try:
        process = spawn(
            arguments, cwd=cwd, env=env, shell=False, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0,
        )
        drain = drain_factory(process.stdout, cap, retain=True)
        deadline = started + timeout
        while True:
            if drain.overflow.is_set():
                errors.append("OUTPUT_OVERFLOW")
                break
            remaining = deadline - clock()
            if remaining <= 0:
                errors.append("COMMAND_TIMEOUT")
                break
            try:
                outcome.exit_code = process.wait(timeout=min(0.2, remaining))
                outcome.exit_observed = True
                break
            except subprocess.TimeoutExpired:
                continue
    except (Exception, KeyboardInterrupt):
        errors.append("LAUNCH_FAILED" if process is None else "INTERNAL_ERROR")
    finally:
        if process is not None:
            try:
                if process.poll() is None:
                    outcome.forced_kill = True
                    process.kill()
                if not outcome.exit_observed:
                    outcome.exit_code = process.wait(timeout=5)
                    outcome.exit_observed = True
            except Exception:
                errors.append("CLEANUP_FAILED")
        if drain is not None:
            outcome.output_complete = drain.finish(1)
            outcome.output_overflow = drain.overflow.is_set()
            outcome.output_bytes = drain.count
            outcome.output = bytes(drain.data)
            if not outcome.output_complete:
                errors.append("OUTPUT_INCOMPLETE")
            if outcome.output_overflow and "OUTPUT_OVERFLOW" not in errors:
                errors.append("OUTPUT_OVERFLOW")
        outcome.seconds = max(0.0, clock() - started)
        outcome.errors = tuple(errors)
    return outcome


def command_line(arguments, env):
    """Use the Windows batch interpreter explicitly, with fixed safe tokens."""
    if Path(arguments[0]).suffix.lower() not in (".bat", ".cmd"):
        return arguments
    if any(re.search(r'["&|<>^%\r\n]', value) for value in arguments):
        raise BaselineFailure("COMMAND_REFUSED")
    interpreter = str(Path(env["SYSTEMROOT"]) / "System32/cmd.exe")
    # Preserve cmd.exe's quoted /c payload without a second quoting pass.
    return subprocess.list2cmdline([interpreter]) + " /d /s /c \"" + subprocess.list2cmdline(arguments) + "\""


def fresh_environment(repo, parent):
    root = repo / ".harness"
    if not root.exists():
        root.mkdir(mode=0o700)
    if not stat.S_ISDIR(plain(root).st_mode):
        raise BaselineFailure("PROFILE_REFUSED")
    profile = root / ("ci-windows-baseline-" + secrets.token_hex(12))
    profile.mkdir(mode=0o700)
    for relative in ("AppData/Roaming", "AppData/Local", "Temp"):
        (profile / relative).mkdir(parents=True, mode=0o700)
    plain(profile)
    env = {key: value for key, value in parent.items() if key in RUNTIME_ENV | EXTRA_ENV}
    env.update({
        "APPDATA": str(profile / "AppData/Roaming"),
        "LOCALAPPDATA": str(profile / "AppData/Local"),
        "TEMP": str(profile / "Temp"), "TMP": str(profile / "Temp"),
        "HOME": str(profile), "USERPROFILE": str(profile),
        "XDG_CONFIG_HOME": str(profile / "config"),
        "XDG_DATA_HOME": str(profile / "data"),
        "XDG_CACHE_HOME": str(profile / "cache"),
        "FLUTTER_SUPPRESS_ANALYTICS": "true", "DART_SUPPRESS_ANALYTICS": "true",
        "CI": "true", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
        "GITHUB_ACTIONS": "true", "RUNNER_OS": "Windows",
        "RUNNER_ENVIRONMENT": "github-hosted", "GITHUB_SHA": parent["GITHUB_SHA"],
        "GITHUB_WORKSPACE": str(repo), "SYRIUS_WINDOWS_BASELINE_PROFILE": str(profile),
    })
    if profile.drive:
        env.update(HOMEDRIVE=profile.drive, HOMEPATH=str(profile)[len(profile.drive):])
    return env


def clean_text(output):
    return ANSI.sub("", output.decode("utf-8", errors="replace"))


def version_record(value, scope, *, absent=False):
    value = value.strip() if isinstance(value, str) else ""
    return {
        "status": "present" if VERSION.fullmatch(value) else ("absent" if absent else "unknown"),
        "version": value if VERSION.fullmatch(value) else None, "scope": scope,
    }


def inventory_projection(values):
    result = {}
    for key in sorted(INVENTORY):
        item = values.get(key, {})
        if not isinstance(item, dict):
            item = {}
        status, version = item.get("status"), item.get("version")
        valid = isinstance(version, str) and (
            VERSION.fullmatch(version) or key == "architecture" and version in ("x64", "x86", "arm64")
        )
        result[key] = {
            "status": status if isinstance(status, str) and status in STATUSES else "unknown",
            "version": version if valid else None,
            "scope": item.get("scope") if isinstance(item.get("scope"), str)
            and item.get("scope") in SCOPES else "standard_install",
        }
        if status == "present" and version is not None and not valid:
            result[key]["status"] = "unknown"
    return result


def native_inventory_command(powershell):
    encoded = base64.b64encode(WINDOWS_INVENTORY.encode('utf-16-le')).decode('ascii')
    return [str(powershell), '-NoLogo', '-NoProfile', '-NonInteractive', '-OutputFormat', 'Text',
            '-EncodedCommand', encoded]


def native_inventory_reply(output):
    markers, details, frames, valid, unframed = [], [], [], True, 0
    for line in clean_text(output).splitlines():
        if line.startswith('SYRIUS_INVENTORY_STAGE:'):
            stage = line.partition(':')[2]
            if stage in NATIVE_INVENTORY_DETAILS:
                if (markers and markers[-1] == 'visual_studio'
                        and len(details) < len(NATIVE_INVENTORY_DETAILS)
                        and stage == NATIVE_INVENTORY_DETAILS[len(details)]):
                    details.append(stage)
                else:
                    valid = False
            elif len(markers) < len(NATIVE_INVENTORY_STAGES) and stage == NATIVE_INVENTORY_STAGES[len(markers)]:
                markers.append(stage)
            else:
                valid = False
        elif line.startswith('SYRIUS_INVENTORY_JSON:'):
            frames.append(line.partition(':')[2])
        elif line.strip():
            unframed += 1
    try:
        values = json.loads(frames[0]) if len(frames) == 1 else None
    except (ValueError, UnicodeError):
        values = None
    complete = (valid and unframed == 0 and tuple(markers) == NATIVE_INVENTORY_STAGES
                and type(values) is dict)
    receipt = dict(milestones=markers, details=details, protocol_valid=valid, json_observed=type(values) is dict,
                   frame_count=len(frames), unframed_lines=unframed, complete=complete)
    return values if complete else None, receipt


def find_git_bash(git):
    """Git can be exposed from cmd, bin or mingw64/bin on a hosted runner."""
    if git:
        for parent in list(Path(git).parents)[:4]:
            for relative in ('bin/bash.exe', 'usr/bin/bash.exe'):
                candidate = parent / relative
                if candidate.is_file():
                    return str(candidate)
    return None


def doctor_status(output):
    sections = {"windows_version": "unknown", "visual_studio": "unknown"}
    seen = set()
    for line in clean_text(output).splitlines():
        # Flutter's pinned VerboseLogger adds this finite timing prefix when
        # global flags precede doctor. The status marker still decides proof.
        line = re.sub(r"^\s*\[(?: {8}| *\+[1-9][0-9]{0,11} ms)\] ", "", line, count=1)
        match = re.match(r"^\s*\[([^\]]+)\]\s+(Windows Version|Visual Studio)(?:\s|$)", line)
        if match:
            key = "windows_version" if match[2] == "Windows Version" else "visual_studio"
            if key in seen:
                raise BaselineFailure("DOCTOR_UNPROVEN")
            seen.add(key)
            sections[key] = {"✓": "pass", "√": "pass", "!": "warning", "X": "fail",
                             "x": "fail"}.get(match[1], "unknown")
    return sections


def analysis_counts(output):
    counts = {"errors": 0, "warnings": 0, "infos": 0}
    levels = {"error": "errors", "warning": "warnings", "info": "infos"}
    summaries = []
    for line in clean_text(output).splitlines():
        match = re.match(r"^\s*(error|warning|info)\s+[•-]\s+", line)
        if match:
            counts[levels[match[1]]] += 1
        if re.match(r"^\s*No issues found!", line):
            summaries.append(0)
        match = re.match(r"^\s*(\d+) issues? found\.", line)
        if match:
            summaries.append(int(match[1]))
    if len(summaries) != 1 or summaries[0] != sum(counts.values()):
        raise BaselineFailure("ANALYSIS_INVALID")
    return counts


def test_counts(output):
    """Count terminal testDone events, including hidden and skipped outcomes."""
    counts = {"passed": 0, "failed": 0, "skipped": 0, "hidden": 0,
              "terminal_events": 0, "error_events": 0}
    seen = set()
    terminal = None
    for line in output.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except (ValueError, UnicodeError):
            raise BaselineFailure("TEST_EVENTS_INVALID") from None
        if not isinstance(event, dict) or terminal is not None:
            raise BaselineFailure("TEST_EVENTS_INVALID")
        kind = event.get("type")
        if kind == "testDone":
            identity, result = event.get("testID"), event.get("result")
            skipped, hidden = event.get("skipped", False), event.get("hidden", False)
            if (type(identity) is not int or identity in seen
                    or result not in ("success", "failure", "error")
                    or type(skipped) is not bool or type(hidden) is not bool):
                raise BaselineFailure("TEST_EVENTS_INVALID")
            seen.add(identity)
            counts["terminal_events"] += 1
            counts["hidden"] += int(hidden)
            if result != "success":
                counts["failed"] += 1
            elif skipped:
                counts["skipped"] += 1
            elif not hidden:
                counts["passed"] += 1
        elif kind == "error":
            counts["error_events"] += 1
        elif kind == "done":
            terminal = event.get("success")
            if type(terminal) is not bool:
                raise BaselineFailure("TEST_EVENTS_INVALID")
        elif kind not in ("start", "suite", "group", "testStart", "print", "allSuites", "debug"):
            raise BaselineFailure("TEST_EVENTS_INVALID")
    if terminal is None or counts["terminal_events"] == 0:
        raise BaselineFailure("TEST_EVENTS_INVALID")
    counts["terminal_success"] = terminal
    return counts


def localization_snapshot(repo):
    folder = repo / "lib/l10n"
    paths = sorted({Path("l10n.yaml"), Path("lib/l10n/untranslated.json"),
                    *(path.relative_to(repo) for pattern in ("*.arb", "app_localizations*.dart")
                      for path in folder.glob(pattern))})
    digest = hashlib.sha256()
    for relative in paths:
        _, value, _ = binary_hash(repo, relative)
        digest.update(relative.as_posix().encode() + b"\0" + value.encode() + b"\n")
    return {"files": len(paths), "sha256": digest.hexdigest()}


def library_reply(output):
    try:
        reply = json.loads(output)
    except (ValueError, UnicodeError):
        raise BaselineFailure("LIBRARY_PROBE_INVALID") from None
    expected = {
        "schema": 1, "mapped": True, "run_node_lookup": True,
        "stop_node_lookup": True, "exports_invoked": False,
    }
    if (not isinstance(reply, dict) or reply != expected
            or any(type(reply[key]) is not type(value) for key, value in expected.items())):
        raise BaselineFailure("LIBRARY_PROBE_INVALID")
    return dict(expected)


class Baseline:
    def __init__(self, repo, parent, source):
        self.repo, self.parent, self.source = repo, parent, source
        self.tree = self.tool_env = None
        self.stages, self.inventory, self.analysis = {}, {}, {}
        self.doctor = {"windows_version": "unknown", "visual_studio": "unknown"}
        self.tests = None
        self.test_failures = None
        self.localization, self.libraries, self.tools = {}, {}, {}
        self.checks = dict.fromkeys(CHECKS, False)
        self.errors = []
        self.inventory_only = False
        self.native_probe = None
        self.deadline = time.monotonic() + 90 * 60

    def command(self, name, arguments, *, required=True, cwd=None, timeout=30,
                cap=262144, fresh=False, hosted_inventory=False):
        if name not in STAGES or name in self.stages:
            raise BaselineFailure("COMMAND_REFUSED")
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise BaselineFailure("COMMAND_TIMEOUT")
        if hosted_inventory:
            if (not self.inventory_only or name != 'inventory_windows'
                    or self.parent.get('GITHUB_ACTIONS') != 'true'
                    or self.parent.get('RUNNER_ENVIRONMENT') != 'github-hosted'
                    or self.parent.get('GITHUB_EVENT_NAME') != 'workflow_dispatch'
                    or self.parent.get('GITHUB_REPOSITORY') != 'edgepillar/syrius'):
                raise BaselineFailure('ENVIRONMENT_REFUSED')
            # Installed-tool COM/registry discovery uses this fresh runner's
            # actual Windows profile. SDK and wallet commands stay isolated.
            env = {key: value for key, value in self.parent.items()
                   if key in RUNTIME_ENV | EXTRA_ENV | HOSTED_INVENTORY_PROFILE_ENV}
        else:
            if self.tool_env is None:
                self.tool_env = fresh_environment(self.repo, self.parent)
            env = fresh_environment(self.repo, self.parent) if fresh else self.tool_env
        outcome = run_bounded(command_line(arguments, env), cwd=cwd or self.repo,
                              env=env, timeout=min(timeout, remaining), cap=cap)
        self.stages[name] = {"required": required, **outcome.public()}
        if required and not outcome.success:
            raise BaselineFailure("REQUIRED_COMMAND_FAILED")
        return outcome

    def flutter(self, stage, arguments, **options):
        return self.command(stage, [self.tools["flutter"], "--no-version-check", *arguments], **options)

    def observe_version(self, key, arguments, expression, *, scope="path", absent_exit=None):
        if arguments is None:
            self.inventory[key] = version_record(None, scope, absent=True)
            return
        outcome = self.command("inventory_" + key, arguments, required=False)
        match = re.search(expression, clean_text(outcome.output)) if outcome.success else None
        self.inventory[key] = version_record(
            match[1] if match else None, scope,
            absent=outcome.transport_complete and outcome.exit_code == absent_exit,
        )

    def collect_inventory(self):
        self.inventory["windows"] = version_record(platform.version(), "platform")
        architecture = {"amd64": "x64", "x86_64": "x64", "arm64": "arm64", "x86": "x86"}.get(platform.machine().lower())
        self.inventory["architecture"] = {
            "status": "present" if architecture else "unknown", "version": architecture, "scope": "platform",
        }
        powershell = Path(self.parent["SYSTEMROOT"]) / "System32/WindowsPowerShell/v1.0/powershell.exe"
        native = self.command('inventory_windows', native_inventory_command(powershell), required=False,
                              hosted_inventory=self.inventory_only)
        values, progress = native_inventory_reply(native.output)
        self.native_probe = dict(command=native.public(),
            environment_scope=('fresh_hosted_runner_readonly_inventory' if self.inventory_only
                               else 'isolated_sdk_profile'), **progress)
        if native.success and values is not None:
            for key in ('msvc', 'native_desktop_workload', 'windows_sdk', 'chrome', 'edge',
                        'docker_desktop', 'developer_mode'):
                if isinstance(values.get(key), dict):
                    self.inventory[key] = values[key]
        def found(name):
            return shutil.which(name, path=self.parent.get("PATH", ""))
        for key, executable, arguments, expression in (
            ("git", found("git"), ["--version"],
             r"^git version ([0-9]+(?:\.[0-9]+){1,3})(?:\.windows\.\d+)?(?:\s|$)"),
            ("cmake", found("cmake"), ["--version"], r"^cmake version ([0-9.]+)"),
            ("node", found("node"), ["--version"], r"^v([0-9.]+)"),
            ("docker_client", found("docker"), ["--version"], r"^Docker version ([0-9.]+)"),
        ):
            self.observe_version(key, [executable, *arguments] if executable else None, expression)
        git = found("git")
        bash = find_git_bash(git)
        self.observe_version("git_bash", [bash, "--version"] if bash else None,
                             r"^GNU bash, version ([0-9.]+)", scope="git_install")
        docker = found("docker")
        self.observe_version("docker_daemon", [docker, "info", "--format", "{{.ServerVersion}}"] if docker else None,
                             r"^([0-9]+(?:\.[0-9]+){1,3})\s*$")
        self.observe_version("python", [sys.executable, "--version"], r"^Python ([0-9.]+)")
        self.observe_version(
            "pillow", [sys.executable, "-c", "import importlib.metadata\ntry:\n print(importlib.metadata.version('Pillow'))\nexcept importlib.metadata.PackageNotFoundError:\n raise SystemExit(3)"],
            r"^([0-9.]+)\s*$", scope="metadata", absent_exit=3,
        )
        flutter = self.flutter("inventory_flutter", ["--version", "--machine"], required=False)
        if flutter.success:
            try:
                values = json.loads(flutter.output)
                self.inventory["flutter"] = version_record(values.get("frameworkVersion"), "path")
            except (ValueError, UnicodeError, AttributeError):
                pass
        self.observe_version("dart", [self.tools["dart"], "--version"], r"^Dart SDK version: ([0-9.]+)")

    def run(self):
        git = shutil.which("git", path=self.parent.get("PATH", ""))
        flutter = shutil.which("flutter", path=self.parent.get("PATH", ""))
        if not git or not flutter:
            raise BaselineFailure("REQUIRED_TOOL_MISSING")
        head = self.command("source_head", [git, "rev-parse", "HEAD"], cap=128).output.strip()
        if head != self.source.encode("ascii"):
            raise BaselineFailure("SOURCE_REFUSED")
        tree = self.command("source_tree", [git, "rev-parse", "HEAD^{tree}"], cap=128).output.strip().decode("ascii")
        if not valid_sha(tree):
            raise BaselineFailure("SOURCE_REFUSED")
        self.tree = tree
        before = self.command("source_clean_before", [git, "status", "--porcelain=v1", "--untracked-files=all"])
        if before.output:
            raise BaselineFailure("SOURCE_CHANGED")
        self.checks["source"] = True
        dart = Path(flutter).parent / "cache/dart-sdk/bin/dart.exe"
        if not dart.is_file():
            raise BaselineFailure("REQUIRED_TOOL_MISSING")
        self.tools.update(flutter=flutter, dart=str(dart))
        self.collect_inventory()
        if self.inventory_only:
            after = self.command('source_clean_after', [git, 'status', '--porcelain=v1', '--untracked-files=all'])
            if after.output:
                raise BaselineFailure('SOURCE_CHANGED')
            self.checks['source_unchanged'] = True
            if any(item['status'] == 'unknown' for key, item in inventory_projection(self.inventory).items()
                   if key != 'docker_daemon'):
                raise BaselineFailure('INVENTORY_INCOMPLETE')
            return
        self.flutter("enable_windows", ["config", "--enable-windows-desktop"])
        doctor = self.flutter("doctor", ["doctor", "-v"], required=False, timeout=180, cap=524288)
        if not doctor.transport_complete:
            raise BaselineFailure("DOCTOR_UNPROVEN")
        self.doctor = doctor_status(doctor.output)
        if set(self.doctor.values()) != {"pass"}:
            raise BaselineFailure("DOCTOR_UNPROVEN")
        self.checks["windows_doctor"] = True
        original_localizations = localization_snapshot(self.repo)
        self.flutter("restore_application", ["pub", "get", "--enforce-lockfile"], timeout=600, cap=4194304)
        self.flutter("restore_vendored", ["pub", "get", "--enforce-lockfile"],
                     cwd=self.repo / "patched_packages/reown_core-1.3.8", timeout=600, cap=4194304)
        restored = self.command("source_clean_restored", [git, "status", "--porcelain=v1", "--untracked-files=all"])
        if restored.output:
            raise BaselineFailure("SOURCE_CHANGED")
        self.checks["locked_restoration"] = True
        for stage, check, cwd in (
            ("analyze_vendored", "vendored_analysis", self.repo / "patched_packages/reown_core-1.3.8"),
            ("analyze_root", "root_analysis", self.repo),
        ):
            result = self.flutter(stage, ["analyze", "--no-pub", "--no-fatal-infos"],
                                  cwd=cwd, required=False, timeout=300, cap=8388608)
            if not result.transport_complete:
                raise BaselineFailure("ANALYSIS_FAILED")
            self.analysis[stage] = analysis_counts(result.output)
            if not result.success or self.analysis[stage]["errors"] or self.analysis[stage]["warnings"]:
                raise BaselineFailure("ANALYSIS_FAILED")
            self.checks[check] = True
        suite = self.flutter("unit_widget_tests", [
            "test", "--no-pub", "--reporter", "json", "--concurrency=1",
            "--timeout", "60s", "--exclude-tags", "chain", "test",
        ], required=False, timeout=2700, cap=67108864)
        if not suite.success:
            self.test_failures = dart_test_failure.locations(suite.output)
        if not suite.transport_complete:
            raise BaselineFailure("TESTS_FAILED")
        self.tests = test_counts(suite.output)
        if (not suite.success or not self.tests["terminal_success"]
                or self.tests["failed"] or self.tests["error_events"] or not self.tests["passed"]):
            raise BaselineFailure("TESTS_FAILED")
        self.checks["unit_widget_tests"] = True
        self.command("generate_sources", [str(dart), "run", "build_runner", "build"], timeout=600, cap=8388608)
        self.command("format_integration", [str(dart), "format", "integration_test"], timeout=120, cap=1048576)
        self.flutter("generate_localizations", ["gen-l10n"], timeout=180, cap=1048576)
        self.localization = {
            "before": original_localizations, "after": localization_snapshot(self.repo),
        }
        if self.localization["before"] != self.localization["after"]:
            raise BaselineFailure("SOURCE_CHANGED")
        generated = self.command("source_clean_generated", [git, "status", "--porcelain=v1", "--untracked-files=all"])
        if generated.output:
            raise BaselineFailure("SOURCE_CHANGED")
        self.checks["generated_correspondence"] = True
        self.command("generate_metadata", [str(dart), "run", "tool/generate_git_metadata.dart"], timeout=120)
        for configuration in ("debug", "release"):
            self.flutter("build_" + configuration, [
                "build", "windows", "--" + configuration, "--no-pub",
                "--dart-define-from-file=.dart_tool/git_metadata.json",
            ], timeout=1200, cap=16777216)
            self.checks[configuration + "_build"] = True
        pinned = {}
        for variant, relative in LIBRARIES.items():
            selected, digest, identity = binary_hash(self.repo, relative)
            pinned[variant] = (selected, digest, identity)
            self.libraries[variant] = {"sha256": digest, "map_exports": False}
        if len({item[1] for item in pinned.values()}) != 1:
            raise BaselineFailure("LIBRARY_CHANGED")
        self.checks["library_hash_correspondence"] = True
        for variant, (_, digest, identity) in pinned.items():
            if binary_hash(self.repo, LIBRARIES[variant])[1:] != (digest, identity):
                raise BaselineFailure("LIBRARY_CHANGED")
            result = self.command("map_" + variant, [
                str(dart), "tool/ci/windows_library_probe.dart", "--variant", variant,
            ], timeout=30, cap=131072, fresh=True)
            library_reply(result.output)
            if binary_hash(self.repo, LIBRARIES[variant])[1:] != (digest, identity):
                raise BaselineFailure("LIBRARY_CHANGED")
            self.libraries[variant]["map_exports"] = True
        self.checks["library_map_exports"] = True
        after = self.command("source_clean_after", [git, "status", "--porcelain=v1", "--untracked-files=all"])
        if after.output:
            raise BaselineFailure("SOURCE_CHANGED")
        self.checks["source_unchanged"] = True

    def public(self):
        run = {}
        for key, environment in (("id", "GITHUB_RUN_ID"), ("attempt", "GITHUB_RUN_ATTEMPT")):
            value = self.parent.get(environment)
            run[key] = value if isinstance(value, str) and re.fullmatch(r"[1-9][0-9]{0,19}", value) else None
        if self.inventory_only:
            inventory = inventory_projection(self.inventory)
            checks = dict(source=self.checks['source'], source_unchanged=self.checks['source_unchanged'],
                inventory=all(item['status'] != 'unknown' for key, item in inventory.items() if key != 'docker_daemon'))
            return dict(schema=1, source_sha=self.source if valid_sha(self.source) else None,
                source_tree=self.tree if valid_sha(self.tree) else None, run=run,
                scope='github_hosted_windows_inventory', inventory=inventory, native_probe=self.native_probe,
                stages={name: self.stages[name] for name in sorted(self.stages) if name in STAGES},
                checks=checks, success=all(checks.values()) and not self.errors,
                error_codes=[code for code in self.errors if code in CODES],
                baseline_qualified=False, wallet_qualified=False)
        return {
            "schema": 1, "source_sha": self.source if valid_sha(self.source) else None,
            "source_tree": self.tree if valid_sha(self.tree) else None,
            "run": run,
            "scope": "github_hosted_windows_baseline",
            "inventory": inventory_projection(self.inventory),
            "stages": {name: self.stages[name] for name in sorted(self.stages) if name in STAGES},
            "doctor": {"scope": "windows_desktop_only", **self.doctor},
            "analysis": self.analysis, "tests": self.tests,
            **({"test_failures": self.test_failures}
               if self.test_failures is not None else {}),
            "localization_correspondence": self.localization, "libraries": self.libraries,
            "checks": {name: self.checks[name] is True for name in CHECKS},
            "success": all(self.checks.values()) and not self.errors,
            "error_codes": [code for code in self.errors if code in CODES],
            "proof_limits": {
                "library": "map_and_export_lookup_only",
                "dll_initialization_side_effects": "not_qualified",
                "wallet_loader": "not_invoked", "node_exports": "not_invoked",
                "owner_machine": "not_qualified", "wallet_runtime": "not_qualified",
                "native_wallet_tests": "pending",
            },
        }


def main(arguments=None):
    report = Baseline(Path("."), {}, None)
    try:
        arguments = sys.argv[1:] if arguments is None else arguments
        if arguments not in ([], ['--inventory-only']):
            raise BaselineFailure("ARGUMENTS_REFUSED")
        parent, source = require_ci(os.environ, None, platform=os.name)
        repo = Path(parent["GITHUB_WORKSPACE"])
        plain(repo)
        if repo.resolve() != Path.cwd().resolve():
            raise BaselineFailure("ENVIRONMENT_REFUSED")
        report = Baseline(repo, parent, source)
        report.inventory_only = arguments == ['--inventory-only']
        report.run()
    except (BaselineFailure, SmokeFailure) as error:
        report.errors.append(error.code if error.code in CODES else "INTERNAL_ERROR")
    except (Exception, KeyboardInterrupt):
        report.errors.append("INTERNAL_ERROR")
    public = report.public()
    if report.inventory_only:
        try:
            if report.checks['source']:
                root = report.repo / '.harness'
                plain(root)
                output = root / 'ci-windows-inventory'
                output.mkdir(mode=0o700)
                with (output / 'manifest.json').open('x', encoding='ascii') as stream:
                    json.dump(public, stream, sort_keys=True, separators=(',', ':'))
                    stream.write('\n')
        except Exception:
            public['success'] = False
            public['error_codes'].append('INVENTORY_REPORT_FAILED')
        notice = json.dumps({key: value for key, value in public.items() if key != 'stages'},
                            sort_keys=True, separators=(',', ':'))
        if len(notice.encode()) <= 3800:
            print('::notice title=Hosted Windows inventory::' + notice)
    print(json.dumps(public, sort_keys=True, separators=(",", ":")))
    return 0 if public["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
