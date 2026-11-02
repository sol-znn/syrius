"""Finite numeric observations never admit visual matches or private payloads."""
import json
import unittest

from tool.ci import welcome_trim_metrics as metrics


class WelcomeTrimMetricsTests(unittest.TestCase):
    @staticmethod
    def value():
        return dict(schema=1, frame=720, frame_count=1800, edge=470,
            swapped_channels=2, samples=[dict(theme=theme, threshold=threshold,
                original=dict(present=14, expected=10, overlap=8, extra=6, missing=2),
                sorted=dict(present=12, expected=10, overlap=9, extra=3, missing=1))
                for theme, threshold in metrics.ORDER])

    @staticmethod
    def encoded(value=None, *, payload=None):
        raw = payload if payload is not None else json.dumps(
            WelcomeTrimMetricsTests.value() if value is None else value)
        return (json.dumps(dict(type='print', message=metrics.PREFIX + raw)) + '\n').encode()

    def refused(self, data, *, complete=True):
        value = metrics.project(data, complete=complete)
        self.assertEqual(value, dict(schema=1, scope='welcome_trim_metrics', status='REFUSED'))
        self.assertNotIn('private-test-material', json.dumps(value))

    def test_two_themes_and_thresholds_retain_only_numeric_original_observations(self):
        value = metrics.project(self.encoded(), complete=True)
        self.assertEqual(value['status'], 'OBSERVED')
        self.assertTrue(value['nonempty'])
        self.assertTrue(value['complete_cases'])
        self.assertTrue(value['numeric_observation_only'])
        self.assertEqual([(row['theme'], row['threshold']) for row in value['samples']],
                         list(metrics.ORDER))
        for row in value['samples']:
            self.assertEqual(row['original']['extra'], 6)
            self.assertEqual(row['sorted']['extra'], 3)
        for key in ('success', 'visual_match', 'accepted', 'pixels', 'path'):
            self.assertNotIn(key, value)

    def test_absent_prints_and_incomplete_or_unbounded_commands_cannot_be_promoted(self):
        self.assertIsNone(metrics.project(b'', complete=True))
        self.assertIsNone(metrics.project(b'{"type":"print","message":"ordinary"}\n',
                                         complete=True))
        for complete in (False, None, 1):
            self.refused(self.encoded(), complete=complete)
        for data in (None, True, '', b'\xff', b'x' * (4 * 1024**2 + 1)):
            self.refused(data)
        self.refused(self.encoded(payload=' ' * 8193))

    def test_unknown_private_coerced_duplicate_and_recursive_fields_are_refused(self):
        for changes in (dict(schema=True), dict(frame=721), dict(frame_count=1799.99),
                dict(edge=471), dict(swapped_channels=1), dict(path='private-test-material'),
                dict(pixels=[]), dict(success=True)):
            value = self.value()
            value.update(changes)
            self.refused(self.encoded(value))
        for changes in (dict(theme='private-test-material'), dict(theme=True),
                dict(threshold=True), dict(threshold=97), dict(path='private-test-material')):
            value = self.value()
            value['samples'][0].update(changes)
            self.refused(self.encoded(value))
        original = json.dumps(self.value())
        self.refused(self.encoded(payload=original.replace('"schema": 1',
            '"schema": 1, "schema": 1', 1)))
        self.refused(self.encoded(payload=original.replace('"present": 14',
            '"present": 14, "present": 14', 1)))
        message = json.dumps(metrics.PREFIX + original)
        self.refused(('{"type":"print","type":"print","message":' + message + '}\n').encode())
        self.refused(self.encoded(payload='[' * 1200 + '0' + ']' * 1200))
        for payload in ('null', 'true', '[]', '{'):
            self.refused(self.encoded(payload=payload))
        self.refused(self.encoded() * 2)

    def test_impossible_areas_and_inconsistent_or_unbounded_counts_are_refused(self):
        cap = metrics.CAP
        for changes in (dict(present=True), dict(present=-1), dict(present=cap + 1),
                dict(present=float('nan')), dict(extra=5), dict(missing=3),
                dict(overlap=11, extra=3, missing=-1),
                dict(present=cap, expected=cap, overlap=0, extra=cap, missing=cap),
                dict(address='private-test-material')):
            value = self.value()
            value['samples'][0]['original'].update(changes)
            self.refused(self.encoded(value))
        value = self.value()
        value['samples'][0]['sorted'].update(expected=11, missing=2)
        self.refused(self.encoded(value))
        for count in (0, 3, 5):
            value = self.value()
            value['samples'] = (value['samples'] * 2)[:count]
            self.refused(self.encoded(value))
        value = self.value()
        value['samples'].reverse()
        self.refused(self.encoded(value))

    def test_zero_measurements_remain_observed_without_nonempty_or_acceptance_authority(self):
        value = self.value()
        for sample in value['samples']:
            for mode in ('original', 'sorted'):
                sample[mode] = dict.fromkeys(metrics.METRICS, 0)
        observed = metrics.project(self.encoded(value), complete=True)
        self.assertEqual(observed['status'], 'OBSERVED')
        self.assertFalse(observed['nonempty'])
        self.assertTrue(observed['numeric_observation_only'])
        self.assertNotIn('accepted', observed)
        self.assertNotIn('success', observed)
        self.assertNotIn('visual_match', observed)
