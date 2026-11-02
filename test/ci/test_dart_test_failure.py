"""Memory-only failure-location privacy and completeness cases."""

import json
import unittest

from tool.ci import dart_test_failure as failure


def event():
    return dict(type='error', isFailure=True, error='Expected: true\nActual: false',
        stackTrace='/fixture/private/wallet_recipe_startup_test.dart:129:5\nprivate')


def encode(rows):
    return b'\n'.join(json.dumps(row).encode() for row in rows)


class DartFailureTests(unittest.TestCase):
    def test_entry_locations_keep_only_exact_names_and_original_numeric_lines(self):
        names = ('entry_capture_source_test.dart', 'entry_capture_opt_in_test.dart',
                 'entry_prepared_draft_test.dart', 'entry_capture_source.dart',
                 'import_wallet_seed_choice_screen.dart', 'native_entry_capture.dart',
                 'launch_decode_observation_test.dart')
        for name in names:
            row = dict(type='error', testID=7, isFailure=False,
                error='Null check operator used on a null value: private text',
                stackTrace='#0 private (/fixture/private/' + name + ':101:9)')
            value = failure.project(encode([row]))['items'][0]
            with self.subTest(name=name):
                self.assertEqual((value['file'], value['line']), (name, 101))
                self.assertEqual(value['category'], 'NULL_CHECK')
                self.assertEqual(value['location_source'], 'STACK')
                self.assertNotIn('private', json.dumps(value))
                self.assertNotIn('/fixture', json.dumps(value))
                self.assertNotIn('text', json.dumps(value))
                row['stackTrace'] = '/fixture/private/private_' + name + ':101:9'
                foreign = failure.project(encode([row]))['items'][0]
                self.assertIsNone(foreign['file'])
                self.assertIsNone(foreign['line'])

    def test_original_test_caller_is_separate_from_the_first_helper_location(self):
        frame = ('#0 private (/fixture/private/agent.dart:976:7)\n'
            '#1 private (/fixture/private/lab_send_ui_binding_test.dart:371:5)')
        for use_print in (False, True):
            row = dict(type='error', testID=7, isFailure=False,
                error='private error', stackTrace='' if use_print else frame)
            rows = [row]
            if use_print:
                rows.insert(0, dict(type='print', testID=7, message=frame))
            value = failure.project(encode(rows))['items'][0]
            with self.subTest(use_print=use_print):
                self.assertEqual((value['file'], value['line']), ('agent.dart', 976))
                self.assertEqual(value['test_context'], dict(
                    file='lab_send_ui_binding_test.dart', line=371,
                    location_source='PRINT' if use_print else 'STACK'))
                self.assertNotIn('private', json.dumps(value))
                self.assertNotIn('/fixture', json.dumps(value))

    def test_foreign_or_unknown_test_frames_cannot_supply_caller_context(self):
        for caller in ('unknown_test.dart:371:5',
                       'private_lab_send_ui_binding_test.dart:371:5',
                       'lab_send_ui_binding_test.dart:0:5',
                       'lab_send_ui_binding_test.dart:1234567:5'):
            row = dict(type='error', testID=7, isFailure=False,
                error='private error', stackTrace='agent.dart:976:7\n' + caller)
            value = failure.project(encode([row]))['items'][0]
            self.assertNotIn('test_context', value)
        rows = [dict(type='print', testID=99,
            message='lab_send_ui_binding_test.dart:371:5'),
            dict(type='error', testID=7, isFailure=False,
                error='private error', stackTrace='agent.dart:976:7')]
        self.assertNotIn('test_context', failure.project(encode(rows))['items'][0])

    def test_known_source_location_never_exports_error_stack_or_host_path(self):
        for name in ('wallet_recipe_startup_test.dart', 'rail_navigation_test.dart',
                     'wallet_address_recipe_test.dart', 'addresses_selection_test.dart',
                     'lab_transfer_witness_test.dart', 'lab_transfer_witness.dart',
                     'lab_send_policy_test.dart', 'lab_send_journal_test.dart',
                     'lab_send_ui_binding.dart', 'lab_send_ui_binding_test.dart',
                     'lab_send_failure.dart', 'lab_send_failure_test.dart',
                     'lab_sender_menu_test.dart', 'transfer_sender_header_test.dart',
                     'startup_key_confirm_test.dart', 'startup_key_refusal_test.dart',
                     'startup_key_support.dart',
                     'send_populated.dart',
                     'lab_send_policy.dart', 'seed_policy_test.dart', 'seed_policy.dart',
                     'lab_seed_binding.dart',
                     'selection_context_revision_test.dart', 'default_address_notifier.dart',
                     'recipe_control_admission_test.dart', 'recipe_control_admission.dart'):
            row = event();row['stackTrace'] = '/fixture/private/' + name + ':129:5\nprivate'
            value = failure.project(encode([row]))
            with self.subTest(name=name):
                self.assertEqual(value, dict(status='OBSERVED', total=1, items=[dict(
                    file=name, line=129, kind='ASSERTION', expectation='TRUE',
                    category='ASSERTION', location_source='STACK')]))
                self.assertNotIn('private', json.dumps(value))

    def test_unknown_locations_and_unhandled_payloads_stay_unattributed(self):
        row = event();row.update(stackTrace='/fixture/private.dart:123',
            error='private input', isFailure=False)
        value = failure.project(encode([row]))
        self.assertEqual(value['items'], [dict(file=None, line=None,
            kind='UNHANDLED', expectation='OTHER', category='OTHER', location_source='NONE')])
        self.assertNotIn('private', json.dumps(value))

    def test_invalid_or_incomplete_event_shapes_cannot_invent_a_location(self):
        invalid = event();invalid['isFailure'] = 1
        for raw in (None, b'x' * (4 * 1024**2 + 1), b'private raw text',
                    b'[]', encode([invalid])):
            self.assertEqual(failure.project(raw), dict(status='REFUSED', total=0, items=[]))

    def test_error_count_is_complete_but_public_details_are_bounded(self):
        row = event();row.update(error='Expected: <1>\nActual: <0>',
            stackTrace='test/harness/wallet_recipe_test.dart 88:5\nprivate')
        value = failure.project(encode([row] * 5))
        self.assertEqual(value['total'], 5)
        self.assertEqual(len(value['items']), 3)
        self.assertEqual(value['items'][0]['expectation'], 'ONE')
        self.assertEqual(value['items'][0]['line'], 88)
        self.assertEqual(failure.project(b'')['status'], 'NO_ERROR_EVENTS')

    def test_generic_framework_error_uses_only_its_own_preceding_print_context(self):
        rows = [dict(type='print', testID=7, messageType='print',
            message='Expected: true\nActual: false\n/fixture/private/wallet_recipe_startup_test.dart:101:5'),
            dict(type='error', testID=7, isFailure=False,
                error='Test failed. See exception logs above.', stackTrace='')]
        value = failure.project(encode(rows))
        self.assertEqual(value['items'], [dict(file='wallet_recipe_startup_test.dart', line=101,
            kind='UNHANDLED', expectation='TRUE', category='ASSERTION', location_source='PRINT')])
        self.assertNotIn('private', json.dumps(value))
        self.assertNotIn('Actual', json.dumps(value))

        prefix = [dict(type='suite', suite=dict(id=2,
            path='/fixture/private/go_to_palette_test.dart')),
            dict(type='testStart', test=dict(id=7, suiteID=2))]
        for theme in ('dark', 'light'):
            for direction in ('ltr', 'rtl'):
                for scale in (1, 2):
                    marker = 'CI_GOTO_GEOMETRY_CASE:%s:%s:%s' % (
                        theme, direction, scale)
                    message = (marker + '\nA RenderFlex overflowed by 12.25 '
                        'pixels on the bottom. private value\n'
                        '/fixture/private/go_to_palette.dart:440:12')
                    rows = prefix + [dict(type='print', testID=7,
                        message=message), dict(type='error', testID=7,
                        isFailure=False, error='Test failed.', stackTrace='')]
                    result = failure.project(encode(rows))['items'][0]
                    self.assertEqual(result['goto_geometry'], dict(
                        theme=theme, direction=direction, scale=scale,
                        overflow=dict(kind='RENDER_FLEX_OVERFLOW',
                            pixels=12.25, edge='bottom'),
                        widget_source=dict(file='go_to_palette.dart',
                            line=440, column=12)))
                    self.assertNotIn('private', json.dumps(result))
                    self.assertNotIn('/fixture', json.dumps(result))
                    rows[-2]['testID'] = 99
                    self.assertNotIn('goto_geometry',
                        failure.project(encode(rows))['items'][0])
                    rows[-2]['testID'] = 7
                    rows[0]['suite']['path'] = 'unknown_test.dart'
                    self.assertNotIn('goto_geometry',
                        failure.project(encode(rows))['items'][0])
                    rows[0]['suite']['path'] = 'go_to_palette_test.dart'
        for marker in ('CI_GOTO_GEOMETRY_CASE:private:ltr:1',
                       'CI_GOTO_GEOMETRY_CASE:dark:ltr:3',
                       'CI_GOTO_GEOMETRY_CASE:dark:ltr:1 private',
                       'CI_GOTO_GEOMETRY_CASE:dark:ltr:1\nprivate'):
            projected = failure.goto_geometry_diagnostic(marker)
            self.assertIsNone(projected) if '1\n' not in marker else self.assertEqual(
                projected, dict(theme='dark', direction='ltr', scale=1))
        for origin in ('private_go_to_palette.dart:440:12',
                       'go_to_palette.dart:0:12',
                       'go_to_palette.dart:440:0',
                       'go_to_palette.dart:1234567:12'):
            result = failure.goto_geometry_diagnostic(
                'CI_GOTO_GEOMETRY_CASE:dark:ltr:1\n' + origin)
            self.assertNotIn('widget_source', result)
        for overflow in ('10000', '12.1234', '-1', 'NaN', 'Infinity'):
            result = failure.goto_geometry_diagnostic(
                'CI_GOTO_GEOMETRY_CASE:dark:ltr:1\n'
                'A RenderFlex overflowed by ' + overflow + ' pixels on the right.')
            self.assertNotIn('overflow', result)

    def test_foreign_prints_cannot_supply_a_location_and_loading_errors_use_known_text(self):
        rows = [dict(type='print', testID=99, message='MissingPluginException private agent.dart:444:1'),
            dict(type='error', testID=7, isFailure=False, stackTrace='',
                error='Failed to load /fixture/private/wallet_recipe_startup_test.dart:81:5')]
        value = failure.project(encode(rows))['items'][0]
        self.assertEqual((value['category'], value['location_source'], value['line']),
            ('LOAD_ERROR', 'ERROR', 81))
        rows[-1]['error'] = 'Test failed. See exception logs above.'
        value = failure.project(encode(rows))['items'][0]
        self.assertEqual((value['file'], value['category'], value['location_source']),
            (None, 'OTHER', 'NONE'))

    def test_framework_assertions_keep_only_known_labels_and_numeric_positions(self):
        for path, label in (
                ('package:flutter/src/widgets/framework.dart', 'flutter_framework'),
                ('package:provider/src/provider.dart', 'provider_core'),
                ('package:bloc/src/emitter.dart', 'bloc_emitter'),
                ('package:get_it/get_it_impl.dart', 'get_it_registry')):
            rows = [dict(type='print', testID=7, messageType='print',
                message="'" + path + "': Failed assertion: line 123 pos 9: "
                    "'private expression': private details\n"
                    '/fixture/private/transfer_sender_header_test.dart:386:5'),
                dict(type='error', testID=7, isFailure=False, stackTrace='',
                    error='Test failed. See exception logs above.')]
            with self.subTest(source=label):
                value = failure.project(encode(rows))['items'][0]
                self.assertEqual(value['framework_assertion'],
                    dict(source=label, line=123, column=9))
                self.assertEqual((value['file'], value['line']),
                    ('transfer_sender_header_test.dart', 386))
                public = json.dumps(value)
                self.assertNotIn(path, public)
                self.assertNotIn('private', public)
                self.assertNotIn('expression', public)

    def test_unknown_assertion_paths_and_foreign_context_cannot_add_framework_data(self):
        for path, position in (
                ('/fixture/private/framework.dart', 'line 123 pos 9'),
                ('package:private/framework.dart', 'line 123 pos 9'),
                ('package:flutter/src/widgets/framework.dart', 'line 0 pos 9'),
                ('package:flutter/src/widgets/framework.dart', 'line 123 pos 0'),
                ('package:flutter/src/widgets/framework.dart', 'line 1234567 pos 9'),
                ('package:flutter/src/widgets/framework.dart', 'line 123 pos 1234567')):
            row = event()
            row['error'] = "'" + path + "': Failed assertion: " + position
            with self.subTest(path=path, position=position):
                value = failure.project(encode([row]))['items'][0]
                self.assertNotIn('framework_assertion', value)
                self.assertNotIn('private', json.dumps(value))
        rows = [dict(type='print', testID=99, messageType='print',
            message="'package:flutter/src/widgets/framework.dart': "
                'Failed assertion: line 123 pos 9: private'),
            dict(type='error', testID=7, isFailure=False, stackTrace='',
                error='Test failed. See exception logs above.')]
        self.assertNotIn('framework_assertion', failure.project(encode(rows))['items'][0])

    def test_owned_package_frame_is_context_and_cannot_claim_an_assertion_origin(self):
        for use_print in (False, True):
            frame = ('#0 private (package:flutter/src/widgets/framework.dart:123:9)\n'
                '#1 private (package:provider/src/provider.dart:456:7)\n'
                '/fixture/private/transfer_sender_header_test.dart:386:5')
            rows = [dict(type='error', testID=7, isFailure=False,
                error='Test failed. See exception logs above.',
                stackTrace='' if use_print else frame)]
            if use_print:
                rows.insert(0, dict(type='print', testID=7, messageType='print',
                    message=frame))
            with self.subTest(use_print=use_print):
                value = failure.project(encode(rows))['items'][0]
                self.assertEqual(value['framework_assertion'], dict(
                    source='flutter_framework', line=123, column=9,
                    kind='STACK_FRAME'))
                self.assertNotIn('private', json.dumps(value))
                self.assertNotIn('package:', json.dumps(value))
        for position in ('0:9', '123:0', '1234567:9', '123:1234567'):
            row = event()
            row['stackTrace'] = '(package:flutter/src/widgets/framework.dart:' + position + ')'
            self.assertNotIn('framework_assertion',
                failure.project(encode([row]))['items'][0])
        rows = [dict(type='print', testID=99, messageType='print', message=frame),
            dict(type='error', testID=7, isFailure=False, stackTrace='',
                error='Test failed. See exception logs above.')]
        self.assertNotIn('framework_assertion', failure.project(encode(rows))['items'][0])

    def test_failure_kind_requires_a_closed_marker_from_the_same_test(self):
        for kind in ('FLUTTER_ERROR', 'ASSERTION_ERROR', 'STATE_ERROR',
                     'TYPE_ERROR', 'NO_SUCH_METHOD', 'FORMAT_ERROR', 'OTHER'):
            rows = [dict(type='print', testID=7, messageType='print',
                message='CI_FRAMEWORK_FAILURE_KIND:' + kind),
                dict(type='error', testID=7, isFailure=False,
                    error='private error', stackTrace='private stack')]
            with self.subTest(kind=kind):
                value = failure.project(encode(rows))['items'][0]
                self.assertEqual(value['framework_failure_kind'], kind)
                self.assertNotIn('private', json.dumps(value))
        for marker in ('CI_FRAMEWORK_FAILURE_KIND:private',
                       'CI_FRAMEWORK_FAILURE_KIND:STATE_ERROR private'):
            rows[0]['message'] = marker
            self.assertNotIn('framework_failure_kind',
                failure.project(encode(rows))['items'][0])
        rows[0].update(testID=99, message='CI_FRAMEWORK_FAILURE_KIND:STATE_ERROR')
        self.assertNotIn('framework_failure_kind',
            failure.project(encode(rows))['items'][0])


class RootSuitePrivacyTests(unittest.TestCase):
    def test_root_catalog_covers_public_test_files_without_unknown_names(self):
        from pathlib import Path
        root = Path(__file__).absolute().parents[2] / 'test'
        expected = {p.name for p in root.rglob('*_test.dart') if p.is_file()}
        self.assertEqual(set(failure.ROOT_TEST_FILES), expected)
        self.assertEqual(len(failure.ROOT_TEST_FILES), len(expected))
        self.assertEqual(list(failure.ROOT_TEST_FILES), sorted(expected))
        self.assertTrue(all('/' not in n and '\\' not in n
                            for n in failure.ROOT_TEST_FILES))

    def test_root_failure_keeps_only_a_known_location_or_suite_label(self):
        for path in ('/fixture/private/test/shell/strip_test.dart',
                     r'C:\fixture\private\test\shell\strip_test.dart'):
            rows = [dict(type='suite', suite=dict(id=2, path=path)),
                dict(type='testStart', test=dict(id=7, suiteID=2,
                    name='private test name')),
                dict(type='error', testID=7, isFailure=False,
                    error='Assertion failed: private input', stackTrace='')]
            value = failure.locations(encode(rows))
            self.assertEqual(value, dict(status='OBSERVED', total=1, items=[dict(
                file=None, line=None, kind='UNHANDLED', category='ASSERTION',
                suite_file='strip_test.dart')]))
            self.assertNotIn('private', json.dumps(value))
            self.assertNotIn('fixture', json.dumps(value))
            rows[-1]['stackTrace'] = path + ':123:9'
            located = failure.locations(encode(rows))['items'][0]
            self.assertEqual((located['file'], located['line']),
                             ('strip_test.dart', 123))

    def test_unknown_suite_paths_and_foreign_test_ids_stay_unattributed(self):
        for path, identity in (
                ('/fixture/private/private_strip_test.dart', 7),
                ('/fixture/private/strip_test.dart.extra', 7),
                ('/fixture/private/unknown_test.dart', 7),
                ('/fixture/private/strip_test.dart', 99)):
            rows = [dict(type='suite', suite=dict(id=2, path=path)),
                dict(type='testStart', test=dict(id=7, suiteID=2)),
                dict(type='error', testID=identity, isFailure=False,
                    error='private input', stackTrace='private stack')]
            item = failure.locations(encode(rows))['items'][0]
            self.assertNotIn('suite_file', item)
            self.assertIsNone(item['file'])
            self.assertNotIn('private', json.dumps(item))

    def test_ambiguous_or_unbounded_event_ids_cannot_assign_a_suite(self):
        suite = dict(type='suite', suite=dict(id=2, path='strip_test.dart'))
        test = dict(type='testStart', test=dict(id=7, suiteID=2))
        for rows in ([suite, suite], [suite, test, test],
                [dict(type='suite', suite=dict(id=True, path='strip_test.dart'))],
                [dict(type='suite', suite=dict(id=20001, path='strip_test.dart'))],
                [dict(type='testStart', test=dict(id=7, suiteID=True))]):
            self.assertEqual(failure.locations(encode(rows)),
                dict(status='REFUSED', total=0, items=[]))

    def test_compact_suite_fields_cannot_export_paths_or_hide_failure_counts(self):
        rows = [dict(type='suite', suite=dict(id=2, path='strip_test.dart')),
            dict(type='testStart', test=dict(id=7, suiteID=2))]
        rows += [dict(type='error', testID=7, isFailure=False,
            error='private input', stackTrace='')] * 5
        value = failure.locations(encode(rows))
        self.assertEqual(value['total'], 5)
        self.assertEqual(len(value['items']), 3)
        self.assertEqual(failure.locations_projection(value), value)
        for name in ('/fixture/private/strip_test.dart', 'unknown_test.dart', True):
            altered = json.loads(json.dumps(value))
            altered['items'][0]['suite_file'] = name
            self.assertIsNone(failure.locations_projection(altered))
        value['items'][0]['private'] = 'private input'
        self.assertIsNone(failure.locations_projection(value))
