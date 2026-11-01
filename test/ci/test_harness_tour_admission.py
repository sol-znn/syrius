"""Exercise the real admission controller without SDK or native execution."""

import contextlib
import io
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest import mock

from tool.ci import run_harness_tour_tests as harness


class HarnessAdmissionTests(unittest.TestCase):
    def run_case(self, *, passed=778, terminal=True, skipped=0, failed=0,
                 error_events=0, command_success=True, complete=True,
                 source_changed=False, asset_fidelity=False):
        parent = dict(GITHUB_WORKSPACE=str(Path.cwd()), FLUTTER_ROOT='/sdk',
                      GITHUB_RUN_ID='1', GITHUB_RUN_ATTEMPT='1')
        if asset_fidelity:
            parent.update(SYRIUS_STARTUP_ASSET_FIDELITY='true',
                          SYRIUS_WINDOWS_STARTUP_PROBE='true')
        counts = dict(passed=passed, failed=failed, skipped=skipped, hidden=28,
                      error_events=error_events,
                      terminal_events=passed + skipped + failed + 28,
                      terminal_success=terminal)
        refused = SimpleNamespace(output=b'CI_WALLET_ERROR\n', exit_code=1,
                                  transport_complete=True, public=lambda: {})
        inspection_refused = SimpleNamespace(output=b'CI_INSPECT_ERROR\n', exit_code=1,
                                  transport_complete=True, public=lambda: {})
        outcome = SimpleNamespace(output=b'{}\n', success=command_success,
            transport_complete=complete, public=lambda: dict(
                exit_code=0 if command_success else 1,
                output_complete=complete, success=command_success))
        trees = ['b' * 40, ('c' if source_changed else 'b') * 40]
        with mock.patch.object(harness.debug.entry, 'require_ci',
                return_value=(parent, 'a' * 40)),\
                mock.patch.object(harness.debug.bounded, 'verify_source') as source,\
                mock.patch.object(harness.debug.entry, 'source_tree',
                    side_effect=trees) as tree,\
                mock.patch.object(harness.debug, 'sdk',
                    return_value=(Path('/sdk/dart'), Path('/sdk/snapshot'))),\
                mock.patch.object(Path, 'exists', return_value=False),\
                mock.patch.object(harness, 'fresh_environment', return_value={}),\
                mock.patch.object(harness, 'startup_check',
                    side_effect=lambda _repo, _parent, _dart, kind:
                        dict(kind=kind, passed=True)),\
                mock.patch.object(harness, 'run_bounded',
                    side_effect=[refused, inspection_refused, outcome]) as command,\
                mock.patch.object(harness, 'test_counts', return_value=counts),\
                mock.patch.object(harness.subprocess, 'Popen',
                    side_effect=AssertionError('Native execution forbidden')),\
                contextlib.redirect_stdout(io.StringIO()) as output:
            code = harness.main()
        report = json.loads(output.getvalue().splitlines()[0])
        self.assertEqual(command.call_count, 3)
        self.command_argv = command.call_args.args[0]
        return code, report, source.call_count, tree.call_count

    def test_complete_current_suite_is_admitted_then_source_is_revalidated(self):
        code, report, source_checks, tree_checks = self.run_case()
        self.assertEqual(code, 0)
        self.assertTrue(report['success'])
        self.assertIsNone(report['code'])
        self.assertEqual(report['counts']['passed'], 778)
        self.assertTrue(report['entry_refusal']['refused_before_build'])
        self.assertTrue(report['inspection_entry_refusal']['refused_before_build'])
        self.assertEqual([value['kind'] for value in report['startup_checks']],
                         ['gate', 'sdk', 'inspection'])
        self.assertEqual((source_checks, tree_checks), (2, 2))

    def test_stale_short_or_extra_suite_counts_are_refused(self):
        for passed in (0, 184, 196, 216, 218, 220, 221, 222, 227, 228, 229, 245, 246, 247, 254, 255, 262, 263, 264, 265, 266, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 360, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 375, 376, 377, 378, 387, 388, 389, 390, 391, 392, 393, 399, 400, 401, 402, 405, 407, 408, 409, 410, 412, 413, 414, 415, 416, 417, 418, 419, 448, 449, 450, 451, 461, 462, 463, 464, 473, 476, 477, 487, 488, 489, 490, 502, 503, 504, 505, 507, 508, 509, 510, 513, 514, 516, 517, 515, 518, 519, 520, 522, 527, 529, 530, 531, 693, 694, 695, 696, 713, 715, 716, 718, 721, 723, 725, 722, 724, 745, 747, 749, 746, 748, 751, 750, 752, 753, 754, 777, 779):
            if passed == 778:
                continue
            with self.subTest(passed=passed):
                code, report, source_checks, tree_checks = self.run_case(
                    passed=passed)
                self.assertEqual(code, 1)
                self.assertFalse(report['success'])
                self.assertEqual(report['code'], 'TESTS_FAILED')
                self.assertEqual((source_checks, tree_checks), (1, 1))

    def test_original_and_prepared_entry_policies_are_in_the_actual_sdk_command(self):
        code, _, _, _ = self.run_case()
        self.assertEqual(code, 0)
        for path in ('test/onboarding/entry_capture_source_test.dart',
                     'test/onboarding/entry_capture_opt_in_test.dart',
                     'test/onboarding/entry_prepared_draft_test.dart',
                     'test/harness/reference_artwork_owner_test.dart',
                     'test/window/window_frame_test.dart',
                     'test/window/window_chrome_test.dart',
                     'test/shell/shell_frame_test.dart',
                     'test/transfer/view/transfer_page_test.dart',
                     'test/import_redesign/import_surface_test.dart',
                     'test/staking/view/staking_page_test.dart',
                     'test/staking/view/create_stake_card_test.dart',
                     'test/harness/entry_capture_progress_test.dart',
                     'test/harness/retained_renderer_frame_test.dart',
                     'test/wallet_maintenance/wallet_maintenance_backend_capture_test.dart'):
            self.assertEqual(self.command_argv.count(path), 1)
        self.assertIn('test/harness/wallet_recipe_test.dart', self.command_argv)
        self.assertIn('test/launch_film/launch_film_test.dart', self.command_argv)
        self.assertEqual(self.command_argv.count(
            'test/launch_film/launch_decode_observation_test.dart'), 1)
        self.assertEqual(self.command_argv.count(
            'test/launch_film/launch_webp_frames_test.dart'), 1)
        self.assertIn('--concurrency=1', self.command_argv)
        self.assertEqual(self.command_argv.count(
            'test/harness/agent_input_test.dart'), 1)
        self.assertEqual(self.command_argv.count(
            'test/harness/logical_capture_test.dart'), 1)
        self.assertEqual(self.command_argv.count(
            'test/harness/restored_unlock_ready_test.dart'), 1)
        self.assertEqual(self.command_argv.count(
            'test/onboarding/welcome_drop_route_test.dart'), 1)
        code, report, _, _ = self.run_case(passed=780, asset_fidelity=True)
        self.assertEqual(code, 0)
        self.assertTrue(report['launch_asset_fidelity'])
        self.assertEqual(self.command_argv.count(
            'test/launch_film/launch_asset_test.dart'), 1)
        for passed in (290, 292, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 376, 377, 378, 379, 388, 389, 390, 391, 392, 393, 394, 400, 401, 402, 403, 408, 409, 410, 411, 413, 414, 415, 416, 417, 418, 419, 420, 449, 450, 451, 452, 462, 463, 464, 465, 473, 476, 478, 488, 489, 490, 491, 503, 504, 505, 506, 507, 508, 509, 510, 511, 514, 515, 516, 518, 517, 520, 522, 528, 529, 531, 722, 724, 723, 725, 745, 747, 749, 746, 748, 751, 750, 752, 753, 754, 777, 779):
            code, report, _, _ = self.run_case(
                passed=passed, asset_fidelity=True)
            self.assertEqual(code, 1)
            self.assertFalse(report['success'])

    def test_deposit_and_complete_fixture_selection_cannot_borrow_old_counts(self):
        for fidelity, passed in ((False, 778), (True, 780)):
            with self.subTest(fidelity=fidelity):
                code, report, source, tree = self.run_case(
                    passed=passed, asset_fidelity=fidelity)
                self.assertEqual(code, 0)
                self.assertTrue(report['success'])
                self.assertEqual((source, tree), (2, 2))
                for path in ('test/harness/seed_deposit_entry_test.dart',
                             'test/harness/seed_fixture_admission_test.dart'):
                    self.assertEqual(self.command_argv.count(path), 1)
            for earlier in (462, 464, 473, 476, 478, 746, 748, 750, 752, 751, 753, 754, 777, 779):
                if earlier == passed:
                    continue
                with self.subTest(fidelity=fidelity, earlier=earlier):
                    code, report, source, tree = self.run_case(
                        passed=earlier, asset_fidelity=fidelity)
                    self.assertEqual(code, 1)
                    self.assertFalse(report['success'])
                    self.assertEqual(report['code'], 'TESTS_FAILED')
                    self.assertEqual((source, tree), (1, 1))

    def test_deposit_exit_selection_and_exact_profile_counts_are_bound(self):
        for fidelity, passed in ((False, 778), (True, 780)):
            code, report, source, tree = self.run_case(
                passed=passed, asset_fidelity=fidelity)
            self.assertEqual(code, 0)
            self.assertTrue(report['success'])
            self.assertEqual((source, tree), (2, 2))
            self.assertEqual(self.command_argv.count(
                'test/harness/seed_deposit_presentation_test.dart'), 1)
            for earlier in (488, 490, 502, 503, 504, 505, 507, 508, 509, 510, 513, 514, 515, 516, 517, 518, 746, 748, 750, 752, 751, 753, 754, 777, 779):
                if earlier == passed:
                    continue
                code, report, source, tree = self.run_case(
                    passed=earlier, asset_fidelity=fidelity)
                self.assertEqual(code, 1)
                self.assertFalse(report['success'])
                self.assertEqual((source, tree), (1, 1))

    def test_skips_errors_failures_or_missing_terminal_success_refuse(self):
        for change in (dict(skipped=1), dict(failed=1), dict(error_events=1),
                       dict(terminal=False)):
            with self.subTest(change=change):
                code, report, source_checks, _ = self.run_case(**change)
                self.assertEqual(code, 1)
                self.assertFalse(report['success'])
                self.assertEqual(report['code'], 'TESTS_FAILED')
                self.assertEqual(source_checks, 1)

    def test_original_process_failure_or_incomplete_output_cannot_be_admitted(self):
        for change, expected in ((dict(command_success=False), 'TESTS_FAILED'),
                                 (dict(complete=False), 'OUTPUT_REFUSED')):
            with self.subTest(change=change):
                code, report, source_checks, _ = self.run_case(**change)
                self.assertEqual(code, 1)
                self.assertFalse(report['success'])
                self.assertEqual(report['code'], expected)
                self.assertEqual(source_checks, 1)

    def test_passing_current_suite_cannot_hide_changed_source(self):
        code, report, source_checks, tree_checks = self.run_case(source_changed=True)
        self.assertEqual(code, 1)
        self.assertFalse(report['success'])
        self.assertEqual(report['code'], 'SOURCE_REFUSED')
        self.assertEqual((source_checks, tree_checks), (2, 2))

    def test_paused_owner_observations_are_in_both_exact_sdk_selections(self):
        paths = ('test/publication_session/original_publications_test.dart',
                 'test/harness/readonly_sdk_admission_test.dart',
                 'test/harness/readonly_sdk_binding_test.dart',
                 'test/harness/readonly_native_commands_test.dart')
        for fidelity, passed in ((False, 778), (True, 780)):
            with self.subTest(fidelity=fidelity):
                code, report, source, tree = self.run_case(
                    passed=passed, asset_fidelity=fidelity)
                self.assertEqual(code, 0)
                self.assertTrue(report['success'])
                self.assertEqual((source, tree), (2, 2))
                for path in paths:
                    self.assertEqual(self.command_argv.count(path), 1)
                self.assertEqual(self.command_argv.count(
                    'test/harness/retained_renderer_frame_test.dart'), 1)
                self.assertEqual(self.command_argv.count(
                    'test/home/home_hero_test.dart'), 1)
            for old in (517, 519, 520, 522, 528, 529, 530, 531, 532, 533, 534, 535, 546, 547, 548, 549, 550, 554, 555, 556, 557, 558, 566, 568, 570, 635, 637, 657, 658, 659, 660, 661, 662, 663, 692, 698, 699, 700, 701, 704, 706, 709, 711, 712, 714, 713, 715, 716, 718, 721, 723, 722, 724, 725, 745, 747, 749, 746, 748, 751, 750, 752, 753, 754, 777, 779):
                if old == passed:
                    continue
                with self.subTest(fidelity=fidelity, old=old):
                    code, report, source, tree = self.run_case(
                        passed=old, asset_fidelity=fidelity)
                    self.assertEqual(code, 1)
                    self.assertFalse(report['success'])
                    self.assertEqual(report['code'], 'TESTS_FAILED')
                    self.assertEqual((source, tree), (1, 1))
        for fidelity, passed in ((False, 780), (True, 778)):
            code, report, source, tree = self.run_case(
                passed=passed, asset_fidelity=fidelity)
            self.assertEqual(code, 1)
            self.assertFalse(report['success'])
            self.assertEqual((source, tree), (1, 1))

    def test_native_startup_and_actual_agent_cases_are_selected_once(self):
        paths = ('test/harness/readonly_native_mode_test.dart',
                 'test/harness/readonly_native_agent_test.dart',
                 'test/harness/readonly_wallet_admission_test.dart',
                 'test/harness/readonly_inspection_session_test.dart',
                 'test/harness/readonly_viewport_probe_test.dart',
                 'test/harness/screen_capture_test.dart',
                 'test/settings/display_settings_test.dart',
                 'test/go_to_palette/go_to_palette_test.dart')
        for fidelity, passed in ((False, 778), (True, 780)):
            with self.subTest(fidelity=fidelity):
                code, report, source, tree = self.run_case(
                    passed=passed, asset_fidelity=fidelity)
                self.assertEqual(code, 0)
                self.assertTrue(report['success'])
                self.assertEqual((source, tree), (2, 2))
                for path in paths:
                    self.assertEqual(self.command_argv.count(path), 1)
                for path in ('test/harness/readonly_sdk_binding_test.dart',
                             'test/harness/readonly_native_commands_test.dart'):
                    self.assertEqual(self.command_argv.count(path), 1)
            for old in (555, 557, 567, 569, 587, 589, 591, 588, 590, 595, 597, 614, 615, 616, 617, 618, 634, 636, 638, 723, 725, 745, 747, 749, 746, 748, 751, 750, 752, 753, 754, 777, 779):
                if old == passed:
                    continue
                code, report, source, tree = self.run_case(
                    passed=old, asset_fidelity=fidelity)
                self.assertEqual(code, 1)
                self.assertFalse(report['success'])
                self.assertEqual(report['code'], 'TESTS_FAILED')
                self.assertEqual((source, tree), (1, 1))
        for fidelity, passed in ((False, 780), (True, 778)):
            code, report, source, tree = self.run_case(
                passed=passed, asset_fidelity=fidelity)
            self.assertEqual(code, 1)
            self.assertFalse(report['success'])
            self.assertEqual((source, tree), (1, 1))
