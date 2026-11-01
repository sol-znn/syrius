"""Inspect retained readonly wallet archives without another native execution."""

from __future__ import annotations

import base64
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import zipfile

from . import inspect_chain321 as archive
from . import windows_wallet_inspection as producer


MAX_ARCHIVE = producer.MAX_CAPTURE_TOTAL + producer.MAX_MANIFEST + 65536
MAX_HOME_ARCHIVE = producer.MAX_HOME_CAPTURE_TOTAL + producer.MAX_HOME_MANIFEST + 65536
MAX_TREE = 2 * 1024**2
WORKFLOW_SOURCE = '.github/workflows/public-contribution-qualification.yml'
MAX_WORKFLOW_SOURCE = 128 * 1024
MAX_WORKFLOW_RESPONSE = 256 * 1024
JOB = 'Windows readonly inspection with owned chain-321'
PREFLIGHT = ('Test all isolated controllers before SDK allocation',
    'Analyze the gated wallet entry and tour',
    'Test page coverage and refusal before wallet build')
RUNTIME = 'Build, observe and stop the original isolated lab'
SOURCE_FILES = (
    'tool/ci/windows_wallet_inspection.py', 'tool/ci/hosted_chain321.py',
    'tool/ci/readonly_viewport_capture.py', 'harness/bin/readonly_viewport_probe.dart',
    'tool/ci/run_harness_tour_tests.py', 'tool/ci/windows_debug_loop.py',
    'tool/ci/windows_debug_process.py', 'tool/ci/windows_entry_capture_smoke.py',
    'tool/ci/windows_presentation_smoke.py', 'tool/ci/windows_wallet_tour.py',
    'harness/bin/ci_wallet_inspection.dart',
    'harness/bin/readonly_inspection_session.dart', 'harness/bin/harness.dart',
    'harness/bin/wallet_recipe.dart', 'harness/app/agent.dart',
    'harness/app/readonly_native_mode.dart',
    'harness/app/readonly_native_commands.dart',
    'harness/app/readonly_sdk_admission.dart', 'harness/app/readonly_sdk_binding.dart',
    'harness/app/readonly_wallet_admission.dart',
    'harness/app/readonly_wallet_binding.dart', 'harness/app/native_window_owner.dart',
    'harness/app/logical_capture.dart', 'harness/app/readonly_shot_layout.dart',
    'harness/bin/readonly_home_catalog.dart', 'harness/bin/screen_capture.dart',
    'harness/screens/home-rest.txt', 'harness/screens/home-hidden.txt', 'harness/screens/home-open.txt',
    '.github/workflows/public-contribution-qualification.yml',
    'pubspec.yaml', 'pubspec.lock',
)
PHASE = 'environment'


def need(value):
    archive.need(value)


def digest(value, length=64):
    return type(value) is str and re.fullmatch('[a-f0-9]{' + str(length) + '}', value) is not None


def decode(raw):
    def unique(pairs):
        value = {}
        for key, item in pairs:
            need(key not in value)
            value[key] = item
        return value
    return json.loads(raw, object_pairs_hook=unique)


def owned_lab(report, head, tree, run_id):
    """The explicit reader scope cannot adopt a financial or restored lab."""
    need(type(report) is dict and report.get('application_tree') == tree)
    summary = archive.project(report, 'native', head, run_id,
        archive.UPSTREAM_NODE_SHA, expected_patched=True, expected_inspection=True)
    exits = summary['node_exits']
    positive = (all(summary['checks'].values()) and not summary['error_codes']
        and len(exits) == 5 and summary['native_shutdown_order'] == list(archive.ROLES)
        and summary['native_shutdown_mode'] == 'coordinated_requests_then_wait'
        and all(type(row['exit_code']) is int and row['exit_code'] == 0
                and row['output_complete'] is True and row['forced'] is False
                and row['stop_code'] is None for row in exits))
    need(not report['success'] or positive)
    summary['original_lab_closure_qualified'] = bool(report['success'] and positive)
    return summary


def projection(report, lab, lab_summary, head, tree, run_id, manifest_sha):
    """Check independent success requirements after the closed privacy schema."""
    producer.public_manifest(report)
    need(report.get('source_sha') == head and report.get('source_tree') == tree
         and report.get('run_id') == str(run_id) and report.get('run_attempt') == '1'
         and digest(manifest_sha) and lab.get('application_sha') == head
         and lab.get('application_tree') == tree and lab.get('run_id') == str(run_id)
         and lab.get('attempt') == '1' and lab_summary.get('source_head') == head
         and lab_summary.get('source_run_id') == run_id)
    original = lab.get('wallet_inspection')
    need(type(original) is dict and set(original) == {'success', 'phase', 'checks',
         'errors', 'captured_pages', 'visited_pages', 'manifest_sha256'}
         and original['manifest_sha256'] == manifest_sha
         and original['success'] is report['success'] and original['phase'] == report['phase']
         and original['checks'] == report['checks'] and original['errors'] == report['errors']
         and type(original['captured_pages']) is type(original['visited_pages']) is int
         and original['captured_pages'] == len(report['captures'])
         and original['visited_pages'] == sum(len(v['tour']['visited']) for v in report['tours'].values()))
    positive = (report['phase'] == 'complete' and not report['errors']
        and all(report['checks'].values())
        and report['input_attempted'] is True and report['lab_revalidations'] == 2
        and report['address_selection'] is not None
        and report['sdk_admission'] is not None and report['wallet_admission'] is not None
        and set(report['tours']) == set(report['locales']) == set(report['stalls']) == set(producer.THEMES)
        and len(report['captures']) == len(producer.THEMES) * len(producer.PAGES)
        and all(v['tour']['complete'] is True
                and len(v['tour']['visited']) == len(producer.PAGES)
                and all(p['captured'] is True and p['nodes'] > 0
                        and p['error_widgets'] == p['severe_logs'] == 0
                        for p in v['tour']['visited']) for v in report['tours'].values())
        and type(report.get('application_exit')) is int and report['application_exit'] == 0
        and type(report.get('entry_exit')) is int and report['entry_exit'] == 0
        and report['required_actor_forced_cleanup'] is False
        and report.get('owned_job_active_at_close') == 0
        and report['owned_job_images_before_close'] ==
            dict(status='OBSERVED', listed=0, observed=0, counts={})
        and report['entry_output']['output_complete'] is True
        and report['entry_output']['overflow'] is False
        and report['auxiliary_cleanup'] is not None
        and producer.debug.helper_cleanup_complete(report['auxiliary_cleanup'])
        and report['forced_cleanup'] is report['auxiliary_cleanup']['forced'])
    need(report['success'] is bool(positive))
    if positive:
        producer.capture_records(report['captures'])
        producer.sdk_receipt(report['sdk_admission'])
        producer.wallet_receipt(report['wallet_admission'])
    captures = json.dumps(report['captures'], sort_keys=True, separators=(',', ':')).encode('ascii')
    return dict(schema=1, scope='retained_readonly_wallet_inspection',
        source_head=head, source_tree=tree, source_run_id=run_id, source_attempt=1,
        artifact_reported_success=report['success'],
        original_lab_closure_qualified=lab_summary['original_lab_closure_qualified'],
        native_inspection_qualified=False, original_checks=dict(report['checks']),
        original_errors=list(report['errors']),
        entry_failure=report.get('entry_failure'), application_exit=report.get('application_exit'),
        entry_exit=report.get('entry_exit'),
        entry_output=report.get('entry_output'), forced_cleanup=report['forced_cleanup'],
        auxiliary_cleanup=report['auxiliary_cleanup'],
        required_actor_forced_cleanup=report['required_actor_forced_cleanup'],
        sdk_admission=report['sdk_admission'], wallet_admission=report['wallet_admission'],
        address_selection=report['address_selection'], lab_revalidations=report['lab_revalidations'],
        reported_capture_count=len(report['captures']), verified_png_count=0,
        capture_catalog_sha256=archive.sha(captures),
        visited_pages={t: len(v['tour']['visited']) for t, v in report['tours'].items()},
        locale_verified=sorted(report['locales']), stalls=report['stalls'],
        inspection_only=True, runtime_started=False, wallet_qualified=False,
        seed_admitted=False, financial_send_qualified=False,
        motion_baseline_compared=False, arabic_or_minimum_window_qualified=False,
        visual_matches=0)


LAYOUT_STATUS_ORDER = ('MISSING', 'OBSERVED', 'DUPLICATE', 'UNAVAILABLE', 'LIMIT')
LAYOUT_TARGETS = ('home_hero', 'transfer_card', 'nodes_tab_pillars',
    'nodes_tab_sentinels', 'staking_stake_button', 'plasma_open_fuse',
    'tokens_filter_held', 'p2p_start_swap', 'accelerator_strip', 'bell_panel',
    'node_settings_add', 'apps_settings_web_switch')
LAYOUT_COLUMNS = tuple(boundary + '_' + name
    for boundary in ('before', 'after')
    for name in ('body_status', 'body_top', 'caption_status', 'caption_bottom',
                 'target_status', 'target_top')) + ('unchanged',)


def layout_projection(report, head, tree, run_id):
    """Finite coordinates from the retained archive, never original widget text."""
    producer.public_manifest(report)
    need(report['success'] and report['source_sha'] == head
         and report['source_tree'] == tree and report['run_id'] == str(run_id)
         and report['run_attempt'] == '1' and len(LAYOUT_TARGETS) == len(producer.PAGES))
    rows = {}
    for theme in producer.THEMES:
        tour = report['tours'][theme]
        need(producer.tour_complete(tour))
        frames = []
        for page, target in zip(tour['tour']['visited'], LAYOUT_TARGETS):
            original = producer.layout_observation(page['layout'])
            frame = []
            for boundary in ('before', 'after'):
                entries = {row['key']: row for row in original[boundary]}
                for key, coordinate in (('window-body', 1), ('window-caption', 3),
                                         (target, 1)):
                    row = entries[key]
                    frame.extend((LAYOUT_STATUS_ORDER.index(row['status']),
                        row['rect'][coordinate] if row['status'] == 'OBSERVED' else None))
            frame.append(original['unchanged'])
            frames.append(frame)
        rows[theme] = frames
    return dict(schema=1, scope='retained_readonly_shot_layout_observation',
        source_head=head, source_tree=tree, source_run_id=run_id, source_attempt=1,
        pages=list(producer.PAGES), targets=list(LAYOUT_TARGETS),
        statuses=list(LAYOUT_STATUS_ORDER), columns=list(LAYOUT_COLUMNS), rows=rows,
        sample_count=24, boundaries=['before_raster', 'after_encoding'],
        inspection_only=True, runtime_started=False, atomic_frame_qualified=False,
        visual_matches=0, original_layout_or_raster_cause='NOT_ESTABLISHED')


def unpack(raw, expected_sha, expected_size, head, tree, run_id, lab, lab_summary):
    need(type(raw) is bytes and type(expected_size) is int and digest(expected_sha)
         and 0 < len(raw) == expected_size <= MAX_ARCHIVE and archive.sha(raw) == expected_sha)
    allowed = {'manifest.json'} | {'captures/' + t + '/' + p + '.png'
        for t in producer.THEMES for p in producer.PAGES}
    with zipfile.ZipFile(io.BytesIO(raw)) as zipped:
        members = zipped.infolist()
        names = [m.filename for m in members]
        need(1 <= len(members) <= 25 and len(set(names)) == len(names)
             and 'manifest.json' in names and set(names) <= allowed)
        total = 0
        for member in members:
            cap = producer.MAX_MANIFEST if member.filename == 'manifest.json' else producer.debug.entry.MAX_PNG
            need(not member.is_dir() and not member.flag_bits & 1
                 and stat.S_IFMT(member.external_attr >> 16) in (0, stat.S_IFREG)
                 and 0 < member.file_size <= cap)
            total += member.file_size
        need(total <= producer.MAX_CAPTURE_TOTAL + producer.MAX_MANIFEST)

        def member(name, cap):
            with zipped.open(name) as stream:
                value = stream.read(cap + 1)
                need(not stream.read(1))
            need(0 < len(value) == zipped.getinfo(name).file_size <= cap)
            return value

        manifest = member('manifest.json', producer.MAX_MANIFEST)
        report = decode(manifest)
        summary = projection(report, lab, lab_summary, head, tree, run_id, archive.sha(manifest))
        if report['success']:
            need(set(names) == allowed)
            for row in report['captures']:
                name = 'captures/' + row['theme'] + '/' + row['page'] + '.png'
                image = member(name, producer.debug.entry.MAX_PNG)
                need(len(image) == row['bytes'] and archive.sha(image) == row['sha256'])
                producer.debug.entry.png_bytes(base64.b64encode(image).decode('ascii'))
            summary['verified_png_count'] = 24
            summary['_layout_observation'] = layout_projection(report, head, tree, run_id)
            summary['_home_catalog_reference'] = report['home_catalog']
            summary['_viewport_reference'] = report['viewport']
        else:
            need(names == ['manifest.json'])
    summary.update(archive_sha256=archive.sha(raw), manifest_sha256=archive.sha(manifest))
    return summary


def home_script_source_pins(source_digests, schema):
    producer.home_catalog_files(schema)
    first = source_digests['harness/screens/home-rest.txt']
    if schema == 1:
        return first
    if schema == 2:
        return {'home-rest': first,
            'home-hidden': source_digests['harness/screens/home-hidden.txt']}
    return {'home-rest': first,
        'home-open': source_digests['harness/screens/home-open.txt'],
        'home-hidden': source_digests['harness/screens/home-hidden.txt']}


def unpack_home_catalog(raw, expected_sha, expected_size, head, tree, run_id,
                        reference, script_sha):
    """Verify each literal state; only the caller can bind parent closure."""
    producer.home_catalog_reference(reference)
    schema = reference['schema']
    files = producer.home_catalog_files(schema)
    script_field = producer._home_script_field(schema)
    pins = {'home-rest': script_sha} if schema == 1 else script_sha
    need(type(pins) is dict and set(pins) == set(
        producer.home_catalog_screens(schema))
        and all(digest(pin) for pin in pins.values()))
    need(type(raw) is bytes and type(expected_size) is int and digest(expected_sha)
         and 0 < len(raw) == expected_size <= MAX_HOME_ARCHIVE and archive.sha(raw) == expected_sha)
    allowed = {'manifest.json', *files}
    with zipfile.ZipFile(io.BytesIO(raw)) as zipped:
        members = zipped.infolist()
        names = [m.filename for m in members]
        need(len(members) == len(set(names)) == len(allowed) and set(names) == allowed)
        total = 0
        for member in members:
            cap = producer.MAX_HOME_MANIFEST if member.filename == 'manifest.json' else producer.MAX_HOME_CAPTURE_TOTAL
            need(member.orig_filename == member.filename and not member.is_dir()
                 and not member.flag_bits & 1
                 and stat.S_IFMT(member.external_attr >> 16) in (0, stat.S_IFREG)
                 and 0 < member.file_size <= cap)
            total += member.file_size
        need(total <= producer.MAX_HOME_CAPTURE_TOTAL + producer.MAX_HOME_MANIFEST)

        def member(name, cap):
            with zipped.open(name) as stream:
                value = stream.read(cap + 1)
                need(not stream.read(1))
            need(0 < len(value) == zipped.getinfo(name).file_size <= cap)
            return value

        manifest = member('manifest.json', producer.MAX_HOME_MANIFEST)
        need(archive.sha(manifest) == reference['manifest_sha256'])
        value = producer.public_home_catalog(decode(manifest))
        need(value['schema'] == schema and value['source_sha'] == head
             and value['source_tree'] == tree and value['run_id'] == str(run_id)
             and value['run_attempt'] == '1' and value[script_field] == script_sha)
        for row in producer.home_capture_records(value['captures'], schema=schema):
            pixels = member(row['file'], producer.MAX_HOME_CAPTURE_TOTAL)
            need(len(pixels) == row['bytes'] and archive.sha(pixels) == row['sha256'])
            producer.debug.entry.png_bytes(base64.b64encode(pixels).decode('ascii'))
    result = dict(schema=schema, scope='retained_readonly_home_catalog', source_head=head,
        source_tree=tree, source_run_id=run_id, source_attempt=1,
        themes=list(producer.THEMES), filenames=list(files),
        width=1280, height=780, scale=1, verified_png_count=len(files),
        archive_sha256=archive.sha(raw), manifest_sha256=archive.sha(manifest),
        catalog_capture_qualified=False, parent_closure_qualified=False,
        atomic_frame_qualified=False, inspection_only=True, runtime_started=False,
        wallet_qualified=False, seed_admitted=False, financial_send_qualified=False,
        visual_matches=0)
    result.update(dict(screen='home-rest', number=1) if schema == 1
                  else dict(screens=list(producer.home_catalog_screens(schema))))
    result[script_field] = script_sha
    return result


def source_files(repo, value, tree, *, read_workflow_blob=None):
    need(type(value) is dict and value.get('sha') == tree and value.get('truncated') is False
         and type(value.get('tree')) is list and len(value['tree']) <= 10000)
    entries = {}
    for item in value['tree']:
        if item.get('path') in SOURCE_FILES:
            need(item['path'] not in entries and item.get('mode') == '100644'
                 and item.get('type') == 'blob' and digest(item.get('sha'), 40))
            entries[item['path']] = item
    need(set(entries) == set(SOURCE_FILES))
    digests = {}
    for name in SOURCE_FILES:
        if name == WORKFLOW_SOURCE and read_workflow_blob is not None:
            # The sparse checkout omits workflows. Read the exact producer blob,
            # including when the independent reader is from a later revision.
            need(callable(read_workflow_blob))
            value = read_workflow_blob(entries[name]['sha'])
            need(type(value) is dict and value.get('sha') == entries[name]['sha']
                 and value.get('encoding') == 'base64'
                 and type(value.get('size')) is int
                 and 0 < value['size'] <= MAX_WORKFLOW_SOURCE
                 and type(value.get('content')) is str
                 and 0 < len(value['content']) <= MAX_WORKFLOW_RESPONSE
                 and re.fullmatch(r'[A-Za-z0-9+/=\n]+', value['content']) is not None)
            encoded = value['content'].replace('\n', '')
            raw = base64.b64decode(encoded, validate=True)
            need(len(raw) == value['size']
                 and base64.b64encode(raw).decode('ascii') == encoded)
        else:
            raw = producer.read_original(repo / name, MAX_TREE)
        blob = hashlib.sha1(b'blob ' + str(len(raw)).encode('ascii') + b'\0' + raw).hexdigest()
        need(blob == entries[name]['sha'])
        digests[name] = archive.sha(raw)
    return digests


def selected_job(value, head, run_id):
    need(type(value) is dict and type(value.get('jobs')) is list
         and type(value.get('total_count')) is int
         and value['total_count'] == len(value['jobs']) <= 50)
    jobs = [j for j in value['jobs'] if j.get('name') == JOB]
    need(len(jobs) == 1)
    job = jobs[0]
    need(type(job.get('id')) is int and 0 < job['id'] < 2**63
         and job.get('head_sha') == head and type(job.get('run_id')) is int
         and job['run_id'] == run_id and type(job.get('run_attempt')) is int
         and job['run_attempt'] == 1 and job.get('status') == 'completed'
         and job.get('conclusion') in ('success', 'failure', 'cancelled', 'timed_out'))
    need(all(j.get('status') == 'completed' and j.get('conclusion') == 'skipped'
             for j in value['jobs'] if j is not job))
    steps = job.get('steps')
    need(type(steps) is list and len(steps) <= 60)
    selected = []
    for name in (*PREFLIGHT, RUNTIME):
        found = [s for s in steps if s.get('name') == name]
        need(len(found) == 1 and found[0].get('status') == 'completed'
             and type(found[0].get('number')) is int)
        selected.append(found[0])
    need([s['number'] for s in selected] == sorted({s['number'] for s in selected})
         and all(s.get('conclusion') == 'success' for s in selected[:-1])
         and (job['conclusion'] != 'success' or selected[-1].get('conclusion') == 'success'))
    return job


def artifact(listing, name, head, run_id):
    need(type(listing) is dict and type(listing.get('artifacts')) is list
         and type(listing.get('total_count')) is int
         and listing.get('total_count') == len(listing['artifacts']) <= 20)
    selected = [a for a in listing['artifacts'] if a.get('name') == name]
    need(len(selected) == 1)
    value = selected[0]
    need(value.get('expired') is False and type(value.get('id')) is int and value['id'] > 0
         and type(value.get('workflow_run', {}).get('id')) is int
         and value['workflow_run']['id'] == run_id
         and value['workflow_run'].get('head_sha') == head
         and type(value.get('digest')) is str and re.fullmatch('sha256:[a-f0-9]{64}', value['digest'])
         and type(value.get('size_in_bytes')) is int and value['size_in_bytes'] > 0)
    return value


def emit(title, value):
    raw = json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True)
    need(len(raw.encode('ascii')) <= 3800)
    print('::notice title=' + title + '::' + raw.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A'), flush=True)


def main(parent=None):
    global PHASE
    parent = os.environ if parent is None else parent
    need(parent.get('GITHUB_ACTIONS') == 'true' and parent.get('SYRIUS_HOSTED_RUNNER') == 'github-hosted'
         and parent.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
         and parent.get('GITHUB_REPOSITORY') == 'edgepillar/syrius')
    text, head = parent.get('WALLET_INSPECT_RUN', ''), parent.get('WALLET_INSPECT_HEAD', '')
    need(type(text) is str and re.fullmatch('[1-9][0-9]{0,19}', text) and digest(head, 40))
    run_id = int(text)
    client = archive.Client(parent.get('GH_TOKEN'), max_calls=16)
    PHASE = 'producer_metadata'
    run = client.json('/actions/runs/' + text)
    need(type(run.get('id')) is int and run['id'] == run_id and run.get('head_sha') == head
         and type(run.get('run_attempt')) is int and run['run_attempt'] == 1
         and run.get('workflow_id') == 381413107 and run.get('event') == 'workflow_dispatch'
         and run.get('status') == 'completed' and run.get('repository', {}).get('full_name') == 'edgepillar/syrius')
    commit = client.json('/git/commits/' + head)
    need(commit.get('sha') == head and digest(commit.get('tree', {}).get('sha'), 40))
    tree = commit['tree']['sha']
    PHASE = 'producer_source'
    source_digests = source_files(Path(parent['GITHUB_WORKSPACE']), decode(client.read(
        archive.API + '/git/trees/' + tree + '?recursive=1', cap=MAX_TREE)), tree,
        read_workflow_blob=lambda blob: decode(client.read(
            archive.API + '/git/blobs/' + blob, cap=MAX_WORKFLOW_RESPONSE)))
    jobs = client.json('/actions/runs/' + text + '/attempts/1/jobs?per_page=50')
    job = selected_job(jobs, head, run_id)
    need((run.get('conclusion') == 'success') is (job['conclusion'] == 'success'))
    PHASE = 'lab_artifact'
    listing = client.json('/actions/runs/' + text + '/artifacts?per_page=20')

    def download(item, cap):
        need(item['size_in_bytes'] <= cap)
        location = client.read(archive.API + '/actions/artifacts/' + str(item['id']) + '/zip', redirect=True)
        return client.read(location, authenticated=False, cap=cap)

    root_item = artifact(listing, 'chain321-native-' + head + '-' + text + '-1', head, run_id)
    lab, lab_sha = archive.unpack(download(root_item, archive.MAX_ARCHIVE),
        root_item['digest'][7:], root_item['size_in_bytes'])
    lab_summary = owned_lab(lab, head, tree, run_id)
    lab_summary.update(archive_sha256=root_item['digest'][7:], manifest_sha256=lab_sha)
    PHASE = 'wallet_artifact'
    name = 'wallet-inspection-' + head + '-' + text + '-1'
    child = [v for v in listing['artifacts'] if v.get('name') == name]
    if not child:
        need(lab['success'] is False and job['conclusion'] != 'success')
        receipt = lab.get('wallet_inspection')
        need(receipt is None or type(receipt) is dict and receipt.get('manifest_sha256') is None)
        summary = dict(schema=1, scope='retained_readonly_wallet_inspection',
            source_head=head, source_tree=tree, source_run_id=run_id, source_attempt=1,
            artifact_reported_success=False, native_inspection_qualified=False,
            wallet_artifact_status='UNAVAILABLE', verified_png_count=0,
            inspection_only=True, runtime_started=False, wallet_qualified=False,
            seed_admitted=False, financial_send_qualified=False, visual_matches=0)
    else:
        item = artifact(listing, name, head, run_id)
        summary = unpack(download(item, MAX_ARCHIVE), item['digest'][7:], item['size_in_bytes'],
            head, tree, run_id, lab, lab_summary)
        summary['native_inspection_qualified'] = bool(summary['artifact_reported_success']
            and summary['original_lab_closure_qualified'] and summary['verified_png_count'] == 24
            and job['conclusion'] == 'success')
    need(job['conclusion'] != 'success' or summary['native_inspection_qualified'])
    catalog = viewport_observation = None
    reference = summary.pop('_home_catalog_reference', None)
    viewport_reference = summary.pop('_viewport_reference', None)
    if summary['native_inspection_qualified']:
        PHASE = 'home_catalog_artifact'
        need(reference is not None)
        item = artifact(listing, 'home-catalog-' + head + '-' + text + '-1', head, run_id)
        catalog = unpack_home_catalog(download(item, MAX_HOME_ARCHIVE), item['digest'][7:],
            item['size_in_bytes'], head, tree, run_id, reference,
            home_script_source_pins(source_digests, reference['schema']))
        PHASE = 'viewport_artifact'
        need(viewport_reference is not None)
        item = artifact(listing, 'viewport-observation-' + head + '-' + text + '-1', head, run_id)
        viewport_observation = producer.viewport.unpack(download(item, producer.viewport.MAX_ARCHIVE),
            item['digest'][7:], item['size_in_bytes'], head, tree, run_id, viewport_reference,
            source_digests['harness/bin/readonly_viewport_probe.dart'])
    PHASE = 'metadata_after'
    after = client.json('/actions/runs/' + text)
    need(all(after.get(k) == run.get(k) for k in ('id', 'head_sha', 'run_attempt', 'workflow_id', 'status', 'conclusion')))
    after_job = selected_job(client.json('/actions/runs/' + text + '/attempts/1/jobs?per_page=50'), head, run_id)
    need(all(after_job.get(k) == job.get(k) for k in ('id', 'head_sha', 'run_id', 'run_attempt', 'status', 'conclusion')))
    PHASE = 'emit'
    layout = summary.pop('_layout_observation', None)
    for component, frame in archive.restored_wallet_run.notice_frames(lab_summary):
        emit('Readonly inspection parent' + (' ' + component if component else ''), frame)
    summary.update(verified_viewport_png_count=4 if viewport_observation is not None else 0,
        verified_catalog_png_count=catalog['verified_png_count'] if catalog is not None else 0,
        producer_job_id=job['id'], producer_conclusion=job['conclusion'],
        producer_source_files_verified=len(SOURCE_FILES), metadata_revalidated=True)
    emit('Retained readonly wallet inspection', summary)
    if layout is not None and summary['native_inspection_qualified']:
        layout.update(archive_sha256=summary['archive_sha256'],
            manifest_sha256=summary['manifest_sha256'],
            producer_job_id=job['id'], metadata_revalidated=True,
            producer_source_files_verified=len(SOURCE_FILES),
            all_original_png_digests_verified=True)
        emit('Retained readonly shot layout', layout)
    if catalog is not None:
        catalog.update(catalog_capture_qualified=True, parent_closure_qualified=True,
            producer_job_id=job['id'], metadata_revalidated=True,
            producer_source_files_verified=len(SOURCE_FILES),
            all_original_png_digests_verified=True)
        emit('Retained readonly Home catalog', catalog)
    if viewport_observation is not None:
        viewport_observation.update(viewport_observation_qualified=True, parent_closure_qualified=True,
            producer_job_id=job['id'], metadata_revalidated=True,
            producer_source_files_verified=len(SOURCE_FILES), all_original_png_digests_verified=True)
        emit('Retained readonly viewport observation', viewport_observation)
    return summary


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('::error title=Readonly wallet inspection::INSPECTION_REFUSED phase=' + PHASE, flush=True)
        raise SystemExit(1) from None
