"""Inspect one fresh native wallet while its original five-node lab is owned.

Financial and copied-wallet flows are separate. Only closed-schema observations
and explicitly admitted English page captures can leave the isolated runner.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import subprocess
import sys
import time

from . import windows_debug_loop as debug
from . import windows_wallet_tour as shared
from . import readonly_viewport_capture as viewport
from .windows_debug_process import IMAGE_NAMES
from .hosted_chain321 import CODES as LAB_CODES


PAGES = shared.PAGES
THEMES = ('dark', 'light')
OUTPUT = Path('.harness/ci-wallet-inspection')
MAX_CAPTURE_TOTAL = 32 * 1024**2
MAX_MANIFEST = 128 * 1024
HOME_OUTPUT = Path('.harness/ci-home-catalog')
HOME_FILES = ('01-home-rest-dark.png', '01-home-rest-light.png')
MAX_HOME_CAPTURE_TOTAL = 4 * 1024**2
MAX_HOME_MANIFEST = 64 * 1024
HOME_SCRIPT = Path('harness/screens/home-rest.txt')
CHECKS = ('environment', 'source', 'unused_destinations', 'job_owned',
    'entry_gate', 'entry_ready', 'application_owned', 'lab_revalidated',
    'input_released', 'wallet_bound', 'tours_complete', 'locale_verified',
    'captures', 'close_ack', 'application_exit', 'entry_exit',
    'output_complete', 'source_unchanged', 'auxiliary_cleanup')
CODES = shared.CODES | LAB_CODES | frozenset(('BINDING_REFUSED', 'INSPECTION_REFUSED',
    'LAB_REVALIDATION_TIMEOUT_ERROR', 'LAB_REVALIDATION_CONNECTION_ERROR',
    'LAB_REVALIDATION_KEY_ERROR', 'LAB_REVALIDATION_TYPE_ERROR',
    'LAB_REVALIDATION_VALUE_ERROR', 'LAB_REVALIDATION_OS_ERROR'))
STAGES = frozenset(('unused_destinations', 'build', 'start', 'input', 'window',
    'onboarding', 'signing_policy', 'onboarding_logs', 'address_selection',
    'wallet_binding', 'tour_dark', 'tour_light', 'home_catalog', 'viewport', 'finish'))


class Refused(Exception):
    def __init__(self, code):
        self.code = code if type(code) is str and code in CODES else 'INTERNAL_ERROR'
        super().__init__(self.code)


def need(value, code='INSPECTION_REFUSED'):
    if not value:
        raise Refused(code)


def inspection_failure_code(error, phase):
    """Retain only fixed failure labels, never exception text or class names."""
    try:
        code = getattr(error, 'code', None)
    except Exception:
        code = None
    if code is None and type(error) is debug.ProcessRefused and len(error.args) == 1:
        code = error.args[0]
    if type(code) is str and code in CODES:
        return code
    if phase == 'lab_revalidation':
        for kind, label in ((TimeoutError, 'LAB_REVALIDATION_TIMEOUT_ERROR'),
            (ConnectionError, 'LAB_REVALIDATION_CONNECTION_ERROR'),
            (KeyError, 'LAB_REVALIDATION_KEY_ERROR'),
            (TypeError, 'LAB_REVALIDATION_TYPE_ERROR'),
            (ValueError, 'LAB_REVALIDATION_VALUE_ERROR'),
            (OSError, 'LAB_REVALIDATION_OS_ERROR')):
            if isinstance(error, kind):
                return label
    return 'INTERNAL_ERROR'


def read_original(path, cap):
    """Bound one original plain file and keep its identity across the read."""
    for parent in reversed(path.parents):
        need(stat.S_ISDIR(debug.bounded.plain(parent).st_mode), 'OUTPUT_REFUSED')
    before = debug.bounded.plain(path)

    def identity(info):
        need(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
             and 0 < info.st_size <= cap, 'OUTPUT_REFUSED')
        return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)

    expected = identity(before)
    with path.open('rb') as original:
        need(identity(os.fstat(original.fileno())) == expected, 'OUTPUT_REFUSED')
        raw = original.read(cap + 1)
        need(identity(os.fstat(original.fileno())) == expected, 'OUTPUT_REFUSED')
    need(identity(debug.bounded.plain(path)) == expected
         and len(raw) == before.st_size, 'OUTPUT_REFUSED')
    return raw


def home_capture_receipt(value):
    """Admit fixed metadata only after the original capture runner returns."""
    expected = dict(schema=1, scope='readonly_native_home_catalog_capture',
        screen='home-rest', number=1, themes=list(THEMES), files=list(HOME_FILES),
        width=1280, height=780, scale=1, capture_returned=True)
    need(type(value) is dict and set(value) == set(expected)
         and all(type(value[k]) is type(v) and value[k] == v
                 for k, v in expected.items()), 'CAPTURE_REFUSED')
    return value


def home_capture_records(value):
    """The two literal filenames are not aliases for generic tour pages."""
    need(type(value) is list and len(value) == 2, 'CAPTURE_REFUSED')
    for row, theme, name in zip(value, THEMES, HOME_FILES):
        need(type(row) is dict and set(row) ==
             {'theme', 'file', 'bytes', 'sha256', 'width', 'height', 'scale'}
             and row['theme'] == theme and row['file'] == name
             and type(row['bytes']) is int and 0 < row['bytes'] <= MAX_HOME_CAPTURE_TOTAL
             and type(row['sha256']) is str and re.fullmatch('[a-f0-9]{64}', row['sha256'])
             and all(type(row[k]) is int for k in ('width', 'height', 'scale'))
             and (row['width'], row['height'], row['scale']) == (1280, 780, 1),
             'CAPTURE_REFUSED')
    need(sum(row['bytes'] for row in value) <= MAX_HOME_CAPTURE_TOTAL, 'CAPTURE_REFUSED')
    return value


def home_catalog_reference(value):
    need(type(value) is dict and set(value) ==
         {'schema', 'scope', 'screen', 'captured', 'manifest_sha256'}
         and type(value['schema']) is int and value['schema'] == 1
         and value['scope'] == 'readonly_native_home_catalog_reference'
         and value['screen'] == 'home-rest'
         and type(value['captured']) is int and value['captured'] == 2
         and type(value['manifest_sha256']) is str
         and re.fullmatch('[a-f0-9]{64}', value['manifest_sha256']), 'CAPTURE_REFUSED')
    return value


def public_home_catalog(value):
    """This capture bundle cannot qualify its later parent closure or a match."""
    flags = {'inspection_only', 'parent_closure_qualified', 'atomic_frame_qualified',
             'wallet_qualified', 'seed_admitted', 'financial_send_qualified'}
    required = flags | {'schema', 'scope', 'source_sha', 'source_tree', 'run_id',
        'run_attempt', 'script_sha256', 'capture', 'captures', 'visual_matches'}
    need(type(value) is dict and set(value) == required
         and type(value['schema']) is int and value['schema'] == 1
         and value['scope'] == 'readonly_native_home_catalog_capture_bundle'
         and all(type(value[k]) is bool for k in flags)
         and value['inspection_only'] is True
         and all(value[k] is False for k in flags - {'inspection_only'})
         and type(value['visual_matches']) is int and value['visual_matches'] == 0,
         'OUTPUT_REFUSED')
    for key in ('source_sha', 'source_tree'):
        need(type(value[key]) is str and re.fullmatch('[a-f0-9]{40}', value[key]), 'OUTPUT_REFUSED')
    need(type(value['run_id']) is str and re.fullmatch('[1-9][0-9]{0,19}', value['run_id'])
         and type(value['run_attempt']) is str and value['run_attempt'] == '1'
         and type(value['script_sha256']) is str
         and re.fullmatch('[a-f0-9]{64}', value['script_sha256']), 'OUTPUT_REFUSED')
    home_capture_receipt(value['capture'])
    home_capture_records(value['captures'])
    return value


def home_output_bytes(output):
    """Account only this fresh finite family, including incomplete writes."""
    if not output.exists() and not output.is_symlink():
        return 0
    root = debug.bounded.plain(output)
    need(stat.S_ISDIR(root.st_mode), 'STORAGE_REFUSED')
    allowed = {'manifest.json', *HOME_FILES}
    total = count = 0
    for path in output.iterdir():
        count += 1
        need(count <= 3 and path.name in allowed, 'STORAGE_REFUSED')
        info = debug.bounded.plain(path)
        cap = MAX_HOME_MANIFEST if path.name == 'manifest.json' else MAX_HOME_CAPTURE_TOTAL
        need(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
             and 0 <= info.st_size <= cap, 'STORAGE_REFUSED')
        total += info.st_size
    need(total <= MAX_HOME_CAPTURE_TOTAL + MAX_HOME_MANIFEST, 'STORAGE_REFUSED')
    return total


def collect_home_catalog(repo, receipt, source, tree, parent):
    """Retain original PNG references without creating another archive copy."""
    home_capture_receipt(receipt)
    output = repo / HOME_OUTPUT
    home_output_bytes(output)
    records = []
    for theme, name in zip(THEMES, HOME_FILES):
        raw = read_original(output / name, MAX_HOME_CAPTURE_TOTAL)
        debug.entry.png_bytes(base64.b64encode(raw).decode('ascii'))
        records.append(dict(theme=theme, file=name, bytes=len(raw),
            sha256=hashlib.sha256(raw).hexdigest(), width=1280, height=780, scale=1))
    home_capture_records(records)
    script = read_original(repo / HOME_SCRIPT, 65536)
    value = dict(schema=1, scope='readonly_native_home_catalog_capture_bundle',
        source_sha=source, source_tree=tree, run_id=parent['GITHUB_RUN_ID'],
        run_attempt=parent['GITHUB_RUN_ATTEMPT'], script_sha256=hashlib.sha256(script).hexdigest(),
        capture=receipt, captures=records, inspection_only=True,
        parent_closure_qualified=False, atomic_frame_qualified=False,
        wallet_qualified=False, seed_admitted=False, financial_send_qualified=False,
        visual_matches=0)
    public_home_catalog(value)
    data = (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode('ascii')
    need(len(data) <= MAX_HOME_MANIFEST, 'OUTPUT_REFUSED')
    with (output / 'manifest.json').open('xb') as stream:
        stream.write(data)
    home_output_bytes(output)
    return home_catalog_reference(dict(schema=1,
        scope='readonly_native_home_catalog_reference', screen='home-rest',
        captured=2, manifest_sha256=hashlib.sha256(data).hexdigest()))


def home_artifact_paths(repo, report):
    """Only a completed generic parent can export the two catalog originals."""
    if report.get('success') is not True:
        return []
    need(completed(report), 'CAPTURE_REFUSED')
    reference = home_catalog_reference(report['home_catalog'])
    output = repo / HOME_OUTPUT
    home_output_bytes(output)
    raw = read_original(output / 'manifest.json', MAX_HOME_MANIFEST)
    need(hashlib.sha256(raw).hexdigest() == reference['manifest_sha256'], 'CAPTURE_REFUSED')
    def unique(pairs):
        value = {}
        for key, item in pairs:
            need(key not in value, 'OUTPUT_REFUSED')
            value[key] = item
        return value

    value = public_home_catalog(json.loads(raw, object_pairs_hook=unique))
    need(all(value[k] == report[k] for k in
             ('source_sha', 'source_tree', 'run_id', 'run_attempt'))
         and value['script_sha256'] == hashlib.sha256(
             read_original(repo / HOME_SCRIPT, 65536)).hexdigest(), 'SOURCE_REFUSED')
    paths = [str(HOME_OUTPUT / 'manifest.json').replace('\\', '/')]
    for row in home_capture_records(value['captures']):
        image = read_original(output / row['file'], MAX_HOME_CAPTURE_TOTAL)
        need(len(image) == row['bytes'] and hashlib.sha256(image).hexdigest() == row['sha256'],
             'CAPTURE_REFUSED')
        debug.entry.png_bytes(base64.b64encode(image).decode('ascii'))
        paths.append(str(HOME_OUTPUT / row['file']).replace('\\', '/'))
    return paths


def sdk_receipt(value):
    expected = dict(schema=1, scope='readonly_native_sdk_admission', status='CURRENT',
        publicationAdmissionPaused=True, automaticReceiveDisabled=True)
    need(type(value) is dict and set(value) == set(expected)
         and all(type(value[k]) is type(v) and value[k] == v for k, v in expected.items()))
    return value


def wallet_receipt(value):
    expected = dict(schema=1, scope='readonly_native_wallet_admission', status='CURRENT',
        chain=321, selectedIndex=1, nativeFrameObserved=True)
    need(type(value) is dict and set(value) == set(expected)
         and all(type(value[k]) is type(v) and value[k] == v for k, v in expected.items()),
         'BINDING_REFUSED')
    return value


def readonly_reply(value, pid, *, wallet=False):
    need(type(value) is dict and value.get('ok') is True
         and value.get('booted') is True and value.get('readOnly') is True
         and value.get('harnessMode') == 'readonly-native'
         and type(value.get('pid')) is int and value['pid'] == pid)
    sdk_receipt(value.get('readonlyAdmission'))
    if wallet:
        wallet_receipt(value.get('readonlyWallet'))
    return value


def ready_receipt(value):
    need(type(value) is dict and set(value) == {'schema', 'scope', 'pid', 'port'}
         and type(value['schema']) is int and value['schema'] == 1
         and value['scope'] == 'readonly_native_inspection_ready'
         and type(value['pid']) is int and 0 < value['pid'] < 2**32
         and type(value['port']) is int and 1024 <= value['port'] <= 65535,
         'ENTRY_REFUSED')
    return value


LAYOUT_KEYS = ('window-caption', 'window-body', 'home_hero', 'home_send', 'nodes_tab_pillars', 'nodes_tab_sentinels', 'staking_stake_button', 'plasma_open_fuse', 'tokens_filter_held', 'p2p_start_swap', 'node_settings_add', 'apps_settings_web_switch', 'transfer_card', 'accelerator_strip', 'bell_panel')
LAYOUT_STATUS = frozenset(('OBSERVED', 'MISSING', 'DUPLICATE', 'UNAVAILABLE', 'LIMIT'))


def layout_observation(value):
    """Only fixed keys and bounded numeric facts at two readback boundaries."""
    need(type(value) is dict and set(value) ==
         {'schema', 'scope', 'boundaries', 'before', 'after', 'unchanged'}
         and type(value['schema']) is int and value['schema'] == 1
         and value['scope'] == 'readonly_shot_layout_observation'
         and value['boundaries'] == ['before_raster', 'after_encoding']
         and type(value['unchanged']) is bool, 'CAPTURE_REFUSED')
    for boundary in ('before', 'after'):
        rows = value[boundary]
        need(type(rows) is list and len(rows) == len(LAYOUT_KEYS), 'CAPTURE_REFUSED')
        for row, key in zip(rows, LAYOUT_KEYS):
            need(type(row) is dict and row.get('key') == key
                 and type(row.get('status')) is str
                 and row['status'] in LAYOUT_STATUS, 'CAPTURE_REFUSED')
            need(set(row) == ({'key', 'status', 'rect'} if row['status'] == 'OBSERVED'
                              else {'key', 'status'}), 'CAPTURE_REFUSED')
            if row['status'] == 'OBSERVED':
                rect = row['rect']
                need(type(rect) is list and len(rect) == 4
                     and all(type(x) is int and abs(x) <= 32768 for x in rect)
                     and rect[2] >= rect[0] and rect[3] >= rect[1], 'CAPTURE_REFUSED')
        if any(row['status'] == 'LIMIT' for row in rows):
            need(all(row['status'] == 'LIMIT' for row in rows), 'CAPTURE_REFUSED')
    need(value['unchanged'] is (value['before'] == value['after']), 'CAPTURE_REFUSED')
    return value


def tour_receipt(value):
    need(type(value) is dict and set(value) == {'theme', 'tour'}
         and value['theme'] in THEMES, 'TOUR_REFUSED')
    tour = value['tour']
    need(type(tour) is dict and set(tour) ==
         {'schema', 'scope', 'complete', 'requested', 'visited'}
         and type(tour['schema']) is int and tour['schema'] == 1
         and tour['scope'] == 'readonly_native_page_tour'
         and type(tour['complete']) is bool and tour['requested'] == list(PAGES)
         and type(tour['visited']) is list and len(tour['visited']) <= len(PAGES),
         'TOUR_REFUSED')
    for index, page in enumerate(tour['visited']):
        need(type(page) is dict and set(page) ==
             {'page', 'nodes', 'error_widgets', 'severe_logs', 'captured', 'layout'}
             and page['page'] == PAGES[index] and type(page['captured']) is bool
             and all(type(page[k]) is int and 0 <= page[k] <= 100000
                     for k in ('nodes', 'error_widgets', 'severe_logs')), 'TOUR_REFUSED')
        if page['captured']:
            layout_observation(page['layout'])
        else:
            need(page['layout'] is None, 'TOUR_REFUSED')
    return value


def tour_complete(value):
    tour_receipt(value)
    tour = value['tour']
    return (tour['complete'] and len(tour['visited']) == len(PAGES)
        and all(p['captured'] and p['error_widgets'] == p['severe_logs'] == 0
                for p in tour['visited']))


def locale_receipt(value):
    need(type(value) is dict and set(value) ==
         {'schema', 'scope', 'theme', 'language', 'direction', 'stable'}
         and type(value['schema']) is int and value['schema'] == 1
         and value['scope'] == 'readonly_native_locale_observation'
         and value['theme'] in THEMES and value['language'] == 'en'
         and value['direction'] == 'ltr' and value['stable'] is True)
    return value


def stalls_receipt(value):
    need(type(value) is dict and set(value) ==
         {'schema', 'scope', 'theme', 'events', 'longest_ms'}
         and type(value['schema']) is int and value['schema'] == 1
         and value['scope'] == 'readonly_native_stalls_observation'
         and value['theme'] in THEMES
         and type(value['events']) is int and 0 <= value['events'] <= 100000
         and type(value['longest_ms']) is int and 0 <= value['longest_ms'] <= 900000)
    return value


def entry_failure(value):
    need(type(value) is dict and set(value) in
         ({'stage', 'code'}, {'stage', 'code', 'diagnostic'})
         and value['stage'] in STAGES and (value['code'] is None
             or type(value['code']) is str and (
                 re.fullmatch('wallet-recipe-[a-z-]{1,80}', value['code'])
                 or value['code'] in {'inspection-' + reason for reason in
                     ('process', 'retired', 'command', 'reply', 'binding')})), 'ENTRY_REFUSED')
    if 'diagnostic' in value:
        if value['stage'] in ('onboarding', 'address_selection'):
            shared.entry_failure(value)
        elif value['stage'] == 'viewport':
            need(value['code'] is None or value['code'] in {
                'inspection-' + reason for reason in
                ('process', 'retired', 'command', 'reply', 'binding')}, 'ENTRY_REFUSED')
            try:
                viewport.failure_diagnostic(value['diagnostic'])
            except viewport.Refused:
                need(False, 'ENTRY_REFUSED')
        else:
            need(value['stage'] in ('tour_dark', 'tour_light')
                 and value['code'] is None, 'ENTRY_REFUSED')
            shared.tour_failure_diagnostic(value['diagnostic'])
    return value


def capture_records(value, *, complete=True):
    need(type(value) is list and len(value) <= len(THEMES) * len(PAGES)
         and (not complete or len(value) == len(THEMES) * len(PAGES)), 'CAPTURE_REFUSED')
    for row, (theme, page) in zip(value, ((t, p) for t in THEMES for p in PAGES)):
        need(type(row) is dict and set(row) ==
             {'theme', 'page', 'bytes', 'sha256', 'width', 'height'}
             and row['theme'] == theme and row['page'] == page
             and type(row['bytes']) is int and 0 < row['bytes'] <= debug.entry.MAX_PNG
             and type(row['sha256']) is str and re.fullmatch('[a-f0-9]{64}', row['sha256'])
             and type(row['width']) is type(row['height']) is int
             and row['width'] == 1280 and row['height'] == 780, 'CAPTURE_REFUSED')
    need(not complete or sum(row['bytes'] for row in value) <= MAX_CAPTURE_TOTAL, 'CAPTURE_REFUSED')
    return value


def completed(report):
    try:
        capture_records(report['captures'])
        home_catalog_reference(report['home_catalog'])
        viewport.reference(report['viewport'])
        sdk_receipt(report['sdk_admission'])
        wallet_receipt(report['wallet_admission'])
        return (report['phase'] == 'complete' and not report['errors']
            and set(report['checks']) == set(CHECKS)
            and all(v is True for v in report['checks'].values())
            and type(report['lab_revalidations']) is int and report['lab_revalidations'] == 2
            and set(report['tours']) == set(report['locales']) == set(report['stalls']) == set(THEMES)
            and all(tour_complete(report['tours'][t]) and locale_receipt(report['locales'][t])
                    and stalls_receipt(report['stalls'][t]) for t in THEMES)
            and type(report.get('application_exit')) is int and report['application_exit'] == 0
            and type(report.get('entry_exit')) is int and report['entry_exit'] == 0
            and type(report.get('owned_job_active_at_close')) is int
            and report['owned_job_active_at_close'] == 0
            and report['owned_job_images_before_close']['status'] == 'OBSERVED'
            and report['owned_job_images_before_close']['listed'] ==
                report['owned_job_images_before_close']['observed'] == 0
            and not report['required_actor_forced_cleanup']
            and report['entry_output']['output_complete'] and not report['entry_output']['overflow']
            and debug.helper_cleanup_complete(report['auxiliary_cleanup'])
            and report['forced_cleanup'] is report['auxiliary_cleanup']['forced'])
    except (Refused, viewport.Refused, KeyError, TypeError):
        return False


def output_bytes(output):
    """Only the manifest and finite capture paths belong to this output root."""
    total = entries = 0
    allowed = {output / 'manifest.json'} | {
        output / 'captures' / theme / (page + '.png') for theme in THEMES for page in PAGES}
    for path in (output, output / 'captures', *(output / 'captures' / t for t in THEMES)):
        if path.exists() or path.is_symlink():
            debug.bounded.plain(path)
            for child in path.iterdir():
                if child in (output / 'captures', *(output / 'captures' / t for t in THEMES)):
                    debug.bounded.plain(child)
                else:
                    need(child in allowed, 'STORAGE_REFUSED')
                    info = debug.bounded.plain(child)
                    total += info.st_size
                    entries += 1
    need(entries <= len(allowed) and total <= MAX_CAPTURE_TOTAL + MAX_MANIFEST, 'STORAGE_REFUSED')
    return total


def public_manifest(value):
    """Refuse unexpected fields and strings before any artifact or annotation."""
    flags = {'success', 'inspection_qualified', 'wallet_qualified', 'seed_admitted',
        'forced_cleanup', 'required_actor_forced_cleanup', 'financial_send_qualified',
        'motion_baseline_compared', 'arabic_or_minimum_window_qualified'}
    required = flags | {'schema', 'scope', 'visual_matches', 'checks', 'errors', 'phase',
        'captures', 'tours', 'locales', 'stalls', 'home_catalog', 'viewport', 'sdk_admission', 'wallet_admission',
        'address_selection', 'lab_revalidations', 'auxiliary_cleanup', 'min_free_bytes',
        'workspace_cap_bytes', 'storage_scope', 'storage', 'cleanup'}
    optional = {'source_sha', 'source_tree', 'run_id', 'run_attempt', 'input_attempted',
        'entry_failure', 'application_exit', 'cleanup_application_exit', 'entry_exit',
        'owned_job_images_before_close', 'owned_job_active_at_close', 'entry_output'}
    need(type(value) is dict and required <= set(value) <= required | optional, 'OUTPUT_REFUSED')
    need(type(value['schema']) is int and value['schema'] == 1
         and value['scope'] == 'owned_chain321_wallet_inspection'
         and all(type(value[k]) is bool for k in flags)
         and all(value[k] is False for k in ('wallet_qualified', 'seed_admitted',
             'financial_send_qualified', 'motion_baseline_compared', 'arabic_or_minimum_window_qualified'))
         and type(value['visual_matches']) is int and value['visual_matches'] == 0
         and value['success'] is value['inspection_qualified'], 'OUTPUT_REFUSED')
    need(type(value['checks']) is dict and set(value['checks']) == set(CHECKS)
         and all(type(v) is bool for v in value['checks'].values())
         and type(value['errors']) is list and len(value['errors']) <= 32
         and all(type(e) is str and e in CODES for e in value['errors'])
         and value['phase'] in ('admission', 'build_and_start', 'lab_revalidation',
             'onboarding_and_inspection', 'ordinary_close', 'complete')
         and type(value['lab_revalidations']) is int and 0 <= value['lab_revalidations'] <= 2,
         'OUTPUT_REFUSED')
    need(value['min_free_bytes'] == shared.FIXTURE_FLOOR
         and value['workspace_cap_bytes'] == shared.WORK_CAP
         and value['storage_scope'] == 'isolated_hosted_regression_fixture_cooperative_samples'
         and value['cleanup'] == 'runner_lifecycle_not_qualified', 'OUTPUT_REFUSED')
    for name in ('source_sha', 'source_tree'):
        if name in value:
            need(type(value[name]) is str and re.fullmatch('[a-f0-9]{40}', value[name]), 'OUTPUT_REFUSED')
    for name in ('run_id', 'run_attempt'):
        if name in value:
            need(type(value[name]) is str and re.fullmatch('[1-9][0-9]{0,19}', value[name]), 'OUTPUT_REFUSED')
    for name in ('application_exit', 'cleanup_application_exit', 'entry_exit', 'owned_job_active_at_close'):
        if name in value:
            need(value[name] is None or type(value[name]) is int
                 and -2**31 <= value[name] < 2**32, 'OUTPUT_REFUSED')
    if 'input_attempted' in value:
        need(type(value['input_attempted']) is bool, 'OUTPUT_REFUSED')
    if 'entry_failure' in value:
        entry_failure(value['entry_failure'])
    if value['home_catalog'] is not None:
        home_catalog_reference(value['home_catalog'])
    need(not value['success'] or value['home_catalog'] is not None, 'OUTPUT_REFUSED')
    if value['viewport'] is not None:
        viewport.reference(value['viewport'])
    need(not value['success'] or value['viewport'] is not None, 'OUTPUT_REFUSED')
    capture_records(value['captures'], complete=value['success'])
    if value['sdk_admission'] is not None:
        sdk_receipt(value['sdk_admission'])
    if value['wallet_admission'] is not None:
        wallet_receipt(value['wallet_admission'])
    if value['address_selection'] is not None:
        shared.address_selection_receipt(value['address_selection'])
    for key, validate in (('tours', tour_receipt), ('locales', locale_receipt), ('stalls', stalls_receipt)):
        need(type(value[key]) is dict and set(value[key]) <= set(THEMES), 'OUTPUT_REFUSED')
        for theme, observed in value[key].items():
            validate(observed)
            need(observed['theme'] == theme, 'OUTPUT_REFUSED')
    storage = value['storage']
    need(type(storage) is dict and set(storage) ==
         {'samples', 'peak_logical_bytes', 'minimum_free_bytes', 'refusal'}
         and all(type(storage[k]) is int and 0 <= storage[k] < 2**63
                 for k in ('samples', 'peak_logical_bytes'))
         and (storage['minimum_free_bytes'] is None or
              type(storage['minimum_free_bytes']) is int and 0 <= storage['minimum_free_bytes'] < 2**63)
         and storage['refusal'] in (None, 'STORAGE_REFUSED'), 'OUTPUT_REFUSED')
    labels = set(IMAGE_NAMES.values()) | {'OTHER'}
    if 'owned_job_images_before_close' in value:
        images = value['owned_job_images_before_close']
        need(type(images) is dict and set(images) == {'status', 'listed', 'observed', 'counts'}
             and images['status'] in ('OBSERVED', 'UNKNOWN')
             and all(type(images[k]) is int and 0 <= images[k] <= 64 for k in ('listed', 'observed'))
             and type(images['counts']) is dict and set(images['counts']) <= labels
             and all(type(n) is int and 0 <= n <= 64 for n in images['counts'].values()), 'OUTPUT_REFUSED')
    if 'entry_output' in value:
        observed = value['entry_output']
        need(type(observed) is dict and set(observed) == {'bytes', 'sha256', 'output_complete', 'overflow'}
             and type(observed['bytes']) is int and 0 <= observed['bytes'] < 2**63
             and type(observed['sha256']) is str and re.fullmatch('[a-f0-9]{64}', observed['sha256'])
             and type(observed['output_complete']) is type(observed['overflow']) is bool, 'OUTPUT_REFUSED')
    aux = value['auxiliary_cleanup']
    if aux is not None:
        need(type(aux) is dict and set(aux) ==
             {'scope', 'status', 'code', 'forced', 'remaining', 'receipts', 'observation'}
             and aux['scope'] == debug.HELPER_SCOPE and aux['status'] in ('PASSED', 'FAILED')
             and (aux['code'] is None or type(aux['code']) is str and aux['code'] in CODES)
             and type(aux['forced']) is bool
             and (aux['remaining'] is None or type(aux['remaining']) is int and 0 <= aux['remaining'] <= 64)
             and type(aux['receipts']) is list and len(aux['receipts']) <= 2, 'OUTPUT_REFUSED')
        for receipt in aux['receipts']:
            need(type(receipt) is dict and set(receipt) == {'role', 'image_sha256', 'forced',
                 'termination_requested', 'termination_succeeded', 'actual_exit', 'exit_observed', 'stdio_captured'}
                 and receipt['role'] in ('sdk_dart', 'msvc_telemetry')
                 and type(receipt['image_sha256']) is str
                 and re.fullmatch('[a-f0-9]{64}', receipt['image_sha256'])
                 and all(type(receipt[k]) is bool for k in ('forced', 'termination_requested',
                     'termination_succeeded', 'exit_observed', 'stdio_captured'))
                 and (receipt['actual_exit'] is None or type(receipt['actual_exit']) is int
                      and -2**31 <= receipt['actual_exit'] < 2**32), 'OUTPUT_REFUSED')
        observation = aux['observation']
        need(type(observation) is dict and set(observation) ==
             {'stage', 'image_class', 'image_bytes', 'path_match'}
             and observation['stage'] in ('members', 'member', 'sdk_image', 'compiler_metadata',
                 'compiler_image', 'image_pin', 'membership_recheck', 'image_recheck',
                 'termination', 'exit_observation', 'empty_job', 'complete')
             and observation['image_class'] in labels | {None}
             and (observation['image_bytes'] is None or type(observation['image_bytes']) is int
                  and 0 <= observation['image_bytes'] <= 64 * 1024**2)
             and (observation['path_match'] is None or type(observation['path_match']) is bool), 'OUTPUT_REFUSED')
    return value


def run(repo, parent, runtime, lab_root, observation, revalidate):
    report = dict(schema=1, scope='owned_chain321_wallet_inspection', success=False,
        inspection_qualified=False, wallet_qualified=False, seed_admitted=False, visual_matches=0,
        checks=dict.fromkeys(CHECKS, False), errors=[], phase='admission', captures=[],
        tours={}, locales={}, stalls={}, home_catalog=None, viewport=None,
        sdk_admission=None, wallet_admission=None,
        address_selection=None, lab_revalidations=0, forced_cleanup=False,
        required_actor_forced_cleanup=False, auxiliary_cleanup=None,
        min_free_bytes=shared.FIXTURE_FLOOR, workspace_cap_bytes=shared.WORK_CAP,
        storage_scope='isolated_hosted_regression_fixture_cooperative_samples',
        storage=dict(samples=0, peak_logical_bytes=0, minimum_free_bytes=None, refusal=None),
        cleanup='runner_lifecycle_not_qualified', financial_send_qualified=False,
        motion_baseline_compared=False, arabic_or_minimum_window_qualified=False)
    original = lines = job = output = transport = token = None
    close_attempted = False
    catalog_receipt = viewport_receipt = None
    try:
        parent, source = debug.entry.require_ci(parent, None, platform=os.name)
        need(parent.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
             and parent.get('SYRIUS_HOSTED_RUNNER') == 'github-hosted'
             and parent.get('SYRIUS_WINDOWS_WALLET_INSPECTION') == 'true'
             and parent.get('SYRIUS_WINDOWS_WALLET_TOUR', 'false') == 'false'
             and parent.get('SYRIUS_LAB_NODE_SOURCE') == 'lab-fix'
             and parent.get('SYRIUS_NATIVE_STACK_DIAGNOSTIC') == 'true', 'ENVIRONMENT_REFUSED')
        report['checks']['environment'] = True
        debug.bounded.verify_source(repo, source, parent)
        tree = debug.entry.source_tree(repo, parent)
        report.update(source_sha=source, source_tree=tree, run_id=parent['GITHUB_RUN_ID'],
            run_attempt=parent['GITHUB_RUN_ATTEMPT'])
        report['checks']['source'] = True
        root = debug.entry.private_root(repo)
        output = repo / OUTPUT
        output.mkdir(mode=0o700)
        free = shutil.disk_usage(repo).free
        report['storage']['minimum_free_bytes'] = free
        need(free >= shared.FIXTURE_FLOOR + shared.WORK_CAP, 'STORAGE_REFUSED')
        debug.bounded.check_no_existing(repo, parent)
        name = 'ci-inspect-' + secrets.token_hex(12)
        home, app, build = root / name, root / 'app', repo / 'build/windows/x64'
        need(not any(p.exists() or p.is_symlink() for p in (home, app, build, repo / HOME_OUTPUT, repo / viewport.OUTPUT)), 'PROFILE_REFUSED')
        report['checks']['unused_destinations'] = True
        profile = debug.entry.new_profile(repo)
        profile_identity = shared.directory_identity(profile.lstat())
        need(profile_identity is not None, 'PROFILE_REFUSED')
        env = debug.profile_environment(parent, profile, 1, secrets.token_hex(16))
        env.update(SYRIUS_CI_WALLET_INSPECTION='true', SYRIUS_CI_INSPECTION_INSTANCE=name)
        dart, _ = debug.sdk(parent)
        job = debug.WindowsJob()
        original = subprocess.Popen([str(dart), '--disable-dart-dev',
            '--packages=' + str(repo / '.dart_tool/package_config.json'),
            'harness/bin/ci_wallet_inspection.dart'], cwd=repo, env=env, shell=False,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
        job.assign(original)
        report['checks']['job_owned'] = True
        lines = debug.Lines(original.stdout)
        deadline, next_sample = time.monotonic() + 900, 0.0
        used = set()
        stages = []
        ready = None

        def write(data):
            need(original.poll() is None and len(data) <= 4096, 'INPUT_REFUSED')
            original.stdin.write(data)
            original.stdin.flush()

        def lab_current():
            report['phase'] = 'lab_revalidation'
            runtime.healthy()
            now = revalidate()
            need(now['chain'] == observation['chain'] == 321
                 and now['genesis_hash'] == observation['genesis_hash']
                 and now['last_height'] >= observation['last_height']
                 and now['cross_transport_hash_equal'] is observation['cross_transport_hash_equal'] is True,
                 'LAB_REFUSED')
            report['lab_revalidations'] += 1

        def wait(marker, *, seconds=None):
            nonlocal next_sample, ready, catalog_receipt, viewport_receipt
            limit = deadline if seconds is None else min(deadline, time.monotonic() + seconds)
            while True:
                runtime.healthy()
                now = time.monotonic()
                need(now < limit, 'TOTAL_DEADLINE')
                if now >= next_sample:
                    logical = shared.sample_workspace((home, app, build, profile),
                        expected_profile=profile_identity)
                    logical += output_bytes(output)
                    logical += home_output_bytes(repo / HOME_OUTPUT)
                    logical += viewport.output_bytes(repo / viewport.OUTPUT)
                    need(logical <= shared.WORK_CAP, 'STORAGE_REFUSED')
                    free = shutil.disk_usage(repo).free
                    storage = report['storage']
                    storage['samples'] += 1
                    storage['peak_logical_bytes'] = max(storage['peak_logical_bytes'], logical)
                    storage['minimum_free_bytes'] = min(storage['minimum_free_bytes'], free)
                    need(free >= shared.FIXTURE_FLOOR, 'STORAGE_REFUSED')
                    next_sample = now + 5
                raw = lines.take(.1)
                if raw is None:
                    need(original.poll() is None or not lines.complete, 'ENTRY_FAILED')
                    continue
                line = raw.rstrip(b'\r\n')
                if line.startswith(b'CI_INSPECT_STAGE:'):
                    ordered = (b'CI_INSPECT_STAGE:gate', b'CI_INSPECT_STAGE:build',
                               b'CI_INSPECT_STAGE:start')
                    need(len(stages) < len(ordered) and line == ordered[len(stages)], 'ENTRY_REFUSED')
                    stages.append(line)
                    used.add(line)
                    if line == marker:
                        return
                elif line.startswith(b'CI_INSPECT_READY:'):
                    need(marker == b'CI_INSPECT_READY' and ready is None
                         and len(stages) == 3, 'ENTRY_REFUSED')
                    ready = ready_receipt(json.loads(line.partition(b':')[2]))
                    return
                elif line.startswith(b'SYRIUS_INSPECTION_ADDRESS:'):
                    need(marker == b'CI_INSPECT_DONE' and 'address' not in used, 'ENTRY_REFUSED')
                    used.add('address')
                    report['address_selection'] = shared.address_selection_receipt(
                        json.loads(line.partition(b':')[2]))
                elif line.startswith(b'SYRIUS_INSPECTION_WALLET:'):
                    need('address' in used and 'wallet' not in used, 'ENTRY_REFUSED')
                    used.add('wallet')
                    report['wallet_admission'] = wallet_receipt(json.loads(line.partition(b':')[2]))
                elif line.startswith(b'SYRIUS_INSPECTION_TOUR:'):
                    value = tour_receipt(json.loads(line.partition(b':')[2]))
                    theme = value['theme']
                    need('wallet' in used and theme not in report['tours']
                         and len(report['tours']) == len(report['locales']) ==
                             len(report['stalls']) == THEMES.index(theme), 'ENTRY_REFUSED')
                    report['tours'][theme] = value
                elif line.startswith(b'SYRIUS_INSPECTION_LOCALE:'):
                    value = locale_receipt(json.loads(line.partition(b':')[2]))
                    theme = value['theme']
                    need(theme in report['tours'] and theme not in report['locales']
                         and len(report['tours']) == len(report['locales']) + 1
                         and len(report['stalls']) == THEMES.index(theme), 'ENTRY_REFUSED')
                    report['locales'][theme] = value
                elif line.startswith(b'SYRIUS_INSPECTION_STALLS:'):
                    value = stalls_receipt(json.loads(line.partition(b':')[2]))
                    theme = value['theme']
                    need(theme in report['locales'] and theme not in report['stalls']
                         and len(report['locales']) == len(report['stalls']) + 1
                         and len(report['stalls']) == THEMES.index(theme), 'ENTRY_REFUSED')
                    report['stalls'][theme] = value
                elif line.startswith(b'SYRIUS_INSPECTION_CATALOG:'):
                    need(marker == b'CI_INSPECT_DONE' and catalog_receipt is None
                         and 'wallet' in used and set(report['stalls']) == set(THEMES),
                         'ENTRY_REFUSED')
                    catalog_receipt = home_capture_receipt(json.loads(line.partition(b':')[2]))
                elif line.startswith(b'SYRIUS_INSPECTION_VIEWPORT:'):
                    need(marker == b'CI_INSPECT_DONE' and viewport_receipt is None
                         and catalog_receipt is not None, 'ENTRY_REFUSED')
                    viewport_receipt = viewport.receipt(json.loads(line.partition(b':')[2]))
                elif line.startswith(b'CI_INSPECT_ERROR:'):
                    report['entry_failure'] = entry_failure(json.loads(line.partition(b':')[2]))
                    raise Refused('ENTRY_FAILED')
                elif line == b'CI_INSPECT_DONE':
                    need(marker == line and set(report['stalls']) == set(THEMES)
                         and catalog_receipt is not None and viewport_receipt is not None, 'ENTRY_REFUSED')
                    return
                elif line.startswith((b'CI_INSPECT_', b'SYRIUS_INSPECTION_',
                        b'CI_WALLET_', b'SYRIUS_LAB_SEND:', b'SYRIUS_WALLET_TOUR:')):
                    raise Refused('ENTRY_REFUSED')

        report['phase'] = 'build_and_start'
        write(b'START\n')
        wait(b'CI_INSPECT_STAGE:gate', seconds=30)
        report['checks']['entry_gate'] = True
        wait(b'CI_INSPECT_READY')
        report['checks']['entry_ready'] = True
        info = debug.bounded.plain(home / 'instance.json')
        debug.bounded.plain(home)
        need(0 < info.st_size <= 4096, 'PROFILE_REFUSED')
        private = json.loads((home / 'instance.json').read_bytes())
        pid, port, token = private.get('pid'), private.get('port'), private.get('token')
        need(type(pid) is int and pid == ready['pid'] and port == ready['port']
             and type(token) is str and re.fullmatch('[a-f0-9]{32}', token)
             and private.get('mode') == 'release' and private.get('harnessMode') == 'readonly-native'
             and private.get('presentationScreen') is None, 'ENTRY_REFUSED')
        job.bind_application(pid, app / 'release/syrius.exe')
        transport = debug.bounded.LoopbackTransport(port, 32768)
        ping = transport.exchange(dict(cmd='ping'), token, 5)
        need(ping.status == 200)
        response = readonly_reply(json.loads(ping.body), pid)
        report['sdk_admission'] = response['readonlyAdmission']
        report['checks']['application_owned'] = True
        report['phase'] = 'lab_revalidation'
        lab_current()
        report['checks']['lab_revalidated'] = True
        fixture = shared.public_fixture((repo / 'tools/devnet/lab/README.md').read_text(encoding='utf-8'))
        report['phase'] = 'onboarding_and_inspection'
        report['input_attempted'] = True
        write((json.dumps(dict(chain='321', node='ws://127.0.0.1:45998',
            mnemonic=fixture, password=secrets.token_hex(16) + 'A!1')) + '\n').encode())
        report['checks']['input_released'] = True
        wait(b'CI_INSPECT_DONE')
        shared.address_selection_receipt(report['address_selection'])
        wallet_receipt(report['wallet_admission'])
        confirm = transport.exchange(dict(cmd='ping'), token, 5)
        need(confirm.status == 200)
        readonly_reply(json.loads(confirm.body), pid, wallet=True)
        report['checks']['wallet_bound'] = True
        need(all(tour_complete(report['tours'][theme]) for theme in THEMES), 'TOUR_REFUSED')
        report['checks']['tours_complete'] = True
        need(set(report['locales']) == set(THEMES))
        report['checks']['locale_verified'] = True
        for theme in THEMES:
            for page in PAGES:
                path = output / 'captures' / theme / (page + '.png')
                raw = read_original(path, debug.entry.MAX_PNG)
                debug.entry.png_bytes(base64.b64encode(raw).decode('ascii'))
                report['captures'].append(dict(theme=theme, page=page, bytes=len(raw),
                    sha256=hashlib.sha256(raw).hexdigest(), width=1280, height=780))
        capture_records(report['captures'])
        output_bytes(output)
        report['checks']['captures'] = True
        report['home_catalog'] = collect_home_catalog(
            repo, catalog_receipt, source, tree, parent)
        report['viewport'] = viewport.collect(repo, viewport_receipt, source, tree, parent,
            read_original=read_original)
        lab_current()
        report['phase'] = 'ordinary_close'
        close_attempted = True
        closed = transport.exchange(dict(cmd='quit'), token, 5)
        need(closed.status == 200, 'CLOSE_UNCONFIRMED')
        value = json.loads(closed.body)
        need(set(value) == {'ok', 'pid', 'booted', 'harnessMode', 'readOnly',
             'readonlyAdmission', 'readonlyWallet'}, 'CLOSE_UNCONFIRMED')
        readonly_reply(value, pid, wallet=True)
        report['checks']['close_ack'] = True
        report['application_exit'] = job.application_exit()
        need(report['application_exit'] == 0, 'CLOSE_UNCONFIRMED')
        report['checks']['application_exit'] = True
        write(b'FINISH\n')
        need(original.wait(timeout=15) == 0, 'ENTRY_FAILED')
        report['checks']['entry_exit'] = True
        need(lines.finish(), 'OUTPUT_REFUSED')
        report['checks']['output_complete'] = True
        debug.bounded.verify_source(repo, source, parent)
        need(debug.entry.source_tree(repo, parent) == tree, 'SOURCE_REFUSED')
        report['checks']['source_unchanged'] = True
        report['auxiliary_cleanup'] = job.finish_known_helpers(
            dart, lambda: debug.compiler_telemetry_image(repo))
        report['forced_cleanup'] = report['auxiliary_cleanup']['forced']
        need(debug.helper_cleanup_complete(report['auxiliary_cleanup']), 'HELPER_CLOSE_UNCONFIRMED')
        report['checks']['auxiliary_cleanup'] = True
        report['phase'] = 'complete'
    except (Exception, KeyboardInterrupt) as error:
        report['errors'].append(inspection_failure_code(error, report['phase']))
    finally:
        if job is not None:
            if job.application is not None and not close_attempted:
                close_attempted = True
                try:
                    reply = transport.exchange(dict(cmd='quit'), token, 5)
                    need(reply.status == 200, 'CLOSE_UNCONFIRMED')
                    readonly_reply(json.loads(reply.body), pid,
                        wallet=report['wallet_admission'] is not None)
                    report['cleanup_application_exit'] = job.application_exit()
                except Exception:
                    report['errors'].append('CLOSE_UNCONFIRMED')
            try:
                report['owned_job_images_before_close'] = job.remaining_images()
            except Exception:
                report['errors'].append('CLOSE_UNCONFIRMED')
            try:
                job.close()
            except Exception:
                report['errors'].append('CLOSE_UNCONFIRMED')
            report['owned_job_active_at_close'] = job.active_at_close
            report['forced_cleanup'] |= job.forced
            report['required_actor_forced_cleanup'] |= job.forced
        if original is not None:
            if original.poll() is None:
                report['required_actor_forced_cleanup'] = report['forced_cleanup'] = True
                original.kill()
            try:
                report['entry_exit'] = original.wait(timeout=10)
            except Exception:
                report['entry_exit'] = None
                report['errors'].append('CLOSE_UNCONFIRMED')
            try:
                original.stdin.close()
            except OSError:
                report['errors'].append('CLOSE_UNCONFIRMED')
        if lines is not None:
            lines.finish()
            report['entry_output'] = lines.public()
        report['success'] = report['inspection_qualified'] = completed(report)
        try:
            public_manifest(report)
        except Exception:
            report['success'] = report['inspection_qualified'] = False
            report['errors'].append('OUTPUT_REFUSED')
            if output is not None:
                with (output / 'manifest.private.json').open('x', encoding='ascii') as stream:
                    json.dump(report, stream, sort_keys=True, separators=(',', ':'))
            print(json.dumps(dict(schema=1, scope='readonly_native_output_refusal', code='OUTPUT_REFUSED')))
            return report
        if output is not None:
            text = json.dumps(report, sort_keys=True, separators=(',', ':')) + '\n'
            need(len(text.encode('ascii')) <= MAX_MANIFEST, 'OUTPUT_REFUSED')
            with (output / 'manifest.json').open('x', encoding='ascii') as stream:
                stream.write(text)
        summary = {key: value for key, value in report.items()
                   if key not in ('captures', 'tours', 'locales', 'stalls', 'home_catalog', 'viewport')}
        summary.update(viewport_captured=4 if report['viewport'] is not None else 0,
            catalog_captured=2 if report['home_catalog'] is not None else 0,
            home_catalog_manifest_sha256=(report['home_catalog']['manifest_sha256']
                if report['home_catalog'] is not None else None),
            captured_pages=len(report['captures']),
            visited_pages=sum(len(t['tour']['visited']) for t in report['tours'].values()))
        public = json.dumps(summary, sort_keys=True, separators=(',', ':'))
        print(public)
        if len(public.encode()) <= 3800:
            print('::notice title=Windows readonly inspection outcome::' + public)
    return report


def artifact_paths(parent):
    """Select only verified manifest references, never a recursive profile tree."""
    parent, source = debug.entry.require_ci(parent, None, platform=os.name)
    repo = Path(parent['GITHUB_WORKSPACE'])
    debug.bounded.verify_source(repo, source, parent)
    path = repo / OUTPUT / 'manifest.json'
    value = json.loads(read_original(path, MAX_MANIFEST))
    public_manifest(value)
    need(value.get('scope') == 'owned_chain321_wallet_inspection'
         and value.get('source_sha') == source
         and value.get('source_tree') == debug.entry.source_tree(repo, parent)
         and value.get('run_id') == parent['GITHUB_RUN_ID']
         and value.get('run_attempt') == parent['GITHUB_RUN_ATTEMPT'], 'SOURCE_REFUSED')
    paths = [str(OUTPUT / 'manifest.json').replace('\\', '/')]
    if value.get('success') is True:
        need(completed(value), 'CAPTURE_REFUSED')
        output_bytes(repo / OUTPUT)
        for row in capture_records(value['captures']):
            relative = OUTPUT / 'captures' / row['theme'] / (row['page'] + '.png')
            capture = repo / relative
            raw = read_original(capture, debug.entry.MAX_PNG)
            need(len(raw) == row['bytes']
                 and hashlib.sha256(raw).hexdigest() == row['sha256'], 'CAPTURE_REFUSED')
            debug.entry.png_bytes(base64.b64encode(raw).decode('ascii'))
            paths.append(str(relative).replace('\\', '/'))
    home_paths = home_artifact_paths(repo, value)
    viewport_paths = viewport.artifact_paths(repo, value, parent_completed=completed,
        read_original=read_original)
    output = Path(parent['GITHUB_OUTPUT'])
    debug.bounded.plain(output)
    with output.open('a', encoding='utf-8') as stream:
        stream.write('paths<<INSPECTION_PATHS_V1\n' + '\n'.join(paths) + '\nINSPECTION_PATHS_V1\n')
        stream.write('catalog_paths<<HOME_CATALOG_PATHS_V1\n'
            + '\n'.join(home_paths) + '\nHOME_CATALOG_PATHS_V1\n')
        stream.write('viewport_paths<<VIEWPORT_PATHS_V1\n'
            + '\n'.join(viewport_paths) + '\nVIEWPORT_PATHS_V1\n')
    return paths


if __name__ == '__main__':
    if sys.argv[1:] != ['--artifact-paths']:
        raise SystemExit(1)
    try:
        artifact_paths(os.environ)
    except Exception:
        print('WALLET_INSPECTION_ARTIFACT_REFUSED')
        raise SystemExit(1) from None
