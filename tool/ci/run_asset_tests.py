"""Observe the original memory-only asset controls without publishing raw output."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil

from . import windows_baseline as baseline
from . import windows_entry_capture_smoke as source


PREFIX = b'::notice title=Lab asset helper tests::'
PROGRESS_PREFIX = b'SYRIUS_LAB_ASSET_CONTROL_PHASE:'
CONTROL_PHASES = (
    'STARTED', 'SOURCE_READ_STARTED', 'SOURCE_READ_FINISHED',
    'LEGACY_STARTED', 'LEGACY_RETURNED', 'OBSERVED_STARTED',
    'OBSERVED_RETURNED', 'INVALID_OPTION_STARTED', 'INVALID_OPTION_RETURNED',
    'EXISTING_STARTED', 'EXISTING_RETURNED', 'INTERRUPTED_STARTED',
    'INTERRUPTED_RETURNED', 'COMPLETE',
)
CODES = frozenset(('ENVIRONMENT_REFUSED', 'SOURCE_REFUSED', 'TOOL_REFUSED',
    'VERSION_REFUSED', 'CONTROL_FAILED', 'CONTROL_REPLY_REFUSED', 'OUTPUT_REFUSED',
    'INTERNAL_ERROR'))


def need(value, code):
    if not value:
        raise ValueError(code)


def admit(environment, cwd):
    parent = {}
    for key, value in environment.items():
        upper = key.upper()
        need(upper not in parent or parent[upper] == value, 'ENVIRONMENT_REFUSED')
        parent[upper] = value
    need(parent.get('GITHUB_ACTIONS') == 'true'
        and parent.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
        and parent.get('RUNNER_ENVIRONMENT') == 'github-hosted'
        and parent.get('SYRIUS_HOSTED_RUNNER') == 'github-hosted'
        and parent.get('GITHUB_REPOSITORY') == 'edgepillar/syrius'
        and parent.get('GITHUB_REF') == 'refs/heads/redesign'
        and re.fullmatch('[a-f0-9]{40}', parent.get('GITHUB_SHA', '')) is not None
        and re.fullmatch('[1-9][0-9]{0,19}', parent.get('GITHUB_RUN_ID', '')) is not None
        and re.fullmatch('[1-9][0-9]{0,5}', parent.get('GITHUB_RUN_ATTEMPT', '')) is not None
        and parent.get('GITHUB_WORKSPACE'), 'ENVIRONMENT_REFUSED')
    repo = Path(parent['GITHUB_WORKSPACE'])
    need(repo.resolve() == cwd.resolve(), 'ENVIRONMENT_REFUSED')
    return parent, repo


def control_reply(raw):
    need(type(raw) is bytes and len(raw) <= 65536, 'CONTROL_REPLY_REFUSED')
    offered = [line[len(PREFIX):] for line in raw.splitlines() if line.startswith(PREFIX)]
    need(len(offered) == 1, 'CONTROL_REPLY_REFUSED')

    def pairs(items):
        value = {}
        for key, item in items:
            need(key not in value, 'CONTROL_REPLY_REFUSED')
            value[key] = item
        return value

    try:
        value = json.loads(offered[0], object_pairs_hook=pairs)
    except (ValueError, UnicodeError):
        raise ValueError('CONTROL_REPLY_REFUSED') from None
    need(type(value) is dict and set(value) == {'schema', 'scope', 'success',
        'cases', 'asset_bytes_equal', 'filesystem_scratch', 'native_wallet_executions'},
        'CONTROL_REPLY_REFUSED')
    need(type(value['schema']) is int and value['schema'] == 1
        and value['scope'] == 'lab_asset_helper_inmemory_cases'
        and value['success'] is True and value['asset_bytes_equal'] is True
        and type(value['cases']) is int and value['cases'] == 4
        and all(type(value[key]) is int and value[key] == 0
                for key in ('filesystem_scratch', 'native_wallet_executions')),
        'CONTROL_REPLY_REFUSED')
    return value


def failure_labels(raw):
    """Copy only fixed categories and known source basenames with numeric lines."""
    need(type(raw) is bytes and len(raw) <= 65536, 'OUTPUT_REFUSED')
    category = next((label for pattern, label in (
        (b'ERR_SCRIPT_EXECUTION_TIMEOUT', 'VM_TIMEOUT'),
        (b'ERR_ASSERTION', 'ASSERTION'), (b'MODULE_NOT_FOUND', 'MISSING_MODULE'),
        (b'ENOENT', 'MISSING_FILE'), (b'SyntaxError', 'SYNTAX'),
        (b'ReferenceError', 'REFERENCE'), (b'TypeError', 'TYPE')) if pattern in raw), 'UNKNOWN')
    match = re.search(rb'(lab_asset_progress_test[.]js|make-assets[.]js):([1-9][0-9]{0,5}):[0-9]+', raw)
    return dict(category=category,
        source=('asset_test' if match[1] == b'lab_asset_progress_test.js' else 'asset_helper') if match else None,
        line=int(match[2]) if match else None)


def control_progress(raw):
    """Disclose only an exact original phase prefix, independently of success."""
    result = dict(schema=1, scope='lab_asset_control_progress', status='ABSENT',
        observations=0, last=None, sequence_complete=False)
    if raw is None:
        return result
    if type(raw) is not bytes or len(raw) > 65536:
        return dict(result, status='REFUSED')
    offered = [line[len(PROGRESS_PREFIX):] for line in raw.splitlines()
               if line.startswith(PROGRESS_PREFIX)]
    expected = [phase.encode('ascii') for phase in CONTROL_PHASES]
    if len(offered) > len(expected) or offered != expected[:len(offered)]:
        return dict(result, status='REFUSED')
    if offered:
        return dict(result, status='OBSERVED', observations=len(offered),
            last=CONTROL_PHASES[len(offered)-1],
            sequence_complete=len(offered) == len(expected))
    return result


def main():
    report = dict(schema=1, scope='lab_asset_helper_command', success=False,
        phase='environment', code=None, node_version=None, control_failure=None,
        control_progress=control_progress(None),
        filesystem_scratch=0, native_wallet_executions=0, native_node_executions=0,
        commands=[])
    reply = None
    try:
        parent, repo = admit(os.environ, Path.cwd())
        head = parent['GITHUB_SHA']
        source.bounded.verify_source(repo, head, parent)
        tree = source.source_tree(repo, parent)
        report.update(source_sha=head, source_tree=tree,
            run_id=parent['GITHUB_RUN_ID'], run_attempt=parent['GITHUB_RUN_ATTEMPT'])
        node = shutil.which('node', path=parent.get('PATH'))
        need(node is not None, 'TOOL_REFUSED')

        def command(stage, arguments, timeout, cap):
            outcome = baseline.run_bounded(arguments, cwd=repo, env=parent,
                                           timeout=timeout, cap=cap)
            report['commands'].append(dict(stage=stage, **outcome.public(),
                output_sha256=hashlib.sha256(outcome.output).hexdigest()))
            if stage == 'asset_controls':
                report['control_progress'] = control_progress(outcome.output)
            need(outcome.transport_complete, 'OUTPUT_REFUSED')
            return outcome

        report['phase'] = 'node_version'
        version = command('node_version', [node, '--version'], 15, 256)
        need(version.success and re.fullmatch(rb'v[0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}\r?\n',
                                              version.output) is not None, 'VERSION_REFUSED')
        report['node_version'] = version.output.decode('ascii').strip()
        report['phase'] = 'asset_controls'
        outcome = command('asset_controls', [node, 'test/ci/lab_asset_progress_test.js'], 15, 65536)
        if not outcome.success:
            report['control_failure'] = failure_labels(outcome.output)
            raise ValueError('CONTROL_FAILED')
        reply = control_reply(outcome.output)
        source.bounded.verify_source(repo, head, parent)
        need(source.source_tree(repo, parent) == tree, 'SOURCE_REFUSED')
        report.update(phase='source_unchanged', success=True)
    except (Exception, KeyboardInterrupt) as error:
        code = getattr(error, 'code', None) or str(error)
        report['code'] = code if code in CODES else 'INTERNAL_ERROR'
    public = json.dumps(report, sort_keys=True, separators=(',', ':'))
    print(public)
    if len(public.encode()) <= 3800:
        print('::notice title=Lab asset helper command::' + public)
    if report['success']:
        print(PREFIX.decode('ascii') + json.dumps(reply, sort_keys=True, separators=(',', ':')))
    return 0 if report['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
