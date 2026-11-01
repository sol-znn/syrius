import copy
import io
import json
import stat
import struct
import unittest
import zipfile
import zlib

from tool.ci import readonly_settings_capture as settings
from tool.ci import windows_wallet_inspection as legacy


SCREENS = ('set-node', 'set-security', 'set-display', 'set-wallet',
    'set-apps', 'set-addresses', 'set-about')
FILES = (
    '30-set-node-dark.png', '30-set-node-light.png',
    '31-set-security-dark.png', '31-set-security-light.png',
    '32-set-display-dark.png', '32-set-display-light.png',
    '33-set-wallet-dark.png', '33-set-wallet-light.png',
    '34-set-apps-dark.png', '34-set-apps-light.png',
    '35-set-addresses-dark.png', '35-set-addresses-light.png',
    '36-set-about-dark.png', '36-set-about-light.png',
)
HEAD, TREE, RUN = '1' * 40, '2' * 40, 7
PINS = {name: format(i, '064x') for i, name in enumerate(SCREENS, 1)}


def receipt():
    return dict(schema=1, scope='readonly_native_settings_catalog_capture',
        screens=list(SCREENS), themes=['dark', 'light'], files=list(FILES),
        width=1280, height=780, scale=1, capture_returned=True)


def png():
    def chunk(kind, value):
        body = kind + value
        return struct.pack('>I', len(value)) + body + struct.pack('>I',
            zlib.crc32(body) & 0xffffffff)
    return (bytes((137, 80, 78, 71, 13, 10, 26, 10))
        + chunk(b'IHDR', struct.pack('>IIBBBBB', 1280, 780, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress((bytes(1 + 1280 * 3)) * 780))
        + chunk(b'IEND', b''))


def fixture():
    pixels = png()
    captures = [dict(theme=('dark', 'light')[i % 2], file=name,
        bytes=len(pixels), sha256=settings.sha(pixels), width=1280,
        height=780, scale=1) for i, name in enumerate(FILES)]
    value = dict(schema=1, scope='readonly_native_settings_catalog_capture_bundle',
        source_sha=HEAD, source_tree=TREE, run_id=str(RUN), run_attempt='1',
        script_sha256_by_screen=PINS, capture=receipt(), captures=captures,
        inspection_only=True, parent_closure_qualified=False,
        atomic_frame_qualified=False, wallet_qualified=False,
        seed_admitted=False, financial_send_qualified=False, visual_matches=0)
    return value, {name: pixels for name in FILES}


def bundle(value, images, *, link=None):
    raw = io.BytesIO()
    manifest = (json.dumps(value, sort_keys=True, separators=(',', ':'))
        + '\n').encode('ascii')
    with zipfile.ZipFile(raw, 'w', zipfile.ZIP_DEFLATED) as target:
        target.writestr('manifest.json', manifest)
        for name, pixels in images.items():
            info = zipfile.ZipInfo(name)
            info.external_attr = ((stat.S_IFLNK if name == link else stat.S_IFREG)
                | 0o600) << 16
            target.writestr(info, pixels)
    reference = dict(schema=1, scope='readonly_native_settings_catalog_reference',
        screens=list(SCREENS), captured=14, manifest_sha256=settings.sha(manifest))
    return raw.getvalue(), reference


class SettingsCatalogTests(unittest.TestCase):
    def test_closed_settings_namespace_cannot_adopt_home_or_private_fields(self):
        value = receipt()
        self.assertEqual(settings.capture_receipt(value), value)
        self.assertEqual(settings.catalog_files(1), FILES)
        self.assertEqual(settings.catalog_screens(1), SCREENS)
        with self.assertRaises(legacy.Refused):
            legacy.home_capture_receipt(value)
        mutations = [
            dict(schema=True), dict(schema=2), dict(schema='1'),
            dict(scope='readonly_native_home_catalog_capture'),
            dict(files=list(legacy.HOME_GOTO_FILES)), dict(capture_returned=1),
            dict(screens=list(reversed(SCREENS))), dict(scale=True),
            dict(width=1200), dict(unexpected='unapproved'),
        ]
        for delta in mutations:
            with self.subTest(delta=delta), self.assertRaises(settings.Refused):
                settings.capture_receipt(dict(value, **delta))
        report, _ = fixture()
        self.assertEqual(settings.public_catalog(report), report)
        for key, bad in (
            ('inspection_only', False), ('parent_closure_qualified', True),
            ('atomic_frame_qualified', True), ('wallet_qualified', True),
            ('seed_admitted', True), ('financial_send_qualified', True),
            ('visual_matches', 1), ('unexpected', 'unapproved'),
        ):
            with self.subTest(key=key), self.assertRaises(settings.Refused):
                settings.public_catalog(dict(report, **{key: bad}))

    def test_exact_archive_pins_pixels_and_namespace_are_bound_independently(self):
        report, images = fixture()
        raw, reference = bundle(report, images)
        def inspect(data, ref=reference, pins=PINS):
            return settings.unpack(data, settings.sha(data), len(data),
                HEAD, TREE, RUN, ref, pins)
        result = inspect(raw)
        self.assertEqual(result['filenames'], list(FILES))
        self.assertEqual(result['verified_png_count'], 14)
        self.assertEqual(result['scope'], 'retained_readonly_settings_catalog')
        self.assertIs(result['catalog_capture_qualified'], False)
        self.assertIs(result['parent_closure_qualified'], False)
        self.assertIs(result['runtime_started'], False)
        self.assertEqual(result['visual_matches'], 0)
        for delta in (
            dict(schema=True), dict(captured=13), dict(captured=True),
            dict(scope='readonly_native_home_catalog_reference'),
            dict(screens=list(reversed(SCREENS))),
            dict(manifest_sha256='3' * 64), dict(unexpected='unapproved'),
        ):
            with self.subTest(reference=delta), self.assertRaises(settings.Refused):
                inspect(raw, dict(reference, **delta))
        swapped = dict(PINS, **{SCREENS[0]: 'f' * 64})
        with self.assertRaises(settings.Refused):
            inspect(raw, pins=swapped)
        altered = []
        for key, value in (
            ('source_sha', '3' * 40), ('source_tree', '3' * 40),
            ('run_id', '8'), ('run_attempt', '2'),
            ('script_sha256_by_screen', swapped),
            ('unexpected', 'unapproved'),
        ):
            altered.append((dict(report, **{key: value}), images, None))
        reverse = copy.deepcopy(report)
        reverse['captures'].reverse()
        altered.append((reverse, images, None))
        aliases = dict(images)
        aliases['01-home-rest-dark.png'] = aliases.pop(FILES[0])
        altered.append((report, aliases, None))
        changed = dict(images, **{FILES[0]: images[FILES[0]] + b'extra'})
        altered.append((report, changed, None))
        altered.append((report, images, FILES[0]))
        for index, (value, payload, link) in enumerate(altered):
            data, ref = bundle(value, payload, link=link)
            with self.subTest(archive=index), self.assertRaises(settings.Refused):
                inspect(data, ref)


if __name__ == '__main__':
    unittest.main()
