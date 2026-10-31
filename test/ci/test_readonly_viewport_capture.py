"""Synthetic original viewport archive controls; no renderer or native process."""

import copy
import hashlib
import io
import json
import stat
import struct
import unittest
import zipfile
import zlib

from tool.ci import readonly_viewport_capture as viewport
from tool.ci import windows_wallet_inspection as inspection


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode('ascii')


def png(width, height):
    def chunk(name, body):
        return struct.pack('>I', len(body)) + name + body + struct.pack('>I', zlib.crc32(name + body))
    row = b'\0' + b'\0\0\0\xff' * width
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(row * height)) + chunk(b'IEND', b'')


def fixture():
    images = {name: png(width, height) for name, (_, _, width, height, _, _)
              in zip(viewport.FILES, viewport.CASES)}
    rows = [dict(file=name, theme=theme, width=width, height=height,
        locale=locale, direction=direction, scale=1, bytes=len(images[name]))
        for name, (_, theme, width, height, locale, direction)
        in zip(viewport.FILES, viewport.CASES)]
    captured = dict(schema=1, scope='readonly_native_viewport_observation',
        captures=rows, rendered_locale_restored=True, theme_window_and_rail_restored=True,
        locale_preference_restoration_qualified=False, atomic_frame_qualified=False, visual_matches=0)
    manifest = dict(schema=1, scope='readonly_native_viewport_capture_bundle',
        source_sha='a' * 40, source_tree='b' * 40, run_id='1', run_attempt='1',
        probe_sha256=hashlib.sha256(b'synthetic public probe').hexdigest(),
        capture=captured, captures=[dict(row, sha256=hashlib.sha256(images[row['file']]).hexdigest())
                                    for row in rows], inspection_only=True,
        parent_closure_qualified=False, atomic_frame_qualified=False, wallet_qualified=False,
        seed_admitted=False, financial_send_qualified=False,
        locale_preference_restoration_qualified=False, visual_matches=0)
    return manifest, images


def packed(manifest, images, *, extra=None):
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_STORED) as archive:
        for name, raw in [('manifest.json', encode(manifest)), *images.items()]:
            member = zipfile.ZipInfo(name)
            member.external_attr = (stat.S_IFREG | 0o600) << 16
            archive.writestr(member, raw)
        if extra is not None:
            member = zipfile.ZipInfo(extra)
            member.external_attr = (stat.S_IFLNK | 0o600) << 16
            archive.writestr(member, b'synthetic private bytes')
    return out.getvalue()


def reference(manifest):
    return dict(schema=1, scope='readonly_native_viewport_reference', captured=4,
                manifest_sha256=hashlib.sha256(encode(manifest)).hexdigest())


class ViewportCaptureTests(unittest.TestCase):
    def test_viewport_failure_steps_are_closed_and_cannot_change_original_outcome(self):
        for step in inspection.viewport.STEPS:
            for code in (None, 'inspection-reply'):
                value = dict(stage='viewport', code=code, diagnostic=dict(
                    schema=1, kind='readonly_viewport_failure', last_entered_step=step))
                self.assertIs(inspection.entry_failure(value), value)
                self.assertEqual(set(value), {'stage', 'code', 'diagnostic'})
        value = dict(stage='viewport', code=None, diagnostic=dict(
            schema=1, kind='readonly_viewport_failure', last_entered_step='minimumCapture'))
        for change in ({'schema': True}, {'kind': 'synthetic private kind'},
            {'last_entered_step': 'synthetic private path'}, {'last_entered_step': None},
            {'message': 'synthetic private exception'}, {'success': True}):
            with self.subTest(fields=list(change)), self.assertRaises(inspection.Refused):
                inspection.entry_failure(dict(value, diagnostic=dict(value['diagnostic'], **change)))
        for change in ({'stage': 'home_catalog'}, {'code': 'wallet-recipe-command-refused'},
                       {'success': True}):
            with self.subTest(fields=list(change)), self.assertRaises(inspection.Refused):
                inspection.entry_failure(dict(value, **change))

    def test_closed_metadata_preserves_original_parent_and_saved_locale_limits(self):
        value, _ = fixture()
        self.assertIs(viewport.public_manifest(value), value)
        self.assertEqual(viewport.reference(reference(value))['captured'], 4)
        for change in ({'private': 'synthetic private'}, {'parent_closure_qualified': True},
            {'atomic_frame_qualified': True}, {'locale_preference_restoration_qualified': True},
            {'visual_matches': True}, {'run_attempt': '2'}, {'source_sha': 'foreign'}):
            with self.subTest(fields=list(change)), self.assertRaises(viewport.Refused):
                viewport.public_manifest({**value, **change})
        for fault in ('order', 'dimensions', 'language', 'bytes', 'digest', 'private'):
            changed = copy.deepcopy(value)
            if fault == 'order':changed['captures'].reverse()
            elif fault == 'dimensions':changed['captures'][0]['width'] = 1280
            elif fault == 'language':changed['capture']['captures'][2]['direction'] = 'ltr'
            elif fault == 'bytes':changed['captures'][0]['bytes'] = True
            elif fault == 'digest':changed['captures'][0]['sha256'] = 'private'
            else:changed['capture']['private'] = 'synthetic private'
            with self.subTest(fault=fault), self.assertRaises(viewport.Refused):
                viewport.public_manifest(changed)
        self.assertEqual(viewport.artifact_paths(None, {'success': False},
            parent_completed=lambda _: self.fail('Parent must remain failed'),
            read_original=lambda *_: self.fail('No failed archive image read')), [])

    def test_exact_archive_binds_all_four_original_pixels_and_allowed_dimensions(self):
        value, images = fixture()
        def inspect(manifest, pixels, **options):
            raw = packed(manifest, pixels, **options)
            return viewport.unpack(raw, hashlib.sha256(raw).hexdigest(), len(raw),
                'a' * 40, 'b' * 40, 1, reference(manifest), value['probe_sha256'])
        observed = inspect(value, images)
        self.assertEqual(observed['verified_png_count'], 4)
        self.assertEqual(observed['filenames'], list(viewport.FILES))
        for key in ('parent_closure_qualified', 'viewport_observation_qualified',
            'locale_preference_restoration_qualified', 'atomic_frame_qualified',
            'runtime_started', 'wallet_qualified', 'seed_admitted', 'financial_send_qualified'):
            self.assertIs(observed[key], False)
        for fault in ('missing', 'digest', 'header', 'run', 'foreign_member'):
            manifest = copy.deepcopy(value);pixels = dict(images)
            if fault == 'missing':pixels.pop(viewport.FILES[0])
            elif fault == 'digest':pixels[viewport.FILES[0]] += b'changed'
            elif fault == 'header':
                image = png(1280, 780);pixels[viewport.FILES[0]] = image
                manifest['captures'][0].update(bytes=len(image), sha256=hashlib.sha256(image).hexdigest())
                manifest['capture']['captures'][0]['bytes'] = len(image)
            elif fault == 'run':manifest['run_id'] = '2'
            with self.subTest(fault=fault), self.assertRaises((viewport.Refused,
                    viewport.debug.entry.Failure)):
                inspect(manifest, pixels, **({'extra': 'profile.json'} if fault == 'foreign_member' else {}))
        raw = packed(value, images)
        for sha, size in (('e' * 64, len(raw)), (hashlib.sha256(raw).hexdigest(), True)):
            with self.assertRaises(viewport.Refused):
                viewport.unpack(raw, sha, size, 'a' * 40, 'b' * 40, 1,
                                reference(value), value['probe_sha256'])


if __name__ == '__main__':
    unittest.main()
