"""Turn the wallet's own Lottie files into art/<name>.js for the mockup page.

The page runs from file://, where fetch() of a JSON file is refused, so each
animation is a script that sets window.LOTTIE_DATA[name]. Nothing is redrawn:
the files are assets/lottie/*.json as the wallet ships them. The launch
animation alone is changed, and only in weight: its 56 frames of 2560x1440
JPEG are halved to 1280x720 so the review page loads it in a moment; the
composition keeps its size, so it plays the same.

    python art.py                         rebuild art/ in place
    python art.py --output FRESH_ROOT     build FRESH_ROOT/art/ independently
"""
import argparse
import base64
import io
import json
import os
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent

NAMES = ['splash', 'welcome', 'map', 'pillar', 'pillar_small', 'sentinel', 'sentinel_small',
         'zts', 'zts_small', 'plasma_generation', 'eye', 'no_data']


def fresh_output_root(destination):
    """Claim one new directory without adopting an existing or linked tree."""
    root = Path(os.path.abspath(destination))
    if any(path.is_symlink() for path in (root, *root.parents)):
        raise ValueError('Output must not have a symbolic-link ancestor')
    # The parent must already exist so a missing managed mount is not recreated.
    root.mkdir()
    return root


def generate_art(destination, source=None):
    """Keep the original compositions and re-encode only the launch frames."""
    source = Path(source) if source is not None else HERE.parent.parent / 'assets' / 'lottie'
    destination = Path(destination)
    destination.mkdir(exist_ok=True)
    paths = []
    for name in NAMES:
        with (source / f'ic_anim_{name}.json').open(encoding='utf-8') as stream:
            animation = json.load(stream)
        if name == 'splash':
            for asset in animation['assets']:
                data = asset.get('p', '')
                if data.startswith('data:image'):
                    with Image.open(io.BytesIO(base64.b64decode(data.split(',', 1)[1]))) as frame:
                        image = frame.convert('RGB').resize((1280, 720), Image.Resampling.LANCZOS)
                    encoded = io.BytesIO()
                    image.save(encoded, 'JPEG', quality=78, optimize=True)
                    asset['p'] = 'data:image/jpeg;base64,' + base64.b64encode(encoded.getvalue()).decode()
        body = json.dumps(animation, separators=(',', ':'))
        path = destination / (name + '.js')
        with path.open('w', encoding='utf-8', newline='\n') as stream:
            stream.write('(window.LOTTIE_DATA=window.LOTTIE_DATA||{})["%s"]=%s;\n' % (name, body))
        paths.append(path)
        duration = (animation['op'] - animation['ip']) / animation['fr']
        print(f'{name:18s} {path.stat().st_size//1024:6d} KB  '
              f'{animation["w"]}x{animation["h"]}  {duration:.2f} s')
    return paths


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='new root for an independent art/ tree; parent must exist')
    args = parser.parse_args(argv)
    try:
        root = HERE if args.output is None else fresh_output_root(args.output)
        generate_art(root / 'art')
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f'Art generation failed: {error}\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
