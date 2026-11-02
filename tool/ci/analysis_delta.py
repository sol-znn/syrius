"""Attribute analyzer changes on fixed sources without builds or wallet execution.

Only tracked relative source paths, lint codes and numeric locations are public.
Original analyzer/dependency output remains in bounded runner memory. The two
historical worktrees and profiles belong to this fresh hosted job and are preserved.
"""

from collections import Counter
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import secrets
import shutil
import sys
import unittest

from .run_debug_tests import execute_suite
from . import windows_baseline as baseline
from . import windows_debug_loop as debug


HISTORY = (
    ('before', '1d663dc58b9ce6f2abdbe66898e85e2ef850a8c0',
     '9a8eec6320aa5cf1be0cad89f4bf9b4e8e979d18'),
    ('reported', 'f024e78bf777d9b16d9e4a81c295ef092c9bf79d',
     '197785948b180221aa3521b35fcc4def52620ba9'),
)
SDK = 'abaf9c523780a608bd46686fd5e53740a07077f8'
INPUTS = ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
          'patched_packages/reown_core-1.3.8/pubspec.yaml',
          'patched_packages/reown_core-1.3.8/pubspec.lock')
CODES = frozenset(('ENVIRONMENT_REFUSED', 'SOURCE_REFUSED', 'TOOL_REFUSED',
    'SPACE_REFUSED', 'COMMAND_FAILED', 'ANALYSIS_INVALID', 'ANALYSIS_FAILED',
    'ANALYSIS_MACHINE_SHAPE', 'ANALYSIS_MACHINE_COUNTS',
    'ANALYSIS_PATH_OUTSIDE', 'ANALYSIS_PATH_UNTRACKED',
    'ANALYSIS_PATH_PARENT', 'ANALYSIS_PATH_UNC', 'ANALYSIS_PATH_SYNTAX',
    'ANALYSIS_PATH_URI',
    'INPUTS_CHANGED', 'INTERNAL_ERROR'))
DART_PATH = re.compile(r'[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*\.dart')
SOURCE_PATH = re.compile(
    r'(?:[A-Za-z0-9_.-]+/)*(?:[A-Za-z0-9_.-]+\.dart|pubspec\.yaml|analysis_options\.yaml)')
MAX_OUTPUT = 8 * 1024**2
FREE_FLOOR = 10 * 1024**3
RESERVATION = 4 * 1024**3


class Refused(Exception):
    pass


def need(value, code):
    if not value:
        raise Refused(code)


def decode_machine_path(offered):
    """Decode only the path's documented machine escapes, never its message."""
    need(len(offered) <= 16384, 'ANALYSIS_MACHINE_SHAPE')
    result = []
    index = 0
    while index < len(offered):
        character = offered[index]
        if character == '\\':
            index += 1
            need(index < len(offered) and offered[index] in '\\|nr',
                 'ANALYSIS_MACHINE_SHAPE')
            character = {'n': '\n', 'r': '\r'}.get(offered[index], offered[index])
        result.append(character)
        index += 1
    return ''.join(result)


def relative_source(offered, root, tracked):
    """Reject private or untracked paths rather than trimming them for output."""
    offered = offered.replace('\\', '/')
    root = str(root).replace('\\', '/')
    windows = bool(re.match(r'^[A-Za-z]:/', root))
    cls = PureWindowsPath if windows else PurePosixPath
    path = cls(offered)
    need('..' not in path.parts, 'ANALYSIS_PATH_PARENT')
    need(not offered.startswith('//'), 'ANALYSIS_PATH_UNC')
    need(re.match(r'^[A-Za-z][A-Za-z0-9+.-]+://', offered) is None,
         'ANALYSIS_PATH_URI')
    if path.is_absolute():
        try:
            path = path.relative_to(cls(root))
        except ValueError:
            raise Refused('ANALYSIS_PATH_OUTSIDE') from None
    value = path.as_posix()
    need(SOURCE_PATH.fullmatch(value) is not None, 'ANALYSIS_PATH_SYNTAX')
    need(value in tracked, 'ANALYSIS_PATH_UNTRACKED')
    return value


def diagnostics(raw, root, tracked, expected):
    """Read machine fields only; private messages are never decoded or emitted.

    The independently framed Flutter summary must account for every severity.
    This uses the same machine protocol as the existing hosted debug analysis.
    """
    need(type(raw) is bytes and len(raw) <= MAX_OUTPUT, 'ANALYSIS_INVALID')
    need(type(expected) is dict and set(expected) == {'errors', 'warnings', 'infos'}
        and all(type(value) is int and 0 <= value <= 20000 for value in expected.values()),
        'ANALYSIS_MACHINE_COUNTS')
    rows = []
    for line in raw.splitlines():
        fields = line.split(b'|', 7)
        if fields[0] not in (b'ERROR', b'WARNING', b'INFO'):
            continue
        need(len(fields) == 8, 'ANALYSIS_MACHINE_SHAPE')
        try:
            level, kind, code, offered, row, column, length = (
                value.decode('ascii', 'strict') for value in fields[:7])
        except UnicodeError:
            raise Refused('ANALYSIS_MACHINE_SHAPE') from None
        need(re.fullmatch('[A-Z][A-Z0-9_]{0,99}', code) is not None
            and re.fullmatch('[A-Z][A-Z0-9_]{0,63}', kind) is not None
            and all(0 < len(value) <= 8 and value.isdecimal()
                    for value in (row, column, length)),
            'ANALYSIS_MACHINE_SHAPE')
        row, column, length = int(row), int(column), int(length)
        need(0 < row <= 10**7 and 0 < column <= 10**7 and 0 <= length <= 10**7,
             'ANALYSIS_MACHINE_SHAPE')
        rows.append((level.lower(), relative_source(decode_machine_path(offered), root, tracked),
                     code.lower(), row, column))
    levels = Counter(row[0] for row in rows)
    counts = dict(errors=levels['error'], warnings=levels['warning'], infos=levels['info'])
    need(counts == expected and len(rows) <= 20000, 'ANALYSIS_MACHINE_COUNTS')
    return counts, rows


def changes(before, after):
    """Compare multiplicities per file/code; shifted line numbers are not new lints."""
    old = Counter(row[:3] for row in before)
    new = Counter(row[:3] for row in after)
    groups = []
    for key in sorted(old.keys() | new.keys()):
        if old[key] == new[key]:
            continue
        level, path, code = key
        locations = sorted({row[3:] for row in after if row[:3] == key})
        groups.append(dict(level=level, file=path, code=code, before=old[key],
            after=new[key], delta=new[key] - old[key],
            locations=[dict(line=row, column=column) for row, column in locations[:3]],
            locations_truncated=len(locations) > 3))
    return groups


def notice_projection(value, groups, *, cap=3800):
    result = dict(value, groups=[], total_groups=len(groups), truncated=False)
    for group in groups:
        candidate = dict(result, groups=result['groups'] + [group])
        if len(json.dumps(candidate, separators=(',', ':'), sort_keys=True).encode()) > cap:
            result['truncated'] = True
            break
        result = candidate
    return result


def load_controls():
    # A regular CPython stdlib test package can shadow this repository's
    # namespace. Reuse direct discovery and the finite result projection.
    directory = str(Path(__file__).absolute().parents[2] / 'test/ci')
    return unittest.TestLoader().discover(directory, pattern='test_analysis_delta.py')


def run_controls():
    suite = load_controls()
    if suite.countTestCases() != 10:
        print(json.dumps(dict(scope='analysis_delta_inmemory_cases',
            success=False, code='CONTROLS_REFUSED', tests=suite.countTestCases(),
            native_wallet_executions=0, native_node_executions=0)))
        return 1
    return execute_suite(suite, scope='analysis_delta_inmemory_cases',
        title='Analyzer location controller tests', wallet_node_scope=True)


def main():
    report = dict(schema=1, scope='source_bound_analysis_delta', success=False,
        wallet_qualified=False, native_wallet_executions=0, builds=0, tests=0,
        phase='environment', code=None, sources=[], commands=[])
    comparisons = []
    try:
        parent, head = debug.entry.require_ci(os.environ, None, platform=os.name)
        need(parent.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
            and parent.get('GITHUB_REPOSITORY') == 'edgepillar/syrius'
            and parent.get('GITHUB_REF') == 'refs/heads/redesign', 'ENVIRONMENT_REFUSED')
        repo = Path(parent['GITHUB_WORKSPACE'])
        need(repo.resolve() == Path.cwd().resolve(), 'ENVIRONMENT_REFUSED')
        debug.bounded.verify_source(repo, head, parent)
        tree = debug.entry.source_tree(repo, parent)
        report.update(source_sha=head, source_tree=tree,
            run_id=parent['GITHUB_RUN_ID'], run_attempt=parent['GITHUB_RUN_ATTEMPT'])
        dart, snapshot = debug.sdk(parent)
        packages = Path(parent['FLUTTER_ROOT']) / 'packages/flutter_tools/.dart_tool/package_config.json'
        flutter = [str(dart), '--packages=' + str(packages), str(snapshot)]
        env = baseline.fresh_environment(repo, parent)
        git = shutil.which('git', path=env.get('PATH'))
        need(git is not None, 'TOOL_REFUSED')
        temporary = Path(parent.get('RUNNER_TEMP', ''))
        need(temporary.is_absolute() and temporary.is_dir(), 'ENVIRONMENT_REFUSED')
        debug.bounded.plain(temporary)
        need(shutil.disk_usage(temporary).free >= FREE_FLOOR + RESERVATION, 'SPACE_REFUSED')
        root = temporary / ('syrius-analysis-' + secrets.token_hex(12))
        root.mkdir(mode=0o700)

        def command(label, arguments, cwd, *, timeout=120, cap=262144, required=True,
                    child_env=None):
            need(shutil.disk_usage(root).free >= FREE_FLOOR, 'SPACE_REFUSED')
            outcome = baseline.run_bounded(arguments, cwd=cwd, env=env if child_env is None else child_env,
                                           timeout=timeout, cap=cap)
            report['commands'].append(dict(stage=label, **outcome.public(),
                output_sha256=hashlib.sha256(outcome.output).hexdigest()))
            need(outcome.transport_complete and (not required or outcome.success), 'COMMAND_FAILED')
            return outcome.output

        report['phase'] = 'sdk'
        actual_sdk = command('sdk_source', [git, '-C', parent['FLUTTER_ROOT'],
            'rev-parse', 'HEAD'], repo, cap=128).decode('ascii').strip()
        need(actual_sdk == SDK, 'TOOL_REFUSED')
        report['sdk_revision'] = actual_sdk
        report['phase'] = 'source'
        origin = command('origin', [git, 'remote', 'get-url', 'origin'], repo,
                         cap=256).decode('ascii').strip()
        need(origin in ('https://github.com/edgepillar/syrius',
                        'https://github.com/edgepillar/syrius.git'), 'SOURCE_REFUSED')
        command('fetch_fixed_history', [git, '-c', 'credential.helper=', '-c',
            'http.followRedirects=false', 'fetch', '--quiet', '--no-tags', '--depth=1',
            'origin', HISTORY[0][1], HISTORY[1][1]], repo, timeout=180)
        declarations = []
        for label, source, expected_tree in (*HISTORY, ('current', head, tree)):
            report['phase'] = label
            target = repo if label == 'current' else root / label
            if label != 'current':
                command(label + '_worktree', [git, 'worktree', 'add', '--quiet',
                    '--detach', str(target), source], repo, timeout=180)
            actual = command(label + '_tree', [git, 'rev-parse', 'HEAD^{tree}'],
                             target, cap=128).decode('ascii').strip()
            need(actual == expected_tree, 'SOURCE_REFUSED')
            tracked_raw = command(label + '_tracked', [git, 'ls-files', '-z', '--',
                '*.dart', '*pubspec.yaml', '*analysis_options.yaml'],
                                  target, cap=1024**2)
            tracked = set(tracked_raw.decode('utf-8').rstrip('\0').split('\0'))
            need(tracked and all(SOURCE_PATH.fullmatch(name) for name in tracked), 'SOURCE_REFUSED')
            configs = {name for name in tracked if DART_PATH.fullmatch(name) is None}
            inputs = {name: hashlib.sha256((target / name).read_bytes()).hexdigest()
                      for name in set(INPUTS) | configs}
            need(not declarations or inputs == declarations[0], 'INPUTS_CHANGED')
            declarations.append(inputs)
            child_env = baseline.fresh_environment(target, parent)
            command(label + '_restore', flutter + ['pub', 'get', '--enforce-lockfile'],
                    target, child_env=child_env, timeout=600, cap=4 * 1024**2)
            command(label + '_restore_vendored', flutter + ['pub', 'get', '--enforce-lockfile'],
                    target / 'patched_packages/reown_core-1.3.8', child_env=child_env,
                    timeout=600, cap=4 * 1024**2)
            raw = command(label + '_analysis', flutter + ['analyze', '--no-pub', '--no-fatal-infos'],
                          target, child_env=child_env, timeout=300, cap=MAX_OUTPUT, required=False)
            counts = baseline.analysis_counts(raw)
            need(not counts['errors'] and not counts['warnings']
                and report['commands'][-1]['success'], 'ANALYSIS_FAILED')
            report['sources'].append(dict(label=label, head=source, tree=actual,
                counts=counts, tracked_dart_files=len(tracked) - len(configs),
                tracked_config_files=len(configs),
                inputs_sha256=hashlib.sha256(json.dumps(inputs, sort_keys=True,
                    separators=(',', ':')).encode()).hexdigest(), locations_complete=False))
            raw = command(label + '_locations', [str(dart), 'analyze', '--format', 'machine'],
                          target, child_env=child_env, timeout=300, cap=MAX_OUTPUT, required=False)
            _, rows = diagnostics(raw, target, tracked, counts)
            need(report['commands'][-1]['success'], 'ANALYSIS_FAILED')
            report['sources'][-1]['locations_complete'] = True
            debug.bounded.verify_source(target, source, parent)
            need(debug.entry.source_tree(target, parent) == expected_tree, 'SOURCE_REFUSED')
            comparisons.append(rows)
        report['phase'] = 'source_unchanged'
        debug.bounded.verify_source(repo, head, parent)
        need(debug.entry.source_tree(repo, parent) == tree, 'SOURCE_REFUSED')
        report['dependency_inputs_equal'] = True
        report['success'] = True
    except (Exception, KeyboardInterrupt) as error:
        code = str(error)
        report['code'] = code if code in CODES else 'INTERNAL_ERROR'
    print(json.dumps(report, sort_keys=True, separators=(',', ':')))
    summary = {key: value for key, value in report.items() if key != 'commands'}
    fields = ('stage', 'exit_code', 'exit_observed', 'output_complete', 'forced_kill',
              'output_overflow', 'output_sha256', 'seconds', 'success')
    summary['analysis_commands'] = [{key: row[key] for key in fields}
        for row in report['commands'] if row['stage'].endswith(('_analysis', '_locations'))]
    print('::notice title=Hosted analysis delta::' + json.dumps(summary, sort_keys=True, separators=(',', ':')))
    for title, start, end in (('Historical analysis locations', 0, 1),
                              ('Current analysis locations', 1, 2)):
        if len(comparisons) > end:
            projection = notice_projection(dict(schema=1, scope='source_bound_analysis_locations',
                source_sha=report['source_sha'], run_id=report['run_id'],
                before=report['sources'][start]['head'], after=report['sources'][end]['head']),
                changes(comparisons[start], comparisons[end]))
            print('::notice title=' + title + '::' + json.dumps(projection, sort_keys=True, separators=(',', ':')))
    return 0 if report['success'] else 1


if __name__ == '__main__':
    if sys.argv[1:] == ['--controls-only']:
        raise SystemExit(run_controls())
    if sys.argv[1:]:
        print(json.dumps(dict(scope='source_bound_analysis_delta', success=False,
                              code='ARGUMENTS_REFUSED')))
        raise SystemExit(1)
    raise SystemExit(main())
