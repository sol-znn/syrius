"""Exercise partial progress, protocol ambiguity and the closed privacy boundary."""

import json
from pathlib import PureWindowsPath
import unittest

from tool.ci import dart_test_progress as progress


PATHS = ['test/harness/first_test.dart', 'test/receive/second_test.dart']
ROOT = '/fixture/private-repository'
CANARY = 'private-name secret-value private-message private-host'


def stream(*events):
    return ('\n'.join(json.dumps(event) for event in events) + '\n').encode()


def suite(identity=1, *, path=None, stamp=1):
    return dict(type='suite', time=stamp,
                suite=dict(id=identity, path=path or ROOT + '/' + PATHS[0]))


def start(identity=1, *, suite_id=1, stamp=2, url=None, line=12):
    return dict(type='testStart', time=stamp,
                test=dict(id=identity, suiteID=suite_id, name=CANARY,
                          url=url or ROOT + '/' + PATHS[0], line=line))


def done(identity=1, *, stamp=5, **extra):
    return dict(type='testDone', time=stamp, testID=identity, result='success', **extra)


class DartProgressTests(unittest.TestCase):
    def observe(self, raw, **kwargs):
        return progress.project(raw, suite_paths=kwargs.get('paths', PATHS),
                                repo=kwargs.get('repo', ROOT))

    def test_partial_stream_exports_only_bounded_opaque_positions(self):
        raw = stream(suite(), start(), dict(type='print', time=42,
            testID=1, message=CANARY, remoteDebugger=CANARY))
        value = self.observe(raw)
        self.assertEqual(value['status'], 'OBSERVED_PARTIAL')
        self.assertFalse(value['qualification'])
        self.assertEqual(value['unfinished_total'], 1)
        self.assertEqual(value['unfinished'][0], dict(test_id=1, suite_id=1,
            suite_index=1, case_ordinal=1, line=12, observed_span_ms=40))
        for forbidden in (CANARY, ROOT, *PATHS, 'remoteDebugger', 'message'):
            self.assertNotIn(forbidden, json.dumps(value))

    def test_interleaved_hidden_loading_and_late_errors_stay_observations(self):
        raw = stream(start(90, suite_id=0, stamp=0), suite(), start(),
            done(90, stamp=7, hidden=True), done(stamp=6),
            dict(type='error', time=9, testID=1, error=CANARY, stackTrace=CANARY),
            dict(type='done', time=10, success=False))
        value = self.observe(raw)
        self.assertEqual(value['status'], 'OBSERVED_TERMINAL')
        self.assertFalse(value['engine_terminal_success'])
        self.assertFalse(value['qualification'])
        self.assertEqual(value['finished_observed'], 2)
        self.assertEqual(value['ordinary_done_observed'], 1)
        self.assertEqual(value['hidden_done_observed'], 1)
        self.assertEqual(value['error_events_observed'], 1)
        self.assertEqual(value['unfinished_total'], 0)
        self.assertEqual(value['longest_observed'][0]['suite_index'], 0)
        self.assertNotIn(CANARY, json.dumps(value))

    def test_windows_file_urls_map_only_exact_selected_sources(self):
        root = r'D:\fixture\repo'
        value = self.observe(stream(suite(path=r'd:\fixture\repo\test\harness\first_test.dart'),
            start(url=PureWindowsPath('D:/fixture/repo/test/harness/first_test.dart').as_uri()),
            start(2, url=PureWindowsPath('D:/elsewhere/first_test.dart').as_uri(), stamp=3)), repo=root)
        self.assertEqual(value['unfinished'][0]['suite_index'], 1)
        self.assertEqual(value['unfinished'][0]['line'], 12)
        self.assertEqual(value['unfinished'][1]['line'], 0)
        outside = self.observe(stream(suite(path='/elsewhere/' + PATHS[0]), start()))
        self.assertEqual(outside['last_started']['suite_index'], 0)
        self.assertEqual(outside['last_started']['line'], 0)

    def test_duplicate_invalid_and_truncated_events_refuse_without_echo(self):
        cases = [stream(suite(), suite()), stream(suite(), start(), start()),
            stream(suite(), start(), done(), done()), stream(suite(), done()),
            stream(suite(), start(stamp=True)), stream(suite(), start(), done(stamp=1)),
            stream(suite(), start(), dict(type='done', time=3, success=True), done()),
            stream(suite(), start()) + ('{"secret":"' + CANARY).encode(),
            b'[]\n', stream(dict(type='unknown', time=2, data=CANARY))]
        for raw in cases:
            with self.subTest(sha_length=len(raw)):
                value = self.observe(raw)
                self.assertEqual(value['status'], 'REFUSED')
                self.assertFalse(value['qualification'])
                self.assertNotIn(CANARY, json.dumps(value))

    def test_output_and_identity_limits_and_partial_terminal_are_explicit(self):
        self.assertEqual(self.observe(b'x' * (4 * 1024**2 + 1))['status'], 'REFUSED')
        self.assertEqual(self.observe(stream(suite(), start(identity=20001)))['status'], 'REFUSED')
        self.assertEqual(self.observe(stream(suite(), start()),
            paths=['test/../private_test.dart'])['status'], 'REFUSED')
        value = self.observe(stream(suite(), start(),
            dict(type='done', time=8, success=None)))
        self.assertTrue(value['engine_terminal_seen'])
        self.assertIsNone(value['engine_terminal_success'])
        self.assertEqual(value['status'], 'OBSERVED_PARTIAL')
        self.assertEqual(value['unfinished_total'], 1)

    def test_tail_caps_preserve_totals_without_claiming_suite_completion(self):
        events = []
        for identity in range(1, 31):
            events += [suite(identity, stamp=identity),
                       start(identity, suite_id=identity, stamp=identity + 1)]
        value = self.observe(stream(*events))
        self.assertEqual(value['unfinished_total'], 30)
        self.assertEqual(len(value['unfinished']), 8)
        self.assertEqual(len(value['recent_suites']), 8)
        self.assertEqual(value['last_started']['test_id'], 30)
        self.assertNotIn('suite_complete', json.dumps(value))
        self.assertLess(len(json.dumps(value).encode()), 3400)
