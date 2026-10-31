"""Manual hosted-Windows Flutter debug loop; no wallet or chain admission.

Only finite receipts leave this controller. Flutter machine messages, VM service
authentication addresses, profile paths and process IDs remain private. DevTools
availability is recorded separately from a real frontend attachment.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import queue
import re
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time

try:
    from . import flutter_debug_protocol as protocol
    from . import windows_entry_capture_smoke as entry
    from .windows_debug_process import (WindowsJob, ProcessRefused, compiler_helper_path,
                                       HELPER_EXIT_MARKER, HELPER_SCOPE)
except ImportError:
    import flutter_debug_protocol as protocol
    import windows_entry_capture_smoke as entry
    from windows_debug_process import (WindowsJob, ProcessRefused, compiler_helper_path,
                                      HELPER_EXIT_MARKER, HELPER_SCOPE)


bounded = entry.bounded
OUTPUT = Path('.harness/ci-windows-debug')
EXIT_PREFIX = b'SYRIUS_DEBUG_TOOL_EXIT:'
CHECKS = ('environment', 'source', 'profile', 'preflight', 'job_owned',
          'tool_started', 'application_owned', 'ordinary_entry', 'service_bound',
          'breakpoint_hit', 'hot_reload', 'reload_state_preserved', 'hot_restart',
          'restart_state_reset', 'devtools_available', 'probe_closed',
          'frontend_job_owned', 'frontend_attached', 'frontend_exit',
          'close_ack', 'application_exit', 'tool_exit', 'output_complete', 'source_unchanged')
CODES = protocol.CODES | frozenset(('ENVIRONMENT_REFUSED', 'PROFILE_REFUSED',
    'SOURCE_REFUSED', 'TOOL_REFUSED', 'JOB_REFUSED', 'PROCESS_REFUSED',
    'APPLICATION_EXIT_UNCONFIRMED', 'TOOL_EXIT_UNCONFIRMED', 'PROBE_REFUSED',
    'PROBE_EXIT_UNCONFIRMED', 'ENTRY_REFUSED', 'READINESS_TIMEOUT', 'TOTAL_DEADLINE',
    'APPLICATION_EXIT_FAILED', 'INTERNAL_ERROR', 'FORCED_CLEANUP', 'ANALYSIS_FAILED',
    'CLOSE_UNCONFIRMED'))
DART_CODES = frozenset(('PID_REFUSED', 'ISOLATE_REFUSED', 'MARKER_REFUSED',
    'BREAKPOINT_REFUSED', 'SERVICE_OUTPUT_REFUSED', 'SERVICE_IO_REFUSED',
    'INPUT_REFUSED', 'CLOSE_UNCONFIRMED'))
CODES |= DART_CODES
FRONTEND_CODES = frozenset(('SOCKET_REPLACED', 'REQUEST_REFUSED', 'VM_REFUSED',
    'CDP_OUTPUT_REFUSED', 'CDP_RESPONSE_REFUSED', 'CDP_IO_REFUSED', 'CDP_COMMAND_UNCERTAIN',
    'BROWSER_REFUSED', 'BROWSER_TIMEOUT', 'FRONTEND_REFUSED', 'FRONTEND_UNCONFIRMED',
    'BROWSER_EXIT_UNCONFIRMED', 'FRONTEND_EXIT_UNCONFIRMED'))
CODES |= FRONTEND_CODES
CODES |= frozenset(('HELPER_IMAGE_REFUSED', 'HELPER_IDENTITY_REFUSED', 'HELPER_CLOSE_UNCONFIRMED'))
FRONTEND_PHASES = frozenset(('new', 'admitted', 'browser_started', 'browser_socket_bound',
    'page_navigated', 'vm_matched', 'ui_ready', 'close_requested', 'browser_exited'))
FRONTEND_FLAGS = ('pageLoaded', 'documentReady', 'devtoolsTitle', 'frontendSourceMatched', 'webglIssue', 'wasmIssue',
    'frontendGetVmMatched', 'frontendSocketClosed', 'held', 'serviceSocketSeen')
FRONTEND_COUNTS = ('runtimeExceptions', 'networkFailures', 'workerTargets',
    'getVmRequests', 'getVmReplies', 'otherSockets')


def required_actors_complete(report):
    """Helpers cannot be signalled until every required original actor passed."""
    checks = report.get('checks')
    if (type(checks) is not dict or set(checks) != set(CHECKS)
            or not all(value is True for value in checks.values())
            or report.get('errors') != [] or report.get('required_actor_forced_cleanup') is not False
            or report.get('devtools_attached') is not True):
        return False
    if not all(type(report.get(key)) is int and report[key] == 0 for key in
               ('application_exit', 'bootstrap_exit', 'tool_exit', 'probe_exit', 'frontend_exit')):
        return False
    frontend = report.get('frontend')
    if (type(frontend) is not dict or frontend.get('ok') is not True
            or type(frontend.get('browserExit')) is not int or frontend['browserExit'] != 0
            or frontend.get('forced') is not False or frontend.get('outputComplete') is not True):
        return False
    for key in ('tool_output', 'probe_output', 'frontend_output'):
        output = report.get(key)
        if (type(output) is not dict or output.get('output_complete') is not True
                or output.get('overflow') is not False):
            return False
    protocol_state = report.get('protocol')
    return (type(protocol_state) is dict and protocol_state.get('held') is False
            and protocol_state.get('app_stopped') is True
            and type(protocol_state.get('pending_commands')) is int
            and protocol_state['pending_commands'] == 0)


def helper_cleanup_complete(value):
    if (type(value) is not dict or value.get('scope') != HELPER_SCOPE
            or value.get('status') != 'PASSED' or value.get('code') is not None
            or type(value.get('remaining')) is not int or value['remaining'] != 0
            or type(value.get('forced')) is not bool or type(value.get('receipts')) is not list
            or len(value['receipts']) > 2):
        return False
    seen, forced = set(), False
    for receipt in value['receipts']:
        if (type(receipt) is not dict or set(receipt) != {'role', 'image_sha256', 'forced',
                'termination_requested', 'termination_succeeded', 'actual_exit', 'exit_observed', 'stdio_captured'}
                or receipt['role'] not in ('sdk_dart', 'msvc_telemetry') or receipt['role'] in seen
                or not bounded.safe_digest(receipt['image_sha256'])
                or any(type(receipt[key]) is not bool for key in ('forced', 'termination_requested',
                        'termination_succeeded', 'exit_observed', 'stdio_captured'))
                or not receipt['exit_observed'] or receipt['stdio_captured']
                or type(receipt['actual_exit']) is not int):
            return False
        seen.add(receipt['role'])
        if receipt['forced']:
            if (not receipt['termination_requested'] or not receipt['termination_succeeded']
                    or receipt['actual_exit'] != HELPER_EXIT_MARKER):
                return False
            forced = True
        elif (receipt['termination_requested'] or receipt['termination_succeeded']
              or receipt['actual_exit'] != 0):
            return False
    return value['forced'] is forced


def debug_complete(report):
    cleanup = report.get('auxiliary_cleanup')
    return (required_actors_complete(report) and helper_cleanup_complete(cleanup)
            and type(report.get('owned_job_active_at_close')) is int
            and report['owned_job_active_at_close'] == 0
            and report.get('forced_cleanup') is cleanup['forced'])


def compiler_metadata_version(name):
    # Visual Studio distributes CMake with vendor version suffixes.
    return (type(name) is str and len(name) <= 64
            and re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,3}(?:-[A-Za-z][A-Za-z0-9_.-]{0,31})?', name)
            is not None)


def compiler_telemetry_image(repo):
    root = repo / 'build/windows/x64/CMakeFiles'
    bounded.plain(root)
    candidates = []
    for directory in root.iterdir():
        if compiler_metadata_version(directory.name):
            bounded.plain(directory)
            offered = directory / 'CMakeCXXCompiler.cmake'
            if offered.is_file():
                info = bounded.plain(offered)
                need(0 < info.st_size <= 128 * 1024, 'HELPER_IMAGE_REFUSED')
                candidates.append(offered)
    need(len(candidates) == 1, 'HELPER_IMAGE_REFUSED')
    return Path(compiler_helper_path(candidates[0].read_text(encoding='utf-8')))


def need(value, code):
    if not value:
        raise ProcessRefused(code)


class Lines:
    """One original output stream, capped in memory and drained to real EOF."""
    def __init__(self, stream):
        self.stream, self.items = stream, queue.Queue(128)
        self.count, self.digest = 0, hashlib.sha256()
        self.complete = self.overflow = self.failed = False
        self.thread = threading.Thread(target=self._read, daemon=True)
        self.thread.start()

    def _read(self):
        try:
            while True:
                raw = self.stream.readline(protocol.MAX_LINE + 1)
                if not raw:
                    self.complete = True
                    return
                self.count += len(raw)
                self.digest.update(raw)
                if (len(raw) > protocol.MAX_LINE or self.count > protocol.MAX_TOTAL
                        or self.overflow):
                    self.overflow = True
                    continue
                try:
                    self.items.put_nowait(raw)
                except queue.Full:
                    self.overflow = True
        except Exception:
            self.failed = True

    def take(self, seconds=.1):
        need(not self.overflow and not self.failed, 'OUTPUT_REFUSED')
        try:
            return self.items.get(timeout=max(0, seconds))
        except queue.Empty:
            return None

    def finish(self):
        self.thread.join(5)
        return self.complete and not self.thread.is_alive() and not self.failed and not self.overflow

    def public(self):
        return dict(bytes=self.count, sha256=self.digest.hexdigest(),
                    output_complete=self.complete and not self.failed,
                    overflow=self.overflow)


def sdk(parent):
    root = Path(parent.get('FLUTTER_ROOT', ''))
    need(root.is_absolute(), 'TOOL_REFUSED')
    paths = (root / 'bin/cache/dart-sdk/bin/dart.exe', root / 'bin/cache/flutter_tools.snapshot')
    for path in paths:
        need(path.is_file(), 'TOOL_REFUSED')
        bounded.plain(path)
    return paths


def profile_environment(parent, profile, port, token):
    env = entry.child_environment(parent, profile, port, token)
    for name in ('FLUTTER_ROOT', 'PUB_CACHE', 'PROGRAMFILES', 'PROGRAMFILES(X86)',
                 'PROGRAMW6432', 'GITHUB_ACTIONS', 'RUNNER_OS', 'RUNNER_ENVIRONMENT',
                 'GITHUB_SHA', 'GITHUB_WORKSPACE', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT'):
        if name in parent:
            env[name] = parent[name]
    env.update(SYRIUS_WINDOWS_DEBUG_PROFILE=str(profile), FLUTTER_SUPPRESS_ANALYTICS='true',
               DART_SUPPRESS_ANALYTICS='true', CI='true')
    return env


def sdk_child():
    """The job owner must release this gate before any SDK process can exist."""
    parent, _ = entry.require_ci(os.environ, None, platform=os.name)
    profile = Path(parent.get('SYRIUS_WINDOWS_DEBUG_PROFILE', ''))
    need(profile.is_absolute() and parent.get('APPDATA') == str(profile / 'AppData/Roaming')
         and parent.get('HOME') == str(profile), 'PROFILE_REFUSED')
    need(os.read(0, 6) == b'START\n', 'JOB_REFUSED')
    dart, snapshot = sdk(parent)
    packages = Path(parent['FLUTTER_ROOT']) / 'packages/flutter_tools/.dart_tool/package_config.json'
    need(packages.is_file(), 'TOOL_REFUSED')
    bounded.plain(packages)
    # Match Flutter 3.47.7's Windows launcher while keeping the original SDK
    # process supervised directly, without a command-shell intermediary.
    original = subprocess.Popen([str(dart), '--packages=' + str(packages), str(snapshot),
        'run', '--machine', '--no-pub',
        '-d', 'windows', '--target', 'harness/app/main.dart',
        '--dart-define-from-file=.dart_tool/git_metadata.json'],
        shell=False, stdin=sys.stdin.buffer, stdout=sys.stdout.buffer, stderr=sys.stdout.buffer,
        env=parent, cwd=Path(parent['GITHUB_WORKSPACE']))
    code = original.wait()
    sys.stdout.buffer.write(EXIT_PREFIX + json.dumps(dict(exit=code)).encode() + b'\n')
    sys.stdout.buffer.flush()
    return code


class Tool:
    def __init__(self, original, lines):
        self.original, self.lines = original, lines
        self.protocol, self.exit = protocol.DaemonTranscript(), None

    def observe(self, seconds=.1):
        raw = self.lines.take(seconds)
        if raw is None:
            return
        if raw.startswith(EXIT_PREFIX):
            need(self.exit is None, 'TOOL_EXIT_UNCONFIRMED')
            value = json.loads(raw[len(EXIT_PREFIX):])
            need(type(value) is dict and set(value) == {'exit'} and type(value['exit']) is int,
                 'TOOL_EXIT_UNCONFIRMED')
            self.exit = value['exit']
        else:
            self.protocol.feed(raw)

    def until(self, predicate, seconds):
        deadline = time.monotonic() + seconds
        while not predicate():
            need(time.monotonic() < deadline, 'TOTAL_DEADLINE')
            self.observe(min(.1, max(0, deadline - time.monotonic())))
            need(not (self.original.poll() is not None and self.lines.complete
                      and self.lines.items.empty() and not predicate()), 'TOOL_EXIT_UNCONFIRMED')

    def command(self, method, *, full_restart=None, seconds=60):
        message = self.protocol.reserve(method, full_restart=full_restart)
        try:
            self.original.stdin.write(json.dumps([message], separators=(',', ':')).encode() + b'\n')
            self.original.stdin.flush()
            self.until(lambda: not self.protocol._pending, seconds)
        except Exception:
            if message['id'] in self.protocol._pending:
                self.protocol.uncertain(message['id'])
            raise


class Probe:
    def __init__(self, dart, repo, env):
        packages = repo / '.dart_tool/package_config.json'
        need(packages.is_file(), 'TOOL_REFUSED')
        bounded.plain(packages)
        self.original = subprocess.Popen([str(dart), '--disable-dart-dev',
            '--packages=' + str(packages),
            'tool/ci/windows_debug_service_probe.dart'], cwd=repo, env=env, shell=False,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
        self.lines = Lines(self.original.stdout)
        self.reserved = set()
        self.failure = None

    def command(self, action, tool, **values):
        need(action in ('bind', 'breakpoint', 'reload', 'restart', 'close')
             and action not in self.reserved, 'PROBE_REFUSED')
        self.reserved.add(action)
        self.original.stdin.write(json.dumps(dict(action=action, **values)).encode() + b'\n')
        self.original.stdin.flush()
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            tool.observe(0)
            raw = self.lines.take(.1)
            if raw is None:
                need(self.original.poll() is None or not self.lines.complete, 'PROBE_EXIT_UNCONFIRMED')
                continue
            try:
                value = json.loads(raw)
            except (ValueError, UnicodeError):
                self.failure = probe_line_observation(raw)
                raise ProcessRefused('PROBE_REFUSED') from None
            phase = 'bound' if action == 'bind' else 'closed' if action == 'close' else action
            if type(value) is dict and value.get('ok') is False and value.get('code') in CODES:
                raise ProcessRefused(value['code'])
            need(type(value) is dict and value.get('ok') is True and value.get('phase') == phase,
                 'PROBE_REFUSED')
            if action == 'bind':
                need(value == dict(ok=True, phase='bound', pidMatched=True, rootMatched=True,
                                   debugLoopQualified=False), 'PROBE_REFUSED')
            elif action == 'close':
                need(value == dict(ok=True, phase='closed'), 'PROBE_REFUSED')
            else:
                need(value == dict(ok=True, phase=phase, debugLoopQualified=False), 'PROBE_REFUSED')
            return
        raise ProcessRefused('PROBE_REFUSED')


def probe_line_observation(raw):
    """Classify only fixed startup shapes; preserve no line or private detail."""
    code = 'UNCLASSIFIED_OUTPUT'
    if raw.startswith((b'Resolving dependencies', b'Downloading packages')):
        code = 'PUB_RESOLUTION'
    elif raw.startswith(b'Building package executable'):
        code = 'PUB_EXECUTABLE_BUILD'
    elif raw.startswith(b'Unhandled exception:'):
        code = 'UNHANDLED_EXCEPTION'
    elif re.search(rb'\bError:', raw):
        code = 'COMPILE_OR_USAGE_ERROR'
    elif raw.startswith(b'The Dart VM service is listening'):
        code = 'VM_SERVICE_LISTENER'
    return dict(code=code, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())


def request_close(transport, token):
    """One ordinary close request; a lost acknowledgement is never retried."""
    try:
        reply = transport.exchange(dict(cmd='quit'), token, 5)
        value = json.loads(reply.body)
        need(reply.status == 200 and type(value) is dict and set(value) == {'ok'}
             and value['ok'] is True, 'CLOSE_UNCONFIRMED')
    except Exception:
        raise ProcessRefused('CLOSE_UNCONFIRMED') from None


class Frontend:
    def __init__(self, repo, env):
        node = shutil.which('node', path=env.get('PATH'))
        need(node is not None, 'BROWSER_REFUSED')
        bounded.plain(Path(node))
        self.original = subprocess.Popen([node, 'tool/ci/windows_devtools_frontend.mjs'],
            cwd=repo, env=env, shell=False, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, bufsize=0)
        self.lines = Lines(self.original.stdout)
        self.result = None

    def attach(self, tool, pid):
        data = json.dumps(dict(devtools=tool.protocol._devtools,
                               service=tool.protocol._service, pid=pid)).encode()
        need(len(data) <= 16378, 'ENDPOINT_REFUSED')
        self.original.stdin.write(b'START\n' + data + b'\n')
        self.original.stdin.flush()
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            tool.observe(0)
            raw = self.lines.take(.1)
            if raw is None:
                need(self.original.poll() is None or not self.lines.complete, 'FRONTEND_EXIT_UNCONFIRMED')
                continue
            value = json.loads(raw)
            fields = {'schema', 'ok', 'scope', 'attached', 'headless', 'browserExit',
                      'outputComplete', 'forced', 'code', 'outputBytes', 'outputSha256',
                      'phase', 'observations'}
            need(type(value) is dict and set(value) == fields and type(value['schema']) is int and value['schema'] == 1
                 and value['scope'] == 'owned_devtools_frontend'
                 and all(type(value[name]) is bool for name in
                         ('ok', 'attached', 'headless', 'outputComplete', 'forced'))
                 and type(value['outputBytes']) is int and 0 <= value['outputBytes'] <= 1024**2
                 and bounded.safe_digest(value['outputSha256'])
                 and (value['browserExit'] is None or type(value['browserExit']) is int)
                 and (value['code'] is None or value['code'] in CODES)
                 and value['phase'] in FRONTEND_PHASES, 'FRONTEND_REFUSED')
            observations = value['observations']
            need(type(observations) is dict and set(observations) == set(FRONTEND_FLAGS + FRONTEND_COUNTS)
                 and all(type(observations[key]) is bool for key in FRONTEND_FLAGS)
                 and all(type(observations[key]) is int and 0 <= observations[key] <= 1000
                         for key in FRONTEND_COUNTS), 'FRONTEND_REFUSED')
            self.result = value
            if value['code'] is not None:
                raise ProcessRefused(value['code'])
            need(value['ok'] and value['attached'] and value['headless']
                 and value['outputComplete'] and value['browserExit'] == 0 and not value['forced'],
                 'FRONTEND_UNCONFIRMED')
            need(value['phase'] == 'browser_exited' and not observations['held']
                 and all(observations[key] for key in ('documentReady', 'frontendSourceMatched',
                         'frontendGetVmMatched', 'serviceSocketSeen'))
                 and observations['getVmRequests'] >= observations['getVmReplies'] >= 1,
                 'FRONTEND_UNCONFIRMED')
            need(self.original.wait(timeout=15) == 0 and self.lines.finish(), 'FRONTEND_EXIT_UNCONFIRMED')
            return
        raise ProcessRefused('FRONTEND_UNCONFIRMED')


def ready(tool, transport, token, seconds=45):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        tool.observe(0)
        try:
            reply = transport.exchange(dict(cmd='ping'), token, 1)
        except (OSError, TimeoutError):
            time.sleep(.1)
            continue
        need(reply.status == 200, 'ENTRY_REFUSED')
        value = json.loads(reply.body)
        need(type(value) is dict and value.get('ok') is True and value.get('harnessMode') == 'wallet'
             and type(value.get('pid')) is int and value['pid'] > 0, 'ENTRY_REFUSED')
        if value.get('booted') is True:
            return value['pid']
        time.sleep(.1)
    raise ProcessRefused('READINESS_TIMEOUT')


def analyze(parent, repo):
    dart, _ = sdk(parent)
    original = subprocess.Popen([str(dart), 'analyze', '--format', 'machine',
        'tool/ci/windows_debug_service_probe.dart', 'harness/app/main.dart',
        'harness/bin/harness.dart', 'test/harness/wallet_tour_test.dart',
        'harness/bin/copied_wallet_pointer.dart',
        'test/harness/copied_wallet_pointer_test.dart',
        'harness/bin/ci_copied_wallet_pointer.dart',
        'test/harness/copied_pointer_input_test.dart',
        'harness/bin/ci_wallet_reopen.dart',
        'test/harness/restored_startup_test.dart',
        'test/harness/restored_unlock_ready_test.dart',
        'test/harness/lock_view_observation_test.dart',
        'test/harness/import_selector_metrics_test.dart',
        'test/import_redesign/import_surface_test.dart',
        'harness/lock_view_observation.dart',
        'harness/home_preparation_observation.dart',
        'lib/widgets/tab_children_widgets/lock_tab_child.dart',
        'test/onboarding/welcome_drop_route_test.dart',
        'test/welcome/welcome_surface_test.dart',
        'lib/screens/onboarding/welcome_surface.dart',
        'test/welcome/support.dart',
        'harness/seed/restored_seed_workflow.dart',
        'test/harness/restored_seed_workflow_test.dart',
        'harness/app/fixtures/lab_quiescence.dart',
        'test/harness/lab_quiescence_test.dart',
        'harness/bin/build_output.dart', 'test/harness/build_output_test.dart',
        'harness/bin/ci_wallet_tour.dart', 'harness/bin/wallet_recipe.dart',
        'harness/wallet_address_context.dart',
        'test/harness/wallet_address_recipe_test.dart',
        'test/harness/addresses_selection_test.dart',
        'harness/app/fixtures/lab_transfer_witness.dart',
        'test/harness/lab_transfer_witness_test.dart',
        'harness/app/fixtures/seed_policy.dart',
        'harness/app/fixtures/seed_commands.dart',
        'harness/seed_preparation_failure.dart',
        'harness/app/fixtures/seed_project_presentation.dart',
        'harness/app/seed_project_presentation_binding.dart',
        'harness/app/fixtures/seed_token_presentation.dart',
        'harness/app/fixtures/seed_deposit_entry.dart',
        'harness/app/seed_deposit_entry_binding.dart',
        'test/harness/seed_deposit_entry_test.dart',
        'harness/app/fixtures/seed_deposit_presentation.dart',
        'harness/app/seed_deposit_presentation_binding.dart',
        'test/harness/seed_deposit_presentation_test.dart',
        'test/harness/seed_fixture_admission_test.dart',
        'harness/app/seed_token_presentation_binding.dart',
        'lib/rearchitecture/features/registration_success/registration_confirmation.dart',
        'test/harness/seed_policy_test.dart',
        'lib/widgets/modular_widgets/accelerator_widgets/accelerator_action_stepper.dart',
        'harness/app/fixtures/lab_seed_binding.dart',
        'harness/app/fixtures/lab_send_policy.dart',
        'harness/app/fixtures/lab_send_ui_binding.dart',
        'test/harness/lab_send_ui_binding_test.dart',
        'harness/lab_send_failure.dart',
        'test/harness/lab_send_failure_test.dart',
        'test/harness/lab_sender_menu_test.dart',
        'test/harness/transfer_sender_header_test.dart',
        'lib/rearchitecture/features/send/widgets/send_populated.dart',
        'test/harness/lab_send_policy_test.dart',
        'test/harness/lab_send_journal_test.dart',
        'test/harness/selection_context_revision_test.dart',
        'lib/utils/notifiers/default_address_notifier.dart',
        'lib/widgets/main_app_container.dart',
        'lib/utils/app_theme.dart',
        'lib/widgets/shell/shell_frame.dart',
        'lib/rearchitecture/features/transfer/view/transfer_page.dart',
        'test/shell/shell_frame_test.dart',
        'test/transfer/view/transfer_page_test.dart',
        'lib/rearchitecture/features/home/view/home_hero.dart',
        'lib/rearchitecture/features/home/view/home_view.dart',
        'lib/rearchitecture/utils/widgets/eye_toggle.dart',
        'test/home/home_hero_test.dart',
        'lib/widgets/modular_widgets/settings_widgets/addresses_settings_view.dart',
        'harness/app/agent.dart', 'harness/wallet_recipe_failure.dart',
        'harness/app/recipe_control_admission.dart',
        'test/harness/recipe_control_admission_test.dart',
        'test/harness/wallet_recipe_startup_test.dart',
        'test/harness/startup_key_confirm_test.dart',
        'test/harness/startup_key_refusal_test.dart',
        'test/harness/startup_key_support.dart',
        'lib/utils/entry_capture_source.dart',
        'lib/screens/onboarding/import_wallet/import_wallet_seed_choice_screen.dart',
        'harness/app/native_entry_capture.dart',
        'harness/app/entry_capture_progress.dart',
        'test/harness/entry_capture_progress_test.dart',
        'harness/app/retained_renderer_frame.dart',
        'harness/app/retained_png.dart',
        'test/harness/retained_renderer_frame_test.dart',
        'lib/utils/original_publications.dart',
        'test/publication_session/original_publications_test.dart',
        'harness/app/readonly_sdk_admission.dart',
        'test/harness/readonly_sdk_admission_test.dart',
        'harness/app/readonly_sdk_binding.dart',
        'test/harness/readonly_sdk_binding_test.dart',
        'harness/app/readonly_native_commands.dart',
        'harness/app/logical_capture.dart',
        'harness/app/readonly_shot_layout.dart',
        'test/harness/logical_capture_test.dart',
        'test/harness/readonly_native_commands_test.dart',
        'harness/app/readonly_native_mode.dart',
        'harness/app/presentation_mode.dart',
        'test/harness/readonly_native_mode_test.dart',
        'test/harness/readonly_native_agent_test.dart',
        'harness/app/readonly_wallet_admission.dart',
        'harness/app/readonly_wallet_binding.dart',
        'test/harness/readonly_wallet_admission_test.dart',
        'harness/bin/readonly_inspection_session.dart',
        'harness/bin/ci_wallet_inspection.dart',
        'test/harness/readonly_inspection_session_test.dart',
        'harness/bin/readonly_viewport_probe.dart',
        'test/harness/readonly_viewport_probe_test.dart',
        'harness/bin/screen_capture.dart',
        'test/harness/screen_capture_test.dart',
        'test/settings/display_settings_test.dart',
        'lib/utils/reference_artwork_source.dart',
        'lib/utils/wallet_maintenance_binding.dart',
        'test/wallet_maintenance/wallet_maintenance_backend_capture_test.dart',
        'test/harness/reference_artwork_owner_test.dart',
        'lib/rearchitecture/utils/widgets/entry_field.dart',
        'lib/widgets/reusable_widgets/app_lottie.dart',
        'lib/widgets/window_frame.dart',
        'test/window/window_frame_test.dart',
        'test/window/window_chrome_test.dart',
        'test/onboarding/entry_capture_source_test.dart',
        'test/onboarding/entry_capture_opt_in_test.dart',
        'test/onboarding/entry_prepared_draft_test.dart',
        'lib/widgets/reusable_widgets/launch_film.dart',
        'lib/widgets/reusable_widgets/launch_film_decoder.dart',
        'test/launch_film/launch_webp_frames_test.dart',
        'test/launch_film/launch_asset_test.dart',
        'test/launch_film/launch_decode_observation_test.dart',
        'test/harness/key_dispatch_test.dart', 'test/harness/rail_navigation_test.dart',
        'test/harness/agent_input_test.dart',
        'test/harness/wallet_recipe_failure_test.dart', 'test/harness/wallet_recipe_test.dart'],
        cwd=repo, env=parent, shell=False, stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
    lines = Lines(original.stdout)
    counts = dict(error=0, warning=0, info=0)
    locations = []
    failed = False
    deadline = time.monotonic() + 180
    try:
        while not (original.poll() is not None and lines.complete and lines.items.empty()):
            need(time.monotonic() < deadline, 'TOTAL_DEADLINE')
            raw = lines.take()
            if raw is not None:
                severity = raw.partition(b'|')[0].decode('ascii', errors='ignore').lower()
                if severity in counts:
                    counts[severity] += 1
                    fields = raw.decode('utf-8', errors='replace').rstrip('\r\n').split('|')
                    if len(fields) >= 7:
                        code, line, column = fields[2], fields[4], fields[5]
                        if (re.fullmatch(r'[A-Z][A-Z0-9_]{0,95}', code)
                                and line.isascii() and line.isdigit()
                                and column.isascii() and column.isdigit()):
                            relative = re.sub('/+', '/', fields[3].replace('\\', '/')).casefold()
                            selected = ('service_probe' if relative.endswith('/tool/ci/windows_debug_service_probe.dart')
                                        else 'harness_entry' if relative.endswith('/harness/app/main.dart')
                                        else 'home_observation' if relative.endswith('/harness/home_preparation_observation.dart')
                                        else 'harness_cli' if relative.endswith('/harness/bin/harness.dart')
                                        else 'tour_test' if relative.endswith('/test/harness/wallet_tour_test.dart')
                                        else 'copied_pointer' if relative.endswith('/harness/bin/copied_wallet_pointer.dart')
                                        else 'copied_pointer_test' if relative.endswith('/test/harness/copied_wallet_pointer_test.dart')
                                        else 'copied_pointer_ci' if relative.endswith('/harness/bin/ci_copied_wallet_pointer.dart')
                                        else 'copied_pointer_input_test' if relative.endswith('/test/harness/copied_pointer_input_test.dart')
                                        else 'wallet_reopen_ci' if relative.endswith('/harness/bin/ci_wallet_reopen.dart')
                                        else 'restored_startup_test' if relative.endswith('/test/harness/restored_startup_test.dart')
                                        else 'restored_seed' if relative.endswith('/harness/seed/restored_seed_workflow.dart')
                                        else 'restored_seed_test' if relative.endswith('/test/harness/restored_seed_workflow_test.dart')
                                        else 'lab_quiescence' if relative.endswith('/harness/app/fixtures/lab_quiescence.dart')
                                        else 'lab_quiescence_test' if relative.endswith('/test/harness/lab_quiescence_test.dart')
                                        else 'build_output' if relative.endswith('/harness/bin/build_output.dart')
                                        else 'build_output_test' if relative.endswith('/test/harness/build_output_test.dart')
                                        else 'harness_ci' if relative.endswith('/harness/bin/ci_wallet_tour.dart')
                                        else 'wallet_recipe' if relative.endswith('/harness/bin/wallet_recipe.dart')
                                        else 'address_context' if relative.endswith('/harness/wallet_address_context.dart')
                                        else 'address_recipe_test' if relative.endswith('/test/harness/wallet_address_recipe_test.dart')
                                        else 'addresses_selection_test' if relative.endswith('/test/harness/addresses_selection_test.dart')
                                        else 'transfer_witness' if relative.endswith('/harness/app/fixtures/lab_transfer_witness.dart')
                                        else 'transfer_witness_test' if relative.endswith('/test/harness/lab_transfer_witness_test.dart')
                                        else 'seed_policy' if relative.endswith('/harness/app/fixtures/seed_policy.dart')
                                        else 'seed_commands' if relative.endswith('/harness/app/fixtures/seed_commands.dart')
                                        else 'seed_preparation_failure' if relative.endswith('/harness/seed_preparation_failure.dart')
                                        else 'project_presentation' if relative.endswith('/harness/app/fixtures/seed_project_presentation.dart')
                                        else 'project_presentation_binding' if relative.endswith('/harness/app/seed_project_presentation_binding.dart')
                                        else 'deposit_entry' if relative.endswith('/harness/app/fixtures/seed_deposit_entry.dart')
                                        else 'deposit_entry_binding' if relative.endswith('/harness/app/seed_deposit_entry_binding.dart')
                                        else 'seed_deposit_entry_test' if relative.endswith('/test/harness/seed_deposit_entry_test.dart')
                                        else 'deposit_presentation' if relative.endswith('/harness/app/fixtures/seed_deposit_presentation.dart')
                                        else 'deposit_presentation_binding' if relative.endswith('/harness/app/seed_deposit_presentation_binding.dart')
                                        else 'seed_deposit_presentation_test' if relative.endswith('/test/harness/seed_deposit_presentation_test.dart')
                                        else 'seed_fixture_admission_test' if relative.endswith('/test/harness/seed_fixture_admission_test.dart')
                                        else 'token_presentation' if relative.endswith('/harness/app/fixtures/seed_token_presentation.dart')
                                        else 'token_presentation_binding' if relative.endswith('/harness/app/seed_token_presentation_binding.dart')
                                        else 'registration_confirmation' if relative.endswith('/lib/rearchitecture/features/registration_success/registration_confirmation.dart')
                                        else 'seed_policy_test' if relative.endswith('/test/harness/seed_policy_test.dart')
                                        else 'accelerator_stepper' if relative.endswith('/lib/widgets/modular_widgets/accelerator_widgets/accelerator_action_stepper.dart')
                                        else 'lab_seed_binding' if relative.endswith('/harness/app/fixtures/lab_seed_binding.dart')
                                        else 'lab_send_policy' if relative.endswith('/harness/app/fixtures/lab_send_policy.dart')
                                        else 'lab_send_ui_binding' if relative.endswith('/harness/app/fixtures/lab_send_ui_binding.dart')
                                        else 'lab_send_ui_binding_test' if relative.endswith('/test/harness/lab_send_ui_binding_test.dart')
                                        else 'lab_send_failure' if relative.endswith('/harness/lab_send_failure.dart')
                                        else 'lab_send_failure_test' if relative.endswith('/test/harness/lab_send_failure_test.dart')
                                        else 'lab_sender_menu_test' if relative.endswith('/test/harness/lab_sender_menu_test.dart')
                                        else 'transfer_sender_header_test' if relative.endswith('/test/harness/transfer_sender_header_test.dart')
                                        else 'send_form' if relative.endswith('/lib/rearchitecture/features/send/widgets/send_populated.dart')
                                        else 'lab_send_policy_test' if relative.endswith('/test/harness/lab_send_policy_test.dart')
                                        else 'lab_send_journal_test' if relative.endswith('/test/harness/lab_send_journal_test.dart')
                                        else 'selection_revision_test' if relative.endswith('/test/harness/selection_context_revision_test.dart')
                                        else 'selection_notifier' if relative.endswith('/lib/utils/notifiers/default_address_notifier.dart')
                                        else 'wallet_shell' if relative.endswith('/lib/widgets/main_app_container.dart')
                                        else 'addresses_view' if relative.endswith('/lib/widgets/modular_widgets/settings_widgets/addresses_settings_view.dart')
                                        else 'native_entry_capture' if relative.endswith('/harness/app/native_entry_capture.dart')
                                        else 'entry_capture_progress' if relative.endswith('/harness/app/entry_capture_progress.dart')
                                        else 'entry_capture_progress_test' if relative.endswith('/test/harness/entry_capture_progress_test.dart')
                                        else 'reference_artwork' if relative.endswith('/lib/utils/reference_artwork_source.dart')
                                        else 'maintenance_binding' if relative.endswith('/lib/utils/wallet_maintenance_binding.dart')
                                        else 'maintenance_backend_test' if relative.endswith('/test/wallet_maintenance/wallet_maintenance_backend_capture_test.dart')
                                        else 'reference_artwork_test' if relative.endswith('/test/harness/reference_artwork_owner_test.dart')
                                        else 'entry_field' if relative.endswith('/lib/rearchitecture/utils/widgets/entry_field.dart')
                                        else 'app_lottie' if relative.endswith('/lib/widgets/reusable_widgets/app_lottie.dart')
                                        else 'window_frame_test' if relative.endswith('/test/window/window_frame_test.dart')
                                        else 'window_chrome_test' if relative.endswith('/test/window/window_chrome_test.dart')
                                        else 'window_frame' if relative.endswith('/lib/widgets/window_frame.dart')
                                        else 'harness_agent' if relative.endswith('/harness/app/agent.dart')
                                        else 'control_admission' if relative.endswith('/harness/app/recipe_control_admission.dart')
                                        else 'control_admission_test' if relative.endswith('/test/harness/recipe_control_admission_test.dart')
                                        else 'recipe_failure' if relative.endswith('/harness/wallet_recipe_failure.dart')
                                        else 'recipe_startup_test' if relative.endswith('/test/harness/wallet_recipe_startup_test.dart')
                                        else 'startup_key_confirm_test' if relative.endswith('/test/harness/startup_key_confirm_test.dart')
                                        else 'startup_key_refusal_test' if relative.endswith('/test/harness/startup_key_refusal_test.dart')
                                        else 'startup_key_support' if relative.endswith('/test/harness/startup_key_support.dart')
                                        else 'launch_film' if relative.endswith('/lib/widgets/reusable_widgets/launch_film.dart')
                                        else 'key_dispatch_test' if relative.endswith('/test/harness/key_dispatch_test.dart')
                                        else 'agent_input_test' if relative.endswith('/test/harness/agent_input_test.dart')
                                        else 'logical_capture_test' if relative.endswith('/test/harness/logical_capture_test.dart')
                                        else 'logical_capture' if relative.endswith('/harness/app/logical_capture.dart')
                                        else 'readonly_shot_layout' if relative.endswith('/harness/app/readonly_shot_layout.dart')
                                        else 'rail_navigation_test' if relative.endswith('/test/harness/rail_navigation_test.dart')
                                        else 'recipe_failure_test' if relative.endswith('/test/harness/wallet_recipe_failure_test.dart')
                                        else 'wallet_recipe_test' if relative.endswith('/test/harness/wallet_recipe_test.dart') else 'other')
                            location = dict(source=selected, code=code,
                                            line=int(line), column=int(column))
                            if location not in locations and len(locations) < 16:
                                locations.append(location)
        code = original.wait(timeout=5)
        need(lines.finish() and type(code) is int and code == 0
             and all(value == 0 for value in counts.values()),
             'ANALYSIS_FAILED')
    except Exception:
        failed = True
        if original.poll() is None:
            original.kill()
            original.wait(timeout=10)
        lines.finish()
        raise
    finally:
        value = dict(scope='debug_probe_analysis', actual_exit=original.returncode,
                     diagnostics=counts, locations=locations, failed=failed, **lines.public())
        public = json.dumps(value, sort_keys=True, separators=(',', ':'))
        print(public)
        if len(public.encode()) <= 3800:
            print('::notice title=Windows debug analysis::' + public)
    return 0


def main(arguments=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    if arguments == ['--sdk-child']:
        return sdk_child()
    checks = dict.fromkeys(CHECKS, False)
    report = dict(schema=2, scope='ordinary_entry_debug_loop', checks=checks, errors=[],
                  success=False, debug_loop_qualified=False, wallet_qualified=False,
                  devtools_attached=False, seed_admitted=False, forced_cleanup=False,
                  required_actor_forced_cleanup=False, auxiliary_cleanup=None)
    job = original = tool = probe = frontend = None
    output = None
    try:
        need(arguments in ([], ['--analyze']), 'ENVIRONMENT_REFUSED')
        parent, expected = entry.require_ci(os.environ, None, platform=os.name)
        repo = Path(parent['GITHUB_WORKSPACE'])
        need(repo.resolve() == Path.cwd().resolve(), 'ENVIRONMENT_REFUSED')
        checks['environment'] = True
        bounded.verify_source(repo, expected, parent)
        tree = entry.source_tree(repo, parent)
        report.update(source_sha=expected, source_tree=tree,
            run_id=parent['GITHUB_RUN_ID'], run_attempt=parent['GITHUB_RUN_ATTEMPT'])
        checks['source'] = True
        if arguments == ['--analyze']:
            return analyze(parent, repo)
        output = entry.private_root(repo) / OUTPUT.name
        output.mkdir(mode=0o700)
        bounded.check_no_existing(repo, parent)
        checks['preflight'] = True
        profile = entry.private_root(repo) / ('ci-windows-debug-' + secrets.token_hex(12))
        profile.mkdir(mode=0o700)
        for name in ('AppData/Roaming', 'AppData/Local', 'Temp', 'Config', 'Data', 'Cache'):
            (profile / name).mkdir(parents=True, mode=0o700)
        checks['profile'] = True
        token = secrets.token_urlsafe(32)
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as reservation:
            reservation.bind(('127.0.0.1', 0))
            port = reservation.getsockname()[1]
        env = profile_environment(parent, profile, port, token)
        dart, _ = sdk(parent)
        job = WindowsJob()
        original = subprocess.Popen([sys.executable, '-B', str(Path(__file__).absolute()), '--sdk-child'],
            cwd=repo, env=env, shell=False, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, bufsize=0)
        job.assign(original)
        checks['job_owned'] = True
        tool = Tool(original, Lines(original.stdout))
        original.stdin.write(b'START\n')
        original.stdin.flush()
        tool.until(lambda: tool.protocol._started, 900)
        checks['tool_started'] = True
        transport = bounded.LoopbackTransport(port, 32768)
        pid = ready(tool, transport, token)
        binary = repo / bounded.BINARY
        job.bind_application(pid, binary)
        checks['application_owned'] = checks['ordinary_entry'] = True
        probe = Probe(dart, repo, env)
        probe.command('bind', tool, pid=pid, wsUri=tool.protocol._service)
        checks['service_bound'] = True
        probe.command('breakpoint', tool)
        checks['breakpoint_hit'] = True
        tool.command('app.restart', full_restart=False)
        checks['hot_reload'] = True
        probe.command('reload', tool)
        checks['reload_state_preserved'] = True
        tool.command('app.restart', full_restart=True)
        checks['hot_restart'] = True
        need(ready(tool, transport, token) == pid, 'PROCESS_REFUSED')
        probe.command('restart', tool)
        checks['restart_state_reset'] = True
        tool.until(lambda: tool.protocol._devtools is not None, 45)
        checks['devtools_available'] = True
        probe.command('close', tool)
        need(probe.original.wait(timeout=15) == 0 and probe.lines.finish(), 'PROBE_EXIT_UNCONFIRMED')
        checks['probe_closed'] = True
        frontend = Frontend(repo, env)
        job.assign(frontend.original)
        checks['frontend_job_owned'] = True
        frontend.attach(tool, pid)
        checks['frontend_attached'] = checks['frontend_exit'] = True
        report['devtools_attached'] = True
        report['close_attempted'] = True
        request_close(transport, token)
        checks['close_ack'] = True
        report['application_exit'] = job.application_exit()
        need(report['application_exit'] == 0, 'APPLICATION_EXIT_FAILED')
        checks['application_exit'] = True
        tool.until(lambda: tool.exit is not None and tool.protocol._stopped, 20)
        need(original.wait(timeout=10) == 0 and tool.exit == 0, 'TOOL_EXIT_UNCONFIRMED')
        checks['tool_exit'] = True
        checks['output_complete'] = tool.lines.finish()
        bounded.verify_source(repo, expected, parent)
        need(entry.source_tree(repo, parent) == tree, 'SOURCE_REFUSED')
        checks['source_unchanged'] = True
        report['success'] = all(checks.values())
    except (protocol.Refused, ProcessRefused, bounded.SmokeFailure) as error:
        report['errors'].append(error.code if getattr(error, 'code', None) in CODES
                                else str(error) if str(error) in CODES else 'INTERNAL_ERROR')
    except (Exception, KeyboardInterrupt):
        report['errors'].append('INTERNAL_ERROR')
    finally:
        if frontend is not None:
            if frontend.original.poll() is None:
                report['forced_cleanup'] = True
                report['required_actor_forced_cleanup'] = True
                frontend.original.kill()
                frontend.original.wait(timeout=10)
            frontend.lines.finish()
            report['frontend_output'] = frontend.lines.public()
            report['frontend_exit'] = frontend.original.returncode
            report['frontend'] = frontend.result
        if probe is not None and probe.original.poll() is None:
            report['forced_cleanup'] = True
            report['required_actor_forced_cleanup'] = True
            probe.original.kill()
            probe.original.wait(timeout=10)
        if probe is not None:
            probe.lines.finish()
            report['probe_output'] = probe.lines.public()
            report['probe_exit'] = probe.original.returncode
            report['probe_failure'] = probe.failure
        if job is not None:
            if original is not None:
                report['bootstrap_exit'] = original.poll()
            if tool is not None:
                report['tool_output'] = tool.lines.public()
                report['tool_exit'] = tool.exit
                report['protocol'] = tool.protocol.public()
            try:
                report['owned_job_images_before_close'] = job.remaining_images()
            except Exception:
                report['owned_job_images_before_close'] = dict(
                    status='UNKNOWN', listed=0, observed=0, counts={})
            if required_actors_complete(report):
                cleanup = job.finish_known_helpers(dart, lambda: compiler_telemetry_image(repo))
                report['auxiliary_cleanup'] = cleanup
                report['forced_cleanup'] |= cleanup['forced']
                if not helper_cleanup_complete(cleanup):
                    report['errors'].append(cleanup['code'] if cleanup['code'] in CODES
                                             else 'HELPER_CLOSE_UNCONFIRMED')
            job.close()
            report['forced_cleanup'] |= job.forced
            report['required_actor_forced_cleanup'] |= job.forced
            report['owned_job_active_at_close'] = job.active_at_close
        if original is not None:
            if original.poll() is None:
                report['forced_cleanup'] = True
                report['required_actor_forced_cleanup'] = True
                original.kill()
            original.wait(timeout=10)
            report['bootstrap_exit'] = original.returncode
        if tool is not None:
            tool.lines.finish()
            report['tool_output'] = tool.lines.public()
            report['tool_exit'] = tool.exit
            report['protocol'] = tool.protocol.public()
        report['success'] = report['debug_loop_qualified'] = debug_complete(report)
        if output is not None:
            target = output / 'manifest.json'
            with target.open('x', encoding='utf-8') as stream:
                json.dump(report, stream, sort_keys=True, separators=(',', ':'))
                stream.write('\n')
    if arguments != ['--analyze']:
        public = json.dumps(report, sort_keys=True, separators=(',', ':'))
        print(public)
        if len(public.encode()) <= 3800:
            print('::notice title=Windows debug outcome::' + public)
    return 0 if report['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
