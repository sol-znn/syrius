"""Closed original viewport observations; capture and parent closure stay separate."""

import base64
import hashlib
import io
import json
from pathlib import Path
import re
import stat
import zipfile

from . import windows_debug_loop as debug


OUTPUT = Path('.harness/ci-viewport-observations')
PROBE = Path('harness/bin/readonly_viewport_probe.dart')
CASES = tuple((name, theme, width, height, locale, direction)
    for name, width, height, locale, direction in (
        ('minimum', 1200, 600, 'en', 'ltr'), ('arabic', 1280, 780, 'ar', 'rtl'))
    for theme in ('dark', 'light'))
FILES = tuple('v04-home-' + name + '-' + theme + '.png'
              for name, theme, *_ in CASES)
MAX_CAPTURE_TOTAL = 4 * 1024**2
MAX_MANIFEST = 64 * 1024
MAX_ARCHIVE = MAX_CAPTURE_TOTAL + MAX_MANIFEST + 16384


STEPS = (
    'admission',
    'destination',
    'initialHome',
    'railState',
    'themeState',
    'windowState',
    'prepareRail',
    'minimumHome',
    'minimumResize',
    'minimumTheme',
    'minimumReady',
    'minimumCapture',
    'minimumPixels',
    'minimumWrite',
    'arabicPage',
    'arabicDisplay',
    'arabicMenu',
    'arabicOpen',
    'arabicOptionReady',
    'arabicChoice',
    'arabicLocale',
    'arabicHome',
    'arabicLayout',
    'arabicResize',
    'arabicTheme',
    'arabicReady',
    'arabicCapture',
    'arabicPixels',
    'arabicWrite',
    'englishPage',
    'englishDisplay',
    'englishMenu',
    'englishOpen',
    'englishOptionReady',
    'englishChoice',
    'englishLocale',
    'englishHome',
    'restoreTheme',
    'restoreWindow',
    'restoreRail',
    'finalHome',
    'complete',
)


class Refused(Exception):
    code = 'CAPTURE_REFUSED'


def need(value):
    if not value:
        raise Refused()


def failure_diagnostic(value):
    need(type(value) is dict and set(value) == {'schema', 'kind', 'last_entered_step'}
         and type(value['schema']) is int and value['schema'] == 1
         and value['kind'] == 'readonly_viewport_failure'
         and type(value['last_entered_step']) is str
         and value['last_entered_step'] in STEPS)
    return value


def digest(value, size=64):
    return type(value) is str and re.fullmatch('[a-f0-9]{' + str(size) + '}', value)


def records(value, *, digests):
    need(type(value) is list and len(value) == 4)
    for row, case, filename in zip(value, CASES, FILES):
        _, theme, width, height, locale, direction = case
        expected = dict(file=filename, theme=theme, width=width, height=height,
                        locale=locale, direction=direction, scale=1)
        keys = set(expected) | {'bytes'} | ({'sha256'} if digests else set())
        need(type(row) is dict and set(row) == keys
             and all(type(row[k]) is type(v) and row[k] == v for k, v in expected.items())
             and type(row['bytes']) is int and 0 < row['bytes'] <= MAX_CAPTURE_TOTAL
             and (not digests or digest(row['sha256'])))
    need(sum(row['bytes'] for row in value) <= MAX_CAPTURE_TOTAL)
    return value


def receipt(value):
    expected = dict(schema=1, scope='readonly_native_viewport_observation',
        rendered_locale_restored=True, theme_window_and_rail_restored=True,
        locale_preference_restoration_qualified=False,
        atomic_frame_qualified=False, visual_matches=0)
    need(type(value) is dict and set(value) == set(expected) | {'captures'}
         and all(type(value[k]) is type(v) and value[k] == v for k, v in expected.items()))
    records(value['captures'], digests=False)
    return value


def reference(value):
    expected = dict(schema=1, scope='readonly_native_viewport_reference', captured=4)
    need(type(value) is dict and set(value) == set(expected) | {'manifest_sha256'}
         and all(type(value[k]) is type(v) and value[k] == v for k, v in expected.items())
         and digest(value['manifest_sha256']))
    return value


def public_manifest(value):
    expected = dict(schema=1, scope='readonly_native_viewport_capture_bundle',
        inspection_only=True, parent_closure_qualified=False,
        atomic_frame_qualified=False, wallet_qualified=False,
        seed_admitted=False, financial_send_qualified=False,
        locale_preference_restoration_qualified=False, visual_matches=0)
    need(type(value) is dict and set(value) == set(expected) | {
        'source_sha', 'source_tree', 'run_id', 'run_attempt', 'probe_sha256',
        'capture', 'captures'} and all(type(value[k]) is type(v) and value[k] == v
                                      for k, v in expected.items())
         and digest(value['source_sha'], 40) and digest(value['source_tree'], 40)
         and digest(value['probe_sha256']) and type(value['run_id']) is str
         and re.fullmatch('[1-9][0-9]{0,19}', value['run_id'])
         and type(value['run_attempt']) is str and value['run_attempt'] == '1')
    receipt(value['capture'])
    records(value['captures'], digests=True)
    need(value['capture']['captures'] == [
        {k: v for k, v in row.items() if k != 'sha256'} for row in value['captures']])
    return value


def output_bytes(output):
    if not output.exists() and not output.is_symlink():
        return 0
    need(stat.S_ISDIR(debug.bounded.plain(output).st_mode))
    total = count = 0
    for path in output.iterdir():
        count += 1
        need(count <= 5 and path.name in {'manifest.json', *FILES})
        info = debug.bounded.plain(path)
        cap = MAX_MANIFEST if path.name == 'manifest.json' else MAX_CAPTURE_TOTAL
        need(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and 0 <= info.st_size <= cap)
        total += info.st_size
    need(total <= MAX_CAPTURE_TOTAL + MAX_MANIFEST)
    return total


def collect(repo, captured, source, tree, parent, *, read_original):
    receipt(captured)
    output = repo / OUTPUT
    output_bytes(output)
    observed = []
    for row in captured['captures']:
        pixels = read_original(output / row['file'], MAX_CAPTURE_TOTAL)
        need(len(pixels) == row['bytes'])
        debug.entry.png_bytes(base64.b64encode(pixels).decode('ascii'),
                              dimensions=(row['width'], row['height']))
        observed.append(dict(row, sha256=hashlib.sha256(pixels).hexdigest()))
    probe = read_original(repo / PROBE, 65536)
    value = dict(schema=1, scope='readonly_native_viewport_capture_bundle',
        source_sha=source, source_tree=tree, run_id=parent['GITHUB_RUN_ID'],
        run_attempt=parent['GITHUB_RUN_ATTEMPT'], probe_sha256=hashlib.sha256(probe).hexdigest(),
        capture=captured, captures=observed, inspection_only=True,
        parent_closure_qualified=False, atomic_frame_qualified=False,
        wallet_qualified=False, seed_admitted=False, financial_send_qualified=False,
        locale_preference_restoration_qualified=False, visual_matches=0)
    public_manifest(value)
    raw = (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode('ascii')
    need(len(raw) <= MAX_MANIFEST)
    with (output / 'manifest.json').open('xb') as stream:
        stream.write(raw)
    output_bytes(output)
    return reference(dict(schema=1, scope='readonly_native_viewport_reference', captured=4,
                          manifest_sha256=hashlib.sha256(raw).hexdigest()))


def decode(raw):
    def unique(pairs):
        value = {}
        for key, item in pairs:
            need(key not in value)
            value[key] = item
        return value
    return json.loads(raw, object_pairs_hook=unique)


def artifact_paths(repo, report, *, parent_completed, read_original):
    if report.get('success') is not True:
        return []
    need(parent_completed(report))
    selected = reference(report['viewport'])
    output = repo / OUTPUT
    output_bytes(output)
    raw = read_original(output / 'manifest.json', MAX_MANIFEST)
    need(hashlib.sha256(raw).hexdigest() == selected['manifest_sha256'])
    value = public_manifest(decode(raw))
    need(all(value[k] == report[k] for k in ('source_sha', 'source_tree', 'run_id', 'run_attempt'))
         and value['probe_sha256'] == hashlib.sha256(read_original(repo / PROBE, 65536)).hexdigest())
    paths = [str(OUTPUT / 'manifest.json').replace('\\', '/')]
    for row in value['captures']:
        pixels = read_original(output / row['file'], MAX_CAPTURE_TOTAL)
        need(len(pixels) == row['bytes'] and hashlib.sha256(pixels).hexdigest() == row['sha256'])
        debug.entry.png_bytes(base64.b64encode(pixels).decode('ascii'),
                              dimensions=(row['width'], row['height']))
        paths.append(str(OUTPUT / row['file']).replace('\\', '/'))
    return paths


def unpack(raw, expected_sha, expected_size, head, tree, run_id, selected, probe_sha):
    """Only the independent caller can qualify the original required parent exits."""
    reference(selected)
    need(type(raw) is bytes and type(expected_size) is int
         and 0 < len(raw) == expected_size <= MAX_ARCHIVE and digest(expected_sha)
         and hashlib.sha256(raw).hexdigest() == expected_sha and digest(probe_sha))
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        members = archive.infolist()
        names = [member.filename for member in members]
        need(len(members) == len(set(names)) == 5 and set(names) == {'manifest.json', *FILES})
        total = 0
        for member in members:
            cap = MAX_MANIFEST if member.filename == 'manifest.json' else MAX_CAPTURE_TOTAL
            need(member.orig_filename == member.filename and not member.is_dir()
                 and not member.flag_bits & 1
                 and stat.S_IFMT(member.external_attr >> 16) in (0, stat.S_IFREG)
                 and 0 < member.file_size <= cap)
            total += member.file_size
        need(total <= MAX_CAPTURE_TOTAL + MAX_MANIFEST)
        def read(name, cap):
            with archive.open(name) as stream:
                value = stream.read(cap + 1)
                need(not stream.read(1))
            need(0 < len(value) == archive.getinfo(name).file_size <= cap)
            return value
        manifest = read('manifest.json', MAX_MANIFEST)
        need(hashlib.sha256(manifest).hexdigest() == selected['manifest_sha256'])
        value = public_manifest(decode(manifest))
        need(value['source_sha'] == head and value['source_tree'] == tree
             and value['run_id'] == str(run_id) and value['run_attempt'] == '1'
             and value['probe_sha256'] == probe_sha)
        for row in value['captures']:
            pixels = read(row['file'], MAX_CAPTURE_TOTAL)
            need(len(pixels) == row['bytes'] and hashlib.sha256(pixels).hexdigest() == row['sha256'])
            debug.entry.png_bytes(base64.b64encode(pixels).decode('ascii'),
                                  dimensions=(row['width'], row['height']))
    return dict(schema=1, scope='retained_readonly_viewport_observation',
        source_head=head, source_tree=tree, source_run_id=run_id, source_attempt=1,
        filenames=list(FILES), cases=[dict(file=row['file'], theme=row['theme'],
            width=row['width'], height=row['height'], locale=row['locale'],
            direction=row['direction'], scale=row['scale']) for row in value['captures']],
        verified_png_count=4, archive_sha256=hashlib.sha256(raw).hexdigest(),
        manifest_sha256=hashlib.sha256(manifest).hexdigest(), probe_sha256=probe_sha,
        rendered_locale_restored=True, theme_window_and_rail_restored=True,
        viewport_observation_qualified=False, parent_closure_qualified=False,
        locale_preference_restoration_qualified=False, atomic_frame_qualified=False,
        inspection_only=True, runtime_started=False, wallet_qualified=False,
        seed_admitted=False, financial_send_qualified=False, visual_matches=0)
