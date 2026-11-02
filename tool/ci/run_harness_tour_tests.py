"""Bound startup probes and isolated harness tests before wallet allocation."""

import hashlib
import json
import os
import re
from pathlib import Path
import secrets
import subprocess
import time

try:
    from . import dart_test_failure, dart_test_progress
    from . import font_metrics_observation, welcome_trim_metrics
    from . import welcome_path_metrics
    from . import windows_debug_loop as debug
    from .windows_baseline import fresh_environment, run_bounded, test_counts
except ImportError:
    import dart_test_failure
    import dart_test_progress
    import font_metrics_observation
    import welcome_trim_metrics
    import welcome_path_metrics
    import windows_debug_loop as debug
    from windows_baseline import fresh_environment, run_bounded, test_counts


def startup_check(repo, parent, dart, kind):
    debug.need(kind in ('gate', 'sdk', 'inspection'), 'TESTS_FAILED')
    value = dict(kind=kind, passed=False, gate_seen=False, marker_seen=False,
        actual_exit=None, stdin_open_at_exit=False, forced_cleanup=False,
        owned_job_active_at_close=None, output=None, code=None)
    job = original = lines = None
    try:
        env = fresh_environment(repo, parent)
        inspection = kind == 'inspection'
        prefix = b'CI_INSPECT_' if inspection else b'CI_WALLET_'
        name = ('ci-inspect-' if inspection else 'ci-wallet-') + secrets.token_hex(12)
        home, app = repo / '.harness' / name, repo / '.harness/app'
        debug.need(not any(path.exists() or path.is_symlink() for path in (home, app)),
                   'PROFILE_REFUSED')
        if inspection:
            env.pop('SYRIUS_CI_WALLET_TOUR', None)
            env.update(SYRIUS_CI_WALLET_INSPECTION='true', SYRIUS_CI_INSPECTION_INSTANCE=name,
                       SYRIUS_CI_INSPECTION_CHECK='gate')
        else:
            env.update(SYRIUS_CI_WALLET_TOUR='true', SYRIUS_CI_WALLET_INSTANCE=name,
                       SYRIUS_CI_WALLET_CHECK=kind)
        job = debug.WindowsJob()
        original = subprocess.Popen([str(dart), '--disable-dart-dev',
            '--packages=' + str(repo / '.dart_tool/package_config.json'),
            'harness/bin/ci_wallet_inspection.dart' if inspection else
                'harness/bin/ci_wallet_tour.dart'], cwd=repo, env=env, shell=False,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
        job.assign(original)
        lines = debug.Lines(original.stdout)
        deadline = time.monotonic() + 30
        original.stdin.write(b'START\n')
        original.stdin.flush()
        expected = prefix + (b'GATE' if inspection else kind.upper().encode('ascii')) + b'_PASSED'
        while original.poll() is None or not lines.complete or not lines.items.empty():
            debug.need(time.monotonic() < deadline, 'READINESS_TIMEOUT')
            raw = lines.take(.05)
            if raw is None:
                continue
            line = raw.rstrip(b'\r\n')
            if line == prefix + b'STAGE:gate':
                debug.need(not value['gate_seen'], 'ENTRY_REFUSED')
                value['gate_seen'] = True
            elif line == expected:
                debug.need(value['gate_seen'] and not value['marker_seen'], 'ENTRY_REFUSED')
                value['marker_seen'] = True
            elif line.startswith((b'CI_WALLET_', b'CI_INSPECT_')):
                raise debug.ProcessRefused('ENTRY_REFUSED')
        # The same open controller input is used by the real private-input gate.
        value['stdin_open_at_exit'] = not original.stdin.closed
        debug.need(original.wait(timeout=1) == 0 and lines.finish(), 'OUTPUT_REFUSED')
        debug.need(not any(path.exists() or path.is_symlink() for path in (home, app)),
                   'PROFILE_REFUSED')
    except (Exception, KeyboardInterrupt) as error:
        code = getattr(error, 'code', None)
        value['code'] = code if code in debug.CODES else 'INTERNAL_ERROR'
    finally:
        if job is not None:
            value['remaining_images_before_close'] = job.remaining_images()
            job.close()
            value['owned_job_active_at_close'] = job.active_at_close
            value['forced_cleanup'] = job.forced
        if original is not None:
            if original.poll() is None:
                # The original can remain unassigned only before START release.
                value['forced_cleanup'] = True
                original.kill()
            try:
                value['actual_exit'] = original.wait(timeout=10)
            except subprocess.TimeoutExpired:
                value['code'] = 'TOOL_EXIT_UNCONFIRMED'
            original.stdin.close()
        if lines is not None:
            lines.finish()
            value['output'] = lines.public()
    value['passed'] = (value['code'] is None and value['gate_seen']
        and value['marker_seen'] and value['stdin_open_at_exit']
        and type(value['actual_exit']) is int and value['actual_exit'] == 0
        and type(value['owned_job_active_at_close']) is int
        and value['owned_job_active_at_close'] == 0 and not value['forced_cleanup']
        and value['output'] is not None and value['output']['output_complete']
        and not value['output']['overflow'])
    return value


def selected_groups(paths):
    """Keep the complete ordered selection in two nonempty serial groups."""
    debug.need(type(paths) is list and 2 <= len(paths) <= 256 and
        all(type(path) is str and re.fullmatch(
            r'test/(?:[A-Za-z0-9_]+/)*[A-Za-z0-9_]+_test[.]dart', path)
            for path in paths) and len(set(paths)) == len(paths), 'SOURCE_REFUSED')
    middle = (len(paths) + 1) // 2
    return [paths[:middle], paths[middle:]]


def valid_group_counts(row):
    """Require actual normal process completion and every terminal test gate."""
    command, counts = row.get('command'), row.get('counts')
    debug.need(type(command) is dict and type(counts) is dict, 'TESTS_FAILED')
    debug.need(command.get('success') is True and
        type(command.get('exit_code')) is int and command['exit_code'] == 0 and
        command.get('exit_observed') is True and command.get('forced_kill') is False and
        command.get('output_complete') is True and command.get('output_overflow') is False and
        command.get('error_codes') == [] and
        type(command.get('seconds')) in (int, float) and 0 <= command['seconds'] <= 240 and
        type(command.get('output_bytes')) is int and 0 < command['output_bytes'] <= 4 * 1024**2 and
        type(command.get('output_sha256')) is str and
        re.fullmatch('[a-f0-9]{64}', command['output_sha256']), 'TESTS_FAILED')
    keys = ('passed', 'failed', 'skipped', 'hidden', 'terminal_events', 'error_events')
    debug.need(all(type(counts.get(key)) is int and 0 <= counts[key] <= 20000
        for key in keys) and counts.get('terminal_success') is True and
        counts['passed'] > 0 and counts['failed'] == counts['skipped'] ==
        counts['error_events'] == 0 and counts['terminal_events'] ==
        counts['passed'] + counts['hidden'], 'TESTS_FAILED')
    return counts


def combined_counts(rows, paths):
    """Admit neither an incomplete group nor a replayed stream as the whole suite."""
    groups = selected_groups(paths)
    debug.need(type(rows) is list and len(rows) == len(groups) == 2, 'TESTS_FAILED')
    keys = ('passed', 'failed', 'skipped', 'hidden', 'terminal_events', 'error_events')
    result = dict.fromkeys(keys, 0)
    seen, first = set(), 1
    for index, (row, group) in enumerate(zip(rows, groups), 1):
        debug.need(type(row) is dict and type(row.get('index')) is int and
            row['index'] == index and type(row.get('first_suite_index')) is int and
            row['first_suite_index'] == first and type(row.get('selected_suites')) is int and
            row['selected_suites'] == len(group) and row.get('status') == 'SUCCESS',
            'TESTS_FAILED')
        counts = valid_group_counts(row)
        digest = row['command']['output_sha256']
        debug.need(digest not in seen, 'TEST_EVENTS_INVALID')
        seen.add(digest)
        for key in keys:
            result[key] += counts[key]
        first += len(group)
    result['terminal_success'] = True
    return result


def main():
    metric_observations = []
    progress_observations = []
    report = dict(schema=2, scope='wallet_tour_controller_tests', success=False,
                  wallet_qualified=False, native_wallet_executions=0, counts=None,
                  commands=[], groups_expected=2, worker_count=1,
                  command_limit_seconds=240, total_command_limit_seconds=480,
                  command_output_cap=4 * 1024**2,
                  entry_refusal=None, inspection_entry_refusal=None,
                  startup_checks=[], code=None)
    try:
        parent, source = debug.entry.require_ci(os.environ, None, platform=os.name)
        asset_fidelity = parent.get('SYRIUS_STARTUP_ASSET_FIDELITY') == 'true'
        debug.need(not asset_fidelity or
            parent.get('SYRIUS_WINDOWS_STARTUP_PROBE') == 'true', 'ENVIRONMENT_REFUSED')
        repo = Path(parent['GITHUB_WORKSPACE'])
        debug.need(repo.resolve() == Path.cwd().resolve(), 'ENVIRONMENT_REFUSED')
        debug.bounded.verify_source(repo, source, parent)
        tree = debug.entry.source_tree(repo, parent)
        report.update(source_sha=source, source_tree=tree,
                      run_id=parent['GITHUB_RUN_ID'], run_attempt=parent['GITHUB_RUN_ATTEMPT'])
        dart, snapshot = debug.sdk(parent)
        app = repo / '.harness/app'
        debug.need(not app.exists(), 'PROFILE_REFUSED')
        refused = run_bounded([str(dart), '--disable-dart-dev',
            '--packages=' + str(repo / '.dart_tool/package_config.json'),
            'harness/bin/ci_wallet_tour.dart'], cwd=repo,
            env=fresh_environment(repo, parent), timeout=30, cap=65536)
        report['entry_refusal'] = dict(**refused.public(),
            output_sha256=hashlib.sha256(refused.output).hexdigest(),
            refused_before_build=(not app.exists() and refused.exit_code == 1
                and refused.transport_complete
                and refused.output.replace(b'\r\n', b'\n') == b'CI_WALLET_ERROR\n'))
        debug.need(report['entry_refusal']['refused_before_build'], 'TESTS_FAILED')
        inspection_refused = run_bounded([str(dart), '--disable-dart-dev',
            '--packages=' + str(repo / '.dart_tool/package_config.json'),
            'harness/bin/ci_wallet_inspection.dart'], cwd=repo,
            env=fresh_environment(repo, parent), timeout=30, cap=65536)
        report['inspection_entry_refusal'] = dict(**inspection_refused.public(),
            output_sha256=hashlib.sha256(inspection_refused.output).hexdigest(),
            refused_before_build=(not app.exists() and inspection_refused.exit_code == 1
                and inspection_refused.transport_complete
                and inspection_refused.output.replace(b'\r\n', b'\n') == b'CI_INSPECT_ERROR\n'))
        debug.need(report['inspection_entry_refusal']['refused_before_build'], 'TESTS_FAILED')
        for kind in ('gate', 'sdk', 'inspection'):
            check = startup_check(repo, parent, dart, kind)
            report['startup_checks'].append(check)
            debug.need(check['passed'], 'TESTS_FAILED')
        packages = Path(parent['FLUTTER_ROOT']) / 'packages/flutter_tools/.dart_tool/package_config.json'
        selected_tests = [
            'test/harness/wallet_tour_test.dart', 'test/harness/build_output_test.dart',
            'test/harness/agent_input_test.dart',
            'test/harness/logical_capture_test.dart',
            'test/harness/copied_wallet_pointer_test.dart',
            'test/harness/copied_pointer_input_test.dart',
            'test/harness/restored_startup_test.dart',
            'test/harness/restored_unlock_ready_test.dart',
            'test/harness/lock_view_observation_test.dart',
            'test/harness/reference_artwork_owner_test.dart',
            'test/window/window_frame_test.dart',
            'test/window/window_chrome_test.dart',
            'test/shell/shell_frame_test.dart',
            'test/transfer/view/transfer_page_test.dart',
            'test/home/home_hero_test.dart',
            'test/go_to_palette/go_to_palette_test.dart',
            'test/harness/entry_capture_progress_test.dart',
            'test/publication_session/original_publications_test.dart',
            'test/harness/readonly_sdk_admission_test.dart',
            'test/harness/readonly_sdk_binding_test.dart',
            'test/harness/readonly_native_commands_test.dart',
            'test/harness/readonly_native_mode_test.dart',
            'test/harness/readonly_native_agent_test.dart',
            'test/harness/readonly_wallet_admission_test.dart',
            'test/harness/readonly_inspection_session_test.dart',
            'test/harness/readonly_viewport_probe_test.dart',
            'test/harness/screen_capture_test.dart',
            'test/settings/display_settings_test.dart',
            'test/harness/retained_renderer_frame_test.dart',
            'test/wallet_maintenance/wallet_maintenance_backend_capture_test.dart',
            'test/harness/import_selector_metrics_test.dart',
            'test/import_redesign/import_surface_test.dart',
            'test/staking/view/staking_page_test.dart',
            'test/staking/view/create_stake_card_test.dart',
            'test/harness/restored_seed_workflow_test.dart',
            'test/harness/lab_quiescence_test.dart',
            'test/harness/wallet_recipe_failure_test.dart',
            'test/harness/recipe_control_admission_test.dart',
            'test/harness/wallet_recipe_startup_test.dart',
            'test/harness/startup_key_confirm_test.dart',
            'test/harness/startup_key_refusal_test.dart',
            'test/launch_film/launch_film_test.dart',
            'test/launch_film/launch_decode_observation_test.dart',
            'test/launch_film/launch_webp_frames_test.dart',
            'test/onboarding/entry_capture_source_test.dart',
            'test/onboarding/entry_capture_opt_in_test.dart',
            'test/onboarding/entry_prepared_draft_test.dart',
            'test/onboarding/welcome_drop_route_test.dart',
            'test/welcome/welcome_surface_test.dart',
            'test/harness/key_dispatch_test.dart',
            'test/harness/rail_navigation_test.dart',
            'test/harness/wallet_address_recipe_test.dart',
            'test/harness/addresses_selection_test.dart',
            'test/harness/lab_transfer_witness_test.dart',
            'test/harness/seed_policy_test.dart',
            'test/harness/seed_deposit_entry_test.dart',
            'test/harness/seed_deposit_presentation_test.dart',
            'test/harness/seed_fixture_admission_test.dart',
            'test/harness/lab_send_policy_test.dart',
            'test/harness/lab_send_journal_test.dart',
            'test/harness/lab_send_ui_binding_test.dart',
            'test/harness/lab_send_failure_test.dart',
            'test/harness/lab_sender_menu_test.dart',
            'test/harness/transfer_sender_header_test.dart',
            'test/receive/receive_populated_test.dart',
            'test/harness/selection_context_revision_test.dart',
            'test/harness/wallet_recipe_test.dart',
            *(['test/launch_film/launch_asset_test.dart'] if asset_fidelity else [])
        ]
        first = 1
        for index, group in enumerate(selected_groups(selected_tests), 1):
            row = dict(index=index, first_suite_index=first,
                       selected_suites=len(group), status='UNKNOWN', command=None, counts=None)
            report['commands'].append(row)
            outcome = run_bounded([str(dart), '--packages=' + str(packages), str(snapshot),
                'test', '--no-pub', '--reporter', 'json', '--concurrency=1', *group],
                cwd=repo, env=fresh_environment(repo, parent), timeout=240, cap=4 * 1024**2)
            row['command'] = dict(**outcome.public(),
                output_sha256=hashlib.sha256(outcome.output).hexdigest())
            row['status'] = 'FAILURE'
            metadata = dict(source_sha=source, source_tree=tree,
                run_id=parent['GITHUB_RUN_ID'], run_attempt=parent['GITHUB_RUN_ATTEMPT'],
                test_output_sha256=hashlib.sha256(outcome.output).hexdigest(), group_index=index)
            observed = dart_test_progress.project(outcome.output,
                suite_paths=selected_tests, repo=str(repo))
            observed.update(metadata, transport_complete=outcome.transport_complete)
            progress_observations.append(observed)
            for observe in (font_metrics_observation.project,
                            font_metrics_observation.project_caption,
                            welcome_trim_metrics.project, welcome_path_metrics.project):
                metric = observe(outcome.output, complete=outcome.transport_complete)
                if metric is not None:
                    metric.update(metadata)
                    metric_observations.append(metric)
            if not outcome.success:
                report['test_failures'] = dart_test_failure.project(outcome.output)
                report['failed_group'] = index
            debug.need(outcome.transport_complete, 'OUTPUT_REFUSED')
            row['counts'] = test_counts(outcome.output)
            valid_group_counts(row)
            row['status'] = 'SUCCESS'
            if index == 1:
                debug.bounded.verify_source(repo, source, parent)
                debug.need(debug.entry.source_tree(repo, parent) == tree, 'SOURCE_REFUSED')
            first += len(group)
        counts = combined_counts(report['commands'], selected_tests)
        debug.need(counts['passed'] == (819 if asset_fidelity else 817), 'TESTS_FAILED')
        report['counts'] = counts
        if asset_fidelity:
            report['launch_asset_fidelity'] = True
        debug.bounded.verify_source(repo, source, parent)
        debug.need(debug.entry.source_tree(repo, parent) == tree, 'SOURCE_REFUSED')
        report['success'] = True
    except (Exception, KeyboardInterrupt) as error:
        known = {'ENVIRONMENT_REFUSED', 'SOURCE_REFUSED', 'PROFILE_REFUSED',
                 'TOOL_REFUSED', 'OUTPUT_REFUSED', 'TESTS_FAILED', 'TEST_EVENTS_INVALID'}
        code = getattr(error, 'code', None) or str(error)
        report['code'] = code if code in known else 'INTERNAL_ERROR'
    eligible_metrics = []
    for metric in metric_observations:
        encoded = json.dumps(metric, sort_keys=True, separators=(',', ':'))
        if len(encoded.encode('ascii')) <= 3800:
            eligible_metrics.append(encoded)
    budget = 10 - 1 - len(progress_observations)
    report['metrics_without_notice'] = max(0, len(eligible_metrics) - budget)
    public = json.dumps(report, sort_keys=True, separators=(',', ':'))
    print(public)
    if len(public.encode()) <= 3800:
        print('::notice title=Wallet tour controller tests::' + public)
    for observed in progress_observations:
        encoded = json.dumps(observed, sort_keys=True, separators=(',', ':'))
        if len(encoded.encode('ascii')) <= 3800:
            print('::notice title=Selected test progress::' + encoded)
    for index, encoded in enumerate(eligible_metrics):
        # Every closed metric remains in the job log. Keep notices within
        # the per-step annotation budget without discarding test outcomes.
        print(encoded)
        if index < budget:
            print('::notice title=Original grouped test metrics::' + encoded)
    return 0 if report['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
