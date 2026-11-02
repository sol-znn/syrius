"""Project bounded test progress without paths, test names or message text.

This is an observation, never an admission decision. The original test-count,
process-completion and source gates remain the authority for qualification.
"""

import json
import re
from urllib.parse import unquote, urlsplit


def _path(value):
    if type(value) is not str or len(value) > 4096:
        return None
    if value.startswith('file:'):
        try:
            parsed = urlsplit(value)
        except ValueError:
            return None
        if parsed.netloc or parsed.query or parsed.fragment:
            return None
        value = unquote(parsed.path)
    value = value.replace('\\', '/')
    if re.match(r'^/[A-Za-z]:/', value):
        value = value[1:]
    if re.match(r'^[A-Za-z]:/', value):
        return value.casefold().rstrip('/')
    return value.rstrip('/') if value.startswith('/') else None


def _integer(value, maximum=20000):
    return type(value) is int and 0 <= value <= maximum


def project(raw, *, suite_paths, repo):
    """Observe opaque cases and selected-file ordinals in one original stream.

    Event times may interleave. A virtual loading case may refer to a suite
    not yet reported. Late errors are observations even after a testDone.
    No suite is declared complete from its last observed case.
    """
    refused = dict(schema=1, scope='selected_test_progress', status='REFUSED',
                   qualification=False)
    if type(raw) is not bytes or len(raw) > 4 * 1024**2:
        return refused
    if type(suite_paths) not in (list, tuple) or not 1 <= len(suite_paths) <= 256:
        return refused
    prefix = _path(repo)
    if (prefix is None or any(type(path) is not str for path in suite_paths) or
            len(set(suite_paths)) != len(suite_paths)):
        return refused
    expected = {}
    for index, relative in enumerate(suite_paths, 1):
        if (type(relative) is not str or not re.fullmatch(
                r'test/(?:[A-Za-z0-9_]+/)*[A-Za-z0-9_]+_test[.]dart', relative)):
            return refused
        absolute = _path(prefix + '/' + relative)
        if absolute in expected:
            return refused
        expected[absolute] = index
    lines = raw.splitlines()
    if len(lines) > 20000 or any(len(line) > 65536 for line in lines):
        return refused
    suites, tests, per_suite, finished = {}, {}, {}, {}
    last_time = errors = retries = hidden = skipped = ordinary = 0
    terminal_seen, terminal_success = False, None
    declared_suites = None
    try:
        for line in lines:
            if not line.strip():
                continue
            event = json.loads(line)
            if (type(event) is not dict or terminal_seen or
                    not _integer(event.get('time'), 86400000)):
                return refused
            stamp = event['time']
            last_time = max(last_time, stamp)
            kind = event.get('type')
            if kind == 'suite':
                suite = event.get('suite')
                if (type(suite) is not dict or not _integer(suite.get('id')) or
                        suite['id'] in suites or len(suites) >= 1024):
                    return refused
                suites[suite['id']] = expected.get(_path(suite.get('path')), 0)
            elif kind == 'testStart':
                test = event.get('test')
                if (type(test) is not dict or not _integer(test.get('id')) or
                        not _integer(test.get('suiteID')) or test['id'] in tests or
                        len(tests) >= 4096):
                    return refused
                identity, suite_id = test['id'], test['suiteID']
                row = per_suite.setdefault(suite_id, dict(
                    started=0, finished=0, last_event_ms=0))
                row['started'] += 1
                row['last_event_ms'] = max(row['last_event_ms'], stamp)
                location = 0
                source_index = expected.get(_path(test.get('url')), 0)
                if (source_index and source_index == suites.get(suite_id) and
                        _integer(test.get('line'), 999999) and test['line'] > 0):
                    location = test['line']
                tests[identity] = dict(suite_id=suite_id, ordinal=row['started'],
                                       started_ms=stamp, line=location)
            elif kind == 'testDone':
                identity = event.get('testID')
                if (not _integer(identity) or identity not in tests or
                        identity in finished or event.get('result') not in
                        ('success', 'failure', 'error') or any(
                            type(event.get(flag, False)) is not bool
                            for flag in ('hidden', 'skipped', 'retried')) or
                        stamp < tests[identity]['started_ms']):
                    return refused
                finished[identity] = stamp - tests[identity]['started_ms']
                row = per_suite[tests[identity]['suite_id']]
                row['finished'] += 1
                row['last_event_ms'] = max(row['last_event_ms'], stamp)
                hidden += int(event.get('hidden', False))
                skipped += int(event.get('skipped', False))
                retries += int(event.get('retried', False))
                ordinary += int(not event.get('hidden', False))
            elif kind == 'error':
                errors += 1
            elif kind == 'allSuites':
                if declared_suites is not None or not _integer(event.get('count'), 1024):
                    return refused
                declared_suites = event['count']
            elif kind == 'done':
                if event.get('success') is not None and type(event['success']) is not bool:
                    return refused
                terminal_seen, terminal_success = True, event.get('success')
            elif kind not in ('start', 'group', 'print', 'debug'):
                return refused
    except (ValueError, UnicodeError, TypeError, RecursionError):
        return refused
    if not tests:
        return refused

    def case(identity):
        row = tests[identity]
        return dict(test_id=identity, suite_id=row['suite_id'],
                    suite_index=suites.get(row['suite_id'], 0),
                    case_ordinal=row['ordinal'], line=row['line'])

    unfinished = sorted(tests.keys() - finished.keys())
    last_started = max(tests, key=lambda identity: (tests[identity]['started_ms'], identity))
    recent_suites = sorted(per_suite, key=lambda identity:
                           (per_suite[identity]['last_event_ms'], identity), reverse=True)[:8]
    longest = sorted(finished, key=lambda identity: (finished[identity], identity), reverse=True)[:5]
    return dict(schema=1, scope='selected_test_progress',
                status='OBSERVED_TERMINAL' if terminal_seen and
                    type(terminal_success) is bool else 'OBSERVED_PARTIAL',
                qualification=False, engine_terminal_seen=terminal_seen,
                engine_terminal_success=terminal_success,
                last_event_ms=last_time, declared_suites=declared_suites,
                suite_events=len(suites), started_observed=len(tests),
                finished_observed=len(finished), ordinary_done_observed=ordinary,
                hidden_done_observed=hidden, skipped_done_observed=skipped,
                retried_done_observed=retries, error_events_observed=errors,
                unfinished_total=len(unfinished),
                unfinished=[dict(case(identity), observed_span_ms=
                    last_time - tests[identity]['started_ms']) for identity in unfinished[:8]],
                last_started=case(last_started),
                recent_suites=[dict(suite_id=identity,
                    suite_index=suites.get(identity, 0), **per_suite[identity])
                    for identity in recent_suites],
                longest_observed=[dict(case(identity), duration_ms=finished[identity])
                                  for identity in longest])
