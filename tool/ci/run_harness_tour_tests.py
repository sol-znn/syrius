"""Bound startup probes and isolated harness tests before wallet allocation."""

import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import time

try:
    from . import dart_test_failure, font_metrics_observation, welcome_trim_metrics
    from . import welcome_path_metrics
    from . import windows_debug_loop as debug
    from .windows_baseline import fresh_environment, run_bounded, test_counts
except ImportError:
    import dart_test_failure
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


def main():
    font_observation = None
    caption_observation = None
    trim_observation = None
    path_observation = None
    report = dict(schema=1, scope='wallet_tour_controller_tests', success=False,
                  wallet_qualified=False, native_wallet_executions=0, counts=None,
                  command=None, entry_refusal=None, inspection_entry_refusal=None,
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
        outcome = run_bounded([str(dart), '--packages=' + str(packages), str(snapshot),
            'test', '--no-pub', '--reporter', 'json', '--concurrency=1',
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
            'test/harness/selection_context_revision_test.dart',
            'test/harness/wallet_recipe_test.dart',
            *(['test/launch_film/launch_asset_test.dart'] if asset_fidelity else [])], cwd=repo,
            env=fresh_environment(repo, parent), timeout=240, cap=4 * 1024**2)
        report['command'] = dict(**outcome.public(),
            output_sha256=hashlib.sha256(outcome.output).hexdigest())
        if not outcome.success:
            report['test_failures'] = dart_test_failure.project(outcome.output)
        font_observation = font_metrics_observation.project(
            outcome.output, complete=outcome.transport_complete)
        if font_observation is not None:
            font_observation.update(source_sha=source, source_tree=tree,
                run_id=parent['GITHUB_RUN_ID'],
                run_attempt=parent['GITHUB_RUN_ATTEMPT'],
                test_output_sha256=hashlib.sha256(outcome.output).hexdigest())
        caption_observation = font_metrics_observation.project_caption(
            outcome.output, complete=outcome.transport_complete)
        if caption_observation is not None:
            caption_observation.update(source_sha=source, source_tree=tree,
                run_id=parent['GITHUB_RUN_ID'],
                run_attempt=parent['GITHUB_RUN_ATTEMPT'],
                test_output_sha256=hashlib.sha256(outcome.output).hexdigest())
        trim_observation = welcome_trim_metrics.project(
            outcome.output, complete=outcome.transport_complete)
        if trim_observation is not None:
            trim_observation.update(source_sha=source, source_tree=tree,
                run_id=parent['GITHUB_RUN_ID'],
                run_attempt=parent['GITHUB_RUN_ATTEMPT'],
                test_output_sha256=hashlib.sha256(outcome.output).hexdigest())
        path_observation = welcome_path_metrics.project(
            outcome.output, complete=outcome.transport_complete)
        if path_observation is not None:
            path_observation.update(source_sha=source, source_tree=tree,
                run_id=parent['GITHUB_RUN_ID'],
                run_attempt=parent['GITHUB_RUN_ATTEMPT'],
                test_output_sha256=hashlib.sha256(outcome.output).hexdigest())
        debug.need(outcome.transport_complete, 'OUTPUT_REFUSED')
        counts = test_counts(outcome.output)
        report['counts'] = counts
        debug.need(outcome.success and counts['terminal_success'] is True
            and counts['passed'] == (779 if asset_fidelity else 777)
            and counts['skipped'] == counts['failed'] == counts['error_events'] == 0,
            'TESTS_FAILED')
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
    public = json.dumps(report, sort_keys=True, separators=(',', ':'))
    print(public)
    if len(public.encode()) <= 3800:
        print('::notice title=Wallet tour controller tests::' + public)
    if font_observation is not None:
        observation = json.dumps(font_observation, sort_keys=True, separators=(',', ':'))
        if len(observation.encode('ascii')) <= 3800:
            print('::notice title=Bundled interface font metrics::' + observation)
    if caption_observation is not None:
        observation = json.dumps(caption_observation, sort_keys=True, separators=(',', ':'))
        if len(observation.encode('ascii')) <= 3800:
            print('::notice title=Caption wordmark engine metrics::' + observation)

    if trim_observation is not None:
        observation = json.dumps(trim_observation, sort_keys=True, separators=(',', ':'))
        if len(observation.encode('ascii')) <= 3800:
            print('::notice title=Original Welcome trim metrics::' + observation)
    if path_observation is not None:
        observation = json.dumps(path_observation, sort_keys=True, separators=(',', ':'))
        if len(observation.encode('ascii')) <= 3800:
            print('::notice title=Original Welcome path metrics::' + observation)
    return 0 if report['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
