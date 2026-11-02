"""Build index.html from src/*.html and render every screen to shots/.

Fonts: the two woff2 files are taken from ../home/index.html, where they were
inlined for the home mockups, so nothing is fetched. Screenshots: headless
Chrome at 1280x780, one per screen per theme, named NN-<id>-<theme>.png.

    python build.py                         build only, in place
    python build.py shots                   build and render, in place
    python build.py shots --output FRESH_ROOT --chrome CHROME_EXECUTABLE

An independent output includes regenerated art and the local vendor player.
The output's parent must exist. --chrome overrides CHROME_BIN; otherwise a
Chrome-family executable is discovered on Windows, macOS or Linux.
"""
import argparse
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlencode

from PIL import Image

if __package__:
    from .art import fresh_output_root, generate_art
else:
    from art import fresh_output_root, generate_art

HERE = Path(__file__).resolve().parent
CSP = ("default-src 'none'; script-src file: 'unsafe-inline' 'unsafe-eval'; "
       "style-src 'unsafe-inline'; img-src file: data:; font-src data:; "
       "media-src file: data:; connect-src 'none'; base-uri 'none'; form-action 'none'")
BROWSER_FLAGS = (
    '--headless=new', '--disable-gpu', '--hide-scrollbars', '--window-size=1280,780',
    '--force-device-scale-factor=1', '--virtual-time-budget=6000',
    '--no-first-run', '--no-default-browser-check', '--disable-background-networking',
    '--disable-component-update', '--disable-sync', '--disable-extensions',
    '--disable-default-apps', '--disable-breakpad', '--metrics-recording-only',
    '--password-store=basic', '--use-mock-keychain',
    # File assets bypass this proxy; CSP also blocks remote document resources.
    '--proxy-server=http://127.0.0.1:9', '--proxy-bypass-list=<-loopback>',
    '--host-resolver-rules=MAP * ~NOTFOUND',
)


def _usable_browser(candidate, environ):
    candidate = os.fspath(candidate)
    path = Path(candidate).expanduser()
    if not path.is_absolute() and path.parent == Path('.'):
        found = shutil.which(candidate, path=environ.get('PATH', os.defpath))
        if found is None:
            return None
        path = Path(found)
    if path.is_file() and os.access(path, os.X_OK):
        return str(path.resolve())
    return None


def find_browser(explicit=None, environ=None, platform=None):
    """An invalid explicit choice is a refusal, never a discovery fallback."""
    environ = os.environ if environ is None else environ
    platform = sys.platform if platform is None else platform
    override = explicit if explicit is not None else environ.get('CHROME_BIN')
    if explicit is not None or 'CHROME_BIN' in environ:
        browser = _usable_browser(override, environ) if override else None
        if browser is None:
            raise FileNotFoundError('Browser override is not executable; check --chrome or CHROME_BIN')
        return browser
    candidates = []
    if platform == 'win32':
        for base in (environ.get('ProgramFiles', r'C:\Program Files'),
                     environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)'),
                     environ.get('LOCALAPPDATA')):
            if base:
                candidates.extend((Path(base) / 'Google/Chrome/Application/chrome.exe',
                                   Path(base) / 'Microsoft/Edge/Application/msedge.exe'))
    elif platform == 'darwin':
        for base in (Path('/Applications'), Path.home() / 'Applications'):
            candidates.extend(base / app / 'Contents/MacOS' / binary for app, binary in (
                ('Google Chrome.app', 'Google Chrome'), ('Chromium.app', 'Chromium'),
                ('Microsoft Edge.app', 'Microsoft Edge')))
    candidates.extend(('google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser',
                       'microsoft-edge', 'microsoft-edge-stable', 'chrome', 'msedge',
                       'chrome-headless-shell'))
    for candidate in candidates:
        browser = _usable_browser(candidate, environ)
        if browser is not None:
            return browser
    raise FileNotFoundError('No Chrome-family executable found; set --chrome or CHROME_BIN')


def build_mockups(output=None, source=None):
    """Assemble the page before claiming a fresh standalone output, if given."""
    source = HERE if source is None else Path(source)
    fragments = sorted((source / 'src').glob('*.html'))
    if not fragments:
        raise ValueError('No mockup source fragments found')
    original = ''.join(path.read_text(encoding='utf-8') for path in fragments)
    home = (source.parent / 'home' / 'index.html').read_text(encoding='utf-8')
    fonts = re.findall(r'base64,([A-Za-z0-9+/=]+)\)', home)
    if len(fonts) < 2:
        raise ValueError('Fonts not found in ../home/index.html')
    ids = re.findall(r'<section class="scr" id="([^"]+)"', original)
    if not ids or len(ids) != len(set(ids)) or any(not re.fullmatch(r'[A-Za-z0-9_-]+', sid) for sid in ids):
        raise ValueError('Screen ids must be unique and safe as file names')
    if '<head>' not in original:
        raise ValueError('Mockup document has no head for its local-only policy')
    page = original.replace('__SG__', fonts[0]).replace('__JB__', fonts[1])
    page = page.replace('<head>', f'<head>\n<meta http-equiv="Content-Security-Policy" content="{CSP}">', 1)
    destination = source if output is None else fresh_output_root(output)
    if output is not None:
        generate_art(destination / 'art', source.parent.parent / 'assets' / 'lottie')
        shutil.copytree(source / 'vendor', destination / 'vendor')
    for name, text in (('index.src.html', original), ('index.html', page)):
        with (destination / name).open('w', encoding='utf-8', newline='\n') as stream:
            stream.write(text)
    print(f'index.html: {len(page)//1024} KB, {len(ids)} screens')
    return destination, ids


def verify_screenshot(path):
    with Path(path).open('rb') as stream:
        stream.seek(-12, os.SEEK_END)
        if stream.read() != b'\x00\x00\x00\x00IEND\xaeB`\x82':
            raise ValueError('Screenshot PNG is incomplete')
    with Image.open(path) as image:
        if image.format != 'PNG' or image.size != (1280, 780):
            raise ValueError('Screenshot must be a complete 1280x780 PNG')
        image.verify()
    with Image.open(path) as image:
        image.load()


def render_shots(root, ids, browser, timeout=60):
    root = Path(root).resolve()
    shots = root / 'shots'
    shots.mkdir(exist_ok=True)
    url = (root / 'index.html').as_uri()
    # A fresh capture prevents a zero-exit browser from reusing an old shot.
    # Failed and interrupted captures stay with the owned output for diagnosis.
    scratch = Path(tempfile.mkdtemp(prefix='.chrome-render-', dir=root))
    complete = False
    try:
        profile = scratch / 'profile'
        profile.mkdir()
        for n, sid in enumerate(ids, 1):
            for theme in ('dark', 'light'):
                name = f'{n:02d}-{sid}-{theme}.png'
                capture = scratch / name
                query = urlencode({'shot': sid, 'theme': theme})
                subprocess.run([browser, *BROWSER_FLAGS, f'--user-data-dir={profile}',
                                f'--screenshot={capture}', f'{url}?{query}'],
                               check=True, capture_output=True, timeout=timeout)
                verify_screenshot(capture)
                capture.replace(shots / name)
                print(name)
        complete = True
    finally:
        if complete:
            shutil.rmtree(scratch)


def _positive_timeout(value):
    timeout = float(value)
    if not math.isfinite(timeout) or timeout <= 0:
        raise argparse.ArgumentTypeError('timeout must be a finite positive number')
    return timeout


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', nargs='?', choices=('shots',))
    parser.add_argument('--output', type=Path, help='fresh standalone mockup root; parent must exist')
    parser.add_argument('--chrome', help='Chrome-family executable; overrides CHROME_BIN')
    parser.add_argument('--timeout', type=_positive_timeout, default=60, help='seconds allowed per screenshot')
    args = parser.parse_args(argv)
    try:
        browser = find_browser(args.chrome) if args.command == 'shots' else None
        root, ids = build_mockups(args.output)
        if browser is not None:
            render_shots(root, ids, browser, args.timeout)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f'Mockup generation failed: {error}\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
