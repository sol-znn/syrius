"""Finite readonly Details metadata and original-byte archive controls."""

from __future__ import annotations

import base64
import hashlib
import io
import json
from pathlib import Path
import re
import stat
import zipfile

from . import windows_debug_loop as debug


THEMES = ('dark', 'light')
SCREENS = ('receive-qr', 'zap-form', 'plasma-fuse', 'set-licences', 'set-originals')
FILES = ('10-receive-qr-dark.png', '10-receive-qr-light.png', '11-zap-form-dark.png', '11-zap-form-light.png', '22-plasma-fuse-dark.png', '22-plasma-fuse-light.png', '37-set-licences-dark.png', '37-set-licences-light.png', '38-set-originals-dark.png', '38-set-originals-light.png')
OUTPUT = Path('.harness/ci-details-catalog')
MAX_CAPTURE_TOTAL = 4 * 1024**2
MAX_MANIFEST = 64 * 1024
MAX_ARCHIVE = MAX_CAPTURE_TOTAL + MAX_MANIFEST + 65536


class Refused(Exception):
    def __init__(self, code):
        self.code = code if code in ('CAPTURE_REFUSED', 'OUTPUT_REFUSED',
            'STORAGE_REFUSED', 'SOURCE_REFUSED') else 'OUTPUT_REFUSED'
        super().__init__(self.code)


def need(value, code='CAPTURE_REFUSED'):
    if not value:
        raise Refused(code)


def digest(value):
    return type(value) is str and re.fullmatch('[a-f0-9]{64}', value) is not None


def sha(value):
    return hashlib.sha256(value).hexdigest()


def decode(raw):
    def unique(pairs):
        value = {}
        for key, item in pairs:
            need(key not in value, 'OUTPUT_REFUSED')
            value[key] = item
        return value
    return json.loads(raw, object_pairs_hook=unique)


FAILURE_STEPS = ('preflight', 'outputPreflight', 'themeSnapshot', 'windowSnapshot', 'windowShow', 'railSnapshot', 'clientResize', 'homePreparation', 'themeSelection', 'scriptLine', 'shotRequest', 'shotValidation', 'outputRetention', 'afterCaptureLine', 'railRestoration', 'themeRestoration', 'windowRestoration', 'complete')


FAILURE_REPLIES = (
    'targetMissing',
    'targetDisabled',
    'targetCovered',
    'errorWidget',
    'viewAmbiguous',
    'regionRootMissing',
    'regionMissing',
    'regionDuplicate',
    'regionSearchLimit',
    'regionUnmounted',
    'regionBoundsUnavailable',
    'regionBoundsRefused',
    'regionRenderUnavailable',
    'regionPaintClipCheckRefused',
    'unknown',
)


def failure_diagnostic(value):
    required = {'schema', 'kind', 'last_entered_step'}
    optional = {'screen', 'theme', 'line'}
    need(type(value) is dict and type(value.get('schema')) is int)
    if value['schema'] == 2:
        required = required | {'reply'}
        need(type(value.get('reply')) is str
             and value['reply'] in FAILURE_REPLIES)
    else:
        need(value['schema'] == 1)
    need(required <= set(value) <= required | optional)
    need(type(value['schema']) is int and value['schema'] in (1, 2)
         and value['kind'] == 'readonly_details_capture_failure'
         and type(value['last_entered_step']) is str
         and value['last_entered_step'] in FAILURE_STEPS)
    need(('screen' in value) == ('theme' in value))
    if 'screen' in value:
        need(type(value['screen']) is str and value['screen'] in SCREENS
             and type(value['theme']) is str and value['theme'] in THEMES)
    script = value['last_entered_step'] in ('scriptLine', 'afterCaptureLine')
    need(not script or {'screen', 'theme', 'line'} <= set(value))
    if 'line' in value:
        need(script and type(value['line']) is int and 1 <= value['line'] <= 65535)
    return value


def catalog_files(schema):
    need(type(schema) is int and schema == 1)
    return FILES


def catalog_screens(schema):
    catalog_files(schema)
    return SCREENS


def _script_field(schema):
    catalog_files(schema)
    return 'script_sha256_by_screen'


def _script_pins(repo, schema, read_original):
    catalog_files(schema)
    return {name: sha(read_original(repo / 'harness/screens' / (name + '.txt'), 65536))
        for name in SCREENS}


def capture_receipt(value):
    """Admit fixed metadata only after the original capture runner returns."""
    need(type(value) is dict, 'CAPTURE_REFUSED')
    schema = value.get('schema')
    files = catalog_files(schema)
    expected = dict(schema=schema, scope='readonly_native_details_catalog_capture',
        themes=list(THEMES), files=list(files),
        width=1280, height=780, scale=1, capture_returned=True)
    expected.update(screens=list(catalog_screens(schema)))
    need(set(value) == set(expected)
         and all(type(value[k]) is type(v) and value[k] == v
                 for k, v in expected.items()), 'CAPTURE_REFUSED')
    return value


def capture_records(value, *, schema=1):
    """The fixed filenames bind each state and theme in their original order."""
    files = catalog_files(schema)
    need(type(value) is list and len(value) == len(files), 'CAPTURE_REFUSED')
    for index, (row, name) in enumerate(zip(value, files)):
        theme = THEMES[index % len(THEMES)]
        need(type(row) is dict and set(row) ==
             {'theme', 'file', 'bytes', 'sha256', 'width', 'height', 'scale'}
             and row['theme'] == theme and row['file'] == name
             and type(row['bytes']) is int and 0 < row['bytes'] <= MAX_CAPTURE_TOTAL
             and type(row['sha256']) is str and re.fullmatch('[a-f0-9]{64}', row['sha256'])
             and all(type(row[k]) is int for k in ('width', 'height', 'scale'))
             and (row['width'], row['height'], row['scale']) == (1280, 780, 1),
             'CAPTURE_REFUSED')
    need(sum(row['bytes'] for row in value) <= MAX_CAPTURE_TOTAL, 'CAPTURE_REFUSED')
    return value


def catalog_reference(value):
    need(type(value) is dict, 'CAPTURE_REFUSED')
    schema = value.get('schema')
    files = catalog_files(schema)
    expected = dict(schema=schema, scope='readonly_native_details_catalog_reference',
        captured=len(files))
    expected.update(screens=list(catalog_screens(schema)))
    need(set(value) == set(expected) | {'manifest_sha256'}
         and all(type(value[k]) is type(v) and value[k] == v
                 for k, v in expected.items())
         and type(value['manifest_sha256']) is str
         and re.fullmatch('[a-f0-9]{64}', value['manifest_sha256']), 'CAPTURE_REFUSED')
    return value


def public_catalog(value):
    """This bundle cannot qualify its later parent closure or a match."""
    need(type(value) is dict, 'OUTPUT_REFUSED')
    schema = value.get('schema')
    catalog_files(schema)
    flags = {'inspection_only', 'parent_closure_qualified', 'atomic_frame_qualified',
             'wallet_qualified', 'seed_admitted', 'financial_send_qualified'}
    required = flags | {'schema', 'scope', 'source_sha', 'source_tree', 'run_id',
        'run_attempt', _script_field(schema), 'capture', 'captures', 'visual_matches'}
    need(set(value) == required
         and value['scope'] == 'readonly_native_details_catalog_capture_bundle'
         and all(type(value[k]) is bool for k in flags)
         and value['inspection_only'] is True
         and all(value[k] is False for k in flags - {'inspection_only'})
         and type(value['visual_matches']) is int and value['visual_matches'] == 0,
         'OUTPUT_REFUSED')
    for key in ('source_sha', 'source_tree'):
        need(type(value[key]) is str and re.fullmatch('[a-f0-9]{40}', value[key]), 'OUTPUT_REFUSED')
    need(type(value['run_id']) is str and re.fullmatch('[1-9][0-9]{0,19}', value['run_id'])
         and type(value['run_attempt']) is str and value['run_attempt'] == '1', 'OUTPUT_REFUSED')
    pins = value[_script_field(schema)]
    need(type(pins) is dict and set(pins) == set(
        catalog_screens(schema))
        and all(type(pin) is str and re.fullmatch('[a-f0-9]{64}', pin)
                for pin in pins.values()), 'OUTPUT_REFUSED')
    capture_receipt(value['capture'])
    need(value['capture']['schema'] == schema, 'OUTPUT_REFUSED')
    capture_records(value['captures'], schema=schema)
    return value


def output_bytes(output, *, schema=1):
    """Account this finite family, including incomplete original writes."""
    files = catalog_files(schema)
    if not output.exists() and not output.is_symlink():
        return 0
    root = debug.bounded.plain(output)
    need(stat.S_ISDIR(root.st_mode), 'STORAGE_REFUSED')
    allowed = {'manifest.json', *files}
    total = count = 0
    for path in output.iterdir():
        count += 1
        need(count <= len(allowed) and path.name in allowed, 'STORAGE_REFUSED')
        info = debug.bounded.plain(path)
        cap = MAX_MANIFEST if path.name == 'manifest.json' else MAX_CAPTURE_TOTAL
        need(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
             and 0 <= info.st_size <= cap, 'STORAGE_REFUSED')
        total += info.st_size
    need(total <= MAX_CAPTURE_TOTAL + MAX_MANIFEST, 'STORAGE_REFUSED')
    return total


def collect(repo, receipt, source, tree, parent, *, read_original):
    """Retain original PNG references without another archive copy."""
    capture_receipt(receipt)
    schema = receipt['schema']
    output = repo / OUTPUT
    output_bytes(output, schema=schema)
    records = []
    for index, name in enumerate(catalog_files(schema)):
        raw = read_original(output / name, MAX_CAPTURE_TOTAL)
        debug.entry.png_bytes(base64.b64encode(raw).decode('ascii'))
        records.append(dict(theme=THEMES[index % len(THEMES)], file=name, bytes=len(raw),
            sha256=hashlib.sha256(raw).hexdigest(), width=1280, height=780, scale=1))
    capture_records(records, schema=schema)
    value = dict(schema=schema, scope='readonly_native_details_catalog_capture_bundle',
        source_sha=source, source_tree=tree, run_id=parent['GITHUB_RUN_ID'],
        run_attempt=parent['GITHUB_RUN_ATTEMPT'], capture=receipt, captures=records,
        inspection_only=True, parent_closure_qualified=False, atomic_frame_qualified=False,
        wallet_qualified=False, seed_admitted=False, financial_send_qualified=False,
        visual_matches=0)
    value[_script_field(schema)] = _script_pins(repo, schema, read_original)
    public_catalog(value)
    data = (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode('ascii')
    need(len(data) <= MAX_MANIFEST, 'OUTPUT_REFUSED')
    with (output / 'manifest.json').open('xb') as stream:
        stream.write(data)
    output_bytes(output, schema=schema)
    reference = dict(schema=schema, scope='readonly_native_details_catalog_reference',
        captured=len(records), manifest_sha256=hashlib.sha256(data).hexdigest())
    reference.update(screens=list(catalog_screens(schema)))
    return catalog_reference(reference)


def artifact_paths(repo, report, *, read_original, parent_completed):
    """Only a completed generic parent can export every catalog original."""
    if report.get('success') is not True:
        return []
    need(parent_completed is True, 'CAPTURE_REFUSED')
    reference = catalog_reference(report['details_catalog'])
    schema = reference['schema']
    output = repo / OUTPUT
    output_bytes(output, schema=schema)
    raw = read_original(output / 'manifest.json', MAX_MANIFEST)
    need(hashlib.sha256(raw).hexdigest() == reference['manifest_sha256'], 'CAPTURE_REFUSED')
    def unique(pairs):
        value = {}
        for key, item in pairs:
            need(key not in value, 'OUTPUT_REFUSED')
            value[key] = item
        return value

    value = public_catalog(json.loads(raw, object_pairs_hook=unique))
    need(value['schema'] == schema
         and all(value[k] == report[k] for k in
                 ('source_sha', 'source_tree', 'run_id', 'run_attempt'))
         and value[_script_field(schema)] == _script_pins(repo, schema, read_original),
         'SOURCE_REFUSED')
    paths = [str(OUTPUT / 'manifest.json').replace('\\', '/')]
    for row in capture_records(value['captures'], schema=schema):
        image = read_original(output / row['file'], MAX_CAPTURE_TOTAL)
        need(len(image) == row['bytes'] and hashlib.sha256(image).hexdigest() == row['sha256'],
             'CAPTURE_REFUSED')
        debug.entry.png_bytes(base64.b64encode(image).decode('ascii'))
        paths.append(str(OUTPUT / row['file']).replace('\\', '/'))
    return paths


def unpack(raw, expected_sha, expected_size, head, tree, run_id,
                        reference, script_sha):
    """Verify each literal state; only the caller can bind parent closure."""
    catalog_reference(reference)
    schema = reference['schema']
    files = catalog_files(schema)
    script_field = _script_field(schema)
    pins = script_sha
    need(type(pins) is dict and set(pins) == set(
        catalog_screens(schema))
        and all(digest(pin) for pin in pins.values()))
    need(type(raw) is bytes and type(expected_size) is int and digest(expected_sha)
         and 0 < len(raw) == expected_size <= MAX_ARCHIVE and sha(raw) == expected_sha)
    allowed = {'manifest.json', *files}
    with zipfile.ZipFile(io.BytesIO(raw)) as zipped:
        members = zipped.infolist()
        names = [m.filename for m in members]
        need(len(members) == len(set(names)) == len(allowed) and set(names) == allowed)
        total = 0
        for member in members:
            cap = MAX_MANIFEST if member.filename == 'manifest.json' else MAX_CAPTURE_TOTAL
            need(member.orig_filename == member.filename and not member.is_dir()
                 and not member.flag_bits & 1
                 and stat.S_IFMT(member.external_attr >> 16) in (0, stat.S_IFREG)
                 and 0 < member.file_size <= cap)
            total += member.file_size
        need(total <= MAX_CAPTURE_TOTAL + MAX_MANIFEST)

        def member(name, cap):
            with zipped.open(name) as stream:
                value = stream.read(cap + 1)
                need(not stream.read(1))
            need(0 < len(value) == zipped.getinfo(name).file_size <= cap)
            return value

        manifest = member('manifest.json', MAX_MANIFEST)
        need(sha(manifest) == reference['manifest_sha256'])
        value = public_catalog(decode(manifest))
        need(value['schema'] == schema and value['source_sha'] == head
             and value['source_tree'] == tree and value['run_id'] == str(run_id)
             and value['run_attempt'] == '1' and value[script_field] == script_sha)
        for row in capture_records(value['captures'], schema=schema):
            pixels = member(row['file'], MAX_CAPTURE_TOTAL)
            need(len(pixels) == row['bytes'] and sha(pixels) == row['sha256'])
            debug.entry.png_bytes(base64.b64encode(pixels).decode('ascii'))
    result = dict(schema=schema, scope='retained_readonly_details_catalog', source_head=head,
        source_tree=tree, source_run_id=run_id, source_attempt=1,
        themes=list(THEMES), filenames=list(files),
        width=1280, height=780, scale=1, verified_png_count=len(files),
        archive_sha256=sha(raw), manifest_sha256=sha(manifest),
        catalog_capture_qualified=False, parent_closure_qualified=False,
        atomic_frame_qualified=False, inspection_only=True, runtime_started=False,
        wallet_qualified=False, seed_admitted=False, financial_send_qualified=False,
        visual_matches=0)
    result.update(screens=list(catalog_screens(schema)))
    result[script_field] = script_sha
    return result
