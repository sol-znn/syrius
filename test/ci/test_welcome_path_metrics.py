"""Closed aggregate counts do not authorize pixel matches or production changes."""
import json
import unittest
from tool.ci import welcome_path_metrics as metrics


class WelcomePathMetricsTests(unittest.TestCase):
    @staticmethod
    def value():
        return dict(schema=1, frame=720, frame_count=1800, edge=470,
            changed_pixels=dict.fromkeys(metrics.MODES, 7), samples=[
                dict(theme=theme, threshold=threshold,
                    original=dict(present=14, expected=10, overlap=8, extra=6, missing=2),
                    variants={mode: dict(present=12, expected=10, overlap=9,
                        extra=3, missing=1, changed_mask=4) for mode in metrics.MODES})
                for theme, threshold in metrics.ORDER])

    @staticmethod
    def encoded(value=None, *, payload=None):
        raw = payload if payload is not None else json.dumps(
            WelcomePathMetricsTests.value() if value is None else value)
        return (json.dumps(dict(type='print', message=metrics.PREFIX + raw)) + '\n').encode()

    def refused(self, data, *, complete=True):
        result = metrics.project(data, complete=complete)
        self.assertEqual(result, dict(schema=1, scope='welcome_path_metrics', status='REFUSED'))
        self.assertNotIn('private-test-material', json.dumps(result))

    def test_closed_modes_and_thresholds_export_only_bounded_aggregate_columns(self):
        value = metrics.project(self.encoded(), complete=True)
        self.assertEqual(value['status'], 'OBSERVED')
        self.assertEqual(value['order'], [list(row) for row in metrics.ORDER])
        self.assertEqual(value['columns'], list(metrics.COLUMNS))
        self.assertEqual(value['original'], [[14, 10, 8, 6, 2]] * 8)
        for mode in metrics.MODES:
            self.assertEqual(value['variants'][mode], [[12, 10, 9, 3, 1, 4]] * 8)
        self.assertTrue(value['numeric_observation_only'])
        self.assertTrue(value['nonempty'])
        self.assertLess(len(json.dumps(value, separators=(',', ':')).encode()), 3300)
        for key in ('pixels', 'path', 'success', 'visual_match', 'accepted'):
            self.assertNotIn(key, value)

    def test_absent_incomplete_unbounded_duplicate_and_recursive_events_are_refused(self):
        self.assertIsNone(metrics.project(b'', complete=True))
        for complete in (False, None, 1):
            self.refused(self.encoded(), complete=complete)
        for data in (None, True, '', b'\xff', b'x' * (4 * 1024**2 + 1)):
            self.refused(data)
        self.refused(self.encoded(payload=' ' * 16385))
        self.refused(self.encoded() * 2)
        original = json.dumps(self.value())
        for before, after in (('"schema": 1', '"schema": 1, "schema": 1'),
                              ('"present": 14', '"present": 14, "present": 14')):
            self.refused(self.encoded(payload=original.replace(before, after, 1)))
        self.refused(self.encoded(payload='[' * 1200 + '0' + ']' * 1200))

    def test_unknown_private_coerced_or_incomplete_modes_and_columns_are_refused(self):
        for changes in (dict(schema=True), dict(frame=721), dict(edge=471),
                        dict(frame_count=1799.99), dict(path='private-test-material'),
                        dict(pixels=[]), dict(accepted=True)):
            value = self.value()
            value.update(changes)
            self.refused(self.encoded(value))
        for changes in (dict(theme='private-test-material'), dict(threshold=True),
                        dict(threshold=33), dict(address='private-test-material')):
            value = self.value()
            value['samples'][0].update(changes)
            self.refused(self.encoded(value))
        for mode in metrics.MODES:
            value = self.value()
            del value['samples'][0]['variants'][mode]
            self.refused(self.encoded(value))
            value = self.value()
            value['changed_pixels'][mode] = True
            self.refused(self.encoded(value))
        value = self.value()
        value['samples'].reverse()
        self.refused(self.encoded(value))

    def test_impossible_masks_pixel_disagreements_and_coercions_are_refused(self):
        for changes in (dict(present=True), dict(extra=4), dict(missing=2),
                        dict(present=-1), dict(present=metrics.CAP + 1),
                        dict(changed_mask=True), dict(changed_mask=8),
                        dict(changed_mask=1), dict(changed_mask=3),
                        dict(expected=11, missing=2), dict(hash='private-test-material')):
            value = self.value()
            value['samples'][0]['variants']['nested'].update(changes)
            self.refused(self.encoded(value))
        value = self.value()
        value['samples'][0]['original'].update(present=metrics.CAP,
            expected=metrics.CAP, overlap=0, extra=metrics.CAP, missing=metrics.CAP)
        self.refused(self.encoded(value))
        for changed in (-1, metrics.CAP + 1, 7.0):
            value = self.value()
            value['changed_pixels']['channels'] = changed
            self.refused(self.encoded(value))

    def test_zero_or_identical_variants_do_not_grant_acceptance_or_require_improvement(self):
        value = self.value()
        value['changed_pixels'] = dict.fromkeys(metrics.MODES, 0)
        for sample in value['samples']:
            sample['original'] = dict.fromkeys(metrics.COLUMNS[:5], 0)
            sample['variants'] = {mode: dict.fromkeys(metrics.COLUMNS, 0)
                                  for mode in metrics.MODES}
        result = metrics.project(self.encoded(value), complete=True)
        self.assertEqual(result['status'], 'OBSERVED')
        self.assertFalse(result['nonempty'])
        self.assertNotIn('visual_match', result)
        self.assertNotIn('accepted', result)
