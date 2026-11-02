"""Read original Windows receipts in Actions memory without repeating runtime."""

import base64
import io
import json
import os
from pathlib import Path
import re
import stat
import zipfile

from . import inspect_chain321 as archive
from . import inspect_windows_inventory as inventory
from . import dart_test_failure
from . import windows_baseline as baseline
from . import windows_entry_capture_smoke as entry
from . import inspect_startup_qualification as startup


MAX_LOG = 4 * 1024**2
MAX_ENTRY_ARCHIVE = 4 * entry.MAX_PNG + 1024**2
PRODUCERS = ('windows_baseline.py', 'windows_entry_capture_smoke.py',
             'windows_presentation_smoke.py', 'dart_test_failure.py')
# GitHub retains this exact unevaluated name when the job is skipped.
SKIPPED_BASELINE_JOB = (
    "inputs.windows_inventory_only && 'Hosted Windows inventory' "
    "|| 'Hosted Windows baseline'")
PHASE = 'environment'
CHECK_STAGES = {
    'source': ('source_head', 'source_tree', 'source_clean_before'),
    'locked_restoration': ('restore_application', 'restore_vendored', 'source_clean_restored'),
    'windows_doctor': ('enable_windows', 'doctor'),
    'vendored_analysis': ('analyze_vendored',), 'root_analysis': ('analyze_root',),
    'unit_widget_tests': ('unit_widget_tests',),
    'generated_correspondence': ('generate_sources', 'format_integration',
                                 'generate_localizations', 'source_clean_generated'),
    'debug_build': ('generate_metadata', 'build_debug'), 'release_build': ('build_release',),
    'library_map_exports': ('map_source', 'map_debug', 'map_release'),
    'source_unchanged': ('source_clean_after',),
}


def digest(value):
    return type(value) is str and re.fullmatch('[a-f0-9]{64}', value) is not None


def checks(value, names):
    archive.need(type(value) is dict and set(value) == set(names)
                 and all(type(item) is bool for item in value.values()))
    return dict(value)


def numbers(value, names):
    archive.need(type(value) is dict and set(value) == set(names)
        and all(type(item) is int and 0 <= item <= 10**7 for item in value.values()))
    return dict(value)


def log_report(raw, scope):
    """Only one timestamped producer JSON frame is admitted; raw text stays private."""
    archive.need(type(raw) is bytes and 0 < len(raw) <= MAX_LOG)
    lines = raw.splitlines()
    archive.need(len(lines) <= 20000)
    found = []
    for line in lines:
        match = re.fullmatch(rb'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:'
                             rb'[0-9]{2}(?:\.[0-9]{1,9})?Z (\{.*\})', line)
        if match is None:
            continue
        archive.need(len(match[1]) <= archive.MAX_MANIFEST)
        try:
            value = json.loads(match[1])
        except (ValueError, UnicodeError):
            continue
        if type(value) is dict and value.get('scope') == scope:
            found.append(value)
    archive.need(len(found) == 1)
    return found[0]


def baseline_projection(report, head, tree, run_id):
    archive.need(type(report) is dict and report.get('schema') == 1
        and type(report['schema']) is int and report.get('scope') == 'github_hosted_windows_baseline'
        and report.get('source_sha') == head and report.get('source_tree') == tree
        and report.get('run') == dict(id=str(run_id), attempt='1'))
    original = checks(report.get('checks'), baseline.CHECKS)
    stages, errors = report.get('stages'), report.get('error_codes')
    archive.need(type(stages) is dict and set(stages) <= baseline.STAGES)
    outcomes = {name: inventory.outcome(value) for name, value in stages.items()}
    archive.need(type(errors) is list and len(errors) <= 16
                 and all(type(code) is str and code in baseline.CODES for code in errors))
    for check, names in CHECK_STAGES.items():
        if original[check]:
            for name in names:
                archive.need(name in outcomes)
                value = outcomes[name]
                if name == 'doctor':
                    archive.need(value['exit_observed'] and value['output_complete']
                        and not value['forced_kill'] and not value['output_overflow']
                        and not value['error_codes'])
                else:
                    archive.need(value['success'])
    doctor = report.get('doctor')
    archive.need(type(doctor) is dict and doctor.get('scope') == 'windows_desktop_only'
        and set(doctor) <= {'scope', 'windows_version', 'visual_studio'}
        and all(value in ('pass', 'warning', 'fail', 'unknown')
                for name, value in doctor.items() if name != 'scope'))
    if original['windows_doctor']:
        archive.need(doctor == dict(scope='windows_desktop_only',
                                   windows_version='pass', visual_studio='pass'))
    analysis = report.get('analysis')
    archive.need(type(analysis) is dict and set(analysis) <= {'analyze_root', 'analyze_vendored'})
    projected_analysis = {name: numbers(value, ('errors', 'warnings', 'infos'))
                          for name, value in analysis.items()}
    for check, stage in (('root_analysis', 'analyze_root'), ('vendored_analysis', 'analyze_vendored')):
        if original[check]:
            archive.need(stage in projected_analysis and projected_analysis[stage]['errors'] == 0
                         and projected_analysis[stage]['warnings'] == 0)
    tests = report.get('tests')
    if tests is not None:
        archive.need(type(tests) is dict and type(tests.get('terminal_success')) is bool)
        numbers({key: value for key, value in tests.items() if key != 'terminal_success'},
                ('passed', 'failed', 'skipped', 'hidden', 'terminal_events', 'error_events'))
        archive.need(tests['terminal_events'] > 0 and tests['hidden'] <= tests['terminal_events']
            and tests['passed'] + tests['failed'] + tests['skipped'] <= tests['terminal_events'])
    if original['unit_widget_tests']:
        archive.need(tests is not None and tests['terminal_success'] and tests['passed'] > 0
                     and tests['failed'] == tests['error_events'] == 0)
    localization = report.get('localization_correspondence')
    archive.need(type(localization) is dict and set(localization) <= {'before', 'after'})
    for value in localization.values():
        archive.need(type(value) is dict and set(value) == {'files', 'sha256'}
            and type(value['files']) is int and 0 < value['files'] <= 1000 and digest(value['sha256']))
    if original['generated_correspondence']:
        archive.need(set(localization) == {'before', 'after'}
                     and localization['before'] == localization['after'])
    libraries = report.get('libraries')
    archive.need(type(libraries) is dict and set(libraries) <= set(baseline.LIBRARIES))
    for value in libraries.values():
        archive.need(type(value) is dict and set(value) == {'sha256', 'map_exports'}
                     and digest(value['sha256']) and type(value['map_exports']) is bool)
    if original['library_hash_correspondence'] or original['library_map_exports']:
        archive.need(set(libraries) == set(baseline.LIBRARIES)
                     and len({value['sha256'] for value in libraries.values()}) == 1)
    if original['library_map_exports']:
        archive.need(all(value['map_exports'] for value in libraries.values()))
    archive.need(type(report.get('success')) is bool
                 and report['success'] is (all(original.values()) and not errors))
    failures = None
    if 'test_failures' in report:
        failures = dart_test_failure.locations_projection(report['test_failures'])
        archive.need(failures is not None and not original['unit_widget_tests']
            and report['success'] is False)
    return dict(scope='retained_windows_baseline_observation', inspection_only=True,
        runtime_started=False, wallet_qualified=False, source_head=head, source_tree=tree,
        source_run_id=run_id, source_attempt=1, artifact_reported_success=report['success'],
        original_checks=original, original_error_codes=errors, analysis=projected_analysis,
        tests=tests, doctor=doctor,
        **({'test_failures': failures} if failures is not None else {}),
        localization_unchanged=(set(localization) == {'before', 'after'}
            and localization['before'] == localization['after']), libraries=libraries,
        commands={name: outcomes[name] for name in ('analyze_root', 'analyze_vendored',
            'unit_widget_tests', 'build_debug', 'build_release') if name in outcomes})


def entry_projection(report, head, tree, run_id):
    archive.need(type(report) is dict and type(report.get('schema')) is int and report['schema'] == 2
        and report.get('source_sha') == head and report.get('source_tree') == tree
        and report.get('run_id') == str(run_id) and report.get('run_attempt') == '1')
    original = checks(report.get('checks'), entry.CHECKS)
    caption = report.get('caption')
    archive.need(type(caption) is dict and set(caption) == {'schema', 'observations'}
                 and type(caption['schema']) is int and caption['schema'] == 1)
    captions = checks(caption['observations'], entry.CAPTION_CHECKS)
    for name in ('exit_observed', 'output_complete', 'output_overflow', 'forced_kill', 'complete', 'success'):
        archive.need(type(report.get(name)) is bool)
    code, count, captures = report.get('exit_code'), report.get('capture_count'), report.get('captures')
    archive.need(code is None or type(code) is int and -(2**31) <= code < 2**32)
    archive.need(type(count) is int and 0 <= count <= 4 and type(captures) is list and len(captures) == count)
    seen = set()
    for item in captures:
        archive.need(type(item) is dict and set(item) == {'file', 'sha256', 'bytes', 'width', 'height'}
            and item['file'] in entry.FILES and item['file'] not in seen and digest(item['sha256'])
            and type(item['bytes']) is int and 0 < item['bytes'] <= entry.MAX_PNG
            and type(item['width']) is int and type(item['height']) is int
            and (item['width'], item['height']) == (1280, 780))
        seen.add(item['file'])
    for screen, theme in entry.SCENES:
        if original[screen + '_' + theme]:
            archive.need(screen + '-' + theme + '.png' in seen)
    if original['exit']:
        archive.need(report['exit_observed'] and type(code) is int and code == 0)
    archive.need(type(report.get('output_bytes')) is int and 0 <= report['output_bytes'] < 2**63)
    archive.need(digest(report.get('runner_sha256')) and digest(report.get('dart_kernel_sha256')))
    errors, first, cleanup = report.get('error_codes'), report.get('first_command_failure'), report.get('cleanup_failures')
    archive.need(type(errors) is list and len(errors) <= 32
                 and all(type(code) is str and code in entry.CODES for code in errors))
    archive.need(first is None or entry.failure_projection(first) == first)
    archive.need(type(cleanup) is list and len(cleanup) <= 2
        and all(type(value) is dict and entry.failure_projection(value) == value
                and value['phase'] in entry.CLEANUP_PHASES
                for value in cleanup))
    capture_progress = transport_failure = effect_trace = None
    if 'capture_progress' in report:
        capture_progress = entry.capture_progress_projection(report['capture_progress'])
        archive.need(capture_progress is not None and capture_progress == report['capture_progress'])
    if 'transport_failure' in report:
        transport_failure = entry.transport_failure_projection(report['transport_failure'])
        archive.need(transport_failure is not None and transport_failure == report['transport_failure']
                     and 'HTTP_FAILED' in errors)
    if 'effect_trace' in report:
        effect_trace = entry.effect_trace_projection(report['effect_trace'])
        archive.need(effect_trace is not None and effect_trace == report['effect_trace'])
    complete = (all(original.values()) and all(captions.values()) and count == 4
        and report['exit_observed'] and type(code) is int and code == 0
        and report['output_complete'] and not report['output_overflow'] and not report['forced_kill']
        and not errors and first is None and not cleanup)
    archive.need(report['complete'] is complete and report['success'] is complete
                 and report.get('status') == ('SUCCESS' if complete else 'UNKNOWN'))
    return dict(scope='retained_windows_entry_observation', inspection_only=True,
        runtime_started=False, wallet_qualified=False, visual_matches=0, source_head=head,
        source_tree=tree, source_run_id=run_id, source_attempt=1, artifact_reported_success=complete,
        original_checks=original, caption_checks=captions, captures=captures, capture_count=count,
        exit_code=code, exit_observed=report['exit_observed'], forced_kill=report['forced_kill'],
        output_complete=report['output_complete'], output_overflow=report['output_overflow'],
        output_bytes=report['output_bytes'], original_error_codes=errors, first_command_failure=first,
        cleanup_failures=cleanup,
        **({'capture_progress': capture_progress} if capture_progress is not None else {}),
        **({'effect_trace': effect_trace} if effect_trace is not None else {}),
        **({'transport_failure': transport_failure} if transport_failure is not None else {}))


def entry_archive(raw, expected_sha, expected_size, head, tree, run_id):
    archive.need(type(raw) is bytes and type(expected_size) is int and digest(expected_sha)
                 and 0 < len(raw) == expected_size <= MAX_ENTRY_ARCHIVE
                 and archive.sha(raw) == expected_sha)
    with zipfile.ZipFile(io.BytesIO(raw)) as zipped:
        members = zipped.infolist()
        names = [value.filename for value in members]
        archive.need(1 <= len(names) <= 5 and len(set(names)) == len(names)
            and 'manifest.json' in names and set(names) <= {'manifest.json', *entry.FILES})
        for member in members:
            cap = archive.MAX_MANIFEST if member.filename == 'manifest.json' else entry.MAX_PNG
            archive.need(not member.is_dir() and not member.flag_bits & 1
                and 0 < member.file_size <= cap
                and stat.S_IFMT(member.external_attr >> 16) in (0, stat.S_IFREG))
        manifest = zipped.read('manifest.json')
        summary = entry_projection(json.loads(manifest), head, tree, run_id)
        archive.need(set(names) == {'manifest.json', *(value['file'] for value in summary['captures'])})
        for value in summary['captures']:
            data = zipped.read(value['file'])
            archive.need(len(data) == value['bytes'] and archive.sha(data) == value['sha256'])
            entry.png_bytes(base64.b64encode(data).decode('ascii'))
    summary.update(archive_sha256=archive.sha(raw), manifest_sha256=archive.sha(manifest))
    return summary


def emit(title, summary):
    encoded = json.dumps(summary, sort_keys=True, separators=(',', ':'))
    archive.need(encoded.isascii() and len(encoded.encode()) <= 3800)
    print(encoded)
    print('::notice title=' + title + '::' + encoded)


def main():
    global PHASE
    PHASE = 'environment'
    try:
        parent = os.environ
        archive.need(parent.get('GITHUB_ACTIONS') == 'true'
            and parent.get('SYRIUS_HOSTED_RUNNER') == 'github-hosted'
            and parent.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
            and parent.get('GITHUB_REPOSITORY') == 'edgepillar/syrius')
        text, head = parent.get('WINDOWS_INSPECT_RUN', ''), parent.get('WINDOWS_INSPECT_HEAD', '')
        archive.need(re.fullmatch('[1-9][0-9]{0,19}', text) is not None
                     and re.fullmatch('[a-f0-9]{40}', head) is not None)
        run_id, client = int(text), archive.Client(parent.get('GH_TOKEN'))
        PHASE = 'source_metadata'
        run = client.json('/actions/runs/' + text)
        archive.need(run['id'] == run_id and run['head_sha'] == head and run['run_attempt'] == 1
            and run['workflow_id'] == 381413107 and run['event'] == 'workflow_dispatch'
            and run['status'] == 'completed' and run['repository']['full_name'] == 'edgepillar/syrius')
        commit = client.json('/git/commits/' + head)
        tree = commit['tree']['sha']
        archive.need(commit['sha'] == head and re.fullmatch('[a-f0-9]{40}', tree) is not None)
        PHASE = 'job_metadata'
        listing = client.json('/actions/runs/' + text + '/attempts/1/jobs?per_page=20')
        archive.need(listing['total_count'] == len(listing['jobs']) <= 20)
        startup_jobs = [job for job in listing['jobs'] if job['name'] == startup.JOB_NAME]
        archive.need(len(startup_jobs) <= 1)
        if startup_jobs and startup_jobs[0]['conclusion'] != 'skipped':
            job = startup_jobs[0]
            archive.need(all(other['head_sha'] == head and other['run_id'] == run_id
                and other['status'] == 'completed' and other['conclusion'] == 'skipped'
                for other in listing['jobs'] if other is not job))
            PHASE = 'startup_artifacts'
            for summary in startup.inspect_run(
                    client, head=head, tree=tree, run_id=run_id, job=job):
                title = ('Hosted natural startup inspection'
                         if summary['scope'] == 'retained_natural_release_startup_observation'
                         else 'Hosted original startup inspection')
                emit(title, summary)
            return 0
        # The startup reader checks its own four producers. Checking the
        # unselected baseline sources first exhausts the twelve-request bound
        # before either original startup archive can be read.
        PHASE = 'source_metadata'
        for name in PRODUCERS:
            selected = client.json('/contents/tool/ci/' + name + '?ref=' + head)
            archive.need(selected['type'] == 'file' and selected['encoding'] == 'base64'
                         and selected['path'] == 'tool/ci/' + name)
            data = base64.b64decode(selected['content'].replace('\n', ''), validate=True)
            archive.need(len(data) == selected['size'] and data == Path(__file__).with_name(name).read_bytes())
        PHASE = 'job_metadata'
        jobs = {}
        for name in ('Hosted Windows baseline', 'Ordinary Windows entry captures'):
            selected = [job for job in listing['jobs']
                        if job['name'] == name or (
                            name == 'Hosted Windows baseline'
                            and job['name'] == SKIPPED_BASELINE_JOB
                            and job['conclusion'] == 'skipped')]
            outcomes = ('success', 'failure', 'skipped')
            archive.need(len(selected) == 1 and selected[0]['head_sha'] == head
                and selected[0]['run_id'] == run_id and selected[0]['status'] == 'completed'
                and selected[0]['conclusion'] in outcomes)
            if selected[0]['conclusion'] == 'skipped':
                archive.need(selected[0].get('steps') == [])
            jobs[name] = selected[0]
        archive.need(any(job['conclusion'] != 'skipped' for job in jobs.values()))
        job = jobs['Hosted Windows baseline']
        if job['conclusion'] == 'skipped':
            emit('Hosted baseline not selected', dict(scope='retained_windows_baseline_not_selected',
                inspection_only=True, runtime_started=False, wallet_qualified=False,
                source_head=head, source_tree=tree, source_run_id=run_id, source_attempt=1,
                original_job_id=job['id'], original_job_conclusion='skipped',
                baseline_qualified=False, baseline_logs_read=0))
        else:
            PHASE = 'baseline_log'
            location = client.read(archive.API + '/actions/jobs/' + str(job['id']) + '/logs', redirect=True)
            raw = client.read(location, authenticated=False, cap=MAX_LOG)
            summary = baseline_projection(log_report(raw, 'github_hosted_windows_baseline'), head, tree, run_id)
            archive.need(job['conclusion'] != 'success' or summary['artifact_reported_success'])
            summary.update(original_job_id=job['id'], original_job_conclusion=job['conclusion'],
                           log_sha256=archive.sha(raw), log_bytes=len(raw), producer_sources_equal=True)
            emit('Hosted baseline inspection', summary)
        entry_job = jobs['Ordinary Windows entry captures']
        if entry_job['conclusion'] == 'skipped':
            emit('Hosted entry not selected', dict(scope='retained_windows_entry_not_selected',
                inspection_only=True, runtime_started=False, wallet_qualified=False,
                source_head=head, source_tree=tree, source_run_id=run_id, source_attempt=1,
                original_job_id=entry_job['id'], original_job_conclusion='skipped',
                entry_qualified=False, entry_artifacts_read=0))
            return 0
        PHASE = 'entry_artifact'
        listing = client.json('/actions/runs/' + text + '/artifacts?per_page=20')
        archive.need(listing['total_count'] == len(listing['artifacts']) <= 20)
        name = 'windows-entry-capture-' + head + '-' + text + '-1'
        selected = [item for item in listing['artifacts'] if item['name'] == name]
        archive.need(len(selected) == 1)
        item = selected[0]
        archive.need(item['expired'] is False and item['workflow_run']['id'] == run_id
            and item['workflow_run']['head_sha'] == head
            and re.fullmatch('sha256:[a-f0-9]{64}', item.get('digest', '')) is not None)
        location = client.read(archive.API + '/actions/artifacts/' + str(item['id']) + '/zip', redirect=True)
        raw = client.read(location, authenticated=False, cap=MAX_ENTRY_ARCHIVE)
        summary = entry_archive(raw, item['digest'][7:], item['size_in_bytes'], head, tree, run_id)
        job = jobs['Ordinary Windows entry captures']
        archive.need(job['conclusion'] != 'success' or summary['artifact_reported_success'])
        summary.update(original_job_id=job['id'], original_job_conclusion=job['conclusion'],
                       producer_sources_equal=True)
        emit('Hosted entry inspection', summary)
        return 0
    except (Exception, KeyboardInterrupt):
        encoded = json.dumps(dict(scope='retained_windows_qualification_observation',
            inspection_success=False, code='INSPECTION_REFUSED', phase=PHASE,
            runtime_started=False, wallet_qualified=False), sort_keys=True)
        print(encoded)
        print('::notice title=Hosted Windows inspection refusal::' + encoded)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
