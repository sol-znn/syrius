"""Restore locked harness inputs on a fresh hosted runner without a native build."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

from . import windows_baseline as baseline
from . import windows_debug_loop as debug
from .analysis_delta import INPUTS, SDK


FREE_FLOOR = 10 * 1024**3
RESERVATION = 3 * 1024**3
CODES = frozenset(('ENVIRONMENT_REFUSED', 'SOURCE_REFUSED', 'TOOL_REFUSED',
    'SPACE_REFUSED', 'PROFILE_REFUSED', 'COMMAND_FAILED', 'INPUTS_CHANGED',
    'INTERNAL_ERROR'))


def admit(environment, *, platform, cwd):
    """Refuse an unowned or non-opted-in environment before allocating a profile."""
    parent, source = debug.entry.require_ci(environment, None, platform=platform)
    debug.need(parent.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
        and parent.get('GITHUB_REPOSITORY') == 'edgepillar/syrius'
        and parent.get('GITHUB_REF') == 'refs/heads/redesign'
        and parent.get('SYRIUS_HOSTED_RUNNER') == 'github-hosted'
        and parent.get('SYRIUS_HARNESS_TESTS_ONLY') == 'true'
        and parent.get('SYRIUS_WINDOWS_WALLET_TOUR') != 'true', 'ENVIRONMENT_REFUSED')
    repo = Path(parent['GITHUB_WORKSPACE'])
    debug.need(repo.resolve() == cwd.resolve(), 'ENVIRONMENT_REFUSED')
    return parent, source, repo


def input_digest(repo):
    offered = {}
    for name in INPUTS:
        path = repo / name
        debug.bounded.plain(path)
        offered[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashlib.sha256(json.dumps(offered, sort_keys=True,
        separators=(',', ':')).encode()).hexdigest()


def no_native_allocations(repo):
    return not any(path.exists() or path.is_symlink() for path in (
        repo / '.harness/app', repo / '.harness/ci-node-source',
        repo / '.harness/ci-chain321'))


def main(arguments=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    report = dict(schema=1, scope='focused_harness_dependencies', success=False,
        admission_only=arguments == ['--admission-only'], phase='environment',
        native_wallet_executions=0, native_node_executions=0, native_builds=0,
        commands=[], inputs_unchanged=False, code=None)
    try:
        debug.need(arguments in ([], ['--admission-only']), 'ENVIRONMENT_REFUSED')
        parent, source, repo = admit(os.environ, platform=os.name, cwd=Path.cwd())
        debug.bounded.verify_source(repo, source, parent)
        tree = debug.entry.source_tree(repo, parent)
        report.update(source_sha=source, source_tree=tree,
            run_id=parent['GITHUB_RUN_ID'], run_attempt=parent['GITHUB_RUN_ATTEMPT'])
        debug.need(no_native_allocations(repo), 'PROFILE_REFUSED')
        if arguments == ['--admission-only']:
            report.update(phase='admitted', success=True)
        else:
            debug.need(shutil.disk_usage(repo).free >= FREE_FLOOR + RESERVATION,
                       'SPACE_REFUSED')
            before = input_digest(repo)
            dart, snapshot = debug.sdk(parent)
            env = baseline.fresh_environment(repo, parent)
            git = shutil.which('git', path=env.get('PATH'))
            debug.need(git is not None, 'TOOL_REFUSED')

            def command(stage, arguments, cwd, *, timeout=600, cap=4 * 1024**2):
                debug.need(shutil.disk_usage(repo).free >= FREE_FLOOR, 'SPACE_REFUSED')
                outcome = baseline.run_bounded(arguments, cwd=cwd, env=env,
                                               timeout=timeout, cap=cap)
                report['commands'].append(dict(stage=stage, **outcome.public(),
                    output_sha256=hashlib.sha256(outcome.output).hexdigest()))
                debug.need(outcome.success and outcome.transport_complete, 'COMMAND_FAILED')
                return outcome.output

            report['phase'] = 'sdk'
            revision = command('sdk_revision', [git, '-C', parent['FLUTTER_ROOT'],
                'rev-parse', 'HEAD'], repo, timeout=30, cap=128).decode('ascii').strip()
            debug.need(revision == SDK, 'TOOL_REFUSED')
            report['sdk_revision'] = revision
            packages = Path(parent['FLUTTER_ROOT']) / 'packages/flutter_tools/.dart_tool/package_config.json'
            flutter = [str(dart), '--packages=' + str(packages), str(snapshot)]
            report['phase'] = 'restore'
            command('application_restore', flutter + ['pub', 'get', '--enforce-lockfile'], repo)
            command('vendored_restore', flutter + ['pub', 'get', '--enforce-lockfile'],
                    repo / 'patched_packages/reown_core-1.3.8')
            debug.need(input_digest(repo) == before, 'INPUTS_CHANGED')
            debug.bounded.verify_source(repo, source, parent)
            debug.need(debug.entry.source_tree(repo, parent) == tree, 'SOURCE_REFUSED')
            debug.need(no_native_allocations(repo), 'PROFILE_REFUSED')
            report.update(phase='source_unchanged', success=True, inputs_unchanged=True,
                          inputs_sha256=before)
    except (Exception, KeyboardInterrupt) as error:
        code = getattr(error, 'code', None) or str(error)
        report['code'] = code if code in CODES else 'INTERNAL_ERROR'
    public = json.dumps(report, sort_keys=True, separators=(',', ':'))
    print(public)
    if len(public.encode()) <= 3800:
        print('::notice title=Focused harness dependencies::' + public)
    return 0 if report['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
