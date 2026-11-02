"""Synthetic pipeline checks. No browser, download or reference rewrite.

Run with unittest discovery from this directory. A coordinator can place all
temporary fixtures in managed scratch by setting TMPDIR before Python starts.
"""
import base64
from contextlib import redirect_stderr, redirect_stdout
import importlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

from PIL import Image


def import_scripts():
    # Even the first import must refuse generation, before any fixture exists.
    with mock.patch('builtins.open', side_effect=AssertionError('import opened an asset')), \
            mock.patch('pathlib.Path.open', side_effect=AssertionError('import opened an asset')), \
            mock.patch('pathlib.Path.mkdir', side_effect=AssertionError('import created output')), \
            mock.patch('os.makedirs', side_effect=AssertionError('import created output')), \
            mock.patch('subprocess.run', side_effect=AssertionError('import launched a browser')):
        prefix = __package__ + '.' if __package__ else ''
        return importlib.import_module(prefix + 'art'), importlib.import_module(prefix + 'build')


art, build = import_scripts()


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='mockup-pipeline-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.output = io.StringIO()
        self.redirect = redirect_stdout(self.output)
        self.redirect.__enter__()
        self.addCleanup(self.redirect.__exit__, None, None, None)
        self.source = self.root / 'wallet' / 'mockups' / 'redesign'
        (self.source / 'src').mkdir(parents=True)
        (self.source / 'vendor').mkdir()
        (self.source / 'vendor' / 'lottie.min.js').write_text('local player', encoding='utf-8')
        (self.source / 'vendor' / 'LICENSE-lottie-web.md').write_text('local license', encoding='utf-8')
        self.ids = [f'screen-{n:02d}' for n in range(1, 48)]
        self.document = '<html><head></head><body>__SG__ __JB__' + ''.join(
            f'<section class="scr" id="{sid}"></section>' for sid in self.ids) + '</body></html>'
        self.fragment = self.source / 'src' / '00.html'
        self.fragment.write_text(self.document, encoding='utf-8')
        self.home = self.source.parent / 'home' / 'index.html'
        self.home.parent.mkdir()
        self.home.write_text('url(base64,Zm9udC0x) url(base64,Zm9udC0y)', encoding='utf-8')
        self.assets = self.source.parent.parent / 'assets' / 'lottie'
        self.assets.mkdir(parents=True)
        self.animation = {'w': 2560, 'h': 1440, 'ip': 0, 'op': 56, 'fr': 30, 'assets': []}
        for name in art.NAMES:
            (self.assets / f'ic_anim_{name}.json').write_text(json.dumps(self.animation), encoding='utf-8')
        self.source.joinpath('index.html').write_text('original HTML', encoding='utf-8')
        self.source.joinpath('art').mkdir()
        self.source.joinpath('art', 'splash.js').write_text('original art', encoding='utf-8')
        self.source.joinpath('shots').mkdir()
        self.source.joinpath('shots', '01-original-dark.png').write_bytes(b'original reference')

    @staticmethod
    def png(size=(1280, 780)):
        stream = io.BytesIO()
        Image.new('RGB', size, 'green').save(stream, 'PNG')
        return stream.getvalue()

    def test_imports_have_no_generation_or_browser_side_effects(self):
        with mock.patch('builtins.open', side_effect=AssertionError('asset read')), \
                mock.patch('pathlib.Path.open', side_effect=AssertionError('asset read')), \
                mock.patch('pathlib.Path.mkdir', side_effect=AssertionError('output write')), \
                mock.patch('os.makedirs', side_effect=AssertionError('output write')), \
                mock.patch('subprocess.run', side_effect=AssertionError('browser launch')):
            importlib.reload(art)
            importlib.reload(build)

    def test_fresh_output_refuses_existing_missing_parent_and_linked_ancestors(self):
        existing = self.root / 'existing'
        existing.mkdir()
        marker = existing / 'keep.txt'
        marker.write_text('retained', encoding='utf-8')
        with self.assertRaises(FileExistsError):
            art.fresh_output_root(existing)
        self.assertEqual(marker.read_text(encoding='utf-8'), 'retained')
        with self.assertRaises(FileNotFoundError):
            art.fresh_output_root(self.root / 'missing' / 'child')
        self.assertFalse((self.root / 'missing').exists())
        alias = self.root / 'alias'
        try:
            alias.symlink_to(existing, target_is_directory=True)
        except OSError as error:
            self.skipTest(f'fixture symlinks unavailable: {error}')
        with self.assertRaisesRegex(ValueError, 'symbolic-link'):
            art.fresh_output_root(alias / 'new')
        self.assertFalse((existing / 'new').exists())

    def test_standalone_build_regenerates_complete_local_tree_without_source_writes(self):
        before = {p.relative_to(self.source): p.read_bytes() for p in self.source.rglob('*') if p.is_file()}
        root, ids = build.build_mockups(self.root / 'fresh output', source=self.source)
        self.assertEqual(ids, self.ids)
        self.assertEqual((root / 'index.src.html').read_text(encoding='utf-8'), self.document)
        page = (root / 'index.html').read_text(encoding='utf-8')
        self.assertIn('Zm9udC0x Zm9udC0y', page)
        self.assertNotIn('__SG__', page)
        self.assertNotIn('__JB__', page)
        self.assertIn('Content-Security-Policy', page)
        self.assertIn("font-src data:", page)
        self.assertIn("connect-src 'none'", page)
        self.assertNotIn('https:', build.CSP)
        self.assertNotIn('http:', build.CSP)
        self.assertEqual({p.stem for p in (root / 'art').glob('*.js')}, set(art.NAMES))
        self.assertEqual((root / 'vendor' / 'lottie.min.js').read_bytes(), b'local player')
        self.assertEqual((root / 'vendor' / 'LICENSE-lottie-web.md').read_bytes(), b'local license')
        after = {p.relative_to(self.source): p.read_bytes() for p in self.source.rglob('*') if p.is_file()}
        self.assertEqual(after, before)
        with self.assertRaises(FileExistsError):
            build.build_mockups(root, source=self.source)
        self.assertEqual((root / 'vendor' / 'lottie.min.js').read_bytes(), b'local player')

    def test_invalid_fonts_and_screen_ids_do_not_claim_output(self):
        original_home = self.home.read_text(encoding='utf-8')
        cases = (
            ('no fonts', self.document, 'no embedded fonts'),
            ('duplicate id', self.document.replace('screen-02', 'screen-01'), original_home),
            ('unsafe id', self.document.replace('screen-01', '../escape'), original_home),
        )
        for name, document, home in cases:
            with self.subTest(name=name):
                self.fragment.write_text(document, encoding='utf-8')
                self.home.write_text(home, encoding='utf-8')
                target = self.root / 'unclaimed'
                with self.assertRaises(ValueError):
                    build.build_mockups(target, source=self.source)
                self.assertFalse(target.exists())

    def test_art_cli_uses_its_own_fresh_root_and_preserves_composition(self):
        image_data = 'data:image/png;base64,' + base64.b64encode(self.png((8, 8))).decode()
        animation = {**self.animation, 'assets': [{'id': 'frame', 'p': image_data, 'u': ''}]}
        for name in ('splash', 'welcome'):
            (self.assets / f'ic_anim_{name}.json').write_text(json.dumps(animation), encoding='utf-8')
        target = self.root / 'fresh-art'
        with mock.patch.object(art, 'HERE', self.source):
            self.assertEqual(art.main(['--output', str(target)]), 0)
        encoded = (target / 'art' / 'splash.js').read_text(encoding='utf-8').split('=', 2)[2].rstrip(';\n')
        result = json.loads(encoded)
        self.assertEqual((result['w'], result['h'], result['ip'], result['op'], result['fr']),
                         (2560, 1440, 0, 56, 30))
        self.assertTrue(result['assets'][0]['p'].startswith('data:image/jpeg;base64,'))
        pixels = base64.b64decode(result['assets'][0]['p'].split(',', 1)[1])
        with Image.open(io.BytesIO(pixels)) as image:
            self.assertEqual(image.size, (1280, 720))
        self.assertIn(image_data, (target / 'art' / 'welcome.js').read_text(encoding='utf-8'))
        self.assertEqual((self.source / 'art' / 'splash.js').read_text(encoding='utf-8'), 'original art')

    def test_original_no_option_commands_keep_in_place_workflows(self):
        with mock.patch.object(art, 'HERE', self.source):
            self.assertEqual(art.main([]), 0)
        self.assertIn('LOTTIE_DATA', (self.source / 'art' / 'splash.js').read_text(encoding='utf-8'))
        with mock.patch.object(build, 'HERE', self.source), mock.patch.object(build, 'find_browser') as browser:
            self.assertEqual(build.main([]), 0)
            browser.assert_not_called()
        self.assertIn('Content-Security-Policy', (self.source / 'index.html').read_text(encoding='utf-8'))

    def test_explicit_and_environment_browser_choices_never_fall_back(self):
        executable = self.root / 'Browser Executable'
        executable.write_text('not executed', encoding='utf-8')
        executable.chmod(0o700)
        env = {'CHROME_BIN': str(self.root / 'missing'), 'PATH': str(self.root)}
        self.assertEqual(build.find_browser(str(executable), env), str(executable.resolve()))
        self.assertEqual(build.find_browser(environ={'CHROME_BIN': str(executable)}), str(executable.resolve()))
        for explicit, environment in ((str(self.root / 'missing'), {}), (None, env), (None, {'CHROME_BIN': ''})):
            with self.subTest(explicit=explicit, environment=environment):
                with mock.patch.object(build, '_usable_browser', return_value=None) as probe:
                    with self.assertRaisesRegex(FileNotFoundError, 'override'):
                        build.find_browser(explicit, environment)
                    self.assertLessEqual(probe.call_count, 1)

    def test_platform_discovery_and_missing_browser_diagnostics(self):
        for platform, suffix in (('win32', 'Microsoft/Edge/Application/msedge.exe'),
                                 ('darwin', 'Google Chrome.app/Contents/MacOS/Google Chrome'),
                                 ('linux', 'chromium')):
            with self.subTest(platform=platform):
                def usable(candidate, environ):
                    return 'selected-browser' if str(candidate).replace('\\', '/').endswith(suffix) else None
                with mock.patch.object(build, '_usable_browser', side_effect=usable):
                    self.assertEqual(build.find_browser(environ={}, platform=platform), 'selected-browser')
        with mock.patch.object(build, '_usable_browser', return_value=None):
            with self.assertRaisesRegex(FileNotFoundError, '--chrome or CHROME_BIN'):
                build.find_browser(environ={}, platform='linux')

    def test_invalid_browser_fails_before_claiming_output(self):
        target = self.root / 'not-created'
        with mock.patch.object(build, 'find_browser', side_effect=FileNotFoundError('invalid override')), \
                mock.patch.object(build, 'build_mockups') as assemble, redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                build.main(['shots', '--chrome', 'missing', '--output', str(target)])
            self.assertEqual(error.exception.code, 1)
            assemble.assert_not_called()
        self.assertFalse(target.exists())

    def test_all_94_shots_use_local_encoded_uris_isolated_profile_and_bounded_processes(self):
        root = self.root / 'render with spaces'
        root.mkdir()
        (root / 'index.html').write_text('local document', encoding='utf-8')
        png = self.png()

        def capture(command, **kwargs):
            path = next(arg.split('=', 1)[1] for arg in command if arg.startswith('--screenshot='))
            Path(path).write_bytes(png)
            return subprocess.CompletedProcess(command, 0, b'', b'')

        with mock.patch.object(build.subprocess, 'run', side_effect=capture) as process:
            build.render_shots(root, self.ids, 'fake-browser', timeout=7)
        expected = {f'{n:02d}-{sid}-{theme}.png' for n, sid in enumerate(self.ids, 1)
                    for theme in ('dark', 'light')}
        self.assertEqual({p.name for p in (root / 'shots').glob('*.png')}, expected)
        self.assertEqual(process.call_count, 94)
        profiles = set()
        for call in process.call_args_list:
            command = call.args[0]
            self.assertEqual(call.kwargs, {'check': True, 'capture_output': True, 'timeout': 7})
            self.assertTrue(command[-1].startswith((root / 'index.html').as_uri() + '?shot='))
            self.assertIn('render%20with%20spaces', command[-1])
            self.assertIn('--disable-background-networking', command)
            self.assertIn('--proxy-bypass-list=<-loopback>', command)
            self.assertIn('--host-resolver-rules=MAP * ~NOTFOUND', command)
            profile = Path(next(arg.split('=', 1)[1] for arg in command if arg.startswith('--user-data-dir=')))
            self.assertEqual(profile.parent.parent, root)
            profiles.add(profile)
        self.assertEqual(len(profiles), 1)
        self.assertFalse(next(iter(profiles)).exists())
        self.assertEqual(list(root.glob('.chrome-render-*')), [])

    def test_incomplete_wrong_size_and_missing_png_are_refused(self):
        path = self.root / 'capture.png'
        with self.assertRaises(OSError):
            build.verify_screenshot(path)
        for data in (b'invalid', self.png()[:-1], self.png((1, 1))):
            with self.subTest(length=len(data)):
                path.write_bytes(data)
                with self.assertRaises((OSError, ValueError)):
                    build.verify_screenshot(path)
        path.write_bytes(self.png())
        build.verify_screenshot(path)

    def test_failed_browser_or_zero_exit_without_capture_preserves_old_shot_and_failure_scratch(self):
        failures = (subprocess.TimeoutExpired('fake-browser', 1),
                    subprocess.CalledProcessError(2, 'fake-browser'), None, 'truncated')
        for index, failure in enumerate(failures):
            with self.subTest(failure=failure):
                root = self.root / f'failed-{index}'
                shots = root / 'shots'
                shots.mkdir(parents=True)
                previous = shots / '01-one-dark.png'
                previous.write_bytes(b'previous reference')

                def capture(command, **kwargs):
                    if isinstance(failure, Exception):
                        raise failure
                    if failure == 'truncated':
                        path = next(arg.split('=', 1)[1] for arg in command if arg.startswith('--screenshot='))
                        Path(path).write_bytes(self.png()[:-1])
                    return subprocess.CompletedProcess(command, 0, b'', b'')

                with mock.patch.object(build.subprocess, 'run', side_effect=capture):
                    with self.assertRaises((OSError, ValueError, subprocess.SubprocessError)):
                        build.render_shots(root, ['one'], 'fake-browser', timeout=1)
                self.assertEqual(previous.read_bytes(), b'previous reference')
                scratch = list(root.glob('.chrome-render-*'))
                self.assertEqual(len(scratch), 1)
                self.assertTrue((scratch[0] / 'profile').is_dir())
                if failure == 'truncated':
                    self.assertTrue((scratch[0] / '01-one-dark.png').is_file())

    def test_unbounded_or_nonpositive_timeout_is_refused_before_output(self):
        for timeout in ('0', '-1', 'inf', 'nan'):
            with self.subTest(timeout=timeout), mock.patch.object(build, 'build_mockups') as assemble, \
                    redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    build.main(['--timeout', timeout])
                self.assertEqual(error.exception.code, 2)
                assemble.assert_not_called()


if __name__ == '__main__':
    unittest.main()
