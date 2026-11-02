"""Project only finite Welcome trim-renderer counts, never pixel buffers."""
import json

PREFIX = 'CI_WELCOME_TRIM_METRICS:'
ORDER = (('dark', 96), ('dark', 160), ('light', 96), ('light', 160))
METRICS = frozenset(('present', 'expected', 'overlap', 'extra', 'missing'))
CAP = 470 * 470


def _unique(items):
    value = {}
    for key, child in items:
        if key in value:
            raise ValueError('Duplicate field')
        value[key] = child
    return value


def _mask(value):
    return (type(value) is dict and set(value) == METRICS
        and all(type(v) is int and 0 <= v <= CAP for v in value.values())
        and value['overlap'] <= min(value['present'], value['expected'])
        and value['present'] + value['expected'] - value['overlap'] <= CAP
        and value['extra'] == value['present'] - value['overlap']
        and value['missing'] == value['expected'] - value['overlap'])


def project(data, *, complete):
    refused = dict(schema=1, scope='welcome_trim_metrics', status='REFUSED')
    if complete is not True or type(data) is not bytes or len(data) > 4 * 1024**2:
        return refused
    found = []
    try:
        for line in data.decode('utf8').splitlines():
            event = json.loads(line, object_pairs_hook=_unique)
            if type(event) is not dict or event.get('type') != 'print':
                continue
            message = event.get('message')
            if type(message) is str and message.startswith(PREFIX):
                if len(message) > 8192:
                    return refused
                found.append(json.loads(message[len(PREFIX):], object_pairs_hook=_unique))
        if not found:
            return None
        if len(found) != 1:
            return refused
        value = found[0]
        if (type(value) is not dict
                or set(value) != {'schema', 'frame', 'frame_count', 'edge',
                                  'swapped_channels', 'samples'}
                or any(type(value[k]) is not int or value[k] != v
                    for k, v in dict(schema=1, frame=720, frame_count=1800,
                                     edge=470, swapped_channels=2).items())
                or type(value['samples']) is not list
                or len(value['samples']) != len(ORDER)):
            return refused
        samples = []
        for index, sample in enumerate(value['samples']):
            if (type(sample) is not dict
                    or set(sample) != {'theme', 'threshold', 'original', 'sorted'}
                    or type(sample['theme']) is not str
                    or type(sample['threshold']) is not int
                    or (sample['theme'], sample['threshold']) != ORDER[index]
                    or not _mask(sample['original']) or not _mask(sample['sorted'])
                    or sample['original']['expected'] != sample['sorted']['expected']):
                return refused
            samples.append(dict(theme=sample['theme'], threshold=sample['threshold'],
                original=dict(sample['original']), sorted=dict(sample['sorted'])))
        return dict(schema=1, scope='welcome_trim_metrics', status='OBSERVED',
            frame=720, frame_count=1800, edge=470, swapped_channels=2,
            complete_cases=True, numeric_observation_only=True,
            nonempty=all(v[mode][field] > 0 for v in samples
                         for mode in ('original', 'sorted')
                         for field in ('present', 'expected')), samples=samples)
    except (ValueError, TypeError, UnicodeError, OverflowError, KeyError, RecursionError):
        return refused
