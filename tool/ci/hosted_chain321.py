"""Source-bound chain-321 labs in fresh hosted runners, without public RPC.

Linux uses five owned Docker containers. Windows uses five original native
process handles and the same genesis. Importing this module starts nothing.
The default node-only lane admits no wallet or seed. An explicit native-wallet
opt-in runs a fresh public-fixture profile while those original nodes are owned.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import socket
import stat
import struct
import subprocess
import sys
import time

from tool.ci.windows_presentation_smoke import OutputDrain
from tool.ci.loopback_relay import PAIRS as RELAY_PAIRS, TARGET as RELAY_TARGET, Relay
from tool.ci import native_stack_probe, node_panic_projection, producer_shutdown_patch, read_first_client_fixture
from tool.ci import lab_asset_progress
from tools.devnet.lab import owned_lab as wire_policy
from tools.devnet.lab.socket_transport import make_transports


NODE_SHA = "590f43ca7a24dccd8e883bc8903a0cb02e54528a"
UPSTREAM_NODE_SHA = "2d1b929cc3fa5269cf133757d4a6963821137984"
NODE_SOURCES = {
    "original": (NODE_SHA, "3bedc2fde71035c983997451c2d7e76b66d2d210"),
    "upstream": (UPSTREAM_NODE_SHA, "4467fff960ea6a5409908d7c85497a68482e0edb"),
    "lab-fix": (producer_shutdown_patch.BASE_SHA, producer_shutdown_patch.BASE_TREE),
}
SHUTDOWN_TESTS = (
    "TestStopWaitsForGatedRunPeer", "TestStopDoesNotStrandRunLoopOnCheckpoint",
    "TestPeerRunJoinsProtocolGoroutines", "TestWaitExpireTaskReturnsOnQuit",
    "TestProtoRWExposesPeerClose", "TestStopIsIdempotentAndConcurrent",
    "TestSameIdentityReconnectDuringGatedCleanup",
)
GO_FAILURE_CODES = frozenset(("GO_TEST_TIMEOUT", "GO_TEST_PANIC", "GO_TEST_BUILD_FAILED",
    "GO_TEST_ASSERTION", "GO_TEST_UNCLASSIFIED", "GO_RECONNECT_RESET", "GO_RECONNECT_ABORTED",
    "GO_RECONNECT_EOF", "GO_RECONNECT_TIMEOUT", "GO_RECONNECT_WRITE", "GO_RECONNECT_REASON",
    "GO_RECONNECT_UNCLASSIFIED"))
ROLES = ("pillar", "pillar2", "pillar3", "observer", "rpc")
OCTETS = dict(zip(ROLES, (10, 12, 13, 14, 11)))
NATIVE_PORTS = dict(zip(ROLES, (45991, 45992, 45993, 45994, 45995)))
MIB, GIB = 1024**2, 1024**3
MAX_WORK = 4 * GIB
# Only fresh, non-secret hosted regression VMs use this floor. Local and
# production storage retain their separate 10 GiB policy.
FIXTURE_MIN_FREE = 2 * GIB
GO_VERSION = "1.24.1"
CODES = frozenset((
    "ENVIRONMENT_REFUSED", "SOURCE_REFUSED", "STORAGE_REFUSED",
    "COMMAND_FAILED", "COMMAND_TIMEOUT", "OUTPUT_REFUSED", "STOP_UNKNOWN",
    "CONFIG_REFUSED", "PORT_CONFLICT", "NODE_EXITED", "RPC_UNAVAILABLE",
    "RPC_REFUSED", "GENESIS_MISMATCH", "PRODUCTION_UNPROVEN",
    "DOCKER_REFUSED", "RESOURCE_CHANGED", "INTERNAL_ERROR",
    "NODE_REGRESSIONS_REFUSED", "WALLET_TOUR_FAILED", "WALLET_INSPECTION_FAILED", "CHECKPOINT_REFUSED",
)) | wire_policy.CODES
NODE_DIAGNOSTICS = frozenset((
    "NODE_CLI_REFUSED", "NODE_STORAGE_REFUSED", "NODE_PANIC",
    "NODE_KEYSTORE_REFUSED", "NODE_GENESIS_REFUSED", "NODE_PORT_CONFLICT",
    "NODE_STARTUP_FAILED", "NODE_SIGNAL_RECEIVED",
    "NODE_STOP_REQUESTED", "NODE_P2P_STOP_REQUESTED", "NODE_HTTP_STOPPED",
    "NODE_DATA_LOCK_RELEASE_REQUESTED", "NODE_STOP_FAILED",
))


class Failure(Exception):
    def __init__(self, code):
        self.code = code if code in CODES else "INTERNAL_ERROR"
        super().__init__(self.code)


def need(value, code):
    if not value:
        raise Failure(code)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def selected_node_source(value):
    need(type(value) is str and value in NODE_SOURCES, "SOURCE_REFUSED")
    return NODE_SOURCES[value]


def wallet_tour_requested(backend, parent):
    value = parent.get('SYRIUS_WINDOWS_WALLET_TOUR', 'false')
    need(value in ('true', 'false'), 'ENVIRONMENT_REFUSED')
    if value == 'true':
        need(backend == 'native' and parent.get('SYRIUS_LAB_NODE_SOURCE') == 'lab-fix'
             and parent.get('SYRIUS_NATIVE_STACK_DIAGNOSTIC') == 'true', 'ENVIRONMENT_REFUSED')
    return value == 'true'


READONLY_CATALOG_SCHEMAS = dict(home=1, settings=2, navigation=3, details=4)


def readonly_catalog_family(parent):
    """Select exactly one existing family before SDK or private input allocation."""
    value = parent.get('SYRIUS_READONLY_CATALOG_FAMILY', 'details')
    need(type(value) is str and value in READONLY_CATALOG_SCHEMAS,
         'ENVIRONMENT_REFUSED')
    return value


def wallet_inspection_requested(backend, parent):
    value = parent.get('SYRIUS_WINDOWS_WALLET_INSPECTION', 'false')
    need(value in ('true', 'false'), 'ENVIRONMENT_REFUSED')
    if value == 'true':
        need(backend == 'native' and parent.get('SYRIUS_LAB_NODE_SOURCE') == 'lab-fix'
             and parent.get('SYRIUS_NATIVE_STACK_DIAGNOSTIC') == 'true'
             and parent.get('SYRIUS_WINDOWS_WALLET_TOUR', 'false') == 'false', 'ENVIRONMENT_REFUSED')
        readonly_catalog_family(parent)
    return value == 'true'


def require_environment(backend, parent):
    need(parent.get("GITHUB_ACTIONS") == "true" and parent.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
         and parent.get("SYRIUS_HOSTED_RUNNER") == "github-hosted"
         and parent.get("GITHUB_REPOSITORY") in ("edgepillar/syrius", "sol-znn/syrius")
         and re.fullmatch("[a-f0-9]{40}", parent.get("GITHUB_SHA", "")), "ENVIRONMENT_REFUSED")
    need((backend == "docker" and sys.platform == "linux")
         or (backend == "native" and sys.platform == "win32"), "ENVIRONMENT_REFUSED")
    need(parent.get("SYRIUS_NATIVE_STACK_DIAGNOSTIC") in (None, "true", "false"), "ENVIRONMENT_REFUSED")
    selected_node_source(parent.get("SYRIUS_LAB_NODE_SOURCE", "original"))
    wallet_inspection_requested(backend, parent)
    return wallet_tour_requested(backend, parent)


def shutdown_test_result(raw):
    """A zero Go exit alone cannot qualify an empty or skipped test filter."""
    need(type(raw) is bytes and 0 < len(raw) <= MIB, "NODE_REGRESSIONS_REFUSED")
    seen, package_passed = set(), False
    lines = raw.splitlines()
    need(len(lines) <= 10000, "NODE_REGRESSIONS_REFUSED")
    for line in lines:
        try:
            event = json.loads(line)
        except (ValueError, UnicodeError):
            raise Failure("NODE_REGRESSIONS_REFUSED") from None
        need(type(event) is dict and event.get("Action") not in ("skip", "fail", "build-fail"),
             "NODE_REGRESSIONS_REFUSED")
        if event.get("Action") == "pass":
            need(event.get("Package") == "github.com/zenon-network/go-zenon/p2p/legacy",
                 "NODE_REGRESSIONS_REFUSED")
            test = event.get("Test")
            if test is None:
                package_passed = True
            elif test in SHUTDOWN_TESTS:
                need(test not in seen, "NODE_REGRESSIONS_REFUSED")
                seen.add(test)
            else:
                need(type(test) is str and any(test.startswith(name + "/") for name in SHUTDOWN_TESTS),
                     "NODE_REGRESSIONS_REFUSED")
    need(package_passed and seen == set(SHUTDOWN_TESTS), "NODE_REGRESSIONS_REFUSED")
    return dict(passed=True, tests=list(SHUTDOWN_TESTS), skips=0)


def reconnect_failure_code(output):
    """Classify the pinned public assertion without retaining its socket details."""
    match = re.search(r"shutdown_test\.go:381: second attempt rejected with (.+), want [^\r\n]+", output)
    if match is None:
        return None
    error = match[1].lower()
    for code, patterns in (
        ("RESET", ("connection reset", "forcibly closed")),
        ("ABORTED", ("connection was aborted", "connection abort")),
        ("EOF", ("eof",)),
        ("TIMEOUT", ("i/o timeout", "deadline exceeded", "timed out")),
        ("WRITE", ("write error:",)),
        ("REASON", ("too many peers", "useless peer", "quitting", "incompatible", "identity")),
    ):
        if (any(pattern in error for pattern in patterns)
                and (code != "EOF" or error.strip() in ("eof", "unexpected eof"))):
            return "GO_RECONNECT_" + code
    return "GO_RECONNECT_UNCLASSIFIED"


def shutdown_failure_observation(raw, receipt, stderr=b""):
    """Retain failed named tests and public test-line numbers without logs."""
    result = dict(status="UNAVAILABLE", exit_code=None, output_complete=None, forced=None,
                  passed=[], failed=[], skipped=[], active=[], locations=[], codes=[])
    if type(receipt) is not dict:
        return result
    result.update(exit_code=receipt.get("exit_code"), output_complete=receipt.get("output_complete"),
                  forced=receipt.get("forced"))
    result["status"] = "REFUSED"
    if (type(raw) is not bytes or len(raw) > MIB or len(raw.splitlines()) > 10000
            or type(stderr) is not bytes or len(stderr) > MIB):
        return result
    seen = {key: set() for key in ("run", "pass", "fail", "skip")}
    output, reconnect_output, build_failed = [], [], False
    try:
        for line in raw.splitlines():
            event = json.loads(line)
            need(type(event) is dict, "NODE_REGRESSIONS_REFUSED")
            action, name = event.get("Action"), event.get("Test")
            need(type(action) is str, "NODE_REGRESSIONS_REFUSED")
            if action in ("build-output", "build-fail"):
                build_failed |= action == "build-fail"
            else:
                need(event.get("Package") == "github.com/zenon-network/go-zenon/p2p/legacy",
                     "NODE_REGRESSIONS_REFUSED")
            if name is not None:
                need(type(name) is str and name.split("/", 1)[0] in SHUTDOWN_TESTS,
                     "NODE_REGRESSIONS_REFUSED")
                if name in SHUTDOWN_TESTS and action in seen:
                    seen[action].add(name)
            if action in ("output", "build-output"):
                need(type(event.get("Output")) is str, "NODE_REGRESSIONS_REFUSED")
                output.append(event["Output"])
                if name == "TestSameIdentityReconnectDuringGatedCleanup":
                    reconnect_output.append(event["Output"])
    except (Failure, ValueError, UnicodeError):
        return result
    text = "".join(output) + "\n" + stderr.decode("utf-8", "replace")
    codes = []
    if "panic: test timed out after" in text:
        codes.append("GO_TEST_TIMEOUT")
    if "panic:" in text or "fatal error:" in text:
        codes.append("GO_TEST_PANIC")
    if build_failed or "[build failed]" in text:
        codes.append("GO_TEST_BUILD_FAILED")
    if seen["fail"] and not codes:
        codes.append("GO_TEST_ASSERTION")
    if "TestSameIdentityReconnectDuringGatedCleanup" in seen["fail"]:
        reconnect = reconnect_failure_code("".join(reconnect_output))
        if reconnect is not None:
            codes.append(reconnect)
    result.update(status="COMPLETE" if result["output_complete"] is True and result["forced"] is False else "PARTIAL",
        passed=sorted(seen["pass"]), failed=sorted(seen["fail"]), skipped=sorted(seen["skip"]),
        active=sorted(seen["run"] - seen["pass"] - seen["fail"] - seen["skip"]),
        locations=sorted({int(line) for line in re.findall(
            r"(?:^|[/\\\s])shutdown_test\.go:([1-9][0-9]{0,5})(?:[:\s]|$)", text)})[:8],
        codes=codes or ["GO_TEST_UNCLASSIFIED"])
    return result


def run_shutdown_tests(commands, source, report):
    count = len(commands.originals)
    try:
        raw = commands.run(["go", "test", "-json", "-mod=readonly", "-count=1",
            "-run", "^(" + "|".join(SHUTDOWN_TESTS) + ")$", "-timeout", "30s", "./p2p/legacy"],
            cwd=source, timeout=180)
        report["upstream_stop_regressions"] = shutdown_test_result(raw)
    except Failure:
        if len(commands.originals) == count + 1:
            original = commands.originals[-1]
            raw, stderr = (bytes(d.data) for d in original.drains)
            report["upstream_stop_failure"] = shutdown_failure_observation(raw, original.receipt, stderr)
        raise


def source_matches(commands, source, head, base_tree, compiled_tree):
    need(commands.git(source, "rev-parse", "HEAD") == head
         and commands.git(source, "rev-parse", "HEAD^{tree}") == base_tree
         and commands.git(source, "write-tree") == compiled_tree
         and not commands.git(source, "diff", "--name-only")
         and not commands.git(source, "ls-files", "--others", "--exclude-standard"),
         "SOURCE_REFUSED")


def run_wallet_shutdown_tests(commands, repo, source, report):
    """Adapt only the test client, then restore the exact compiled production tree."""
    policy = read_first_client_fixture
    evidence = report['upstream_client_fixture'] = policy.pending()
    patch = repo / 'tool/ci/node_fixtures/read_first_test_client.patch'
    target = source / policy.TEST_PATH
    original = regular(target)
    try:
        adapted = policy.patched(original, regular(patch))
    except policy.Refused:
        raise Failure('NODE_REGRESSIONS_REFUSED') from None
    source_matches(commands, source, producer_shutdown_patch.BASE_SHA,
                   producer_shutdown_patch.BASE_TREE, producer_shutdown_patch.COMPILED_TREE)
    commands.git(source, 'apply', '--check', '--whitespace=error-all', str(patch))
    evidence['phase'] = 'held'
    commands.git(source, 'apply', '--whitespace=error-all', str(patch))
    need(regular(target) == adapted
         and commands.git(source, 'diff', '--name-only') == policy.TEST_PATH,
         'SOURCE_REFUSED')
    evidence.update(phase='applied', all_seven_test_bodies_unchanged=True)
    need(commands.run(['gofmt', '-d', str(target)], cwd=source) == b'', 'SOURCE_REFUSED')
    index = len(commands.originals)
    try:
        run_shutdown_tests(commands, source, report)
    finally:
        evidence['phase'] = 'held'
        if len(commands.originals) == index + 1:
            receipt = commands.originals[index].receipt
            if type(receipt) is dict:
                evidence.update(test_exit=receipt.get('exit_code'),
                    test_output_complete=receipt.get('output_complete'), test_forced=receipt.get('forced'))
        # Never restore over an unknown launch, interrupted command or changed input.
        if (type(evidence['test_exit']) is int and evidence['test_output_complete'] is True
                and evidence['test_forced'] is False):
            need(regular(target) == adapted, 'SOURCE_REFUSED')
            commands.git(source, 'apply', '--reverse', '--check', '--whitespace=error-all', str(patch))
            commands.git(source, 'apply', '--reverse', '--whitespace=error-all', str(patch))
            need(regular(target) == original, 'SOURCE_REFUSED')
            source_matches(commands, source, producer_shutdown_patch.BASE_SHA,
                           producer_shutdown_patch.BASE_TREE, producer_shutdown_patch.COMPILED_TREE)
            evidence.update(phase='restored', original_restored=True)
    try:
        policy.validate(evidence, required=True)
    except policy.Refused:
        raise Failure('NODE_REGRESSIONS_REFUSED') from None


def make_assets(commands, repo, source, assets, report):
    """Observe the original helper without changing its bytes or timeout."""
    index = len(commands.originals)
    try:
        commands.run(['node', str(repo / 'tools/devnet/lab/make-assets.js'),
            str(source / 'docker/devnet'), str(assets), '--progress'], cwd=repo, timeout=20)
    finally:
        progress = lab_asset_progress.project(None)
        if len(commands.originals) == index + 1:
            try:
                progress = lab_asset_progress.project(bytes(commands.originals[index].drains[1].data))
            except Exception:
                pass
        report['asset_generation'] = progress
    need(progress['script_complete'], 'CONFIG_REFUSED')


def prepare_producer_patch(commands, repo, source, report):
    """Reproduce the actual closed-worker crash before changing its source."""
    policy = producer_shutdown_patch
    evidence = report["producer_task_patch"] = policy.pending()
    patch = repo / "tool/ci/node_fixtures/closed_producer_task.patch"
    fixture = repo / "tool/ci/node_fixtures/closed_producer_task_test.go"
    manager = source / "pillar/manager.go"
    destination = source / policy.TEST_PATH
    directories(manager.parent)
    need(digest(regular(patch)) == policy.PATCH_SHA256
         and digest(regular(fixture)) == policy.FIXTURE_SHA256
         and digest(regular(manager)) == policy.ORIGINAL_MANAGER_SHA256
         and not destination.exists() and not destination.is_symlink(), "SOURCE_REFUSED")
    need(commands.run(["gofmt", "-d", str(fixture)], cwd=source) == b"", "SOURCE_REFUSED")
    with destination.open("xb") as stream:
        stream.write(regular(fixture))
    need(digest(regular(destination)) == policy.FIXTURE_SHA256, "SOURCE_REFUSED")
    argv = ["go", "test", "-json", "-mod=readonly", "-count=1", "-run",
            "^" + policy.TEST_NAME + "$", "-timeout", "30s", "./pillar"]
    evidence["phase"] = "unpatched_test"
    count = len(commands.originals)
    try:
        commands.run(argv, cwd=source, timeout=600)
    except Failure as error:
        need(error.code == "COMMAND_FAILED" and len(commands.originals) == count + 1,
             "NODE_REGRESSIONS_REFUSED")
        original = commands.originals[-1]
        receipt = original.receipt
        need(type(receipt) is dict and receipt["exit_code"] == 1
             and receipt["output_complete"] is True and receipt["forced"] is False,
             "NODE_REGRESSIONS_REFUSED")
        try:
            policy.result(bytes(original.drains[0].data), failing=True)
        except policy.Refused:
            raise Failure("NODE_REGRESSIONS_REFUSED") from None
        receipt["expected_failure"] = "CLOSED_PRODUCER_NIL_TASK"
        evidence.update(unpatched_exit=1, unpatched_expected_panic=True)
    else:
        raise Failure("NODE_REGRESSIONS_REFUSED")
    evidence["phase"] = "apply"
    commands.git(source, "add", "--", policy.TEST_PATH)
    commands.git(source, "apply", "--index", "--whitespace=error-all", str(patch))
    need(digest(regular(manager)) == policy.PATCHED_MANAGER_SHA256
         and digest(regular(destination)) == policy.FIXTURE_SHA256, "SOURCE_REFUSED")
    source_matches(commands, source, policy.BASE_SHA, policy.BASE_TREE, policy.COMPILED_TREE)
    evidence.update(phase="patched_test", compiled_tree=policy.COMPILED_TREE)
    need(commands.run(["gofmt", "-d", str(manager), str(destination)], cwd=source) == b"", "SOURCE_REFUSED")
    raw = commands.run(argv, cwd=source, timeout=180)
    try:
        policy.result(raw, failing=False)
    except policy.Refused:
        raise Failure("NODE_REGRESSIONS_REFUSED") from None
    evidence.update(phase="verified", patched_exit=0, patched_test_passed=True)
    policy.validate(evidence, required=True)
    source_matches(commands, source, policy.BASE_SHA, policy.BASE_TREE, policy.COMPILED_TREE)
    return policy.COMPILED_TREE


def failure_code(error):
    return (error.code if isinstance(error, (Failure, wire_policy.Refused))
            and error.code in CODES else "INTERNAL_ERROR")


def node_diagnostics(raw):
    """Finite node failure categories; never include log text or paths."""
    text = raw.decode("utf-8", "replace")
    patterns = (
        ("NODE_CLI_REFUSED", r"flag provided but not defined|Incorrect Usage"),
        ("NODE_STORAGE_REFUSED", r"permission denied|access is denied|operation not permitted"),
        ("NODE_PANIC", r"panic:|fatal error:"),
        ("NODE_KEYSTORE_REFUSED", r"failed to start wallet|could not decrypt|invalid password|(?:failed|cannot|unable).*key file|key file.*not found"),
        ("NODE_GENESIS_REFUSED", r"genesis.*(?:invalid|error)|failed to.*genesis"),
        ("NODE_PORT_CONFLICT", r"address already in use|Only one usage of each socket"),
        ("NODE_STARTUP_FAILED", r"failed to\s+(?!stop\b)[^\r\n]*(?:node|zenon)|Fatal:"),
        ("NODE_SIGNAL_RECEIVED", r"Got interrupt|Got signal|Shutting down"),
        ("NODE_STOP_REQUESTED", r"Stopping znnd "),
        ("NODE_P2P_STOP_REQUESTED", r"stopping p2p server"),
        ("NODE_HTTP_STOPPED", r"HTTP server stopped"),
        ("NODE_DATA_LOCK_RELEASE_REQUESTED", r"releasing dataDir lock"),
        ("NODE_STOP_FAILED", r"failed to stop (?:node|wallet|zenon)"),
    )
    return [code for code, pattern in patterns if re.search(pattern, text, re.IGNORECASE)]


def static_linux_binary(raw):
    """Refuse ELF interpreters or dynamic sections before using FROM scratch."""
    need(type(raw) is bytes and len(raw) >= 64
         and raw[:7] == b"\x7fELF\x02\x01\x01", "SOURCE_REFUSED")
    need(struct.unpack_from("<HHI", raw, 16) == (2, 62, 1), "SOURCE_REFUSED")
    offset = struct.unpack_from("<Q", raw, 32)[0]
    size, count = struct.unpack_from("<HH", raw, 54)
    need(offset >= 64 and size == 56 and 1 <= count <= 128
         and offset + size * count <= len(raw), "SOURCE_REFUSED")
    kinds = {struct.unpack_from("<I", raw, offset + size * i)[0]
             for i in range(count)}
    need(1 in kinds and not kinds.intersection((2, 3)), "SOURCE_REFUSED")
    return True


def compiler_diagnostics(raw):
    """Project known compiler failures to codes, never paths or raw output."""
    text = raw.decode("utf-8", "replace")
    patterns = (
        ("GO_VERSION_REQUIRED", r"requires go >=|requires Go [0-9]"),
        ("BUILD_TAGS_REQUIRED", r"build constraints exclude all Go files"),
        ("LOCKED_MODULE_CHANGED", r"updates to go\.mod needed"),
        ("VCS_STATUS_REFUSED", r"error obtaining VCS status|detected dubious ownership"),
        ("DEPENDENCY_TLS_REFUSED", r"x509:|TLS handshake timeout"),
        ("DEPENDENCY_NETWORK_FAILED", r"dial tcp|network is unreachable|no such host"),
        ("DEPENDENCY_MISSING", r"no required module provides package|cannot find module"),
        ("C_TOOLCHAIN_FAILED", r"C compiler .* not found|gcc: error:|exec: .gcc."),
    )
    found = [dict(code=code) for code, pattern in patterns if re.search(pattern, text)]
    for symbol in re.findall(r"invalid reference to ([A-Za-z_][A-Za-z0-9_./]{0,95})(?:\s|$)", text)[:4]:
        found.append(dict(code="GO_LINKNAME_REFUSED", symbol=symbol))
    for symbol in re.findall(r"undefined: ([A-Za-z_][A-Za-z0-9_.]{0,95})(?:\s|$)", text)[:4]:
        found.append(dict(code="COMPILER_UNDEFINED_SYMBOL", symbol=symbol))
    return found[:12] or [dict(code="UNCLASSIFIED_BUILD_FAILURE")]


def relocated_keyfile(raw, filename, node_path):
    """Move only the public fixture's embedded deployment path."""
    try:
        value = json.loads(raw)
    except (ValueError, UnicodeError):
        raise Failure("CONFIG_REFUSED") from None
    need(type(filename) is str and re.fullmatch(r"z1[a-z0-9]{30,64}", filename)
         and type(node_path) is str and 0 < len(node_path) <= 4096
         and "\0" not in node_path and node_path.endswith(("/" + filename, "\\" + filename)),
         "CONFIG_REFUSED")
    need(type(value) is dict and set(value) == {"Path", "baseAddress", "crypto", "version", "timestamp"}
         and value["Path"] == "/root/.znn/wallet/" + filename
         and type(value["baseAddress"]) is str
         and re.fullmatch(r"z1[a-z0-9]{30,64}", value["baseAddress"])
         and type(value["version"]) is int
         and value["version"] == 1 and type(value["timestamp"]) is int
         and type(value["crypto"]) is dict, "CONFIG_REFUSED")
    crypto = value["crypto"]
    need(crypto.get("cipherName") == "aes-256-gcm" and crypto.get("kdf") == "argon2.IDKey"
         and all(type(crypto.get(key)) is str for key in ("cipherData", "nonce"))
         and type(crypto.get("argon2Params")) is dict, "CONFIG_REFUSED")
    moved = dict(value, Path=node_path)
    return (json.dumps(moved, sort_keys=True, separators=(",", ":")) + "\n").encode("ascii")


def regular(path, cap=MIB):
    info = path.lstat()
    need(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
         and info.st_size <= cap, "STORAGE_REFUSED")
    raw = path.read_bytes()
    after = path.lstat()
    need((info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)
         == (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
         and len(raw) == info.st_size, "STORAGE_REFUSED")
    return raw


def directories(path):
    for parent in reversed((path, *path.parents)):
        info = parent.lstat()
        need(stat.S_ISDIR(info.st_mode) and not parent.is_symlink()
             and not (getattr(info, "st_file_attributes", 0) & 0x400),
             "STORAGE_REFUSED")


def native_log_projection(data):
    """Read only the pinned node's two log files after original process exit."""
    result = dict(status="UNAVAILABLE", files=[], codes=[])
    try:
        directories(data)
        for kind, relative in (("run", ("log", "zenon.log")),
                               ("error", ("log", "error", "zenon.error.log"))):
            path = data.joinpath(*relative)
            try:
                directories(path.parent)
                raw = regular(path)
            except FileNotFoundError:
                continue
            result["files"].append(dict(kind=kind, bytes=len(raw), sha256=digest(raw)))
            result["codes"].extend(node_diagnostics(raw))
        result["codes"] = sorted(set(result["codes"]))
        result["status"] = "READ" if result["files"] else "MISSING"
    except Exception:
        # Log refusal never replaces an original shutdown result or leaks a path.
        result["status"] = "REFUSED"
    return result


def child_environment(root, parent):
    # Build tools and nodes receive no Actions token or user profile.
    allowed = {"PATH", "SystemRoot", "SYSTEMROOT", "WINDIR", "COMSPEC",
               "PATHEXT", "NUMBER_OF_PROCESSORS", "PROCESSOR_ARCHITECTURE",
               "LANG", "LC_ALL", "GOROOT", "SSL_CERT_FILE", "SSL_CERT_DIR"}
    env = {key: value for key, value in parent.items() if key in allowed}
    for name in ("home", "tmp", "go", "gocache", "gomodcache", "gotmp"):
        (root / name).mkdir(mode=0o700)
    env.update({key: str(root / "home") for key in
                ("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA")})
    env.update({key: str(root / "tmp") for key in ("TMP", "TEMP", "TMPDIR")})
    env.update(GOPATH=str(root / "go"), GOCACHE=str(root / "gocache"),
               GOMODCACHE=str(root / "gomodcache"), GOTMPDIR=str(root / "gotmp"),
               GOTOOLCHAIN="local", CGO_ENABLED="1", CC="gcc", USER="ci",
               GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    return env


def sample_storage(root):
    """A finite cooperative sample, not an OS-enforced disk quota."""
    total, count = 0, 0
    pending = [root]
    while pending:
        current = pending.pop()
        try:
            entries = os.scandir(current)
        except FileNotFoundError:
            need(current != root, "STORAGE_REFUSED")
            continue
        with entries:
            for entry in entries:
                count += 1
                need(count <= 100000, "STORAGE_REFUSED")
                try:
                    info = entry.stat(follow_symlinks=False)
                except FileNotFoundError:
                    # Go replaces its own temporary cache entries during a build.
                    continue
                need(not entry.is_symlink()
                     and not (getattr(info, "st_file_attributes", 0) & 0x400),
                     "STORAGE_REFUSED")
                if stat.S_ISDIR(info.st_mode):
                    pending.append(Path(entry.path))
                else:
                    need(stat.S_ISREG(info.st_mode), "STORAGE_REFUSED")
                    total += info.st_size
                    need(total <= MAX_WORK, "STORAGE_REFUSED")
    need(shutil.disk_usage(root).free >= FIXTURE_MIN_FREE, "STORAGE_REFUSED")
    return total


class Original:
    """Retain the original handle and bounded drains through terminal exit."""

    def __init__(self, argv, *, cwd, env, cap=MIB):
        options = (dict(creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)
                   if sys.platform == "win32" else dict(start_new_session=True))
        self.process = subprocess.Popen(argv, cwd=cwd, env=env, shell=False,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            **options)
        self.drains = [OutputDrain(pipe, cap, retain=True) for pipe in
                       (self.process.stdout, self.process.stderr)]
        self.forced = False
        self.receipt = None

    def healthy(self):
        need(not any(d.overflow.is_set() or d.error is not None
                     for d in self.drains), "OUTPUT_REFUSED")

    def finish(self, *, success=True):
        need(self.receipt is None, "STOP_UNKNOWN")
        code = self.process.poll()
        need(type(code) is int, "STOP_UNKNOWN")
        complete = all([d.finish(3) for d in self.drains])
        self.receipt = dict(exit_code=code, output_complete=complete,
            forced=self.forced, stop_code=getattr(self, "stop_code", None),
            stop_os_error=getattr(self, "stop_os_error", None),
            streams={key: dict(bytes=d.count,
                retained_bytes=len(d.data), sha256=digest(bytes(d.data)),
                overflow=d.overflow.is_set()) for key, d in zip(
                    ("stdout", "stderr"), self.drains)})
        if getattr(self, "stack_debug", False):
            self.receipt["stack_probe"] = getattr(self, "stack_probe", None)
            self.receipt["stack_role"] = getattr(self, "stack_role", None)
        need(complete and all(not d.overflow.is_set() and d.error is None
                              for d in self.drains), "OUTPUT_REFUSED")
        if success:
            need(code == 0 and not self.forced, "COMMAND_FAILED")
        return bytes(self.drains[0].data)

    def request_stop(self):
        if self.receipt is not None:
            return
        if getattr(self, "stop_requested", False):
            if getattr(self, "signal_error", None) is not None:
                raise self.signal_error
            return
        self.stop_requested = True
        if self.process.poll() is None:
            try:
                self.process.send_signal(signal.CTRL_BREAK_EVENT if sys.platform == "win32"
                                         else signal.SIGINT)
            except OSError as error:
                self.signal_error = error
                self.stop_code = "SIGNAL_OS_ERROR"
                self.stop_os_error = getattr(error, "winerror", getattr(error, "errno", None))
                raise

    def stop(self):
        if self.receipt is not None:
            return
        try:
            self.request_stop()
            if self.process.poll() is None:
                self.process.wait(timeout=30)
        except (OSError, subprocess.TimeoutExpired) as error:
            if isinstance(error, subprocess.TimeoutExpired) and getattr(self, "stack_debug", False):
                try:
                    self.stack_probe = native_stack_probe.capture(self)
                except Exception:
                    self.stack_probe = dict(status="UNAVAILABLE", bytes=None, sha256=None, frames=[])
            if getattr(self, "stop_code", None) is None:
                self.stop_code = "SIGNAL_OS_ERROR" if isinstance(error, OSError) else "WAIT_TIMEOUT"
                number = getattr(error, "winerror", getattr(error, "errno", None))
                self.stop_os_error = number if type(number) is int else None
            self.forced = True
            self.process.kill()
            self.process.wait(timeout=10)
        self.finish()


class Commands:
    def __init__(self, root, env):
        self.root, self.env, self.originals = root, env, []

    def run(self, argv, *, cwd, timeout=20, cap=MIB):
        need(len(self.originals) < 1024, "COMMAND_FAILED")
        original = Original(argv, cwd=cwd, env=self.env, cap=cap)
        self.originals.append(original)
        end, next_sample = time.monotonic() + timeout, 0.0
        try:
            while original.process.poll() is None:
                original.healthy()
                now = time.monotonic()
                need(now < end, "COMMAND_TIMEOUT")
                if now >= next_sample:
                    sample_storage(self.root)
                    next_sample = now + 2
                time.sleep(0.2)
            return original.finish()
        except BaseException:
            if original.process.poll() is None:
                original.forced = True
                original.process.kill()
                original.process.wait(timeout=10)
            if original.receipt is None:
                original.finish(success=False)
            if argv[:2] == ["go", "build"]:
                original.receipt["compiler_diagnostics"] = compiler_diagnostics(
                    bytes(original.drains[1].data))
            raise

    def git(self, path, *args):
        return self.run(["git", "--no-pager", "-c", "core.fsmonitor=false",
            "-c", "core.hooksPath=" + os.devnull, "-c", "core.pager=cat",
            "-C", str(path), *args], cwd=path).decode("ascii").strip()


def configuration(value, role, data, backend):
    """Move only deployment paths, listen addresses and bootstrap ports."""
    need(role in ROLES and backend in ("docker", "native"), "CONFIG_REFUSED")
    result = json.loads(json.dumps(value))
    need(type(result.get("Net")) is dict and type(result.get("RPC")) is dict,
         "CONFIG_REFUSED")
    net, rpc = result["Net"], result["RPC"]
    for field in ("BootstrapPeers", "Seeders"):
        peers = net.get(field)
        need(type(peers) is list and peers, "CONFIG_REFUSED")
        moved = []
        for peer in peers:
            need(type(peer) is str, "CONFIG_REFUSED")
            pattern = (r"/ip4/172\.30\.0\.(10|11|12|13|14)/tcp/35995/p2p/[A-Za-z0-9]{32,128}"
                       if field == "BootstrapPeers" else
                       r"enode://[a-f0-9]{128}@172\.30\.0\.(10|11|12|13|14):35995")
            need(re.fullmatch(pattern, peer) is not None, "CONFIG_REFUSED")
            expected = [other for other in ROLES if
                        ("172.30.0." + str(OCTETS[other])) in peer]
            need(len(expected) == 1 and peer.count("172.30.0.") == 1,
                 "CONFIG_REFUSED")
            other = expected[0]
            old = "172.30.0." + str(OCTETS[other])
            if backend == "docker":
                peer = peer.replace(old, "172.37.0." + str(OCTETS[other]))
            else:
                peer = peer.replace(old + "/tcp/35995", "127.0.0.1/tcp/" + str(NATIVE_PORTS[other]))
                peer = peer.replace(old + ":35995", "127.0.0.1:" + str(NATIVE_PORTS[other]))
                need("172.30.0." not in peer and "127.0.0.1" in peer,
                     "CONFIG_REFUSED")
            moved.append(peer)
        net[field] = moved
    net["ListenHost"] = "0.0.0.0" if backend == "docker" else "127.0.0.1"
    net["ListenPort"] = 35995 if backend == "docker" else NATIVE_PORTS[role]
    base = "/data" if backend == "docker" else str(data)
    result.update(DataPath=base,
        GenesisFile=(base + "/genesis.json" if backend == "docker"
                     else str(data / "genesis.json")),
        WalletPath=(base + "/wallet" if backend == "docker"
                    else str(data / "wallet")))
    rpc_host = ("0.0.0.0" if backend == "docker" else "127.0.0.1") if role == "rpc" else ""
    rpc.update(EnableHTTP=role == "rpc", EnableWS=role == "rpc",
        HTTPHost=rpc_host, WSHost=rpc_host,
        HTTPPort=35997 if backend == "docker" else 45997,
        WSPort=35998 if backend == "docker" else 45998)
    return result


def preflight_ports(backend, *, stack_debug=False):
    ports = [45997, 45998] + (list(NATIVE_PORTS.values()) if backend == "native" else [])
    if backend == "native" and stack_debug:
        ports.extend(native_stack_probe.PORTS.values())
    sockets = []
    try:
        for port in ports:
            original = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sockets.append(original)
            if sys.platform == "win32":
                original.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            original.bind(("127.0.0.1", port))
    except OSError:
        raise Failure("PORT_CONFLICT") from None
    finally:
        for original in sockets:
            original.close()


class Native:
    def __init__(self, commands, binary, configs, *, stack_debug=False):
        self.commands, self.binary, self.configs = commands, binary, configs
        self.originals = []
        self.stack_debug = stack_debug
        self.stop_attempted = False
        self.stop_order = []

    def start(self):
        for role in ROLES:
            data = self.configs[role]
            argv = [str(self.binary), "--data", str(data),
                "--config", str(data / "config.json"), "--genesis", str(data / "genesis.json"),
                "--wallet", str(data / "wallet")]
            if self.stack_debug:
                argv += ["--pprof", "--pprof.addr", "127.0.0.1", "--pprof.port", str(native_stack_probe.PORTS[role])]
            original = Original(argv, cwd=data, env=self.commands.env)
            original.stack_debug = self.stack_debug
            if self.stack_debug:
                original.stack_role, original.stack_port = role, native_stack_probe.PORTS[role]
            self.originals.append(original)

    def healthy(self):
        need(len(self.originals) == 5, "NODE_EXITED")
        for original in self.originals:
            original.healthy()
            need(original.process.poll() is None, "NODE_EXITED")

    def stop(self):
        need(not self.stop_attempted, "STOP_UNKNOWN")
        self.stop_attempted = True
        failed = False
        # The upstream server joins its peer workers. A live peer can keep a
        # joining member pending, so request the complete set before waiting.
        for index in range(len(self.originals)):
            original = self.originals[index]
            if index < len(ROLES):
                self.stop_order.append(ROLES[index])
            try:
                original.request_stop()
            except Exception:
                failed = True
        for index, original in enumerate(self.originals):
            try:
                original.stop()
            except Exception:
                failed = True
            finally:
                try:
                    if type(original.receipt) is dict:
                        raw = b"\n".join(bytes(d.data) for d in original.drains)
                        codes = node_diagnostics(raw)
                        panic = node_panic_projection.project(raw)
                        if panic is not None:
                            original.receipt["node_panic"] = panic
                        if (index < len(ROLES) and ROLES[index] in self.configs
                                and type(original.process.poll()) is int):
                            logs = native_log_projection(self.configs[ROLES[index]])
                            original.receipt["private_log_projection"] = logs
                            codes.extend(logs["codes"])
                        original.receipt["node_diagnostics"] = sorted(set(codes))
                except Exception:
                    failed = True
        need(not failed and len(self.originals) == 5
             and all(item.receipt is not None and item.receipt["exit_code"] == 0
                     and item.receipt["output_complete"] is True
                     and item.receipt["forced"] is False for item in self.originals),
             "STOP_UNKNOWN")


def checkpoint_closed(runtime, wallet):
    """A saved exit receipt cannot replace the current original process handles."""
    try:
        return (isinstance(runtime, Native) and runtime.stop_attempted is True
            and runtime.stop_order == list(ROLES) and set(runtime.configs) == set(ROLES)
            and len(runtime.originals) == len(ROLES) and wallet.closed() is True
            and wallet.quiescent() is True
            and all(type(item.process.poll()) is int and item.process.poll() == 0
                and type(item.receipt) is dict
                and type(item.receipt.get('exit_code')) is int and item.receipt['exit_code'] == 0
                and item.receipt.get('output_complete') is True
                and item.receipt.get('forced') is False for item in runtime.originals))
    except (Exception, KeyboardInterrupt):
        return False


class Docker:
    def __init__(self, commands, binary, configs, nonce):
        self.commands, self.binary, self.configs = commands, binary, configs
        self.name, self.owner = "syrius-ci321-" + nonce, nonce
        self.image = self.network = None
        self.created, self.started = [], []
        self.states, self.diagnostics = [], []
        self.relay = None
        self.direct_rpc_ready = False
        self.stop_attempted = False
        self.shutdown = dict(mode="single_verified_stop_command", roles=[],
                             exit_code=None, output_complete=None, forced=None)

    def record_state(self, item, phase):
        state = item.get("State", {})
        need(item.get("Id") in self.created
             and type(state.get("Running")) is bool and type(state.get("ExitCode")) is int
             and type(state.get("OOMKilled")) is bool and len(self.states) < 512,
             "RESOURCE_CHANGED")
        self.states.append(dict(phase=phase, role=ROLES[self.created.index(item["Id"])],
            running=state["Running"],
            exit_code=state["ExitCode"], oom_killed=state["OOMKilled"]))

    def call(self, *args, timeout=20):
        return self.commands.run(["docker", *args], cwd=self.binary.parent,
                                 timeout=timeout)

    def inspect(self, kind, identifier):
        value = json.loads(self.call(kind, "inspect", identifier))
        need(type(value) is list and len(value) == 1, "DOCKER_REFUSED")
        return value[0]

    def start(self):
        info = json.loads(self.call("info", "--format", "{{json .}}"))
        need(info.get("OSType") == "linux" and info.get("Architecture") in
             ("x86_64", "amd64"), "DOCKER_REFUSED")
        context = self.binary.parent / "image"
        context.mkdir(mode=0o700)
        image_binary = context / "znnd"
        shutil.copyfile(self.binary, image_binary)
        image_binary.chmod(0o555)
        need(digest(regular(image_binary, 128 * MIB)) == digest(regular(self.binary, 128 * MIB))
             and stat.S_IMODE(image_binary.stat().st_mode) == 0o555, "SOURCE_REFUSED")
        (context / "Dockerfile").write_text('FROM scratch\nCOPY znnd /znnd\nENTRYPOINT ["/znnd"]\n')
        tag = self.name + ":source"
        self.call("build", "--network=none", "--pull=false", "--label",
                  "org.zenon.ci321.owner=" + self.owner, "-t", tag, str(context), timeout=120)
        image = self.inspect("image", tag)
        need(re.fullmatch("sha256:[a-f0-9]{64}", image.get("Id", ""))
             and image["Config"]["Labels"].get("org.zenon.ci321.owner") == self.owner,
             "DOCKER_REFUSED")
        self.image = image["Id"]
        self.network = self.call("network", "create", "--internal", "--subnet", "172.37.0.0/24",
            "--gateway", "172.37.0.1",
            "--label", "org.zenon.ci321.owner=" + self.owner, self.name).decode().strip()
        need(re.fullmatch("[a-f0-9]{64}", self.network), "DOCKER_REFUSED")
        for role in ROLES:
            args = ["create", "--name", self.name + "-" + role, "--label",
                "org.zenon.ci321.owner=" + self.owner, "--network", self.network,
                "--ip", "172.37.0." + str(OCTETS[role]), "--restart=no", "--read-only",
                "--cap-drop=ALL", "--security-opt=no-new-privileges", "--pids-limit=128",
                "--log-opt=max-size=1m", "--log-opt=max-file=2", "--tmpfs", "/tmp:size=32m",
                "--user", str(os.getuid()) + ":" + str(os.getgid()), "--env", "HOME=/data",
                "--env", "USER=ci", "--mount", "type=bind,src=" + str(self.configs[role]) + ",dst=/data"]
            args += [self.image, "--data", "/data", "--config", "/data/config.json",
                     "--genesis", "/data/genesis.json", "--wallet", "/data/wallet"]
            identifier = self.call(*args).decode().strip()
            need(re.fullmatch("[a-f0-9]{64}", identifier), "DOCKER_REFUSED")
            self.created.append(identifier)
            self.call("start", identifier)
            self.started.append(identifier)
        self.healthy()
        # Internal bridges remain isolated. Reach only the exact RPC member
        # from the host, then expose two original loopback byte relays.
        end = time.monotonic() + 90
        while True:
            try:
                for _, port in RELAY_PAIRS:
                    with socket.create_connection((RELAY_TARGET, port), timeout=1):
                        pass
                break
            except OSError:
                need(time.monotonic() < end, "RPC_UNAVAILABLE")
                time.sleep(2)
        self.direct_rpc_ready = True
        self.healthy()
        self.relay = Relay()
        self.relay.start()

    def healthy(self):
        need(len(self.created) == len(self.started) == 5, "RESOURCE_CHANGED")
        network = self.inspect("network", self.network)
        need(network["Id"] == self.network and network["Internal"] is True
             and set(network["Containers"]) == set(self.created), "RESOURCE_CHANGED")
        for identifier in self.started:
            item = self.inspect("container", identifier)
            need(item["Id"] == identifier and item["Image"] == self.image
                 and item["Config"]["Labels"].get("org.zenon.ci321.owner") == self.owner,
                 "RESOURCE_CHANGED")
            self.record_state(item, "health")
            need(item["State"]["Running"] is True and item["RestartCount"] == 0,
                 "RESOURCE_CHANGED")

    def stop(self):
        need(not self.stop_attempted, "STOP_UNKNOWN")
        self.stop_attempted = True
        failed = False
        if self.relay is not None:
            try:
                self.relay.stop()
            except Exception:
                failed = True
        verified = []
        for identifier in reversed(self.created):
            try:
                item = self.inspect("container", identifier)
                need(item["Id"] == identifier and item["Image"] == self.image
                     and item["Config"]["Labels"].get("org.zenon.ci321.owner") == self.owner,
                     "RESOURCE_CHANGED")
                self.record_state(item, "before_stop")
                # The exact created resource was just verified; logs remain
                # private and only finite failure codes enter the manifest.
                try:
                    output = self.call("logs", "--tail", "80", identifier)
                    stderr = bytes(self.commands.originals[-1].drains[1].data)
                    self.diagnostics.extend(node_diagnostics(output + b"\n" + stderr))
                except Exception:
                    pass
                verified.append(identifier)
            except Exception:
                failed = True
        if verified:
            self.shutdown["roles"] = [ROLES[self.created.index(identifier)] for identifier in verified]
            count = len(self.commands.originals)
            try:
                # The first sequential RPC stop timed out before its peers
                # received a request. Submit the verified set in one command.
                self.call("stop", "--time", "20", *verified, timeout=30)
            except Exception:
                failed = True
            finally:
                if len(self.commands.originals) == count + 1:
                    receipt = self.commands.originals[-1].receipt
                    if type(receipt) is dict:
                        self.shutdown.update({key: receipt.get(key) for key in
                                              ("exit_code", "output_complete", "forced")})
        for identifier in verified:
            try:
                item = self.inspect("container", identifier)
                need(item["Id"] == identifier and item["Image"] == self.image
                     and item["Config"]["Labels"].get("org.zenon.ci321.owner") == self.owner,
                     "RESOURCE_CHANGED")
                self.record_state(item, "after_stop")
                state = item["State"]
                need(state["Running"] is False and state["ExitCode"] == 0
                     and state.get("OOMKilled") is False, "STOP_UNKNOWN")
            except Exception:
                failed = True
        need(not failed and len(self.started) == len(self.created) == len(verified) == 5
             and self.shutdown["exit_code"] == 0 and self.shutdown["output_complete"] is True
             and self.shutdown["forced"] is False, "STOP_UNKNOWN")


def observe(runtime, root, report=None, *, measure=None):
    def phase(name):
        if report is not None:
            report["runtime_phase"] = name

    phase("rpc_readiness")
    end = time.monotonic() + 90
    while True:
        runtime.healthy()
        if measure is not None:
            measure()
        try:
            with socket.create_connection(("127.0.0.1", 45997), timeout=1):
                break
        except OSError:
            need(time.monotonic() < end, "RPC_UNAVAILABLE")
            time.sleep(2)
    http_wire, ws_wire = make_transports()
    limits = wire_policy.Limits()
    deadline = wire_policy._Deadline(time.monotonic, time.monotonic() + 230)
    http = wire_policy.HttpRpc(http_wire, limits, deadline, secrets.token_bytes)
    ws = wire_policy.WsRpc(ws_wire, limits, deadline, secrets.token_bytes)
    original_failed = False
    try:
        phase("ws_handshake")
        ws.connect()
        phase("http_genesis")
        genesis = http.call("ledger.getMomentumsByHeight", [1, 1])
        need(type(genesis) is dict and type(genesis.get("list")) is list
             and len(genesis["list"]) == 1, "GENESIS_MISMATCH")
        first_genesis = wire_policy.Momentum.parse(genesis["list"][0])
        need(first_genesis.height == 1, "GENESIS_MISMATCH")
        phase("ws_genesis")
        need(wire_policy.Momentum.parse(ws.call("ledger.getMomentumByHash", [first_genesis.hash]))
             == first_genesis, "GENESIS_MISMATCH")
        phase("first_frontier")
        first = previous = wire_policy.Momentum.parse(http.call("ledger.getFrontierMomentum", []))
        phase("advancing_frontier")
        samples = 0
        for _ in range(36):
            runtime.healthy()
            if measure is None:
                sample_storage(root)
            else:
                measure()
            current = wire_policy.Momentum.parse(http.call("ledger.getFrontierMomentum", []))
            current.follows(previous)
            peer = wire_policy.Momentum.parse(ws.call("ledger.getMomentumByHash", [current.hash]))
            need(peer == current, "RPC_REFUSED")
            samples += 1
            if current.height > first.height and current.timestamp > first.timestamp:
                return dict(chain=321, genesis_hash=first_genesis.hash,
                    first_height=first.height, last_height=current.height,
                    first_timestamp=first.timestamp, last_timestamp=current.timestamp,
                    samples=samples, cross_transport_hash_equal=True)
            previous = current
            time.sleep(5)
        raise Failure("PRODUCTION_UNPROVEN")
    except BaseException:
        original_failed = True
        raise
    finally:
        failed = False
        for original in (ws, http):
            try:
                original.close()
            except Exception:
                failed = True
        if failed:
            if report is not None:
                report["error_codes"].append("CLOSE_UNKNOWN")
            if not original_failed:
                raise Failure("CLOSE_UNKNOWN")


def run(backend):
    repo = Path(__file__).absolute().parents[2]
    parent = os.environ
    wallet_tour = require_environment(backend, parent)
    inspection = wallet_inspection_requested(backend, parent)
    stack_debug = backend == "native" and parent.get("SYRIUS_NATIVE_STACK_DIAGNOSTIC") == "true"
    node_source = parent.get("SYRIUS_LAB_NODE_SOURCE", "original")
    node_sha, node_tree = selected_node_source(node_source)
    directories(repo)
    temp = Path(parent["RUNNER_TEMP"])
    directories(temp)
    need(shutil.disk_usage(temp).free >= FIXTURE_MIN_FREE + MAX_WORK, "STORAGE_REFUSED")
    nonce = secrets.token_hex(12)
    root = temp / ("syrius-chain321-" + nonce)
    root.mkdir(mode=0o700)
    env = child_environment(root, parent)
    commands = Commands(root, env)
    report = dict(schema=1, scope="hosted_chain321_lab", backend=backend,
        application_sha=parent["GITHUB_SHA"], node_sha=node_sha, node_source=node_source,
        run_id=parent.get("GITHUB_RUN_ID"), attempt=parent.get("GITHUB_RUN_ATTEMPT"),
        success=False, error_codes=[], checks=dict.fromkeys(
            ("source", "build", "assets", "preflight", "started", "production", "stopped", "inputs_unchanged"), False),
        wallet_qualified=False, seed_admitted=False, visual_matches=0,
        wallet_tour_requested=wallet_tour, wallet_tour=None,
        native_stack_diagnostic=stack_debug,
        native_stack_scope="all_originals" if stack_debug else "disabled",
        min_free_bytes=FIXTURE_MIN_FREE, work_cap_bytes=MAX_WORK,
        storage_limit_scope="isolated_hosted_regression_fixture_cooperative_samples",
        cleanup="runner_lifecycle_not_qualified")
    if inspection:
        report.update(wallet_inspection_requested=True, wallet_inspection=None)
    runtime = None
    closed_wallets = []
    reopen_anchor = None
    pointer_diagnostic = None
    pointer_binding_completed = False
    reopen_diagnostic = None
    reopen_completed = False
    try:
        source = repo / ".harness/ci-node-source"
        directories(source)
        need(commands.git(repo, "rev-parse", "HEAD") == parent["GITHUB_SHA"]
             and not commands.git(repo, "status", "--porcelain=v1", "--untracked-files=all")
             and commands.git(source, "rev-parse", "HEAD") == node_sha
             and not commands.git(source, "status", "--porcelain=v1", "--untracked-files=all"), "SOURCE_REFUSED")
        report["application_tree"] = commands.git(repo, "rev-parse", "HEAD^{tree}")
        report["node_tree"] = commands.git(source, "rev-parse", "HEAD^{tree}")
        need(report["node_tree"] == node_tree, "SOURCE_REFUSED")
        report["checks"]["source"] = True
        version = commands.run(["go", "version"], cwd=source).decode("ascii").strip()
        need(version == "go version go" + GO_VERSION + (" windows/amd64" if backend == "native" else " linux/amd64"),
             "SOURCE_REFUSED")
        report["compiler"] = version
        target = commands.run(["gcc", "-dumpmachine"], cwd=source).decode("ascii").strip()
        c_version = commands.run(["gcc", "-dumpfullversion"], cwd=source).decode("ascii").strip()
        need(target == ("x86_64-w64-mingw32" if backend == "native" else "x86_64-linux-gnu")
             and re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", c_version), "SOURCE_REFUSED")
        report["c_compiler"] = dict(target=target, version=c_version, cgo_enabled=True)
        compiled_tree = (prepare_producer_patch(commands, repo, source, report)
                         if node_source == "lab-fix" else node_tree)
        report["compiled_node_tree"] = compiled_tree
        binary = root / ("znnd.exe" if backend == "native" else "znnd")
        commands.run(["go", "build", "-trimpath", "-buildvcs=false", "-mod=readonly",
                      "-tags=netgo,osusergo", "-ldflags=-linkmode=external -extldflags=-static",
                      "-o", str(binary), "./cmd/znnd"],
                     cwd=source, timeout=1200)
        binary_bytes = regular(binary, 128 * MIB)
        if backend == "docker":
            report["static_linux_binary_verified"] = static_linux_binary(binary_bytes)
        report["binary_sha256"] = digest(binary_bytes)
        report["checks"]["build"] = True
        if node_sha == UPSTREAM_NODE_SHA:
            if wallet_tour or inspection:
                run_wallet_shutdown_tests(commands, repo, source, report)
            else:
                run_shutdown_tests(commands, source, report)
            source_matches(commands, source, node_sha, node_tree, compiled_tree)
        assets = root / "assets"
        make_assets(commands, repo, source, assets, report)
        genesis = regular(assets / "genesis.json")
        need(json.loads(genesis)["ChainIdentifier"] == 321, "CONFIG_REFUSED")
        report["genesis_sha256"] = digest(genesis)
        configs, pins, keyfile_pins = {}, {}, {}
        report["keyfile_relocations"] = []
        for role in ROLES:
            data = root / role
            data.mkdir(mode=0o700)
            configs[role] = data
            value = configuration(json.loads(regular(source / "docker/devnet" / role / "config.json")), role, data, backend)
            (data / "config.json").write_text(json.dumps(value, indent=2) + "\n")
            (data / "genesis.json").write_bytes(genesis)
            for name in ("network-private-key", "wallet"):
                offered = assets / role / name
                if offered.is_dir():
                    (data / name).mkdir(mode=0o700)
                    for item in offered.iterdir():
                        original_keyfile = regular(item)
                        node_path = ("/data/wallet/" + item.name if backend == "docker"
                                     else str(data / name / item.name))
                        moved_keyfile = relocated_keyfile(original_keyfile, item.name, node_path)
                        destination = data / name / item.name
                        destination.write_bytes(moved_keyfile)
                        keyfile_pins[destination] = digest(moved_keyfile)
                        original_fields = json.loads(original_keyfile)
                        moved_fields = json.loads(moved_keyfile)
                        need({key: value for key, value in original_fields.items() if key != "Path"}
                             == {key: value for key, value in moved_fields.items() if key != "Path"},
                             "CONFIG_REFUSED")
                        report["keyfile_relocations"].append(dict(role=role,
                            source_sha256=digest(original_keyfile), deployed_sha256=digest(moved_keyfile),
                            non_path_fields_unchanged=True))
                elif offered.exists():
                    (data / name).write_bytes(regular(offered))
            pins[role] = digest(regular(data / "config.json"))
        report["config_sha256"] = pins
        report["checks"]["assets"] = True
        preflight_ports(backend, stack_debug=stack_debug)
        report["checks"]["preflight"] = True
        runtime = (Docker(commands, binary, configs, nonce) if backend == "docker"
                   else Native(commands, binary, configs, stack_debug=stack_debug))
        runtime.start()
        report["checks"]["started"] = True
        report["observations"] = observe(runtime, root, report)
        report["checks"]["production"] = True
        if inspection:
            from tool.ci import windows_wallet_inspection
            report['runtime_phase'] = 'wallet_inspection'
            outcome = windows_wallet_inspection.run(repo, parent, runtime, root,
                report['observations'], lambda: observe(runtime, root))
            path = repo / windows_wallet_inspection.OUTPUT / 'manifest.json'
            manifest_hash = digest(regular(path)) if path.exists() or path.is_symlink() else None
            report['wallet_inspection'] = dict(success=outcome['success'],
                phase=outcome['phase'], checks=outcome['checks'], errors=outcome['errors'],
                captured_pages=len(outcome['captures']),
                visited_pages=sum(len(t['tour']['visited']) for t in outcome['tours'].values()),
                manifest_sha256=manifest_hash)
            need(outcome['success'] and manifest_hash is not None, 'WALLET_INSPECTION_FAILED')
        if wallet_tour:
            from tool.ci import windows_wallet_tour
            report['runtime_phase'] = 'wallet_tour'
            outcome = windows_wallet_tour.run(repo, parent, runtime, root,
                report['observations'], lambda: observe(runtime, root),
                retain_closed=closed_wallets.append)
            manifest = regular(repo / '.harness/ci-wallet-tour/manifest.json')
            report['wallet_tour'] = dict(success=outcome['success'],
                phase=outcome['phase'], checks=outcome['checks'], errors=outcome['errors'],
                captured_pages=len(outcome['captures']),
                visited_pages=0 if outcome['tour'] is None else len(outcome['tour']['visited']),
                manifest_sha256=digest(manifest))
            need(outcome['success'], 'WALLET_TOUR_FAILED')
            from tool.ci import restored_wallet_run
            need(len(closed_wallets) == 1 and closed_wallets[0].closed()
                 and closed_wallets[0].quiescent(), 'CHECKPOINT_REFUSED')
            reopen_anchor = restored_wallet_run.chain_read(runtime)
        need(all(digest(regular(configs[role] / "config.json")) == pins[role]
                 and regular(configs[role] / "genesis.json") == genesis for role in ROLES)
             and all(digest(regular(path)) == expected for path, expected in keyfile_pins.items())
             and digest(regular(binary, 128 * MIB)) == report["binary_sha256"]
             and not commands.git(repo, "status", "--porcelain=v1", "--untracked-files=all"), "SOURCE_REFUSED")
        source_matches(commands, source, node_sha, node_tree, compiled_tree)
        report["checks"]["inputs_unchanged"] = True
    except (Exception, KeyboardInterrupt) as error:
        report["error_codes"].append(failure_code(error))
    finally:
        if runtime is not None:
            try:
                runtime.stop()
                report["checks"]["stopped"] = True
            except Exception:
                report["error_codes"].append("STOP_UNKNOWN")
        if isinstance(runtime, Native):
            report["node_exits"] = [item.receipt for item in runtime.originals]
            report["native_shutdown_order"] = runtime.stop_order
            report["native_shutdown_mode"] = "coordinated_requests_then_wait"
        elif isinstance(runtime, Docker):
            report["docker_image_id"] = runtime.image
            report["created_count"] = len(runtime.created)
            report["started_count"] = len(runtime.started)
            report["docker_states"] = runtime.states
            report["docker_shutdown"] = runtime.shutdown
            report["node_diagnostics"] = sorted(set(runtime.diagnostics))
            report["direct_rpc_ready"] = runtime.direct_rpc_ready
            report["loopback_relay"] = None if runtime.relay is None else runtime.relay.summary()
        if wallet_tour and all(report['checks'].values()) and not report['error_codes']:
            report['checkpoint'] = dict(schema=1, scope='closed_owned_lab_checkpoint', complete=False)
            try:
                from tool.ci import closed_lab_checkpoint as checkpoint, restored_lab_paths, closed_wallet_pointer, restored_wallet_run
                need(isinstance(runtime, Native) and len(closed_wallets) == 1,
                     'CHECKPOINT_REFUSED')
                wallet = closed_wallets[0]

                def closed():
                    return checkpoint_closed(runtime, wallet)

                need(closed(), 'CHECKPOINT_REFUSED')
                wallet.claim_checkpoint()
                source_matches(commands, source, node_sha, node_tree, compiled_tree)
                need(commands.git(repo, 'rev-parse', 'HEAD') == parent['GITHUB_SHA']
                     and not commands.git(repo, 'status', '--porcelain=v1', '--untracked-files=all'),
                     'SOURCE_REFUSED')
                roots = dict(wallet_profile=wallet.home, **runtime.configs)
                binding = dict(source_sha=report['application_sha'],
                    source_tree=report['application_tree'], node_sha=node_sha,
                    node_tree=compiled_tree, genesis_sha256=report['genesis_sha256'],
                    run_id=report['run_id'], attempt=int(report['attempt']))
                restored_home = wallet.home.parent / ('ci-wallet-' + secrets.token_hex(12))
                checkpoint_home = root / ('closed-checkpoint-' + secrets.token_hex(12))
                restored_roots, report['checkpoint'] = checkpoint.capture_restore(roots,
                    checkpoint_home, closed,
                    base_bytes=sample_storage(root) + wallet.measured_bytes(), binding=binding,
                    wallet_home=restored_home)

                def measured():
                    return (sample_storage(root) + wallet.measured_bytes()
                            + wallet.copied_home_bytes(restored_home))

                report['path_binding'] = dict(schema=1, scope='closed_node_path_binding', complete=False)
                report['path_binding'] = restored_lab_paths.bind_nodes(runtime.configs,
                    {role: restored_roots[role] for role in ROLES}, checkpoint_home, closed,
                    config_sha256=pins, keyfile_sha256=keyfile_pins, measure=measured)
                report['wallet_pointer_binding'] = dict(schema=1,
                    scope=closed_wallet_pointer.SCOPE, complete=False)
                pointer_diagnostic = closed_wallet_pointer.PointerDiagnostic()
                report['wallet_pointer_binding'] = closed_wallet_pointer.run(repo, parent,
                    wallet, restored_home, checkpoint_home, closed, measured,
                    diagnostic=pointer_diagnostic)
                pointer_binding_completed = True
                report['wallet_reopen'] = dict(schema=1,
                    scope=restored_wallet_run.SCOPE, complete=False)
                reopen_diagnostic = restored_wallet_run.ReopenDiagnostic()
                report['wallet_reopen'] = restored_wallet_run.run(repo, parent, wallet,
                    runtime, reopen_anchor, restored_roots, checkpoint_home, closed, measured,
                    diagnostic=reopen_diagnostic)
                reopen_completed = True
                source_matches(commands, source, node_sha, node_tree, compiled_tree)
                need(not commands.git(repo, 'status', '--porcelain=v1', '--untracked-files=all')
                     and measured() <= MAX_WORK,
                     'SOURCE_REFUSED')
            except (Exception, KeyboardInterrupt) as error:
                report['error_codes'].append('CHECKPOINT_REFUSED')
                report['checkpoint'] = dict(schema=1,
                    scope='closed_owned_lab_checkpoint', complete=False)
                if 'path_binding' in report:
                    report['path_binding'] = dict(schema=1,
                        scope='closed_node_path_binding', complete=False)
                if 'wallet_pointer_binding' in report:
                    report['wallet_pointer_binding'] = dict(schema=1,
                        scope='closed_wallet_pointer_binding', complete=False)
                    if pointer_diagnostic is not None and not pointer_binding_completed:
                        report['wallet_pointer_binding']['diagnostic'] = pointer_diagnostic.snapshot()
                if 'wallet_reopen' in report:
                    report['wallet_reopen'] = dict(schema=1,
                        scope='owned_restored_lab_reopen', complete=False)
                    if reopen_diagnostic is not None and not reopen_completed:
                        reopen_diagnostic.failure(error)
                        report['wallet_reopen']['diagnostic'] = reopen_diagnostic.snapshot()
        report['commands'] = [item.receipt for item in commands.originals]
        report["success"] = all(report["checks"].values()) and not report["error_codes"]
        report['wallet_tour_qualified'] = bool(wallet_tour and report['success']
            and report['wallet_tour'] is not None and report['wallet_tour']['success'])
        output = repo / ".harness/ci-chain321"
        output.mkdir(mode=0o700)
        with (output / "manifest.json").open("x", encoding="ascii") as stream:
            json.dump(report, stream, sort_keys=True, separators=(",", ":"))
            stream.write("\n")
        print(json.dumps(report, sort_keys=True))
        if wallet_tour:
            summary = dict(schema=1, scope='owned_wallet_tour_lab',
                source_sha=report['application_sha'], source_tree=report.get('application_tree'),
                run_id=report['run_id'], run_attempt=report['attempt'],
                success=report['success'], wallet_tour_qualified=report['wallet_tour_qualified'],
                wallet_qualified=False, seed_admitted=False, checks=report['checks'],
                errors=report['error_codes'], node_sha=report['node_sha'],
                compiled_node_tree=report.get('compiled_node_tree'),
                checkpoint=report.get('checkpoint'),
                path_binding=report.get('path_binding'),
                wallet_pointer_binding=report.get('wallet_pointer_binding'),
                wallet_reopen=report.get('wallet_reopen'),
                asset_generation=report.get('asset_generation'),
                upstream_client_fixture=(read_first_client_fixture.validate(
                    report.get('upstream_client_fixture'), required=report['checks']['started'])
                    if report.get('upstream_client_fixture') is not None else None),
                nodes=[dict(role=role, exit_code=original.receipt.get('exit_code'),
                    output_complete=original.receipt.get('output_complete'),
                    forced=original.receipt.get('forced'))
                    for role, original in zip(ROLES, runtime.originals)
                    if type(original.receipt) is dict] if isinstance(runtime, Native) else [])
            text = json.dumps(summary, sort_keys=True, separators=(',', ':'))
            print(text)
            from tool.ci import restored_wallet_run
            for component, frame in restored_wallet_run.notice_frames(summary):
                title = 'Windows wallet tour lab' if not component else 'Closed copy ' + component
                text = json.dumps(frame, sort_keys=True, separators=(',', ':'))
                escaped = text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
                print('::notice title=' + title + '::' + escaped)
    return 0 if report["success"] else 1


def _bind_runtime_module():
    """Keep CLI owners identical to the controller imported by copy helpers."""
    module = sys.modules.get(__name__)
    package = sys.modules.get("tool.ci")
    need(module is not None and package is not None
         and getattr(module, "Native", None) is Native
         and getattr(module, "Docker", None) is Docker, "ENVIRONMENT_REFUSED")
    canonical = "tool.ci.hosted_chain321"
    need(canonical not in sys.modules or sys.modules[canonical] is module,
         "ENVIRONMENT_REFUSED")
    previous = getattr(package, "hosted_chain321", None)
    need(previous is None or previous is module, "ENVIRONMENT_REFUSED")
    sys.modules[canonical] = module
    setattr(package, "hosted_chain321", module)
    return module


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Isolated hosted chain-321 lab")
    parser.add_argument("--backend", required=True, choices=("docker", "native"))
    parser.add_argument('--admission-only', action='store_true')
    options = parser.parse_args()
    try:
        _bind_runtime_module()
        if options.admission_only:
            requested = require_environment(options.backend, os.environ)
            print(json.dumps(dict(schema=1, scope='hosted_lab_admission',
                success=True, wallet_tour_requested=requested)))
            sys.exit(0)
        sys.exit(run(options.backend))
    except (Exception, KeyboardInterrupt) as error:
        print(json.dumps(dict(schema=1, success=False,
            error_codes=[error.code if isinstance(error, Failure) else "INTERNAL_ERROR"])))
        sys.exit(1)
