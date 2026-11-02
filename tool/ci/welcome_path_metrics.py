"""Fixed aggregate path measurements; pixel buffers and match claims are refused."""
import json

PREFIX = 'CI_WELCOME_PATH_METRICS:'
MODES = ('channels', 'nested', 'flattened', 'flattened_sorted')
ORDER = tuple((theme, threshold) for theme in ('dark', 'light')
              for threshold in (32, 64, 96, 160))
COLUMNS = ('present', 'expected', 'overlap', 'extra', 'missing', 'changed_mask')
CAP = 470 * 470


def _unique(items):
    value = {}
    for key, child in items:
        if key in value:
            raise ValueError('Duplicate field')
        value[key] = child
    return value


def _mask(value):
    return (type(value) is dict and set(value) == set(COLUMNS[:5])
            and all(type(v) is int and 0 <= v <= CAP for v in value.values())
            and value['overlap'] <= min(value['present'], value['expected'])
            and value['present'] + value['expected'] - value['overlap'] <= CAP
            and value['extra'] == value['present'] - value['overlap']
            and value['missing'] == value['expected'] - value['overlap'])


def project(data, *, complete):
    refused = dict(schema=1, scope='welcome_path_metrics', status='REFUSED')
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
                if len(message) > 16384:
                    return refused
                found.append(json.loads(message[len(PREFIX):], object_pairs_hook=_unique))
        if not found:
            return None
        if len(found) != 1:
            return refused
        value = found[0]
        if (type(value) is not dict or set(value) != {
                'schema', 'frame', 'frame_count', 'edge', 'changed_pixels', 'samples'}
                or any(type(value[key]) is not int or value[key] != expected
                       for key, expected in dict(schema=1, frame=720,
                           frame_count=1800, edge=470).items())
                or type(value['changed_pixels']) is not dict
                or set(value['changed_pixels']) != set(MODES)
                or any(type(v) is not int or not 0 <= v <= CAP
                       for v in value['changed_pixels'].values())
                or type(value['samples']) is not list or len(value['samples']) != len(ORDER)):
            return refused
        originals = []
        variants = {mode: [] for mode in MODES}
        for index, sample in enumerate(value['samples']):
            if (type(sample) is not dict or set(sample) != {
                    'theme', 'threshold', 'original', 'variants'}
                    or type(sample['theme']) is not str or type(sample['threshold']) is not int
                    or (sample['theme'], sample['threshold']) != ORDER[index]
                    or not _mask(sample['original']) or type(sample['variants']) is not dict
                    or set(sample['variants']) != set(MODES)):
                return refused
            original = sample['original']
            originals.append([original[key] for key in COLUMNS[:5]])
            for mode in MODES:
                measured = sample['variants'][mode]
                if type(measured) is not dict or set(measured) != set(COLUMNS):
                    return refused
                mask = {key: measured[key] for key in COLUMNS[:5]}
                changed = measured['changed_mask']
                if (not _mask(mask) or mask['expected'] != original['expected']
                        or type(changed) is not int
                        or not 0 <= changed <= value['changed_pixels'][mode]):
                    return refused
                a, b = original['present'], mask['present']
                if (not abs(a - b) <= changed <= min(a + b, 2 * CAP - a - b)
                        or (a + b - changed) % 2
                        or abs(original['overlap'] - mask['overlap']) > changed):
                    return refused
                variants[mode].append([measured[key] for key in COLUMNS])
        return dict(schema=1, scope='welcome_path_metrics', status='OBSERVED',
            frame=720, frame_count=1800, edge=470,
            order=[list(case) for case in ORDER], columns=list(COLUMNS),
            original=originals, variants=variants,
            changed_pixels=dict(value['changed_pixels']), complete_cases=True,
            numeric_observation_only=True,
            nonempty=all(row[0] > 0 and row[1] > 0 for row in originals))
    except (ValueError, TypeError, UnicodeError, OverflowError, KeyError, RecursionError):
        return refused
