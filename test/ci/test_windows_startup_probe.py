"""Original-process protocol controls; no files, SDK, network or native app."""

from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import stat
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from tool.ci import windows_startup_probe as probe


def progress():
    return dict(frames=56, shown=0, decoding=12, stage='frame', skip=True,
                pending=False, ticking=True, done=False)


def sample(**changes):
    result = dict(at_ms=1000, phase='startup-before-initialization',
                  film='skip-middle-frame-pending', progress=progress())
    result.update(changes)
    return result


def positive_report(*, natural_only=False):
    report = probe.Report(natural_only=natural_only)
    report.source_sha, report.source_tree = 'a' * 40, 'b' * 40
    report.run_id, report.run_attempt = '9', '1'
    report.runner_sha256, report.payload_sha256 = 'c' * 64, 'd' * 64
    report.checks = dict.fromkeys(probe.CHECKS, True)
    report.handoff, report.key_attempts = 'key-confirmed', 1
    report.exit_observed, report.exit_code = True, 0
    report.output_complete = True
    report.samples = [sample()]
    if natural_only:
        report.handoff, report.key_attempts = 'natural', 0
        report.prior_manifest_sha256 = 'e' * 64
        report.samples = [sample(progress={**progress(), 'skip': False})]
    return report


class Clock:
    def __init__(self):
        self.now = 0

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class Process:
    pid = 17

    def __init__(self):
        self.code = None
        self.kills = 0

    def poll(self):
        return self.code

    def wait(self, timeout):
        if self.code is None:
            raise probe.subprocess.TimeoutExpired('owned-fixture', timeout)
        return self.code

    def kill(self):
        self.kills += 1
        self.code = 9


class Drain:
    error = None
    overflow = threading.Event()

    def finish(self, timeout):
        return True


class Session(probe.StartupProbe):
    def __init__(self, *, ready_after=2, refuse_key=False, natural=False,
                 natural_only=False, observed_skip=False):
        self.timer, self.commands = Clock(), []
        self.reads, self.ready_after = 0, ready_after
        self.refuse_key, self.natural = refuse_key, natural
        self.observed_skip = observed_skip
        report = positive_report(natural_only=natural_only)
        report.samples, report.handoff, report.key_attempts = [], None, 0
        report.checks['startup_ready'] = False
        super().__init__(Process(), None, 'private-token', Drain(), report,
                         limits=probe.LIMITS, clock=self.timer, sleep=self.timer.sleep,
                         natural_only=natural_only)

    def _rpc(self, command, *, until=None, allow_exit=False):
        self.commands.append(dict(command))
        if command['cmd'] == 'entry-state':
            ready = self.reads >= self.ready_after
            return dict(ok=True, available=True, held=False, captures=0,
                        nativeWindowReady=True, startupReady=ready, welcomeReady=ready)
        if command.get('action') == 'observe':
            self.reads += 1
            return dict(ok=True, harnessMode='wallet', booted=True,
                        walletPresent=False, hasError=False,
                        entryPhase='welcome' if self.natural else 'startup-before-initialization',
                        owner=3, revision=4, startupFilmState='skip-middle-frame-pending',
                        startupFilmProgress={**progress(), 'decoding': min(54, self.reads),
                                             'skip': self.report.key_attempts == 1
                                                     or self.observed_skip},
                        controls=[dict(key='launch_skip_hint', enabled=True)])
        if command.get('action') == 'key':
            if self.refuse_key:
                raise probe.Failure('COMMAND_FAILED')
            return dict(ok=True, acted=True)
        raise AssertionError('Unexpected command')


class ProjectionTests(unittest.TestCase):
    def test_original_frame_integers_and_closed_fields_only(self):
        value = progress()
        self.assertEqual(probe.progress_projection(value), value)
        for key, bad in (('frames', True), ('frames', 4097), ('shown', 56),
                         ('decoding', -1), ('decoding', 56), ('decoding', '12'),
                         ('stage', 'private error'), ('stage', []), ('skip', 1)):
            with self.subTest(key=key, bad=bad):
                self.assertIsNone(probe.progress_projection({**value, key: bad}))
        self.assertIsNone(probe.progress_projection({**value, 'private': 'payload'}))
        self.assertIsNone(probe.progress_projection({**value, 'frames': 0}))

    def test_opening_and_finished_facts_do_not_synthesize_a_frame(self):
        opening = dict(frames=0, shown=-1, decoding=None, stage='asset',
                       skip=False, pending=False, ticking=True, done=False)
        self.assertEqual(probe.progress_projection(opening), opening)
        ended = {**progress(), 'shown': 55, 'decoding': 55, 'stage': 'complete',
                 'done': True, 'ticking': False}
        self.assertEqual(probe.progress_projection(ended), ended)
        self.assertIsNone(probe.progress_projection({**opening, 'shown': 0}))

    def test_sample_rejects_payloads_unknown_labels_and_unbounded_time(self):
        value = sample()
        self.assertEqual(probe.sample_projection(value), value)
        for key, bad in (('at_ms', -1), ('at_ms', 90001), ('at_ms', True),
                         ('phase', 'private path'), ('phase', []), ('film', []),
                         ('film', 'private output'), ('progress', {})):
            with self.subTest(key=key):
                self.assertIsNone(probe.sample_projection({**value, key: bad}))
        self.assertIsNone(probe.sample_projection({**value, 'reply': 'private'}))


class ReportTests(unittest.TestCase):
    def test_complete_original_observation_is_not_chain_or_wallet_acceptance(self):
        report = positive_report()
        public = report.public()
        self.assertTrue(public['success'])
        self.assertTrue(public['original_skip_qualified'])
        self.assertFalse(public['wallet_qualified'])
        self.assertFalse(public['chain_qualified'])
        self.assertEqual(public['visual_matches'], 0)
        report.samples = [sample(at_ms=at * 250) for at in range(96)]
        full = report.public()
        self.assertGreater(len(json.dumps(full)), 4096)
        summary = report.summary()
        self.assertLessEqual(len(json.dumps(summary).encode('ascii')), 3800)
        self.assertEqual(summary['scope'], 'original_release_startup_summary')
        self.assertEqual(summary['sample_count'], 96)
        self.assertEqual(summary['first_sample'], full['samples'][0])
        self.assertEqual(summary['last_sample'], full['samples'][-1])
        self.assertEqual(len(summary['report_sha256']), 64)
        self.assertNotIn('samples', summary)
        self.assertEqual(report.public(), full)
        report.samples[48] = sample(at_ms=48 * 250,
                                    progress={**progress(), 'decoding': 13})
        changed = report.summary()
        self.assertEqual(changed['first_sample'], summary['first_sample'])
        self.assertEqual(changed['last_sample'], summary['last_sample'])
        self.assertNotEqual(changed['report_sha256'], summary['report_sha256'])
        for code in probe.CODES:
            report.fail(code)
        summary = report.summary()
        self.assertTrue(summary['errors_truncated'])
        self.assertEqual(summary['error_count'], len(probe.CODES))
        self.assertLessEqual(len(json.dumps(summary).encode('ascii')), 3800)

    def test_original_deadline_failure_cannot_be_healed_by_late_exit(self):
        report = positive_report()
        report.startup_deadline_expired = True
        self.assertFalse(report.public()['success'])
        report.startup_deadline_expired = False
        report.fail('STARTUP_DEADLINE', ValueError('private text'))
        public = report.public()
        self.assertFalse(public['success'])
        self.assertNotIn('private text', json.dumps(public))
        self.assertIn('STARTUP_DEADLINE', public['error_codes'])

    def test_natural_startup_never_becomes_skip_qualification(self):
        report = positive_report()
        report.handoff, report.key_attempts = 'natural', 0
        self.assertTrue(report.public()['success'])
        self.assertFalse(report.public()['original_skip_qualified'])
        report.key_attempts = 1
        self.assertFalse(report.public()['success'])

    def test_incomplete_force_overflow_unpinned_and_malformed_data_deny_success(self):
        for name, value in (('forced_kill', True), ('output_complete', False),
                            ('output_overflow', True), ('exit_observed', False),
                            ('exit_code', 9), ('key_attempts', True),
                            ('runner_sha256', None), ('source_tree', None),
                            ('run_id', None), ('run_attempt', '0')):
            with self.subTest(name=name):
                report = positive_report()
                setattr(report, name, value)
                self.assertFalse(report.public()['success'])
        for values in ([sample(progress={})], [sample()] * 97,
                       [sample(at_ms=2), sample(at_ms=1)]):
            report = positive_report()
            report.samples = values
            self.assertFalse(report.public()['success'])


class ProtocolTests(unittest.TestCase):
    def test_one_original_key_uses_current_owner_revision_and_reads_progress(self):
        session = Session()
        session._startup()
        keys = [row for row in session.commands if row.get('action') == 'key']
        self.assertEqual(keys, [dict(cmd='wallet-recipe', action='key',
            key='launch_skip_hint', owner=3, revision=4)])
        self.assertEqual([row['progress']['decoding'] for row in session.report.samples], [1, 2])
        self.assertEqual(session.report.handoff, 'key-confirmed')
        self.assertTrue(session.report.checks['startup_ready'])

    def test_refused_original_key_is_never_retried(self):
        session = Session(refuse_key=True)
        with self.assertRaises(probe.Failure):
            session._startup()
        self.assertEqual(session.report.key_attempts, 1)
        self.assertEqual(len([row for row in session.commands
                              if row.get('action') == 'key']), 1)
        self.assertIsNone(session.report.handoff)

    def test_natural_handoff_issues_no_input(self):
        session = Session(ready_after=1, natural=True)
        session._startup()
        self.assertEqual(session.report.handoff, 'natural')
        self.assertEqual(session.report.key_attempts, 0)
        self.assertFalse(any(row.get('action') == 'key' for row in session.commands))

    def test_original_deadline_is_twenty_seconds_and_samples_stay_bounded(self):
        session = Session(ready_after=1000)
        with self.assertRaises(probe.Failure) as caught:
            session._startup()
        self.assertEqual(caught.exception.code, 'STARTUP_DEADLINE')
        self.assertEqual(session.timer.now, 20)
        self.assertTrue(session.report.startup_deadline_expired)
        self.assertEqual(session.report.key_attempts, 1)
        self.assertLessEqual(len(session.report.samples), probe.MAX_SAMPLES)
        late = Session(ready_after=1000)

        def failed_exchange(command, **kwargs):
            late.timer.now = 20
            raise probe.Failure('HTTP_FAILED')

        late._rpc = failed_exchange
        with self.assertRaises(probe.Failure) as caught:
            late._startup()
        self.assertEqual(caught.exception.code, 'STARTUP_DEADLINE')
        self.assertIn('HTTP_FAILED', late.report.errors)
        self.assertTrue(late.report.startup_deadline_expired)

    def test_unknown_owners_and_nonempty_wallets_refuse_before_input(self):
        for key, bad in (('walletPresent', True), ('hasError', True),
                         ('owner', True), ('revision', -1)):
            with self.subTest(key=key):
                session = Session()
                original = session._rpc

                def corrupt(command, **kwargs):
                    body = original(command, **kwargs)
                    if command.get('action') == 'observe':
                        body[key] = bad
                    return body

                session._rpc = corrupt
                with self.assertRaises(probe.Failure) as caught:
                    session._startup()
                self.assertEqual(caught.exception.code, 'STARTUP_OBSERVATION_REFUSED')
                self.assertEqual(session.report.key_attempts, 0)


class NaturalStartupTests(unittest.TestCase):
    @staticmethod
    def project(value, *, natural_only=False, prior_manifest_sha256=None):
        return probe.observation_projection(
            value, head='a' * 40, tree='b' * 40, run_id='9', run_attempt='1',
            runner_sha256='c' * 64, payload_sha256='d' * 64,
            natural_only=natural_only,
            prior_manifest_sha256=prior_manifest_sha256,
        )

    def test_delayed_natural_startup_never_uses_the_enabled_skip_control(self):
        session = Session(ready_after=4, natural_only=True)
        session._startup()
        self.assertEqual(session.report.handoff, 'natural')
        self.assertEqual(session.report.key_attempts, 0)
        self.assertEqual(session.reads, 4)
        self.assertFalse(any(row.get('action') == 'key' for row in session.commands))
        self.assertTrue(session.report.checks['startup_ready'])

    def test_natural_deadline_keeps_twenty_seconds_and_zero_input(self):
        session = Session(ready_after=1000, natural_only=True)
        with self.assertRaises(probe.Failure) as caught:
            session._startup()
        self.assertEqual(caught.exception.code, 'STARTUP_DEADLINE')
        self.assertEqual(session.timer.now, 20)
        self.assertTrue(session.report.startup_deadline_expired)
        self.assertEqual(session.report.key_attempts, 0)
        self.assertFalse(any(row.get('action') == 'key' for row in session.commands))
        self.assertLessEqual(len(session.report.samples), probe.MAX_SAMPLES)

    def test_foreign_skip_observation_is_held_without_another_input(self):
        session = Session(natural_only=True, observed_skip=True)
        with self.assertRaises(probe.Failure) as caught:
            session._startup()
        self.assertEqual(caught.exception.code, 'STARTUP_OBSERVATION_REFUSED')
        self.assertEqual(session.report.key_attempts, 0)
        self.assertEqual(session.reads, 1)
        self.assertFalse(any(row.get('action') == 'key' for row in session.commands))

    def test_mode_requires_a_boolean_and_the_same_report(self):
        for value in (None, 0, 1, 'true', []):
            with self.subTest(value=value), self.assertRaises(probe.Failure):
                probe.Report(natural_only=value)
        with self.assertRaises(probe.Failure):
            probe.StartupProbe(Process(), None, 'private-token', Drain(),
                               positive_report(), natural_only=True,
                               limits=probe.LIMITS)

    def test_natural_report_has_its_own_scope_and_no_skip_qualification(self):
        report = positive_report(natural_only=True)
        public = report.public()
        self.assertTrue(public['success'])
        self.assertTrue(public['original_natural_qualified'])
        self.assertFalse(public['original_skip_qualified'])
        self.assertEqual(public['scope'], 'original_release_natural_startup_observation')
        self.assertEqual(report.summary()['scope'], 'original_release_natural_startup_summary')
        ordinary = positive_report().public()
        self.assertNotIn('prior_manifest_sha256', ordinary)
        self.assertNotIn('original_natural_qualified', ordinary)
        self.assertTrue(ordinary['original_skip_qualified'])

    def test_natural_success_requires_prior_exit_no_key_and_no_observed_skip(self):
        for field, bad in (('prior_manifest_sha256', None),
                           ('prior_manifest_sha256', 'private-state'),
                           ('key_attempts', 1), ('handoff', 'key-confirmed'),
                           ('startup_deadline_expired', True),
                           ('forced_kill', True)):
            report = positive_report(natural_only=True)
            setattr(report, field, bad)
            with self.subTest(field=field, bad=bad):
                self.assertFalse(report.public()['success'])
                self.assertFalse(report.public()['original_natural_qualified'])
        report = positive_report(natural_only=True)
        report.samples = [sample()]
        self.assertFalse(report.public()['success'])

    def test_closed_projection_binds_both_original_modes(self):
        ordinary = positive_report().public()
        self.assertEqual(self.project(ordinary), ordinary)
        natural = positive_report(natural_only=True).public()
        self.assertEqual(self.project(natural, natural_only=True,
                                     prior_manifest_sha256='e' * 64), natural)
        self.assertIsNone(self.project(natural))
        self.assertIsNone(self.project(ordinary, natural_only=True,
                                       prior_manifest_sha256='e' * 64))
        self.assertIsNone(self.project(natural, natural_only=True,
                                       prior_manifest_sha256='f' * 64))

    def test_closed_projection_refuses_private_fields_and_boolean_integer_aliases(self):
        ordinary = positive_report().public()
        changes = ({'success': 1}, {'schema': True}, {'visual_matches': False},
                   {'source_sha': 'f' * 40}, {'run_id': '10'},
                   {'runner_sha256': 'f' * 64}, {'private': 'private-state'},
                   {'error_codes': ['private-state']},
                   {'checks': {**ordinary['checks'], 'private': True}},
                   {'samples': [sample(at_ms=True)]})
        for fields in changes:
            with self.subTest(fields=fields):
                self.assertIsNone(self.project({**ordinary, **fields}))
        for field in ('source_sha', 'source_tree', 'run_id', 'run_attempt',
                      'runner_sha256', 'payload_sha256'):
            with self.subTest(field=field):
                self.assertIsNone(self.project({**ordinary, field: None}))

    def test_closed_projection_preserves_original_failure(self):
        report = positive_report()
        report.startup_deadline_expired = True
        report.fail('STARTUP_DEADLINE')
        public = report.public()
        projected = self.project(public)
        self.assertEqual(projected, public)
        self.assertFalse(projected['success'])
        self.assertEqual(projected['error_codes'], ['STARTUP_DEADLINE'])
        self.assertIsNone(self.project({**public,
                                       'error_codes': ['STARTUP_DEADLINE'] * 2}))

    def read_prior(self, raw, report=None, *, size=None):
        report = positive_report(natural_only=True) if report is None else report
        directory = SimpleNamespace(st_mode=stat.S_IFDIR | 0o700)
        file = SimpleNamespace(st_mode=stat.S_IFREG | 0o400,
                               st_size=len(raw) if size is None else size)
        with patch.object(probe.bounded, 'plain',
                          side_effect=[directory, directory, file]), \
                patch.object(Path, 'open', return_value=io.BytesIO(raw)) as opened, \
                patch.object(probe.subprocess, 'Popen') as started:
            result = probe.require_prior_observation(Path('owned-lab'), report)
            opened.assert_called_once_with('rb')
            started.assert_not_called()
            return result

    def test_prior_manifest_retains_exact_bytes_and_matching_payload(self):
        raw = (json.dumps(positive_report().public(), sort_keys=True) + '\n').encode()
        self.assertEqual(self.read_prior(raw), hashlib.sha256(raw).hexdigest())
        target = positive_report(natural_only=True)
        target.payload_sha256 = 'f' * 64
        with self.assertRaises(probe.Failure) as caught:
            self.read_prior(raw, target)
        self.assertEqual(caught.exception.code, 'PRIOR_STARTUP_REFUSED')

    def test_prior_failure_or_truncated_manifest_cannot_start_another_profile(self):
        report = positive_report()
        report.forced_kill = True
        bad = [b'private-state', json.dumps(report.public()).encode()]
        for raw in bad:
            with self.subTest(raw=raw), self.assertRaises(probe.Failure) as caught:
                self.read_prior(raw)
            self.assertEqual(caught.exception.code, 'PRIOR_STARTUP_REFUSED')
        raw = json.dumps(positive_report().public()).encode()
        with self.assertRaises(probe.Failure):
            self.read_prior(raw, size=len(raw) + 1)

    def test_oversized_prior_manifest_is_refused_before_read(self):
        directory = SimpleNamespace(st_mode=stat.S_IFDIR | 0o700)
        file = SimpleNamespace(st_mode=stat.S_IFREG | 0o400,
                               st_size=probe.MAX_MANIFEST + 1)
        with patch.object(probe.bounded, 'plain',
                          side_effect=[directory, directory, file]), \
                patch.object(Path, 'open') as opened, \
                self.assertRaises(probe.Failure) as caught:
            probe.require_prior_observation(Path('owned-lab'),
                                            positive_report(natural_only=True))
        self.assertEqual(caught.exception.code, 'PRIOR_STARTUP_REFUSED')
        opened.assert_not_called()

    def test_only_exact_natural_argument_is_admitted_before_ci(self):
        for arguments in (['--natural-only', 'private-state'], ['--natural'], 'private-state'):
            with self.subTest(arguments=arguments), redirect_stdout(io.StringIO()), \
                    patch.object(probe.entry, 'require_ci') as admitted:
                self.assertEqual(probe.main(arguments), 1)
                admitted.assert_not_called()
        with redirect_stdout(io.StringIO()), \
                patch.object(probe.entry, 'require_ci',
                             side_effect=probe.Failure('ENVIRONMENT_REFUSED')) as admitted, \
                patch.object(probe.entry, 'new_profile') as allocated:
            self.assertEqual(probe.main(['--natural-only']), 1)
            admitted.assert_called_once()
            allocated.assert_not_called()


if __name__ == '__main__':
    unittest.main()
