"""Read retained lab manifests in memory; never start a runtime or admit seed."""

from __future__ import annotations

import hashlib
import io
import json
import os
import re
import stat
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

from tool.ci.hosted_chain321 import (CODES, GO_FAILURE_CODES, NODE_DIAGNOSTICS, NODE_SHA, NODE_SOURCES,
                                   ROLES, SHUTDOWN_TESTS, UPSTREAM_NODE_SHA, selected_node_source)
from tool.ci import native_stack_probe, node_panic_projection, producer_shutdown_patch, read_first_client_fixture
from tool.ci import lab_asset_progress, closed_lab_checkpoint, restored_lab_paths, closed_wallet_pointer, restored_wallet_run


API = "https://api.github.com/repos/edgepillar/syrius"
MAX_ARCHIVE = 1024**2
MAX_MANIFEST = 512 * 1024
DIAGNOSTICS = frozenset((
    "GO_VERSION_REQUIRED", "BUILD_TAGS_REQUIRED", "LOCKED_MODULE_CHANGED",
    "VCS_STATUS_REFUSED", "DEPENDENCY_TLS_REFUSED", "DEPENDENCY_NETWORK_FAILED",
    "DEPENDENCY_MISSING", "C_TOOLCHAIN_FAILED", "GO_LINKNAME_REFUSED",
    "COMPILER_UNDEFINED_SYMBOL", "UNCLASSIFIED_BUILD_FAILURE",
))
CHECKS = frozenset(("source", "build", "assets", "preflight", "started",
                    "production", "stopped", "inputs_unchanged"))
PHASE = "environment"


class Refused(Exception):
    pass


def need(value):
    if not value:
        raise Refused("INSPECTION_REFUSED")


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def selected_backends(value):
    need(value in ("both", "native", "docker"))
    return ("docker", "native") if value == "both" else (value,)


def artifact_location(value):
    need(type(value) is str and len(value) <= 8192
         and all(32 < ord(char) < 127 for char in value))
    parsed = urllib.parse.urlsplit(value)
    need(parsed.scheme == "https" and parsed.hostname is not None
         and parsed.hostname.endswith((".blob.core.windows.net", ".actions.githubusercontent.com"))
         and parsed.port in (None, 443) and parsed.username is None
         and parsed.password is None and not parsed.fragment)
    return value


def request_for(url, token=None):
    if token is None:
        artifact_location(url)
        return urllib.request.Request(url, headers={"User-Agent": "syrius-chain321-inspection"})
    parsed = urllib.parse.urlsplit(url)
    need(parsed.scheme == "https" and parsed.hostname == "api.github.com"
         and parsed.port in (None, 443) and parsed.username is None
         and parsed.password is None and parsed.path.startswith("/repos/edgepillar/syrius/"))
    need(type(token) is str and 0 < len(token) <= 4096)
    return urllib.request.Request(url, headers={"Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "syrius-chain321-inspection"})


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Client:
    def __init__(self, token, *, max_calls=12):
        need(type(max_calls) is int and max_calls in (12, 14, 16))
        self.max_calls = max_calls
        self.token, self.end, self.calls = token, time.monotonic() + 120, 0
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def read(self, url, *, authenticated=True, redirect=False, cap=256 * 1024):
        self.calls += 1
        need(self.calls <= self.max_calls and time.monotonic() < self.end)
        req = request_for(url, self.token if authenticated else None)
        try:
            response = self.opener.open(req, timeout=15)
        except urllib.error.HTTPError as error:
            try:
                need(redirect and authenticated and error.code == 302)
                return artifact_location(error.headers["Location"])
            finally:
                error.close()
        with response:
            need(not redirect and response.status == 200
                 and response.headers.get("Content-Encoding", "identity") == "identity")
            data = bytearray()
            while True:
                need(time.monotonic() < self.end)
                chunk = response.read1(min(65536, cap + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
                need(len(data) <= cap)
            return bytes(data)

    def json(self, path):
        return json.loads(self.read(API + path))


def unpack(raw, expected_sha, expected_size):
    need(type(raw) is bytes and 0 < len(raw) == expected_size <= MAX_ARCHIVE
         and sha(raw) == expected_sha)
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        members = archive.infolist()
        need(len(members) == 1)
        member = members[0]
        need(member.filename == "manifest.json" and not member.is_dir()
             and not member.flag_bits & 1 and 0 < member.file_size <= MAX_MANIFEST
             and stat.S_IFMT(member.external_attr >> 16) in (0, stat.S_IFREG))
        with archive.open(member) as stream:
            data = stream.read(MAX_MANIFEST + 1)
            need(not stream.read(1))
        need(len(data) == member.file_size <= MAX_MANIFEST)
    value = json.loads(data)
    need(type(value) is dict)
    return value, sha(data)


def preparation_command_tail(commands):
    """Keep bounded original outcomes without argv, output text or host paths."""
    tail = []
    for index in range(max(0, len(commands) - 3), len(commands)):
        command = commands[index]
        item = dict(ordinal=index + 1, status="UNKNOWN")
        if command is not None:
            need(type(command) is dict)
            code = command.get("exit_code")
            need(type(code) is int and -(2**63) <= code < 2**63
                 and type(command.get("output_complete")) is bool
                 and type(command.get("forced")) is bool)
            streams = command.get("streams")
            need(type(streams) is dict and set(streams) == {"stdout", "stderr"})
            selected = {}
            for name, stream in streams.items():
                need(type(stream) is dict
                     and all(type(stream.get(key)) is int and 0 <= stream[key] < 2**63
                             for key in ("bytes", "retained_bytes"))
                     and stream["retained_bytes"] <= min(stream["bytes"], MAX_ARCHIVE)
                     and type(stream.get("overflow")) is bool
                     and type(stream.get("sha256")) is str
                     and re.fullmatch(r"[a-f0-9]{64}", stream["sha256"]) is not None)
                selected[name] = {key: stream[key] for key in
                    ("bytes", "retained_bytes", "sha256", "overflow")}
            item.update(status="OBSERVED", exit_code=code,
                output_complete=command["output_complete"], forced=command["forced"],
                streams=selected)
        tail.append(item)
    return dict(count=len(commands), tail=tail)


def project(report, backend, head, run_id, expected_node=NODE_SHA, *,
            expected_patched=False, expected_inspection=False):
    pins = {value[0]: value[1] for value in NODE_SOURCES.values()}
    need(expected_node in pins)
    need(backend in ("docker", "native") and report.get("scope") == "hosted_chain321_lab"
         and report.get("application_sha") == head and report.get("node_sha") == expected_node
         and report.get("run_id") == str(run_id) and report.get("attempt") == "1"
         and report.get("backend") == backend and type(report.get("success")) is bool)
    need(type(expected_inspection) is bool)
    if expected_inspection:
        need(backend == 'native' and expected_patched and expected_node == UPSTREAM_NODE_SHA
             and report.get('wallet_inspection_requested') is True
             and report.get('wallet_tour_requested') is False
             and report.get('wallet_tour') is None
             and report.get('wallet_qualified') is report.get('seed_admitted') is False
             and report.get('native_stack_diagnostic') is True
             and all(report.get(key) is None for key in
                 ('checkpoint', 'path_binding', 'wallet_pointer_binding', 'wallet_reopen')))
    else:
        need(report.get('wallet_inspection_requested', False) is False
             and 'wallet_inspection' not in report)
    checks, errors, commands = report.get("checks"), report.get("error_codes"), report.get("commands")
    need(type(checks) is dict and set(checks) == CHECKS and all(type(v) is bool for v in checks.values()))
    node_tree = report.get("node_tree")
    need((node_tree is None and not checks["source"]) or node_tree == pins[expected_node])
    need(type(expected_patched) is bool)
    patch, compiled_tree = report.get("producer_task_patch"), report.get("compiled_node_tree")
    source_kind = report.get("node_source")
    if expected_patched:
        need(expected_node == UPSTREAM_NODE_SHA and source_kind == "lab-fix"
             and compiled_tree in (None, producer_shutdown_patch.COMPILED_TREE))
        try:
            patch_summary = producer_shutdown_patch.validate(patch,
                required=any(checks[key] for key in ("build", "started", "production")) or report["success"])
        except producer_shutdown_patch.Refused:
            raise Refused("INSPECTION_REFUSED") from None
        need(not checks["build"] or compiled_tree == producer_shutdown_patch.COMPILED_TREE)
    else:
        need(patch is None and source_kind in (None, "upstream" if expected_node == UPSTREAM_NODE_SHA else "original")
             and compiled_tree in (None, pins[expected_node]))
        patch_summary = None
    regressions = report.get("upstream_stop_regressions")
    client_fixture = report.get('upstream_client_fixture')
    if client_fixture is not None:
        need(backend == 'native' and expected_patched
             and (report.get('wallet_tour_requested') is True or expected_inspection))
        try:
            client_fixture = read_first_client_fixture.validate(client_fixture,
                required=any(checks[key] for key in ('assets', 'started', 'production')) or report['success'])
        except read_first_client_fixture.Refused:
            raise Refused('INSPECTION_REFUSED') from None
    need(regressions is None or (expected_node == UPSTREAM_NODE_SHA and type(regressions) is dict
         and set(regressions) == {"passed", "tests", "skips"} and regressions["passed"] is True
         and regressions["tests"] == list(SHUTDOWN_TESTS) and type(regressions["skips"]) is int
         and regressions["skips"] == 0))
    need(not (report["success"] and expected_node == UPSTREAM_NODE_SHA) or regressions is not None)
    go_failure = report.get("upstream_stop_failure")
    if go_failure is not None:
        need(expected_node == UPSTREAM_NODE_SHA and regressions is None
             and not report["success"] and not checks["started"]
             and type(go_failure) is dict
             and set(go_failure) == {"status", "exit_code", "output_complete", "forced", "passed", "failed",
                                    "skipped", "active", "locations", "codes"}
             and go_failure["status"] in ("UNAVAILABLE", "REFUSED", "COMPLETE", "PARTIAL")
             and (go_failure["exit_code"] is None or (type(go_failure["exit_code"]) is int
                  and -(2**63) <= go_failure["exit_code"] < 2**63))
             and all(go_failure[key] is None or type(go_failure[key]) is bool
                     for key in ("output_complete", "forced")))
        for key in ("passed", "failed", "skipped", "active"):
            need(type(go_failure[key]) is list and len(go_failure[key]) <= len(SHUTDOWN_TESTS)
                 and all(name in SHUTDOWN_TESTS for name in go_failure[key])
                 and go_failure[key] == sorted(set(go_failure[key])))
        need(type(go_failure["locations"]) is list and len(go_failure["locations"]) <= 8
             and all(type(line) is int and 0 < line < 1000000 for line in go_failure["locations"])
             and type(go_failure["codes"]) is list and len(go_failure["codes"]) <= len(GO_FAILURE_CODES)
             and all(code in GO_FAILURE_CODES for code in go_failure["codes"])
             and (go_failure["status"] != "COMPLETE" or
                  (go_failure["output_complete"] is True and go_failure["forced"] is False)))
    need(type(errors) is list and len(errors) <= 16 and all(code in CODES for code in errors))
    docker_shutdown = report.get("docker_shutdown")
    if docker_shutdown is not None:
        need(backend == "docker" and type(docker_shutdown) is dict
             and set(docker_shutdown) == {"mode", "roles", "exit_code", "output_complete", "forced"}
             and docker_shutdown["mode"] == "single_verified_stop_command"
             and type(docker_shutdown["roles"]) is list and len(docker_shutdown["roles"]) <= 5
             and all(type(role) is str and role in ROLES for role in docker_shutdown["roles"])
             and docker_shutdown["roles"] == [role for role in reversed(ROLES) if role in docker_shutdown["roles"]]
             and (docker_shutdown["exit_code"] is None or (type(docker_shutdown["exit_code"]) is int
                  and -(2**63) <= docker_shutdown["exit_code"] < 2**63))
             and all(docker_shutdown[key] is None or type(docker_shutdown[key]) is bool
                     for key in ("output_complete", "forced")))
        need(not (report["success"] or checks["stopped"]) or
             (docker_shutdown["roles"] == list(reversed(ROLES)) and docker_shutdown["exit_code"] == 0
              and docker_shutdown["output_complete"] is True and docker_shutdown["forced"] is False))
    need(type(commands) is list and len(commands) <= 1024)
    diagnostics = []
    for command in commands:
        if command is None:
            continue
        need(type(command) is dict)
        found = command.get("compiler_diagnostics", [])
        need(type(found) is list and len(found) <= 12)
        for item in found:
            need(type(item) is dict and set(item) <= {"code", "symbol"}
                 and item.get("code") in DIAGNOSTICS)
            value = dict(code=item["code"])
            if "symbol" in item:
                need(type(item["symbol"]) is str
                     and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_./]{0,95}", item["symbol"]) is not None)
                value["symbol"] = item["symbol"]
            diagnostics.append(value)
    need(len(diagnostics) <= 24)
    compiler = report.get("compiler")
    need(compiler is None or (type(compiler) is str and
         re.fullmatch(r"go version go[0-9]+\.[0-9]+\.[0-9]+ (?:windows|linux)/amd64", compiler)))
    phase = report.get("runtime_phase")
    need(phase in (None, "rpc_readiness", "ws_handshake", "http_genesis", "ws_genesis",
                   "first_frontier", "advancing_frontier")
         or (phase == "wallet_tour" and backend == "native" and expected_patched
             and report.get("wallet_tour_requested") is True and checks["production"]
             and client_fixture is not None)
         or (phase == 'wallet_inspection' and expected_inspection and backend == 'native'
             and expected_patched and checks['production'] and client_fixture is not None))
    node_codes = report.get("node_diagnostics", [])
    need(type(node_codes) is list and len(node_codes) <= len(NODE_DIAGNOSTICS)
         and all(code in NODE_DIAGNOSTICS for code in node_codes))
    states = report.get("docker_states", [])
    need(type(states) is list and len(states) <= 512)
    latest_states, state_counts, first_unhealthy = {}, {}, None
    for state in states:
        need(type(state) is dict and set(state) == {"phase", "role", "running", "exit_code", "oom_killed"}
             and state["phase"] in ("health", "before_stop", "after_stop") and state["role"] in ROLES
             and type(state["running"]) is bool and type(state["oom_killed"]) is bool
             and type(state["exit_code"]) is int and -(2**63) <= state["exit_code"] < 2**63)
        latest_states[state["role"]] = state
        state_counts[state["phase"]] = state_counts.get(state["phase"], 0) + 1
        if first_unhealthy is None and (state["exit_code"] != 0 or state["oom_killed"]
                or (state["phase"] == "health" and not state["running"])):
            first_unhealthy = state
    exits = report.get("node_exits", [])
    need(type(exits) is list and len(exits) <= 5)
    projected_exits = []
    stack_enabled = report.get("native_stack_diagnostic", False)
    need(type(stack_enabled) is bool and (not stack_enabled or backend == "native"))
    stack_scope = report.get("native_stack_scope")
    need(stack_scope is None or stack_scope == ("all_originals" if stack_enabled else "disabled"))
    stop_order = report.get("native_shutdown_order")
    need(stop_order is None or (backend == "native" and type(stop_order) is list
         and len(stop_order) <= len(ROLES) and stop_order == list(ROLES[:len(stop_order)])))
    stop_mode = report.get("native_shutdown_mode")
    need(stop_mode is None or (backend == "native" and stop_mode == "coordinated_requests_then_wait"))
    first_panic, panic_count, first_stack, stack_count = None, 0, None, 0
    for index, item in enumerate(exits):
        if item is None:
            projected_exits.append(dict(exit_code=None, output_complete=None, forced=None,
                                        stop_code=None, stop_os_error=None, node_diagnostics=[], node_log_status=None))
            continue
        need(type(item) is dict)
        selected = {key: item.get(key) for key in ("exit_code", "output_complete", "forced", "stop_code", "stop_os_error")}
        if stack_scope == "all_originals":
            need(item.get("stack_role") == ROLES[index])
            selected["stack_role"] = item["stack_role"]
        else:
            need("stack_role" not in item)
        need(all(selected[key] is None or (type(selected[key]) is int and -(2**63) <= selected[key] < 2**63)
                 for key in ("exit_code", "stop_os_error"))
             and all(selected[key] is None or type(selected[key]) is bool for key in ("output_complete", "forced"))
             and selected["stop_code"] in (None, "SIGNAL_OS_ERROR", "WAIT_TIMEOUT"))
        codes = item.get("node_diagnostics", [])
        need(type(codes) is list and len(codes) <= len(NODE_DIAGNOSTICS)
             and all(code in NODE_DIAGNOSTICS for code in codes))
        selected["node_diagnostics"] = codes
        logs = item.get("private_log_projection")
        need(logs is None or (type(logs) is dict and logs.get("status") in
                             ("UNAVAILABLE", "READ", "MISSING", "REFUSED")))
        selected["node_log_status"] = None if logs is None else logs["status"]
        panic = item.get("node_panic")
        if panic is not None:
            need(backend == "native" and type(panic) is dict
                 and set(panic) == {"status", "kind", "bytes", "sha256", "frames"}
                 and panic["status"] in node_panic_projection.STATUSES
                 and panic["kind"] in node_panic_projection.KINDS
                 and (panic["bytes"] is None or (type(panic["bytes"]) is int
                      and 0 < panic["bytes"] <= node_panic_projection.MAX_BYTES))
                 and (panic["sha256"] is None or (type(panic["sha256"]) is str
                      and re.fullmatch(r"[a-f0-9]{64}", panic["sha256"])))
                 and type(panic["frames"]) is list and len(panic["frames"]) <= 3)
            for frame in panic["frames"]:
                need(type(frame) is dict and set(frame) == {"package", "source_path_sha256", "line"}
                     and frame["package"] in node_panic_projection.PACKAGES
                     and type(frame["line"]) is int and 0 < frame["line"] < 1000000
                     and type(frame["source_path_sha256"]) is str
                     and re.fullmatch(r"[a-f0-9]{64}", frame["source_path_sha256"]))
            need(panic["status"] != "CAPTURED" or
                 (panic["bytes"] is not None and panic["sha256"] is not None))
            panic_count += 1
            if first_panic is None:
                first_panic = dict(role=ROLES[index], **panic)
        probe = item.get("stack_probe")
        if probe is not None:
            need(stack_enabled and type(probe) is dict
                 and {"status", "bytes", "sha256", "frames"} <= set(probe)
                 and set(probe) <= {"status", "bytes", "sha256", "frames", "protocol_workers"}
                 and probe["status"] in native_stack_probe.STATUSES
                 and (probe["bytes"] is None or (type(probe["bytes"]) is int
                      and 0 < probe["bytes"] <= native_stack_probe.MAX_BYTES))
                 and (probe["sha256"] is None or (type(probe["sha256"]) is str
                      and re.fullmatch(r"[a-f0-9]{64}", probe["sha256"]))))
            need(type(probe["frames"]) is list and len(probe["frames"]) <= len(native_stack_probe.CODES)
                 and all(code in native_stack_probe.CODES for code in probe["frames"])
                 and (probe["status"] != "CAPTURED" or (probe["bytes"] is not None
                      and probe["sha256"] is not None and "NODE_STOP" in probe["frames"])))
            workers = probe.get("protocol_workers")
            if workers is not None:
                need(probe["status"] == "CAPTURED" and type(workers) is dict
                     and set(workers) == {"status", "count", "items"}
                     and workers["status"] in ("CAPTURED", "EMPTY", "REFUSED")
                     and type(workers["items"]) is list and len(workers["items"]) <= 4)
                need((workers["status"] == "REFUSED" and workers["count"] is None and not workers["items"])
                     or (type(workers["count"]) is int and 0 <= workers["count"] <= 4096
                         and ((workers["status"] == "EMPTY" and workers["count"] == 0 and not workers["items"])
                              or (workers["status"] == "CAPTURED" and 0 < len(workers["items"]) <= workers["count"]))))
                for site in workers["items"]:
                    need(type(site) is dict and set(site) == {"kind", "state", "package", "source_path_sha256", "line"}
                         and site["kind"] in native_stack_probe.WORKER_KINDS
                         and site["state"] in native_stack_probe.WORKER_STATES
                         and site["package"] in native_stack_probe.WORKER_PACKAGES
                         and type(site["source_path_sha256"]) is str
                         and re.fullmatch(r"[a-f0-9]{64}", site["source_path_sha256"])
                         and type(site["line"]) is int and 0 < site["line"] < 1000000)
                probe = dict(probe, protocol_workers=dict(workers, items=workers["items"][:2]))
            if stack_scope == "all_originals":
                stack_count += 1
                selected["stack_probe_status"] = probe["status"]
                if first_stack is None or (first_stack["status"] != "CAPTURED" and probe["status"] == "CAPTURED"):
                    first_stack = dict(role=ROLES[index], **probe)
            else:
                selected["stack_probe"] = probe
        projected_exits.append(selected)
    counts = {key: report.get(key) for key in ("created_count", "started_count")}
    need(all(value is None or (type(value) is int and 0 <= value <= 5)
             for value in counts.values()))
    c_compiler = report.get("c_compiler")
    need(c_compiler is None or (type(c_compiler) is dict
         and set(c_compiler) == {"target", "version", "cgo_enabled"}
         and c_compiler["target"] in ("x86_64-linux-gnu", "x86_64-w64-mingw32")
         and type(c_compiler["version"]) is str
         and re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", c_compiler["version"])
         and c_compiler["cgo_enabled"] is True))
    direct_ready, relay = report.get("direct_rpc_ready"), report.get("loopback_relay")
    need(direct_ready is None or type(direct_ready) is bool)
    need(relay is None or backend == "docker")
    if relay is not None:
        need(type(relay) is dict and set(relay) == {"started", "closed", "listeners", "accepted", "completed",
                                                   "bytes", "active", "workers_alive"}
             and all(type(relay[key]) is bool for key in ("started", "closed"))
             and all(type(relay[key]) is int and 0 <= relay[key] < 2**63
                     for key in ("listeners", "accepted", "completed", "bytes", "active", "workers_alive"))
             and relay["listeners"] <= 2 and relay["completed"] <= relay["accepted"] <= 256
             and relay["active"] <= 4 and relay["workers_alive"] <= 258)
    observations = report.get("observations")
    if observations is not None:
        need(type(observations) is dict and set(observations) == {"chain", "genesis_hash", "first_height",
            "last_height", "first_timestamp", "last_timestamp", "samples", "cross_transport_hash_equal"}
             and checks["production"] is True and type(observations["chain"]) is int
             and observations["chain"] == 321 and observations["cross_transport_hash_equal"] is True
             and type(observations["genesis_hash"]) is str
             and re.fullmatch(r"[a-f0-9]{64}", observations["genesis_hash"])
             and all(type(observations[key]) is int and 0 < observations[key] < 2**63 for key in
                     ("first_height", "last_height", "first_timestamp", "last_timestamp", "samples"))
             and observations["last_height"] > observations["first_height"]
             and observations["last_timestamp"] > observations["first_timestamp"]
             and observations["samples"] <= 36)
    need(not checks["production"] or observations is not None)
    projected_regressions = regressions
    if expected_patched and regressions is not None:
        projected_regressions = dict(passed=True, count=len(SHUTDOWN_TESTS), skips=0)
    result = dict(scope="retained_chain321_observation", backend=backend,
        source_head=head, source_run_id=run_id, source_attempt=1,
        node_sha=expected_node, node_tree=node_tree, upstream_stop_regressions=projected_regressions,
        artifact_reported_success=report["success"], checks=checks, error_codes=errors,
        compiler=compiler, compiler_diagnostics=diagnostics,
        runtime_phase=phase, node_diagnostics=node_codes,
        docker_states=[latest_states[role] for role in ROLES if role in latest_states],
        docker_state_counts=state_counts, first_unhealthy_docker_state=first_unhealthy,
        node_exits=projected_exits, c_compiler=c_compiler, **counts,
        direct_rpc_ready=direct_ready, loopback_relay=relay,
        observations=observations,
        native_stack_diagnostic=stack_enabled,
        native_shutdown_order=stop_order,
        native_shutdown_mode=stop_mode,
        inspection_only=True, runtime_started=False, seed_admitted=False)
    if 'checkpoint' in report:
        try:
            checkpoint = closed_lab_checkpoint.project(report['checkpoint'])
        except closed_lab_checkpoint.Refused:
            raise Refused('INSPECTION_REFUSED') from None
        if checkpoint is not None and checkpoint['complete']:
            need(backend == 'native' and report.get('wallet_tour_requested') is True
                 and report.get('wallet_tour_qualified') is True and report['success'] is True
                 and all(checks.values()) and not errors and len(projected_exits) == len(ROLES)
                 and all(item['exit_code'] == 0 and item['output_complete'] is True
                         and item['forced'] is False for item in projected_exits))
        result['checkpoint'] = checkpoint
    if 'path_binding' in report:
        try:
            paths = restored_lab_paths.project(report['path_binding'])
        except closed_lab_checkpoint.Refused:
            raise Refused('INSPECTION_REFUSED') from None
        if paths is not None and paths['complete']:
            need(result.get('checkpoint') is not None and result['checkpoint']['complete'] is True
                 and report['success'] is True)
        result['path_binding'] = paths
    if 'wallet_pointer_binding' in report:
        try:
            pointer = closed_wallet_pointer.project(report['wallet_pointer_binding'])
        except closed_lab_checkpoint.Refused:
            raise Refused('INSPECTION_REFUSED') from None
        if pointer is not None and pointer['complete']:
            need(result.get('checkpoint') is not None and result['checkpoint']['complete'] is True
                 and result.get('path_binding') is not None
                 and result['path_binding']['complete'] is True and report['success'] is True)
        result['wallet_pointer_binding'] = pointer
    if 'wallet_reopen' in report:
        try:
            reopened = restored_wallet_run.project(report['wallet_reopen'])
        except closed_lab_checkpoint.Refused:
            raise Refused('INSPECTION_REFUSED') from None
        if reopened is not None and reopened['complete']:
            need(result.get('wallet_pointer_binding') is not None
                 and result['wallet_pointer_binding']['complete'] is True
                 and report['success'] is True)
        result['wallet_reopen'] = reopened
    if panic_count:
        result.update(node_panic_count=panic_count, first_node_panic=first_panic)
    if expected_patched:
        result.update(node_source="lab-fix", compiled_node_tree=compiled_tree,
                      producer_task_patch=patch_summary)
    if client_fixture is not None:
        result['upstream_client_fixture'] = client_fixture
    if go_failure is not None:
        result["upstream_stop_failure"] = go_failure
    if report.get('asset_generation') is not None:
        try:
            progress = lab_asset_progress.validate(report['asset_generation'])
        except ValueError:
            raise Refused('INSPECTION_REFUSED') from None
        need(not checks['assets'] or progress['script_complete'])
        # The validated prefix length is implied by its fixed phase. One label
        # leaves room for all five original exits in the bounded notice.
        result['asset_phase'] = progress['phase'] if progress['status'] == 'OBSERVED' else progress['status']
    if "COMMAND_TIMEOUT" in errors and not checks["started"]:
        result["preparation_commands"] = preparation_command_tail(commands)
    if docker_shutdown is not None:
        result["docker_shutdown"] = docker_shutdown
    if stack_scope is not None:
        result["native_stack_scope"] = stack_scope
    if stack_scope == "all_originals":
        result.update(native_stack_probe_count=stack_count, native_stack_probe=first_stack)
        # The five nodes repeat stop milestones. Share the validated labels
        # so client-restoration and worker details still fit the notice.
        catalog = []
        for item in projected_exits:
            codes = item.pop("node_diagnostics")
            indices = []
            for code in codes:
                if code not in catalog:
                    catalog.append(code)
                indices.append(catalog.index(code))
            item["diagnostic_indices"] = indices
        result["node_diagnostics_catalog"] = catalog
        # Native reports have no Docker resources or host relay. Omit their
        # empty fields so the bounded worker sites fit the complete notice.
        for key in ("created_count", "started_count", "direct_rpc_ready", "loopback_relay",
                    "docker_state_counts", "docker_states", "first_unhealthy_docker_state"):
            need(not result[key])
            del result[key]
        for key in ("compiler_diagnostics", "node_diagnostics"):
            if not result[key]:
                del result[key]
    return result


def project_wallet_tour(report, lab, head, run_id, tree, manifest_sha):
    """Read original page coverage without exporting pixels or private replies."""
    from tool.ci import windows_wallet_tour as wallet

    need(type(report) is dict and type(lab) is dict
         and lab.get("wallet_tour_requested") is True
         and lab.get("application_sha") == head and lab.get("application_tree") == tree
         and re.fullmatch(r"[a-f0-9]{40}", tree) is not None
          and type(report.get("schema")) is int and report["schema"] in (1, 2)
         and report.get("scope") == "owned_chain321_wallet_tour"
         and report.get("source_sha") == head and report.get("source_tree") == tree
         and report.get("run_id") == str(run_id) and report.get("run_attempt") == "1"
         and type(report.get("success")) is bool
         and report.get("wallet_qualified") is report.get("seed_admitted") is False
         and type(report.get("visual_matches")) is int and report["visual_matches"] == 0)
    original = lab.get("wallet_tour")
    need(type(original) is dict and original.get("manifest_sha256") == manifest_sha
         and re.fullmatch(r"[a-f0-9]{64}", manifest_sha) is not None)
    checks, errors, captures = report.get("checks"), report.get("errors"), report.get("captures")
    expected_checks = wallet.CHECKS if report['schema'] == 1 else wallet.CURRENT_CHECKS
    need(type(checks) is dict and set(checks) == set(expected_checks)
         and all(type(value) is bool for value in checks.values())
         and type(errors) is list and len(errors) <= 16
         and all(value in wallet.CODES for value in errors)
         and type(captures) is list and len(captures) <= len(wallet.PAGES)
         and "tour" in report)
    for index, capture in enumerate(captures):
        need(type(capture) is dict and set(capture) == {"page", "bytes", "sha256", "width", "height"}
             and capture["page"] == wallet.PAGES[index]
             and type(capture["bytes"]) is int and 0 < capture["bytes"] <= wallet.debug.entry.MAX_PNG
             and re.fullmatch(r"[a-f0-9]{64}", capture["sha256"]) is not None
             and type(capture["width"]) is type(capture["height"]) is int
             and capture["width"] == 1280 and capture["height"] == 780)
    try:
        tour = None if report["tour"] is None else wallet.tour_receipt(report["tour"])
        failure = None if report.get("entry_failure") is None else wallet.entry_failure(report["entry_failure"])
        extra = {}
        for key, validate in (("lab_send", wallet.lab_send_receipt),
                              ("address_selection", wallet.address_selection_receipt)):
            if key in report:
                extra[key] = None if report[key] is None else validate(report[key])
        if report['schema'] == 2:
            need('quiescence' in report)
            extra['quiescence'] = (None if report['quiescence'] is None
                                   else wallet.quiescence_receipt(report['quiescence']))
        else:
            need('quiescence' not in report)
    except wallet.Refused:
        raise Refused("INSPECTION_REFUSED") from None
    visited = 0 if tour is None else len(tour["visited"])
    need(original.get("success") is report["success"] and original.get("checks") == checks
         and original.get("errors") == errors
         and type(original.get("visited_pages")) is int and original["visited_pages"] == visited
         and type(original.get("captured_pages")) is int and original["captured_pages"] == len(captures)
         and (not report["success"] or wallet.completed(report)))
    exit_code, forced = report.get("entry_exit"), report.get("required_actor_forced_cleanup")
    need((exit_code is None or type(exit_code) is int and -(2**63) <= exit_code < 2**63)
         and type(forced) is bool)
    return dict(schema=1, scope="retained_wallet_tour_observation", source_head=head,
        source_tree=tree, source_run_id=run_id, source_attempt=1,
        artifact_reported_success=report["success"], original_checks=checks,
        original_error_codes=errors, entry_failure=failure, entry_exit=exit_code,
        required_actor_forced_cleanup=forced, tour=tour, captured_pages=len(captures),
        inspection_only=True, runtime_started=False, wallet_qualified=False,
        seed_admitted=False, visual_matches=0, **extra)


def main():
    global PHASE
    parent = os.environ
    need(parent.get("GITHUB_ACTIONS") == "true" and parent.get("SYRIUS_HOSTED_RUNNER") == "github-hosted"
         and parent.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
         and parent.get("GITHUB_REPOSITORY") == "edgepillar/syrius")
    run_text, head = parent.get("LAB_INSPECT_RUN", ""), parent.get("LAB_INSPECT_HEAD", "")
    need(re.fullmatch(r"[1-9][0-9]{0,19}", run_text) is not None
         and re.fullmatch(r"[a-f0-9]{40}", head) is not None)
    run_id = int(run_text)
    backends = selected_backends(parent.get("LAB_INSPECT_BACKEND", "both"))
    expected_choice = parent.get("LAB_INSPECT_NODE_SOURCE", "original")
    expected_node, _ = selected_node_source(expected_choice)
    client = Client(parent.get("GH_TOKEN"))
    PHASE = "source_metadata"
    run = client.json("/actions/runs/" + run_text)
    need(run["id"] == run_id and run["head_sha"] == head and run["run_attempt"] == 1
         and run["workflow_id"] == 381413107 and run["event"] == "workflow_dispatch"
         and run["status"] == "completed" and run["repository"]["full_name"] == "edgepillar/syrius")
    PHASE = "artifact_metadata"
    listing = client.json("/actions/runs/" + run_text + "/artifacts?per_page=20")
    need(listing["total_count"] == len(listing["artifacts"]) <= 20)
    wallet_lab = None
    for backend in backends:
        name = "chain321-" + backend + "-" + head + "-" + run_text + "-1"
        selected = [item for item in listing["artifacts"] if item["name"] == name]
        need(len(selected) == 1)
        item = selected[0]
        need(item["expired"] is False and item["workflow_run"]["id"] == run_id
             and item["workflow_run"]["head_sha"] == head
             and re.fullmatch(r"sha256:[a-f0-9]{64}", item.get("digest", "")) is not None)
        PHASE = "download_" + backend
        location = client.read(API + "/actions/artifacts/" + str(item["id"]) + "/zip", redirect=True)
        raw = client.read(location, authenticated=False, cap=MAX_ARCHIVE)
        PHASE = "unpack_" + backend
        report, manifest_sha = unpack(raw, item["digest"][7:], item["size_in_bytes"])
        PHASE = "projection_" + backend
        summary = project(report, backend, head, run_id, expected_node,
                          expected_patched=expected_choice == "lab-fix")
        if backend == "native" and report.get("wallet_tour") is not None:
            wallet_lab = report
        summary.update(archive_sha256=sha(raw), manifest_sha256=manifest_sha)
        PHASE = "notice_" + backend
        for component, frame in restored_wallet_run.notice_frames(summary):
            encoded = json.dumps(frame, sort_keys=True, separators=(",", ":"))
            title = 'Retained chain-321 observation' if not component else 'Retained closed copy ' + component
            escaped = encoded.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
            print('::notice title=' + title + '::' + escaped, flush=True)
    if wallet_lab is not None:
        PHASE = "wallet_artifact_metadata"
        name = "wallet-tour-" + head + "-" + run_text + "-1"
        selected = [item for item in listing["artifacts"] if item["name"] == name]
        need(len(selected) == 1)
        item = selected[0]
        need(item["expired"] is False and item["workflow_run"]["id"] == run_id
             and item["workflow_run"]["head_sha"] == head
             and re.fullmatch(r"sha256:[a-f0-9]{64}", item.get("digest", "")) is not None)
        commit = client.json("/git/commits/" + head)
        need(commit["sha"] == head)
        PHASE = "download_wallet"
        location = client.read(API + "/actions/artifacts/" + str(item["id"]) + "/zip", redirect=True)
        raw = client.read(location, authenticated=False, cap=MAX_ARCHIVE)
        PHASE = "unpack_wallet"
        report, manifest_sha = unpack(raw, item["digest"][7:], item["size_in_bytes"])
        PHASE = "projection_wallet"
        summary = project_wallet_tour(report, wallet_lab, head, run_id, commit["tree"]["sha"], manifest_sha)
        summary.update(archive_sha256=sha(raw), manifest_sha256=manifest_sha)
        encoded = json.dumps(summary, sort_keys=True, separators=(",", ":"))
        need(len(encoded.encode("ascii")) <= 3800)
        escaped = encoded.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print("::notice title=Retained wallet tour observation::" + escaped, flush=True)
    PHASE = "source_metadata_after"
    after = client.json("/actions/runs/" + run_text)
    need(all(after[key] == run[key] for key in ("id", "head_sha", "run_attempt", "workflow_id", "status", "conclusion")))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("::error title=Retained chain-321 inspection::INSPECTION_REFUSED phase=" + PHASE, flush=True)
        raise SystemExit(1)
