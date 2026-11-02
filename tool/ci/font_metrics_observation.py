"""Project finite metrics from one fixed font fixture, without displayed text."""

import json
import math


PREFIX = 'CI_BUNDLED_FONT_METRICS:'
ORDER = tuple((size, height) for size in (12, 14, 28, 56)
              for height in (1.45, 2))
FIELDS = frozenset(('size', 'height', 'width', 'line_height',
    'natural_ascent', 'natural_descent', 'even_baseline',
    'proportional_baseline', 'even_ascent', 'even_descent',
    'even_mode', 'proportional_mode'))


def project(data, *, complete):
    refused = dict(schema=1, scope='bundled_font_metrics', status='REFUSED')
    if complete is not True or type(data) is not bytes or len(data) > 4 * 1024**2:
        return refused
    records = []
    try:
        for line in data.decode('utf8').splitlines():
            event = json.loads(line)
            if type(event) is not dict or event.get('type') != 'print':
                continue
            message = event.get('message')
            if type(message) is str and message.startswith(PREFIX):
                if len(message) > 8192:
                    return refused
                records.append(json.loads(message[len(PREFIX):]))
        if not records:
            return None
        if len(records) != 1:
            return refused
        record = records[0]
        if (type(record) is not dict or set(record) != {'schema', 'font', 'samples'}
                or type(record['schema']) is not int or record['schema'] != 1
                or record['font'] != 'bundled_interface'
                or type(record['samples']) is not list
                or not 1 <= len(record['samples']) <= len(ORDER)):
            return refused
        samples = []
        for index, sample in enumerate(record['samples']):
            if (type(sample) is not dict or set(sample) != FIELDS
                    or any(type(value) not in (int, float)
                        or not math.isfinite(value) or not 0 <= value <= 4096
                        for value in sample.values())
                    or (sample['size'], sample['height']) != ORDER[index]
                    or not 0 <= sample['line_height'] < 256
                    or sample['even_mode'] not in (0, 1)
                    or sample['proportional_mode'] not in (0, 1)):
                return refused
            samples.append(dict(sample))
        return dict(schema=1, scope='bundled_font_metrics', status='OBSERVED',
            font='bundled_interface', sample_count=len(samples),
            complete_cases=len(samples) == len(ORDER), samples=samples)
    except (ValueError, TypeError, UnicodeError, OverflowError):
        return refused


CAPTION_PREFIX = 'CI_CAPTION_WORDMARK_METRICS:'
CAPTION_ORDER = ((0, 0), (0, 1), (1, 0), (1, 1))
CAPTION_FIELDS = frozenset(('theme', 'variant', 'font_size', 'tracking',
    'line_height', 'line_width', 'baseline', 'origin_x', 'origin_y',
    'ink_left', 'ink_top', 'ink_right', 'ink_bottom', 'ink_pixels',
    'image_width', 'image_height'))


def project_caption(data, *, complete):
    """Keep one fixed caption raster's numeric geometry, including failed states."""
    refused = dict(schema=1, scope='caption_wordmark_metrics', status='REFUSED')
    if complete is not True or type(data) is not bytes or len(data) > 4 * 1024**2:
        return refused
    records = []
    try:
        for line in data.decode('utf8').splitlines():
            event = json.loads(line)
            if type(event) is not dict or event.get('type') != 'print':
                continue
            message = event.get('message')
            if type(message) is str and message.startswith(CAPTION_PREFIX):
                if len(message) > 8192:
                    return refused
                records.append(json.loads(message[len(CAPTION_PREFIX):]))
        if not records:
            return None
        if len(records) != 1:
            return refused
        record = records[0]
        if (type(record) is not dict or set(record) != {'schema', 'samples'}
                or type(record['schema']) is not int or record['schema'] != 1
                or type(record['samples']) is not list
                or not 1 <= len(record['samples']) <= len(CAPTION_ORDER)):
            return refused
        samples = []
        for index, sample in enumerate(record['samples']):
            if (type(sample) is not dict or set(sample) != CAPTION_FIELDS
                    or any(type(value) not in (int, float)
                        or not math.isfinite(value) or not 0 <= value <= 4096
                        for value in sample.values())
                    or type(sample['theme']) is not int
                    or type(sample['variant']) is not int
                    or (sample['theme'], sample['variant']) != CAPTION_ORDER[index]
                    or sample['image_width'] != 128 or sample['image_height'] != 32
                    or sample['font_size'] != 12 or sample['tracking'] != 4.08
                    or not 0 <= sample['line_height'] <= 32
                    or not 0 <= sample['baseline'] <= 32
                    or not 0 <= sample['origin_x'] <= 32
                    or not 0 <= sample['origin_y'] <= 32
                    or not 0 <= sample['ink_left'] <= sample['ink_right'] < 128
                    or not 0 <= sample['ink_top'] <= sample['ink_bottom'] < 32
                    or any(type(sample[key]) is not int for key in
                        ('ink_left', 'ink_top', 'ink_right', 'ink_bottom',
                         'ink_pixels', 'image_width', 'image_height'))):
                return refused
            samples.append(dict(sample))
        return dict(schema=1, scope='caption_wordmark_metrics', status='OBSERVED',
            sample_count=len(samples), complete_cases=len(samples) == len(CAPTION_ORDER),
            samples=samples, visual_match_qualified=False)
    except (ValueError, TypeError, UnicodeError, OverflowError):
        return refused
