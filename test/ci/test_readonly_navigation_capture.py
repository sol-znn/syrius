import copy
import io
import json
import stat
import struct
import unittest
import zipfile
import zlib

from tool.ci import readonly_navigation_capture as navigation
from tool.ci import windows_wallet_inspection as legacy
from tool.ci import readonly_settings_capture as original_settings


SCREENS = ('send-rest', 'receive', 'pillars', 'plasma', 'tokens', 'swap-list', 'az')
FILES = ('07-send-rest-dark.png', '07-send-rest-light.png', '09-receive-dark.png', '09-receive-light.png', '16-pillars-dark.png', '16-pillars-light.png', '21-plasma-dark.png', '21-plasma-light.png', '23-tokens-dark.png', '23-tokens-light.png', '26-swap-list-dark.png', '26-swap-list-light.png', '28-az-dark.png', '28-az-light.png')
HEAD, TREE, RUN = '1' * 40, '2' * 40, 7
PINS = {name: format(i, '064x') for i, name in enumerate(SCREENS, 1)}


def receipt():
    return dict(schema=1, scope='readonly_native_navigation_catalog_capture',
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
        bytes=len(pixels), sha256=navigation.sha(pixels), width=1280,
        height=780, scale=1) for i, name in enumerate(FILES)]
    value = dict(schema=1, scope='readonly_native_navigation_catalog_capture_bundle',
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
    reference = dict(schema=1, scope='readonly_native_navigation_catalog_reference',
        screens=list(SCREENS), captured=14, manifest_sha256=navigation.sha(manifest))
    return raw.getvalue(), reference


class NavigationCatalogTests(unittest.TestCase):
    def test_closed_navigation_namespace_cannot_adopt_home_or_private_fields(self):
        value = receipt()
        self.assertEqual(navigation.capture_receipt(value), value)
        self.assertEqual(navigation.catalog_files(1), FILES)
        self.assertEqual(navigation.catalog_screens(1), SCREENS)
        with self.assertRaises(legacy.Refused):
            legacy.home_capture_receipt(value)
        with self.assertRaises(original_settings.Refused):
            original_settings.capture_receipt(value)
        mutations = [
            dict(schema=True), dict(schema=2), dict(schema='1'),
            dict(scope='readonly_native_home_catalog_capture'),
            dict(scope='readonly_native_settings_catalog_capture'),
            dict(screens=list(original_settings.SCREENS)),
            dict(files=list(legacy.HOME_GOTO_FILES)), dict(capture_returned=1),
            dict(screens=list(reversed(SCREENS))), dict(scale=True),
            dict(width=1200), dict(unexpected='unapproved'),
        ]
        for delta in mutations:
            with self.subTest(delta=delta), self.assertRaises(navigation.Refused):
                navigation.capture_receipt(dict(value, **delta))
        report, _ = fixture()
        self.assertEqual(navigation.public_catalog(report), report)
        for key, bad in (
            ('inspection_only', False), ('parent_closure_qualified', True),
            ('atomic_frame_qualified', True), ('wallet_qualified', True),
            ('seed_admitted', True), ('financial_send_qualified', True),
            ('visual_matches', 1), ('unexpected', 'unapproved'),
        ):
            with self.subTest(key=key), self.assertRaises(navigation.Refused):
                navigation.public_catalog(dict(report, **{key: bad}))

    def test_failure_diagnostic_is_closed_and_cannot_disclose_commands_or_paths(self):
        base = dict(schema=1, kind='readonly_navigation_capture_failure',
            last_entered_step='preflight')
        self.assertIs(navigation.failure_diagnostic(base), base)
        valid = dict(base, last_entered_step='scriptLine',
            screen='send-rest', theme='dark', line=5)
        self.assertIs(navigation.failure_diagnostic(valid), valid)
        self.assertIs(legacy.entry_failure(dict(stage='navigation_catalog',
            code=None, diagnostic=valid))['diagnostic'], valid)
        for delta in (
            dict(schema=True), dict(kind='other'),
            dict(last_entered_step='Synthetic private step'),
            dict(screen='Synthetic private path'), dict(theme='dark'),
            dict(line=True), dict(line=1),
            dict(command='Synthetic private input'), dict(extra='unapproved'),
        ):
            with self.subTest(delta=delta), self.assertRaises(navigation.Refused):
                navigation.failure_diagnostic(dict(base, **delta))
        for delta in (
            dict(screen='home-rest'), dict(theme='ar'), dict(line=True),
            dict(line=0), dict(line=65536), dict(last_entered_step='preflight'),
            dict(extra='Synthetic private path'),
        ):
            with self.subTest(delta=delta), self.assertRaises(legacy.Refused):
                legacy.entry_failure(dict(stage='navigation_catalog', code=None,
                    diagnostic=dict(valid, **delta)))
        for missing in ('screen', 'theme', 'line'):
            broken = dict(valid)
            broken.pop(missing)
            with self.subTest(missing=missing), self.assertRaises(navigation.Refused):
                navigation.failure_diagnostic(broken)
        with self.assertRaises(legacy.Refused):
            legacy.entry_failure(dict(stage='navigation_catalog',
                code='wallet-recipe-other', diagnostic=valid))

    def test_exact_archive_pins_pixels_and_namespace_are_bound_independently(self):
        report, images = fixture()
        raw, reference = bundle(report, images)
        def inspect(data, ref=reference, pins=PINS):
            return navigation.unpack(data, navigation.sha(data), len(data),
                HEAD, TREE, RUN, ref, pins)
        result = inspect(raw)
        self.assertEqual(result['filenames'], list(FILES))
        self.assertEqual(result['verified_png_count'], 14)
        self.assertEqual(result['scope'], 'retained_readonly_navigation_catalog')
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
            with self.subTest(reference=delta), self.assertRaises(navigation.Refused):
                inspect(raw, dict(reference, **delta))
        swapped = dict(PINS, **{SCREENS[0]: 'f' * 64})
        with self.assertRaises(navigation.Refused):
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
            with self.subTest(archive=index), self.assertRaises(navigation.Refused):
                inspect(data, ref)


if __name__ == '__main__':
    unittest.main()
