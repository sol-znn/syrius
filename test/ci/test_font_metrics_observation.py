"""Bound font metrics to the original finite fixture and reject private fields."""

import copy
import json
import unittest

from tool.ci import font_metrics_observation as metrics


class FontMetricsTests(unittest.TestCase):
    def fixture(self):
        samples = [dict(size=size, height=height, width=size * 9,
            line_height=size * height, natural_ascent=size * .8,
            natural_descent=size * .2, even_baseline=size * height / 2,
            proportional_baseline=size * height * .8, even_ascent=size,
            even_descent=size * .2, even_mode=1, proportional_mode=0)
            for size in (12, 14, 28, 56) for height in (1.45, 2)]
        return dict(schema=1, font='bundled_interface', samples=samples)

    def event(self, value):
        return (json.dumps(dict(type='print', testID=17,
            message=metrics.PREFIX + json.dumps(value))) + '\n').encode()

    def test_complete_and_partial_metrics_retain_only_finite_original_samples(self):
        original = self.fixture()
        result = metrics.project(self.event(original), complete=True)
        self.assertEqual(result['status'], 'OBSERVED')
        self.assertTrue(result['complete_cases'])
        self.assertEqual(result['samples'], original['samples'])
        self.assertEqual(set(result), {'schema', 'scope', 'status', 'font',
                                      'sample_count', 'complete_cases', 'samples'})
        partial = dict(original, samples=original['samples'][:3])
        result = metrics.project(self.event(partial), complete=True)
        self.assertEqual(result['status'], 'OBSERVED')
        self.assertFalse(result['complete_cases'])
        self.assertEqual(result['sample_count'], 3)
        # Observation includes failed/zero states and both enum values. It
        # carries no test-success or font-validity authority.
        for even_mode, proportional_mode in ((0, 0), (0, 1), (1, 0), (1, 1)):
            failed = self.fixture()
            failed['samples'][0].update(width=0, line_height=0,
                natural_ascent=0, natural_descent=0, even_baseline=0,
                proportional_baseline=0, even_ascent=0, even_descent=0,
                even_mode=even_mode, proportional_mode=proportional_mode)
            result = metrics.project(self.event(failed), complete=True)
            self.assertEqual(result['status'], 'OBSERVED')
            self.assertEqual(result['samples'][0], failed['samples'][0])
            self.assertNotIn('success', result)
        self.assertEqual(original, self.fixture())

    def test_unknown_fields_labels_and_types_cannot_escape_the_projection(self):
        for change in (dict(font='private-input'), dict(path='private-input'),
                       dict(schema=True), dict(schema=2), dict(samples={}),
                       dict(samples=[])):
            result = metrics.project(self.event(dict(self.fixture(), **change)),
                                     complete=True)
            self.assertEqual(result, dict(schema=1, scope='bundled_font_metrics',
                                          status='REFUSED'))
            self.assertNotIn('private-input', json.dumps(result))

    def test_nonfinite_unbounded_or_private_sample_values_are_refused(self):
        for key, value in (('width', True), ('width', float('nan')),
                          ('width', float('inf')), ('width', -1),
                          ('width', 4097), ('natural_ascent', 'private-input'),
                          ('even_mode', 2), ('proportional_mode', 2),
                          ('detail', 'private-input')):
            original = self.fixture()
            original['samples'][0][key] = value
            result = metrics.project(self.event(original), complete=True)
            self.assertEqual(result['status'], 'REFUSED')
            self.assertNotIn('private-input', json.dumps(result))

    def test_duplicate_malformed_or_reordered_messages_never_grant_observation(self):
        event = self.event(self.fixture())
        self.assertIsNone(metrics.project(b'{"type":"done"}\n', complete=True))
        for raw in (event + event, b'not-json\n', event + b'\xff',
                    self.event('private-input')):
            self.assertEqual(metrics.project(raw, complete=True)['status'], 'REFUSED')
        original = copy.deepcopy(self.fixture())
        original['samples'][0], original['samples'][1] = (
            original['samples'][1], original['samples'][0])
        self.assertEqual(metrics.project(self.event(original), complete=True)['status'],
                         'REFUSED')

    def test_incomplete_and_oversized_streams_never_become_positive_metrics(self):
        event = self.event(self.fixture())
        for raw, complete in ((event, False), (event, None), (event.decode(), True),
                              (b' ' * (4 * 1024**2 + 1), True)):
            self.assertEqual(metrics.project(raw, complete=complete)['status'], 'REFUSED')


class CaptionWordmarkMetricsTests(unittest.TestCase):
    def fixture(self):
        return dict(schema=1, samples=[dict(
            theme=theme, variant=variant, font_size=12, tracking=4.08,
            line_height=17, line_width=65, baseline=12.45,
            origin_x=14 - variant * 2.04, origin_y=7.5,
            ink_left=16 - variant * 2, ink_top=13,
            ink_right=75 - variant * 2, ink_bottom=20, ink_pixels=240,
            image_width=128, image_height=32,
        ) for theme, variant in ((0, 0), (0, 1), (1, 0), (1, 1))])

    def event(self, value):
        return (json.dumps(dict(type='print',
            message=metrics.CAPTION_PREFIX + json.dumps(value))) + '\n').encode()

    def test_complete_partial_and_empty_ink_do_not_grant_visual_success(self):
        source = self.fixture()
        result = metrics.project_caption(self.event(source), complete=True)
        self.assertEqual(result['status'], 'OBSERVED')
        self.assertTrue(result['complete_cases'])
        self.assertFalse(result['visual_match_qualified'])
        self.assertNotIn('success', result)
        self.assertEqual(result['samples'], source['samples'])
        result['samples'][0]['ink_left'] = 0
        self.assertEqual(source, self.fixture())
        partial = dict(source, samples=source['samples'][:2])
        result = metrics.project_caption(self.event(partial), complete=True)
        self.assertFalse(result['complete_cases'])
        empty = self.fixture()
        empty['samples'][0].update(ink_left=0, ink_top=0, ink_right=0,
                                  ink_bottom=0, ink_pixels=0)
        result = metrics.project_caption(self.event(empty), complete=True)
        self.assertEqual(result['status'], 'OBSERVED')
        self.assertEqual(result['samples'][0]['ink_pixels'], 0)
        self.assertFalse(result['visual_match_qualified'])

    def test_unknown_or_private_fields_and_sample_types_are_refused(self):
        for fields in (dict(schema=True), dict(schema=2), dict(text='private-input'),
                       dict(samples=[]), dict(samples={})):
            result = metrics.project_caption(self.event(dict(self.fixture(), **fields)),
                                             complete=True)
            self.assertEqual(result['status'], 'REFUSED')
            self.assertNotIn('private-input', json.dumps(result))
        for field, value in (('line_width', True), ('line_width', float('nan')),
                             ('line_width', float('inf')), ('line_width', -1),
                             ('line_width', 4097), ('ink_left', 2.5),
                             ('theme', 0.0), ('variant', True),
                             ('detail', 'private-input')):
            record = self.fixture()
            record['samples'][0][field] = value
            result = metrics.project_caption(self.event(record), complete=True)
            self.assertEqual(result['status'], 'REFUSED')
            self.assertNotIn('private-input', json.dumps(result))

    def test_wrong_raster_geometry_and_ink_bounds_are_refused(self):
        for field, value in (('image_width', 127), ('image_height', 31),
                             ('font_size', 14), ('tracking', 0),
                             ('ink_left', 76), ('ink_right', 128),
                             ('ink_top', 21), ('ink_bottom', 32),
                             ('line_height', 33), ('baseline', 33),
                             ('origin_x', 33), ('origin_y', 33)):
            record = self.fixture()
            record['samples'][0][field] = value
            self.assertEqual(metrics.project_caption(self.event(record),
                complete=True)['status'], 'REFUSED')

    def test_order_duplicate_or_malformed_records_cannot_replace_the_original(self):
        record = self.fixture()
        record['samples'][0], record['samples'][1] = (
            record['samples'][1], record['samples'][0])
        event = self.event(self.fixture())
        for raw in (self.event(record), event + event, b'not-json\n',
                    event + b'\xff', self.event('private-input')):
            self.assertEqual(metrics.project_caption(raw, complete=True)['status'],
                             'REFUSED')

    def test_incomplete_or_oversized_streams_are_refused(self):
        event = self.event(self.fixture())
        for data, complete in ((event, False), (event, None), (event.decode(), True),
                               (b' ' * (4 * 1024**2 + 1), True)):
            self.assertEqual(metrics.project_caption(data, complete=complete)['status'],
                             'REFUSED')

    def test_other_events_never_export_their_messages_or_test_authority(self):
        private = (json.dumps(dict(type='print', message='private-input')) + '\n').encode()
        self.assertIsNone(metrics.project_caption(private, complete=True))
        terminal = b'{"type":"done","success":true}\n'
        self.assertIsNone(metrics.project_caption(terminal, complete=True))
        result = metrics.project_caption(private + self.event(self.fixture()) + terminal,
                                         complete=True)
        self.assertEqual(result['status'], 'OBSERVED')
        self.assertNotIn('private-input', json.dumps(result))
        self.assertNotIn('success', result)
