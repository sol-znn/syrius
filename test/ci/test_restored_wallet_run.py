"""Memory policies and separate tiny hosted filesystem fixtures, without signing."""

import json
import hashlib
import io
from pathlib import Path, PureWindowsPath
import re
import tempfile
import time
import unittest
from unittest import mock

from tool.ci import hosted_chain321 as lab
from tool.ci import restored_wallet_run as restored
from tool.ci import wallet_restore_origin as origin
from tool.ci import windows_wallet_tour as tour


def wallet_observation():
    return dict(schema=1, scope='restored_lab_wallet_observation', chain=321,
        members=2, selected_index=1, membership_same=True, selection_saved=True,
        wallet_path_mapped=True, original_send_confirmed=True,
        journal_consistent=True, observation_stable=True)


def completed():
    return dict(schema=1, scope=restored.SCOPE, complete=True, claim_once=True,
        originals_closed=True, chain_continuity=True, journal_unchanged=True,
        cipher_unchanged=True, wallet=wallet_observation(), application_exit=0,
        entry_exit=0, output=dict(bytes=123, sha256='a'*64,
            output_complete=True, overflow=False), job_empty=True, forced=False,
        nodes=[dict(role=role, exit_code=0, output_complete=True, forced=False)
               for role in restored.checkpoint.ROLES[1:]],
        private_manifest_sha256='b'*64, seed_admitted=False)


def lock_view_observation():
    return dict(schema=1, status='observed', owner_same=True,
        view=dict({key: False for key in restored.LOCK_VIEW_BOOLEANS},
            password_failures=0, lifecycle='inactive'))


class PolicyTests(unittest.TestCase):
    def test_only_complete_finite_reopen_facts_are_projected(self):
        value = completed()
        self.assertEqual(restored.project(value), value)
        self.assertFalse(restored.project(value)['seed_admitted'])

    def test_absence_and_incomplete_reopen_never_supply_a_wallet(self):
        self.assertIsNone(restored.project(None))
        value = dict(schema=1, scope=restored.SCOPE, complete=False)
        self.assertEqual(restored.project(value), value)
        with self.assertRaises(restored.checkpoint.Refused):
            restored.project(dict(value, wallet=wallet_observation()))

    def test_private_or_missing_observation_fields_are_refused(self):
        for candidate in (dict(wallet_observation(), walletPath='private'),
                {key: value for key, value in wallet_observation().items() if key != 'chain'}):
            with self.subTest(fields=len(candidate)), self.assertRaises(restored.checkpoint.Refused):
                restored.wallet_observation(candidate)

    def test_every_wallet_observation_must_be_positive_and_well_typed(self):
        for field, value in (('schema', True), ('chain', 1), ('chain', 321.0),
                ('members', True), ('members', 129), ('members', 1),
                ('selected_index', 0), ('selected_index', True),
                ('membership_same', False), ('selection_saved', 1),
                ('wallet_path_mapped', False), ('original_send_confirmed', False),
                ('journal_consistent', False), ('observation_stable', False)):
            with self.subTest(field=field), self.assertRaises(restored.checkpoint.Refused):
                restored.wallet_observation(dict(wallet_observation(), **{field: value}))

    def test_failed_forced_or_unclosed_actors_cannot_be_healed(self):
        for change in (dict(application_exit=None), dict(application_exit=False),
                dict(entry_exit=1), dict(forced=True), dict(job_empty=False),
                dict(originals_closed=False), dict(chain_continuity=False),
                dict(journal_unchanged=False), dict(cipher_unchanged=False),
                dict(claim_once=False), dict(seed_admitted=True)):
            with self.subTest(change=change), self.assertRaises(restored.checkpoint.Refused):
                restored.project(dict(completed(), **change))

    def test_each_new_original_node_requires_its_own_normal_complete_exit(self):
        for change in (dict(exit_code=1), dict(exit_code=False),
                       dict(forced=True), dict(output_complete=False), dict(role='foreign')):
            value = completed()
            value['nodes'][2].update(change)
            with self.subTest(change=change), self.assertRaises(restored.checkpoint.Refused):
                restored.project(value)
        value = completed()
        value['nodes'].pop()
        with self.assertRaises(restored.checkpoint.Refused):
            restored.project(value)

    def test_incomplete_overflowed_or_private_output_cannot_be_published(self):
        for change in (dict(bytes=True), dict(bytes=0), dict(output_complete=False),
                       dict(overflow=True), dict(sha256='private'), dict(raw='private')):
            value = completed()
            value['output'].update(change)
            with self.subTest(change=change), self.assertRaises(restored.checkpoint.Refused):
                restored.project(value)

    def test_unowned_local_entry_refuses_before_files_or_processes(self):
        with mock.patch.object(restored.subprocess, 'Popen') as launch, \
                mock.patch.object(restored.checkpoint, 'ancestors') as discover:
            with self.assertRaises(Exception):
                restored.run(Path('/fixture'), {}, mock.Mock(), mock.Mock(),
                    {}, {}, Path('/checkpoint'), lambda: True, lambda: 0)
        launch.assert_not_called()
        discover.assert_not_called()


class ReopenDiagnosticTests(unittest.TestCase):
    def trace(self, raw=b'CI_REOPEN_ERROR:unlock\r\n'):
        trace = restored.ReopenDiagnostic()
        trace.at('unlock_and_observe')
        trace.observe_line(raw)
        return trace

    def test_child_phases_match_the_actual_entry_and_ordered_seed_recipes(self):
        source = Path('harness/bin/ci_wallet_reopen.dart').read_text()
        phases = set(re.findall(r"phase = '([a-z_]+)'", source))
        phases.update('seed_' + name for name in restored.seeds.IDS)
        self.assertEqual(set(restored.CHILD_PHASES), phases)
        for phase in phases:
            raw = ('CI_REOPEN_ERROR:' + phase + '\r\n').encode()
            value = self.trace(raw).snapshot()
            self.assertEqual(value['child_phase'], phase)
            self.assertEqual(value['output'], dict(code='REOPEN_CHILD_REFUSED',
                bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest()))

    def test_ordinary_output_is_ignored_and_error_text_is_only_classified_and_hashed(self):
        trace = restored.ReopenDiagnostic()
        trace.observe_line(b'started an isolated fixture\n')
        self.assertIsNone(trace.snapshot()['output'])
        raw = b'Unhandled exception: synthetic private password and path\n'
        trace.observe_line(raw)
        value = trace.snapshot()
        self.assertEqual(value['output']['code'], 'UNHANDLED_EXCEPTION')
        self.assertEqual(value['output']['sha256'], hashlib.sha256(raw).hexdigest())
        self.assertIsNone(value['child_phase'])
        self.assertNotIn('private', json.dumps(value))
        self.assertNotIn('password', json.dumps(value))

    def test_foreign_markers_fields_coercions_and_unknown_vocabulary_are_refused(self):
        for raw in (b'CI_REOPEN_ERROR:private\n',
                    b'CI_REOPEN_ERROR:unlock:private\n'):
            value = self.trace(raw).snapshot()
            self.assertIsNone(value['child_phase'])
            self.assertEqual(value['output']['code'], 'UNCLASSIFIED_OUTPUT')
        original = self.trace().snapshot()
        changes = [dict(original, private='fixture'), dict(original, schema=True),
            dict(original, phase='private'), dict(original, child_phase='private'),
            dict(original, error='private'), dict(original, code='private'),
            dict(original, output=dict(original['output'], bytes=True)),
            dict(original, output=dict(original['output'], sha256='private')),
            dict(original, output=dict(original['output'], raw='private'))]
        for value in changes:
            with self.subTest(fields=len(value)), self.assertRaises(restored.checkpoint.Refused):
                restored.diagnostic_projection(value)

    def test_error_categories_never_format_the_original_exception(self):
        class Unformattable(Exception):
            def __str__(self):
                raise AssertionError('private error must not be formatted')
        for error, expected in (
                (restored.checkpoint.Refused(), 'CHECKPOINT_REFUSED'),
                (TypeError('private'), 'TYPE_ERROR'),
                (KeyError('private'), 'KEY_ERROR'),
                (OSError('private'), 'OS_ERROR'),
                (ValueError('private'), 'VALUE_ERROR'),
                (KeyboardInterrupt('private'), 'INTERRUPTED'),
                (Unformattable('private'), 'OTHER_ERROR')):
            trace = restored.ReopenDiagnostic()
            trace.failure(error)
            self.assertEqual(trace.snapshot()['error'], expected)
            self.assertIsNone(trace.snapshot()['code'])
            self.assertNotIn('private', json.dumps(trace.snapshot()))

    def test_domain_codes_require_the_exact_known_exception_and_allowlist(self):
        for error, category, code in (
                (lab.Failure('PORT_CONFLICT'), 'LAB_REFUSED', 'PORT_CONFLICT'),
                (restored.debug.ProcessRefused('CLOSE_UNCONFIRMED'),
                 'PROCESS_REFUSED', 'CLOSE_UNCONFIRMED')):
            trace = restored.ReopenDiagnostic()
            trace.failure(error)
            self.assertEqual(trace.snapshot()['error'], category)
            self.assertEqual(trace.snapshot()['code'], code)
        error = lab.Failure('PORT_CONFLICT')
        error.code = 'private'
        for error in (error, restored.debug.ProcessRefused('private')):
            trace = restored.ReopenDiagnostic()
            trace.failure(error)
            self.assertIsNone(trace.snapshot()['code'])
            self.assertNotIn('private', json.dumps(trace.snapshot()))
        value = self.trace().snapshot()
        with self.assertRaises(restored.checkpoint.Refused):
            restored.diagnostic_projection(dict(value, error='OS_ERROR',
                code='CLOSE_UNCONFIRMED'))

    def test_first_output_error_and_snapshots_keep_their_original_values(self):
        trace = self.trace()
        first = trace.snapshot()
        edited = trace.snapshot()
        edited['output']['bytes'] = 1
        trace.observe_line(b'CI_REOPEN_ERROR:finish\n')
        self.assertEqual(trace.snapshot(), first)
        trace.failure(TypeError('private'))
        trace.failure(KeyError('private'))
        self.assertEqual(trace.snapshot()['error'], 'TYPE_ERROR')
        with self.assertRaises(restored.checkpoint.Refused):
            trace.at('start')
        self.assertEqual(trace.snapshot()['phase'], first['phase'])

    def test_original_wire_refusals_keep_only_allowlisted_codes(self):
        error = lab.wire_policy.Refused('RPC_REFUSED')
        trace = restored.ReopenDiagnostic()
        trace.failure(error)
        self.assertEqual(trace.snapshot()['error'], 'WIRE_REFUSED')
        self.assertEqual(trace.snapshot()['code'], 'RPC_REFUSED')
        error.code = 'private'
        trace = restored.ReopenDiagnostic()
        trace.failure(error)
        self.assertIsNone(trace.snapshot()['code'])
        self.assertNotIn('private', json.dumps(trace.snapshot()))
        class Foreign(lab.wire_policy.Refused):
            pass
        trace = restored.ReopenDiagnostic()
        trace.failure(Foreign('RPC_REFUSED'))
        self.assertEqual(trace.snapshot()['error'], 'OTHER_ERROR')
        self.assertIsNone(trace.snapshot()['code'])
        with self.assertRaises(restored.checkpoint.Refused):
            restored.diagnostic_projection(dict(trace.snapshot(),
                error='WIRE_REFUSED', code='private'))

    def test_an_incomplete_diagnostic_cannot_supply_reopen_or_seed_authority(self):
        value = dict(schema=1, scope=restored.SCOPE, complete=False,
                     diagnostic=self.trace().snapshot())
        self.assertFalse(restored.project(value)['complete'])
        self.assertNotIn('seed_admitted', restored.project(value))
        with self.assertRaises(restored.checkpoint.Refused):
            restored.project(dict(value, wallet=wallet_observation()))
        with self.assertRaises(restored.checkpoint.Refused):
            restored.project(dict(completed(), diagnostic=value['diagnostic']))

    def test_output_bounds_and_invalid_phase_never_enter_a_snapshot(self):
        for raw in (None, '', b'', bytearray(b'fixture'),
                    b'a' * (restored.debug.protocol.MAX_LINE + 2)):
            trace = restored.ReopenDiagnostic()
            with self.subTest(kind=type(raw).__name__), self.assertRaises(restored.checkpoint.Refused):
                trace.observe_line(raw)
            self.assertIsNone(trace.snapshot()['output'])
        trace = restored.ReopenDiagnostic()
        with self.assertRaises(restored.checkpoint.Refused):
            trace.at('private')
        self.assertEqual(trace.snapshot()['phase'], 'admission')

    def test_closed_child_failure_vocabulary_matches_the_dart_formatter(self):
        source = Path('harness/bin/ci_wallet_reopen.dart').read_text()
        for name, expected in (
                ('restoredChildPhases', set(restored.CHILD_PHASES)),
                ('restoredChildKinds', restored.CHILD_FAILURE_KINDS),
                ('restoredWindowFailureCodes', restored.WINDOW_FAILURE_CODES),
                ('restoredUnlockFailureCodes', restored.UNLOCK_FAILURE_CODES),
                ('restoredRecipeExtraCodes', restored.CHILD_RECIPE_EXTRA_CODES)):
            match = re.search(r'const Set<String> ' + name
                + r' = <String>\{(.*?)\};', source, re.S)
            self.assertIsNotNone(match)
            values = re.findall(r"'([A-Za-z0-9_-]+)'", match[1])
            self.assertEqual(set(values), expected)
            self.assertEqual(len(values), len(expected))

    def test_original_child_failure_is_bound_and_cannot_be_replaced(self):
        child = dict(schema=1, scope='owned_reopen_child_failure', phase='startup',
            kind='RECIPE_REFUSED', code='wallet-recipe-restored-lock-required',
            recipe=dict(action='observe', control='none', reason='wallet-recipe-refused',
                entry='startup-before-initialization', startup='key-confirmed',
                film='skip-middle-frame-pending'))
        raw = b'CI_REOPEN_FAILURE:' + json.dumps(child).encode() + b'\r\n'
        trace = self.trace(raw)
        first = trace.snapshot()
        self.assertEqual(first['child_failure'], child)
        self.assertEqual(first['child_phase'], 'startup')
        self.assertEqual(first['output'], dict(code='REOPEN_CHILD_REFUSED',
            bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest()))
        changed = trace.snapshot()
        changed['child_failure']['recipe']['film'] = 'ended'
        trace.observe_line(b'CI_REOPEN_ERROR:unlock\n')
        self.assertEqual(trace.snapshot(), first)
        trace.failure(restored.checkpoint.Refused())
        value = dict(schema=1, scope=restored.SCOPE, complete=False,
            diagnostic=trace.snapshot())
        self.assertFalse(restored.project(value)['complete'])
        self.assertNotIn('seed_admitted', restored.project(value))
        with self.assertRaises(restored.checkpoint.Refused):
            restored.project(dict(completed(), diagnostic=trace.snapshot()))
        with self.assertRaises(restored.checkpoint.Refused):
            restored.diagnostic_projection(dict(first, child_phase='unlock'))
        self.assertNotIn('child_failure', self.trace().snapshot())
        for code in restored.UNLOCK_FAILURE_CODES:
            unlock = dict(schema=1, scope='owned_reopen_child_failure',
                phase='unlock', kind='HARNESS_REFUSED', code=code, recipe=None)
            self.assertEqual(restored.child_failure_projection(unlock), unlock)
            raw = b'CI_REOPEN_FAILURE:' + json.dumps(unlock).encode() + b'\n'
            trace = self.trace(raw)
            self.assertEqual(trace.snapshot()['child_failure'], unlock)
            for change in (dict(phase='startup'), dict(kind='FORMAT_ERROR'),
                    dict(code='private'), dict(recipe=dict(private='private'))):
                with self.subTest(code=code, change=change), \
                        self.assertRaises(restored.checkpoint.Refused):
                    restored.child_failure_projection(dict(unlock, **change))

    def test_lock_view_vocabulary_and_original_failure_are_preserved(self):
        source = Path('harness/lock_view_observation.dart').read_text()
        for name, expected in (
                ('lockViewBooleanFields', restored.LOCK_VIEW_BOOLEANS),
                ('lockViewLifecycles', restored.LOCK_VIEW_LIFECYCLES),
                ('lockViewStatuses', restored.LOCK_VIEW_STATUSES),
                ('lockViewUnlockPhases', restored.LOCK_VIEW_UNLOCK_PHASES)):
            match = re.search(r'const Set<String> ' + name
                + r' = <String>\{(.*?)\};', source, re.S)
            self.assertIsNotNone(match)
            self.assertEqual(set(re.findall(r"'([a-z_]+)'", match[1])), expected)
        child = dict(schema=1, scope='owned_reopen_child_failure', phase='unlock',
            kind='HARNESS_REFUSED', code='UNLOCK_WAIT_REFUSED', recipe=None,
            lock_view=lock_view_observation())
        raw = b'CI_REOPEN_FAILURE:' + json.dumps(child).encode() + b'\n'
        trace = self.trace(raw)
        self.assertEqual(trace.snapshot()['child_failure'], child)
        result = dict(schema=1, scope=restored.SCOPE, complete=False,
            diagnostic=trace.snapshot())
        self.assertFalse(restored.project(result)['complete'])
        self.assertNotIn('wallet', restored.project(result))
        for status in restored.LOCK_VIEW_STATUSES - {'observed'}:
            observation = dict(schema=1, status=status, owner_same=False, view=None)
            self.assertEqual(restored.lock_view_projection(observation), observation)

    def test_private_or_invalid_lock_observations_are_only_hashed(self):
        child = dict(schema=1, scope='owned_reopen_child_failure', phase='unlock',
            kind='HARNESS_REFUSED', code='UNLOCK_WAIT_REFUSED', recipe=None,
            lock_view=lock_view_observation())
        values = [dict(child, phase='startup'), dict(child, kind='FORMAT_ERROR'),
            dict(child, lock_view=dict(lock_view_observation(), private='private')),
            dict(child, lock_view=dict(lock_view_observation(), schema=True)),
            dict(child, lock_view=dict(lock_view_observation(), status='private')),
            dict(child, lock_view=dict(lock_view_observation(), owner_same=False)),
            dict(child, lock_view=dict(lock_view_observation(), view=None))]
        for change in (dict(private='private'), dict(busy=1),
                dict(password_failures=True), dict(password_failures=-1),
                dict(password_failures=256), dict(lifecycle='private')):
            observation = lock_view_observation()
            observation['view'].update(change)
            values.append(dict(child, lock_view=observation))
        for value in values:
            with self.subTest(fields=len(value)), \
                    self.assertRaises(restored.checkpoint.Refused):
                restored.child_failure_projection(value)
            raw = b'CI_REOPEN_FAILURE:' + json.dumps(value).encode() + b'\n'
            result = self.trace(raw).snapshot()
            self.assertNotIn('child_failure', result)
            self.assertEqual(result['output']['code'], 'UNCLASSIFIED_OUTPUT')
            self.assertEqual(result['output']['sha256'], hashlib.sha256(raw).hexdigest())
            self.assertNotIn('private', json.dumps(result))

    def test_paired_unlock_progress_never_completes_original_authentication(self):
        for phase in restored.LOCK_VIEW_UNLOCK_PHASES:
            for count in (0, 1, 255):
                observation = lock_view_observation()
                observation['view'].update(unlock_phase=phase, unlock_requests=count)
                child = dict(schema=1, scope='owned_reopen_child_failure', phase='unlock',
                    kind='HARNESS_REFUSED', code='UNLOCK_WAIT_REFUSED', recipe=None,
                    lock_view=observation)
                raw = b'CI_REOPEN_FAILURE:' + json.dumps(child).encode() + b'\n'
                with self.subTest(phase=phase, count=count):
                    trace = self.trace(raw).snapshot()
                    self.assertEqual(trace['child_failure'], child)
                    result = restored.project(dict(schema=1, scope=restored.SCOPE,
                        complete=False, diagnostic=trace))
                    self.assertFalse(result['complete'])
                    self.assertNotIn('wallet', result)
                    self.assertNotIn('seed_admitted', result)

    def test_unknown_partial_or_private_unlock_progress_is_only_hashed(self):
        changes = [dict(unlock_phase='idle'), dict(unlock_requests=1),
            dict(unlock_phase='private', unlock_requests=1),
            dict(unlock_phase='entered', unlock_requests=True),
            dict(unlock_phase='entered', unlock_requests=-1),
            dict(unlock_phase='entered', unlock_requests=256),
            dict(unlock_phase='entered', unlock_requests='private'),
            dict(unlock_phase='entered', unlock_requests=1, password='private')]
        for change in changes:
            observation = lock_view_observation()
            observation['view'].update(change)
            child = dict(schema=1, scope='owned_reopen_child_failure', phase='unlock',
                kind='HARNESS_REFUSED', code='UNLOCK_WAIT_REFUSED', recipe=None,
                lock_view=observation)
            with self.subTest(fields=set(change)), self.assertRaises(restored.checkpoint.Refused):
                restored.child_failure_projection(child)
            raw = b'CI_REOPEN_FAILURE:' + json.dumps(child).encode() + b'\n'
            result = self.trace(raw).snapshot()
            self.assertNotIn('child_failure', result)
            self.assertEqual(result['output']['sha256'], hashlib.sha256(raw).hexdigest())
            self.assertNotIn('private', json.dumps(result))

    def test_private_or_unlisted_child_failure_fields_are_only_hashed(self):
        child = dict(schema=1, scope='owned_reopen_child_failure',
            phase='startup_window', kind='WINDOW_REFUSED',
            code='WINDOW_CLIENT_REFUSED', recipe=None)
        values = [dict(child, private='private'), dict(child, schema=True),
            dict(child, phase='private'), dict(child, phase='startup'),
            dict(child, kind='private'), dict(child, code='private'),
            dict(child, code=None), dict(child, recipe=dict(private='private')),
            dict(child, kind='FORMAT_ERROR', code='WINDOW_CLIENT_REFUSED'),
            dict(child, kind='RECIPE_REFUSED', code='private'),
            dict(child, kind='RECIPE_REFUSED', code=None,
                recipe=dict(action='observe', control='none',
                    reason='wallet-recipe-refused', private='private'))]
        for value in values:
            with self.subTest(kind=value['kind']), self.assertRaises(restored.checkpoint.Refused):
                restored.child_failure_projection(value)
            raw = b'CI_REOPEN_FAILURE:' + json.dumps(value).encode() + b'\n'
            result = self.trace(raw).snapshot()
            self.assertIsNone(result['child_phase'])
            self.assertNotIn('child_failure', result)
            self.assertEqual(result['output']['code'], 'UNCLASSIFIED_OUTPUT')
            self.assertEqual(result['output']['sha256'], hashlib.sha256(raw).hexdigest())
            self.assertNotIn('private', json.dumps(result))


class NoticeTests(unittest.TestCase):
    def test_small_legacy_notices_keep_their_exact_facts(self):
        value = dict(scope='synthetic_observation', source_sha='a'*40,
                     success=False, wallet_reopen=None)
        self.assertEqual(restored.notice_frames(value), [('', value)])

    def test_large_notices_keep_every_component_in_parent_bound_finite_frames(self):
        value = dict(scope='synthetic_observation', source_sha='a'*40, run_id=123,
                     codes=['SYNTHETIC_FINITE']*175, wallet_reopen=completed())
        self.assertGreater(len(json.dumps(value, separators=(',', ':')).encode()), 3800)
        frames = restored.notice_frames(value)
        self.assertEqual(len(frames), 2)
        primary = frames[0][1]
        child = frames[1][1]
        digest = hashlib.sha256(json.dumps(primary, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        self.assertEqual(child['parent_notice_sha256'], digest)
        self.assertEqual(child['components'], ['wallet_reopen'])
        self.assertEqual(dict(primary, wallet_reopen=child['facts']), value)
        self.assertTrue(all(len(json.dumps(frame, sort_keys=True, separators=(',', ':')).encode()) <= 3800
                            for _, frame in frames))

    def test_private_component_fields_refuse_even_in_a_short_notice(self):
        value = dict(scope='synthetic_observation', wallet_reopen=dict(completed(), path='private'))
        with self.assertRaises(restored.checkpoint.Refused):
            restored.notice_frames(value)

    def test_an_oversized_primary_refuses_without_truncating_its_facts(self):
        value = dict(scope='synthetic_observation', codes=['SYNTHETIC_FINITE']*300,
                     wallet_reopen=completed())
        with self.assertRaises(restored.checkpoint.Refused):
            restored.notice_frames(value)


class OutputTests(unittest.TestCase):
    def test_one_original_pipe_is_preserved_exactly_without_public_text(self):
        raw = b'synthetic private path\nfinite marker\n'
        target = io.BytesIO()
        capture = restored._CapturedOutput(io.BytesIO(raw), target.write)
        result = bytearray()
        while True:
            part = capture.readline(7)
            if not part:
                break
            result.extend(part)
        self.assertEqual(bytes(result), raw)
        self.assertEqual(target.getvalue(), raw)
        self.assertEqual(capture.digest.hexdigest(), hashlib.sha256(raw).hexdigest())
        self.assertFalse(capture.overflow)

    def test_overflow_retains_the_exact_bounded_prefix_and_drains_the_original(self):
        raw = b'synthetic full original\n'
        target = io.BytesIO()
        capture = restored._CapturedOutput(io.BytesIO(raw), target.write, cap=8)
        observed = bytearray()
        while True:
            part = capture.readline(5)
            if not part:
                break
            observed.extend(part)
        self.assertEqual(bytes(observed), raw)
        self.assertEqual(target.getvalue(), raw[:8])
        self.assertEqual(capture.bytes, 8)
        self.assertTrue(capture.overflow)

    def test_failed_capture_write_refuses_without_a_second_reader_or_retry(self):
        source = io.BytesIO(b'original\n')
        write = mock.Mock(return_value=0)
        capture = restored._CapturedOutput(source, write)
        with self.assertRaises(restored.checkpoint.Refused):
            capture.readline(20)
        write.assert_called_once_with(b'original\n')
        self.assertEqual(capture.bytes, 0)


def momentum(height, stamp, digit):
    return dict(chainIdentifier=321, height=height, timestamp=stamp, hash=digit*64)


class ChainPolicyTests(unittest.TestCase):
    def test_advancing_reopened_observation_uses_the_aggregate_sampler(self):
        http, ws = mock.Mock(), mock.Mock()
        genesis, first, last = momentum(1, 10, '1'), momentum(10, 100, '2'), momentum(11, 110, '3')
        http.call.side_effect = [dict(list=[genesis]), first, last]
        ws.call.side_effect = [genesis, last]
        measure = mock.Mock()
        with mock.patch.object(lab.socket, 'create_connection', return_value=mock.MagicMock()), \
                mock.patch.object(lab, 'make_transports', return_value=(object(), object())), \
                mock.patch.object(lab.wire_policy, 'HttpRpc', return_value=http), \
                mock.patch.object(lab.wire_policy, 'WsRpc', return_value=ws), \
                mock.patch.object(lab, 'sample_storage', side_effect=AssertionError('partial sample')):
            result = lab.observe(mock.Mock(), Path('/fixture'), measure=measure)
        self.assertEqual(measure.call_count, 2)
        self.assertEqual(result['last_height'], 11)

    def test_a_refused_aggregate_sample_stops_before_new_rpc_allocation(self):
        with mock.patch.object(lab, 'make_transports') as allocate:
            with self.assertRaises(lab.Failure):
                lab.observe(mock.Mock(), Path('/fixture'),
                    measure=mock.Mock(side_effect=lab.Failure('STORAGE_REFUSED')))
        allocate.assert_not_called()

    def run_read(self, *, expected=True, changed=None, ws_wrong=False,
                 close_error=False, original_error=False):
        original_runtime = lab.Native(mock.Mock(), Path('/fixture/node'), {})
        runtime = lab.Native(mock.Mock(), Path('/fixture/node'), {})
        genesis, anchor, frontier = momentum(1, 10, '1'), momentum(10, 100, '2'), momentum(11, 110, '3')
        witness = restored._ChainAnchor(original_runtime,
            lab.wire_policy.Momentum.parse(genesis), lab.wire_policy.Momentum.parse(anchor))
        values = dict(genesis=genesis, anchor=anchor, frontier=frontier)
        if changed:
            for key, value in changed.items():
                values[key] = dict(values[key], **value)
        http, ws = mock.Mock(), mock.Mock()
        def http_call(method, params):
            if method == 'ledger.getFrontierMomentum':
                return values['frontier']
            self.assertEqual(method, 'ledger.getMomentumsByHeight')
            return dict(list=[values['genesis'] if params[0] == 1 else values['anchor']])
        def ws_call(method, params):
            self.assertEqual(method, 'ledger.getMomentumByHash')
            value = next((item for item in values.values() if item['hash'] == params[0]), None)
            return dict(value, timestamp=999) if ws_wrong and value is not None else value
        Http, Ws = lab.wire_policy.HttpRpc, lab.wire_policy.WsRpc
        def admitted_factory(cls, target, respond):
            def create(*args, **kwargs):
                admission = cls(*args, **kwargs)
                target.admission = admission
                def call(method, params):
                    admission._payload(method, params)
                    return respond(method, params)
                target.call.side_effect = call
                return target
            return create
        first_error = lab.wire_policy.Refused('WS_REFUSED')
        if original_error:
            ws.connect.side_effect = first_error
        if close_error:
            ws.close.side_effect = lab.wire_policy.Refused('CLOSE_UNKNOWN')
        with mock.patch.object(runtime, 'healthy'), \
                mock.patch.object(lab, 'make_transports', return_value=(object(), object())), \
                mock.patch.object(lab.wire_policy, 'HttpRpc',
                    side_effect=admitted_factory(Http, http, http_call)), \
                mock.patch.object(lab.wire_policy, 'WsRpc',
                    side_effect=admitted_factory(Ws, ws, ws_call)):
            try:
                result = restored.chain_read(runtime, witness if expected else None)
            except Exception as error:
                result = error
        ws.close.assert_called_once_with()
        http.close.assert_called_once_with()
        return result, runtime, first_error, http, ws

    def test_the_exact_old_momentum_and_genesis_survive_in_a_new_advancing_chain(self):
        value, runtime, _, http, ws = self.run_read()
        self.assertIsInstance(value, restored._ChainAnchor)
        self.assertIs(value.owner, runtime)
        self.assertEqual(value.frontier.height, 11)
        self.assertTrue(all(call.args[0].startswith('ledger.get')
                            for call in http.call.call_args_list + ws.call.call_args_list))

    def test_retained_continuity_uses_the_actual_admission_and_original_height(self):
        value, runtime, _, http, ws = self.run_read()
        self.assertIsInstance(value, restored._ChainAnchor)
        self.assertIs(value.owner, runtime)
        heights = [call.args[1] for call in http.call.call_args_list
                   if call.args[0] == 'ledger.getMomentumsByHeight']
        self.assertEqual(heights, [[1, 1], [10, 1]])
        ws.call.assert_any_call('ledger.getMomentumByHash', ['2' * 64])

    def test_retained_http_scope_does_not_admit_other_heights_counts_or_ws_scope(self):
        value, _, _, http, ws = self.run_read()
        self.assertIsInstance(value, restored._ChainAnchor)
        for params in ([11, 1], [9, 1], [10, 2], [True, 1]):
            with self.subTest(params=params), self.assertRaises(lab.wire_policy.Refused):
                http.admission._payload('ledger.getMomentumsByHeight', params)
        with self.assertRaises(lab.wire_policy.Refused):
            ws.admission._payload('ledger.getMomentumsByHeight', [10, 1])

    def test_initial_anchor_is_captured_without_a_prior_report(self):
        value, runtime, _, _, _ = self.run_read(expected=False)
        self.assertIs(value.owner, runtime)

    def test_matching_heights_or_new_frontiers_cannot_replace_the_original_hash(self):
        for changes in (dict(anchor=dict(hash='4'*64)), dict(genesis=dict(hash='5'*64)),
                        dict(frontier=dict(height=9, timestamp=90)),
                        dict(frontier=dict(height=10, timestamp=100, hash='2'*64)),
                        dict(frontier=dict(timestamp=99))):
            with self.subTest(changes=changes):
                value, *_ = self.run_read(changed=changes)
                self.assertIsInstance(value, Exception)

    def test_cross_transport_disagreement_is_not_continuity(self):
        value, *_ = self.run_read(ws_wrong=True)
        self.assertIsInstance(value, Exception)

    def test_a_failed_transport_close_refuses_after_good_rpc_replies(self):
        value, *_ = self.run_read(close_error=True)
        self.assertIsInstance(value, restored.checkpoint.Refused)

    def test_cleanup_keeps_the_first_original_rpc_failure(self):
        value, _, original_error, _, _ = self.run_read(close_error=True, original_error=True)
        self.assertIs(value, original_error)

    def test_saved_data_refuses_before_new_rpc_transport_creation(self):
        runtime = lab.Native(mock.Mock(), Path('/fixture/node'), {})
        with mock.patch.object(runtime, 'healthy'), \
                mock.patch.object(lab, 'make_transports') as create:
            with self.assertRaises(restored.checkpoint.Refused):
                restored.chain_read(runtime, dict(hash='2'*64, height=10))
        create.assert_not_called()


class HandoffTests(unittest.TestCase):
    def wallet(self):
        home = PureWindowsPath(r'C:\fixture\.harness') / ('ci-wallet-'+'1'*24)
        value = dict(schema=1, scope='private_owned_wallet_origin',
            profile=home.name, home=str(home), wallet=str(home / 'wallet/one.json'),
            cache=str(home / 'cache'), members=['synthetic-zero', 'synthetic-one'],
            selected='synthetic-one', saved='synthetic-one', send_hash='a'*64,
            send_token='zts1znnxxxxxxxxxxxxx9z4ulx', send_amount='100000000',
            node='ws://127.0.0.1:45998', chain=321)
        parsed = origin.parse(value, str(home))
        entry = mock.Mock(poll=mock.Mock(return_value=None))
        quiet = dict(schema=1, scope='owned_lab_quiescence', chain=321, complete=True,
            admission_closed=True, original_send_confirmed=True, originals_positive=True,
            file_operations=1, sdk_publications=1, receive_reads=0, receive_publications=0)
        handoff = tour._QuiescenceHandoff(entry, quiet, parsed)
        entry.poll.return_value = 0
        return tour._ClosedWallet(home, entry, (1, 2), 'synthetic-private-input',
                                 (), (3, 4), handoff)

    def test_only_one_reopen_claim_follows_the_original_checkpoint_claim(self):
        wallet = self.wallet()
        with mock.patch.object(wallet, 'closed', return_value=True):
            with self.assertRaises(tour.Refused):
                wallet.claim_reopen()
            wallet.claim_checkpoint()
            wallet.claim_reopen()
            with self.assertRaises(tour.Refused):
                wallet.claim_reopen()

    def test_private_input_is_one_attempt_and_retains_the_exact_original_hash(self):
        wallet = self.wallet()
        home = wallet.home.parent / ('ci-wallet-'+'2'*24)
        with mock.patch.object(wallet, 'closed', return_value=True):
            wallet.claim_checkpoint()
            wallet.claim_reopen()
            value = wallet.reopen_input(home)
            self.assertEqual(set(value), {'password', 'originalProfile', 'wallet', 'members', 'hash'})
            self.assertEqual(value['hash'], 'a'*64)
            self.assertEqual(value['originalProfile'], wallet.home.name)
            with self.assertRaises(tour.Refused):
                wallet.reopen_input(home)
        self.assertNotIn('synthetic', repr(wallet))

    def test_invalid_or_lost_owned_input_is_held_without_a_second_attempt(self):
        wallet = self.wallet()
        with mock.patch.object(wallet, 'closed', return_value=True):
            wallet.claim_checkpoint()
            wallet.claim_reopen()
            with self.assertRaises(origin.Refused):
                wallet.reopen_input(wallet.home)
            with self.assertRaises(tour.Refused):
                wallet.reopen_input(wallet.home.parent / ('ci-wallet-'+'2'*24))

    def test_legacy_observations_cannot_claim_reopened_ownership(self):
        wallet = self.wallet()
        wallet._quiescence._origin = None
        wallet._checkpoint_claimed = True
        with mock.patch.object(wallet, 'closed', return_value=True):
            with self.assertRaises(tour.Refused):
                wallet.claim_reopen()
        self.assertFalse(wallet._reopen_claimed)


class FilesystemTests(unittest.TestCase):
    def fixture(self, root):
        source, copied, retained = (Path(root) / name for name in ('original.json', 'copy.json', 'retained.json'))
        raw = json.dumps(dict(mode='release', harnessMode='wallet', token='a'*32,
                              pid=123, port=12345)).encode()
        source.write_bytes(raw)
        copied.write_bytes(raw)
        return source, copied, retained, raw

    def test_retirement_preserves_original_and_exact_copied_metadata_identity(self):
        with tempfile.TemporaryDirectory(prefix='syrius-reopen-metadata-') as root:
            source, copied, retained, raw = self.fixture(root)
            old = restored.checkpoint.file_identity(copied.lstat())
            value, original_pin, copied_pin = restored.retire_metadata(
                source, copied, retained, lambda: True, time.monotonic()+10)
            self.assertEqual(value['token'], 'a'*32)
            self.assertEqual(source.read_bytes(), raw)
            self.assertEqual(retained.read_bytes(), raw)
            self.assertEqual(copied_pin[0], old)
            self.assertEqual(original_pin[1], copied_pin[1])
            self.assertFalse(copied.exists())

    def test_existing_retained_or_changed_metadata_refuses_without_overwrite(self):
        with tempfile.TemporaryDirectory(prefix='syrius-reopen-metadata-') as root:
            source, copied, retained, raw = self.fixture(root)
            retained.write_bytes(b'synthetic held metadata')
            with self.assertRaises(restored.checkpoint.Refused):
                restored.retire_metadata(source, copied, retained, lambda: True, time.monotonic()+10)
            self.assertEqual(copied.read_bytes(), raw)
            self.assertEqual(retained.read_bytes(), b'synthetic held metadata')
            retained.unlink()
            copied.write_bytes(raw+b' ')
            with self.assertRaises(restored.checkpoint.Refused):
                restored.retire_metadata(source, copied, retained, lambda: True, time.monotonic()+10)

    def test_lost_closure_refuses_before_the_metadata_is_moved(self):
        with tempfile.TemporaryDirectory(prefix='syrius-reopen-metadata-') as root:
            source, copied, retained, raw = self.fixture(root)
            with self.assertRaises(restored.checkpoint.Refused):
                restored.retire_metadata(source, copied, retained, lambda: False, time.monotonic()+10)
            self.assertEqual(source.read_bytes(), raw)
            self.assertEqual(copied.read_bytes(), raw)
            self.assertFalse(retained.exists())


class SeedFailureProjectionTests(unittest.TestCase):
    @staticmethod
    def home(**changes):
        value = dict(stage='railTogglePresence', target='home', state=dict(
            at='railReadiness', booted='yes', unlocked='yes',
            initialized='yes', tab='home'))
        value.update(changes)
        return value

    def test_original_home_stages_are_finite_copied_observations(self):
        source = Path('harness/home_preparation_observation.dart').read_text()
        match = re.search(r'enum HomePreparationStep\s*\{([^}]+)\}', source)
        self.assertIsNotNone(match)
        self.assertEqual(tuple(re.findall(r'\b[A-Za-z][A-Za-z0-9]*\b', match[1])),
                         restored.HOME_PREPARATION_STAGES)
        match = re.search(r'enum HomeTapReply\s*\{([^}]+)\}', source)
        self.assertIsNotNone(match)
        self.assertEqual(set(re.findall(r'\b[A-Za-z][A-Za-z0-9]*\b', match[1])),
                         restored.HOME_TAP_REPLIES)
        for code in restored.HOME_TAP_REPLIES:
            offered = self.home(stage='gotoTap', reply=code,
                state=self.home()['state'] | dict(at='gotoTarget'))
            self.assertEqual(restored.home_preparation_projection(offered), offered)
        for stage in restored.HOME_PREPARATION_STAGES:
            offered = dict(stage=stage)
            if stage != 'initialState':
                offered['state'] = self.home()['state'] | dict(at='initialReadiness')
            if restored.HOME_PREPARATION_STAGES.index(stage) >= 2:
                offered['target'] = 'dashboard'
            seed = self.seed(recipe='deposit', action='home', step='navigation',
                             home=offered)
            result = restored.seed_failure_projection(seed, 'seed_deposit')
            self.assertEqual(result, seed)
            self.assertIsNot(result['home'], offered)
            if 'state' in offered:
                self.assertIsNot(result['home']['state'], offered['state'])
                offered['state']['tab'] = 'private'
                self.assertEqual(result['home']['state']['tab'], 'home')
            self.assertEqual(restored.child_failure_projection(
                self.child(result))['seed'], result)
        legacy = self.seed(action='home', step='navigation')
        self.assertEqual(restored.seed_failure_projection(legacy, 'seed_stake'), legacy)
        self.assertEqual(len(legacy), 9)
        self.assertNotIn('home', legacy)

    def test_home_projection_refuses_unknown_coerced_private_or_future_state(self):
        values = [None, True, [], 'private', {},
            self.home(stage='private'), self.home(stage=True),
            self.home(target='private'), self.home(target=True),
            self.home(stage='initialState'), self.home(path='private'),
            self.home(state=True), self.home(state={'at': 'railReadiness'})]
        for change in (dict(at='finalReadiness'), dict(at='railWait'),
                dict(booted=True), dict(unlocked=1), dict(initialized=None),
                dict(tab='private'), dict(tab=True), dict(path='private')):
            values.append(self.home(state=self.home()['state'] | change))
        for key in self.home()['state']:
            values.append(self.home(state={name: value for name, value
                in self.home()['state'].items() if name != key}))
        for value in values:
            with self.subTest(value=value), self.assertRaises(restored.checkpoint.Refused):
                restored.home_preparation_projection(value)
        tap = self.home(stage='gotoTap', reply='targetCovered',
            state=self.home()['state'] | dict(at='gotoTarget'))
        for change in (dict(reply='private'), dict(reply=True), dict(reply=None),
                dict(stage='gotoWait'), dict(state=self.home()['state'])):
            with self.subTest(change=change), self.assertRaises(restored.checkpoint.Refused):
                restored.home_preparation_projection(tap | change)
        for missing in ('target', 'state'):
            with self.assertRaises(restored.checkpoint.Refused):
                restored.home_preparation_projection({key: value
                    for key, value in tap.items() if key != missing})
        for flag in ('yes', 'no', 'unknown'):
            for tab in ('home', 'dashboard', 'lock', 'other', 'unknown'):
                value = self.home(state=self.home()['state'] | dict(
                    booted=flag, unlocked=flag, initialized=flag, tab=tab))
                self.assertEqual(restored.home_preparation_projection(value), value)

    def test_home_observations_cannot_relabel_a_later_operation_or_add_authority(self):
        for recipe in restored.SEED_FAILURE_RECIPES:
            value = self.seed(recipe=recipe, action='home', step='navigation',
                              home=self.home())
            self.assertEqual(restored.seed_failure_projection(value,
                'seed_' + recipe), value)
            value['home'] = self.home(stage='gotoTap', reply='targetCovered',
                state=self.home()['state'] | dict(at='gotoTarget'))
            self.assertEqual(restored.seed_failure_projection(value,
                'seed_' + recipe), value)
        for change in (dict(action='source', step='read'),
                dict(action='begin', step='reply'),
                dict(action='prepare', step='owner', command_index=1),
                dict(action='publish', step='reply', command_index=7,
                     publication_call_entered=True), dict(command_index=1),
                dict(publication_call_entered=True), dict(confirmation=self.counts()),
                dict(confirmed=True), dict(retry=True), dict(success=True)):
            value = self.seed(action='home', step='navigation', home=self.home())
            value.update(change)
            with self.subTest(change=change), self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection(value, 'seed_stake')
        value = self.seed(action='home', step='navigation', home=self.home())
        for phase in ('seed_fuse', 'unlock', 'seed_admission'):
            with self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection(value, phase)

    @staticmethod
    def counts(**changes):
        value = dict(polls=18, absent=6, unconfirmed=6,
                     effect_pending=6, last='effect_pending')
        value.update(changes)
        return value

    def exhausted(self, **changes):
        return self.seed(recipe='fuse', action='publish', step='reply',
            command_index=7, publication_call_entered=True, kind='refused',
            reason='exact-confirmation-or-effect-pending',
            confirmation=self.counts(), **changes)

    def test_exhausted_original_seed_rounds_remain_copied_observations(self):
        for last in ('absent', 'unconfirmed', 'effect_pending'):
            offered = self.exhausted()
            offered['confirmation']['last'] = last
            result = restored.seed_failure_projection(offered, 'seed_fuse')
            self.assertEqual(result, offered)
            self.assertIsNot(result['confirmation'], offered['confirmation'])
            offered['confirmation']['absent'] = 0
            self.assertEqual(result['confirmation']['absent'], 6)
            child = self.child(result)
            self.assertEqual(restored.child_failure_projection(child)['seed'], result)
        legacy = self.seed()
        self.assertNotIn('confirmation', restored.seed_failure_projection(legacy, 'seed_stake'))
        for key in ('confirmed', 'complete', 'hash', 'retry', 'success', 'address'):
            self.assertNotIn(key, result['confirmation'])

    def test_seed_counts_refuse_unknown_coerced_missing_and_impossible_values(self):
        changes = (dict(polls=True), dict(polls=17), dict(absent=-1),
            dict(absent=19), dict(unconfirmed=6.0), dict(effect_pending=None),
            dict(effect_pending=5), dict(last='private'), dict(hash='private'),
            dict(path='private'), dict(absent=18, unconfirmed=0, effect_pending=0))
        for change in changes:
            offered = self.exhausted()
            offered['confirmation'] = self.counts(**change)
            with self.subTest(change=change), self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection(offered, 'seed_fuse')
        for key in self.counts():
            offered = self.exhausted()
            del offered['confirmation'][key]
            with self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection(offered, 'seed_fuse')
        for value in (None, True, [], 'private'):
            offered = self.exhausted()
            offered['confirmation'] = value
            with self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection(offered, 'seed_fuse')

    def test_seed_counts_cannot_relabel_another_original_boundary(self):
        for change in (dict(action='check', step='owner'),
                dict(action='publish', step='request'), dict(reason='unknown'),
                dict(kind='timeout'), dict(publication_call_entered=False)):
            offered = self.exhausted()
            offered.update(change)
            with self.subTest(change=change), self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection(offered, 'seed_fuse')
        offered = self.exhausted()
        for phase in ('seed_stake', 'unlock', 'seed_admission'):
            with self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection(offered, phase)

    @staticmethod
    def seed(**changes):
        value = dict(schema=1, scope='original_seed_operation_failure',
            recipe='stake', action='begin', step='reply', command_index=0,
            publication_call_entered=False, kind='refused', reason='unknown')
        value.update(changes)
        return value

    @staticmethod
    def child(seed, **changes):
        value = dict(schema=1, scope='owned_reopen_child_failure',
            phase='seed_' + seed['recipe'], kind='HARNESS_REFUSED',
            code=None, recipe=None, seed=seed)
        value.update(changes)
        return value

    def test_finite_original_boundaries_remain_observation_data(self):
        for recipe in restored.SEED_FAILURE_RECIPES:
            for action in restored.SEED_FAILURE_ACTIONS:
                steps = ({'read', 'parse', 'resolve'} if action == 'source' else
                         {'navigation'} if action == 'home' else
                         {'owner', 'execute'} if action == 'command' else
                         {'owner', 'request', 'reply'})
                for step in steps:
                    entered = action == 'finish' or action == 'publish' and step != 'owner'
                    index = 0 if action in ('source', 'begin', 'home', 'finish') else 5
                    offered = self.seed(recipe=recipe, action=action, step=step,
                        command_index=index, publication_call_entered=entered)
                    self.assertEqual(restored.seed_failure_projection(offered,
                        'seed_' + recipe), offered)
                    self.assertEqual(restored.child_failure_projection(
                        self.child(offered))['seed'], offered)
        for action in ('check', 'command'):
            offered = self.seed(action=action, step='owner', command_index=5,
                                publication_call_entered=True)
            self.assertEqual(restored.seed_failure_projection(offered,
                             'seed_stake'), offered)

    def test_private_unknown_coerced_or_unbounded_metadata_is_refused(self):
        for change in (dict(schema=True), dict(schema=2), dict(scope='private'),
                dict(recipe='private'), dict(recipe=True), dict(action='private'),
                dict(step='private'), dict(command_index=True), dict(command_index=-1),
                dict(command_index=97), dict(publication_call_entered=1),
                dict(kind='private'), dict(kind=True), dict(reason='private'),
                dict(path='private'), dict(message='private'), dict(stack='private'),
                dict(args=['private']), dict(address='private')):
            with self.subTest(change=change), self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection(self.seed(**change), 'seed_stake')
        original = self.seed()
        for key in original:
            with self.subTest(missing=key), self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection({name: value for name, value
                    in original.items() if name != key}, 'seed_stake')
        for value in (None, True, [], 'private'):
            with self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection(value, 'seed_stake')

    def test_recipe_phase_and_original_call_boundaries_cannot_be_relabelled(self):
        for phase in ('unlock', 'seed_admission', 'seed_fuse', True, None):
            with self.subTest(phase=phase), self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection(self.seed(), phase)
        changes = (
            dict(action='source', step='read', publication_call_entered=True),
            dict(action='home', step='navigation', publication_call_entered=True),
            dict(action='prepare', step='owner', command_index=5,
                 publication_call_entered=True),
            dict(action='publish', step='owner', command_index=5,
                 publication_call_entered=True),
            dict(action='publish', step='request', command_index=5),
            dict(action='finish', step='request'),
            dict(action='command', step='execute', command_index=0),
            dict(action='source', step='read', command_index=1),
            dict(action='begin', step='execute'),
        )
        for change in changes:
            with self.subTest(change=change), self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection(self.seed(**change), 'seed_stake')

    def test_only_canonical_source_codes_are_public_and_do_not_imply_success(self):
        for code in (*restored.SEED_REPLY_CODES, 'unknown'):
            prepared = dict(action='prepare', command_index=3) if code in (
                restored.SEED_PREPARATION_REPLY_CODES) else {}
            value = self.seed(reason=code, **prepared)
            self.assertEqual(restored.seed_failure_projection(value,
                             'seed_stake')['reason'], code)
        code = sorted(restored.SEED_REPLY_CODES)[0]
        for value in (code + ' ', code + '-private', 'Seed refused: ' + code):
            with self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection(self.seed(reason=value), 'seed_stake')
        with self.assertRaises(restored.checkpoint.Refused):
            restored.seed_failure_projection(self.seed(reason=code, kind='type'),
                                             'seed_stake')
        for key in ('confirmed', 'complete', 'hash', 'retry', 'seed_admitted', 'success'):
            with self.subTest(key=key), self.assertRaises(restored.checkpoint.Refused):
                restored.seed_failure_projection(self.seed(**{key: True}), 'seed_stake')

    def test_preparation_labels_preserve_only_original_negative_reply_scope(self):
        for code in restored.SEED_PREPARATION_REPLY_CODES:
            value = self.seed(action='prepare', command_index=3, reason=code)
            self.assertEqual(restored.seed_failure_projection(value, 'seed_stake'), value)
            child = restored.child_failure_projection(self.child(value))
            self.assertEqual(child['seed'], value)
            self.assertFalse(value['publication_call_entered'])
        helper = Path('harness/seed_preparation_failure.dart').read_text()
        match = re.search(r'seedPreparationUiFailureCodes = <String>\{([^}]+)\}', helper)
        self.assertIsNotNone(match)
        self.assertEqual(set(re.findall(r"'([a-z0-9-]+)'", match[1])),
                         set(restored.SEED_PREPARATION_REPLY_CODES))

    def test_preparation_labels_refuse_other_actions_input_or_private_fields(self):
        for code in restored.SEED_PREPARATION_REPLY_CODES:
            changes = (dict(action='begin', command_index=0),
                dict(action='check'), dict(action='publish', publication_call_entered=True),
                dict(action='finish', command_index=0, publication_call_entered=True),
                dict(step='request'), dict(publication_call_entered=True),
                dict(confirmed=True), dict(hash='private'), dict(message='private'))
            for change in changes:
                value = self.seed(action='prepare', command_index=3, reason=code)
                value.update(change)
                with self.subTest(change=change), self.assertRaises(restored.checkpoint.Refused):
                    restored.seed_failure_projection(value, 'seed_stake')

    def test_public_enum_and_reply_catalogs_match_the_actual_dart_source(self):
        source = Path('harness/bin/harness.dart').read_text()
        for name, expected in (
                ('SeedOperationAction', restored.SEED_FAILURE_ACTIONS),
                ('SeedOperationStep', restored.SEED_FAILURE_STEPS),
                ('SeedOperationFailureKind', restored.SEED_FAILURE_KINDS)):
            match = re.search(r'enum ' + name + r'\s*\{([^}]+)\}', source)
            self.assertIsNotNone(match)
            labels = set(re.findall(r'\b[A-Za-z][A-Za-z0-9]*\b', match[1]))
            self.assertEqual(labels, set(expected))
        match = re.search(r'seedOperationReplyCodes = <String>\{([^}]+)\}', source)
        self.assertIsNotNone(match)
        self.assertEqual(set(re.findall(r"'([a-z0-9-]+)'", match[1])),
                         set(restored.SEED_REPLY_CODES))
        self.assertIn('length > 96', Path('harness/seed/seed_recipe.dart').read_text())

    def test_child_projection_preserves_legacy_refusals_and_copies_failure_data(self):
        value = self.child(self.seed())
        projected = restored.child_failure_projection(value)
        value['seed']['reason'] = 'private'
        self.assertEqual(projected['seed']['reason'], 'unknown')
        for changes in (dict(phase='unlock'), dict(kind='TYPE_ERROR'),
                dict(code='UNLOCK_TAP_REFUSED'), dict(recipe=dict(private='private')),
                dict(lock_view=lock_view_observation()), dict(complete=True)):
            with self.subTest(change=changes), self.assertRaises(restored.checkpoint.Refused):
                restored.child_failure_projection(self.child(self.seed(), **changes))
        legacy = self.child(self.seed())
        del legacy['seed']
        self.assertEqual(restored.child_failure_projection(legacy), legacy)


if __name__ == '__main__':
    unittest.main()
