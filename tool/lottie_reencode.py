#!/usr/bin/env python3
"""Rebuilds the Lottie assets the wallet ships from their masters.

    python tool/lottie_reencode.py                  # all of it
    python tool/lottie_reencode.py --only launch    # the launch files alone
    python tool/lottie_reencode.py --only lottie    # the Lottie files alone
    python tool/lottie_reencode.py --check          # report sizes, write nothing

Needs Pillow built with WebP (`pip install pillow`).

Three of the animations (the ZTS coin, the pillar, the sentinel) are not
vectors. Each is a 3D render exported as one 1000 x 1000 PNG per frame, with a
256-colour palette and one-bit transparency, and the Lottie file plays them as
a slide show. The old interface drew them 400 px wide. The new one draws the
coin at 64 px and the two nodes at 104 px, and a 1000 px frame sampled
bilinearly at a sixteenth of its size keeps one texel in sixteen: the thin
green ring breaks into dots, the engraving turns to noise, and the one-bit
edge stays a staircase. Every frame is also decoded whole, 4 MB each, so the
64 px coin cost 184 MB of pixels and the page waited for all 46 decodes.

So each master is written twice, from the same frames:

  ic_anim_<name>.json        800 px composition, for the 400 px slot at 2x
  ic_anim_<name>_small.json  for the small slot at 2x (sizes in VARIANTS)

Each frame is cropped to the box the artwork ever touches, resampled with
Lanczos on premultiplied alpha (so the transparent colour does not bleed into
the edge), and stored as WebP. The layer's anchor and scale are rewritten so
the artwork lands on the same place in the composition as before; frame
count, frame rate and in/out points are not touched.

The masters stay in tool/lottie_masters/ and are never bundled. Re-encoding
always starts from them, so a second run does not degrade anything.

The vector files are only re-serialised without whitespace. The map and the
welcome animation were pretty-printed: three quarters of their bytes were
indentation. No number in them changes.

The launch animation is not a Lottie file any more. Its master,
ic_anim_splash.json, is the same kind of slide show: 56 JPEG frames of
2560 x 1440, one per thirtieth of a second. A Lottie player decodes every
image asset before it draws the first frame and holds them until the last,
which is 56 x 2560 x 1440 x 4 bytes, 826 MB, for a two second film. So it is
written as one animated WebP at the same size:

  assets/images/launch.webp

Flutter's image codec decodes an animated image a frame at a time, on demand,
so the wallet holds two frames (the one on screen and the one being
composited), about 30 MB, and not 56. The file is a ninth of the master.

The well on the lock card replays the film 640 px wide. Flutter ignores a
target width for an image of more than one frame, so from launch.webp it
would decode 2560 px frames, sixteen times the pixels, to draw each one
down. So the same master is written a second time, every frame reduced with
Lanczos, with the same 56 frames and the same durations:

  assets/images/launch_well.webp    640 x 360, about 0.2 MB

The frames go in the order the layers play them (by in point, through
refId), not in the order of the assets array. WebP counts time in whole
milliseconds and a thirtieth of a second is 33.3, so each frame runs from its
rounded start to its rounded end: 33 and 34 ms mixed, 1867 ms in all, and the
error never adds up. The loop count is 1: it plays once and holds.

The container is written here and not by Pillow's `save_all`. That goes
through libwebp's animation encoder, which folds a frame that matches the one
before into that one's duration; the film ends on six identical frames and
came out as 50. The lock screen replays frames 14 to 56 by number, so all 56
have to be there. Changed rectangles are coded from the master's pixels,
and the still ending costs a few bytes. The full film's last independent
frame is also stored as launch_end.webp, with its original compressed
payload. Pixel equality with the final canvas is required before writing
it. Skip can then decode that same ending without decoding every unseen
intermediate frame; normal playback keeps every original frame and clock.
"""

from __future__ import annotations

import argparse
import base64
import copy
import io
import json
import math
import struct
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageStat

ROOT = Path(__file__).resolve().parent.parent
MASTERS = ROOT / "tool" / "lottie_masters"
OUT = ROOT / "assets" / "lottie"

# name -> (full composition edge, small composition edge), in pixels.
# Full is twice the 400 px success slot. Small is twice the slot the pages
# use: 64 px for the coin on Tokens, 104 px for a node on its card.
# lib/widgets/reusable_widgets/app_lottie.dart picks between the two and
# holds the same small edges.
VARIANTS = {
    "zts": (800, 128),
    "pillar": (800, 208),
    "sentinel": (800, 208),
}

# Re-serialised only.
VECTORS = ["eye", "map", "welcome", "no_data", "plasma_generation"]

# Lossy colour, lossless alpha. Method 6 is twenty times slower than 4 for a
# tenth off the size. The small frames can afford a higher quality: they are
# a few kilobytes each either way.
WEBP = {"format": "WEBP", "method": 4, "alpha_quality": 100}
# At 80 a full frame beside its lossless self shows no difference at 1:1,
# and the three full files together come out a little under the palette
# PNGs they replace (the pillar alone is larger: 256 colours packed well).
QUALITY_FULL = 80
QUALITY_SMALL = 92

# A frame reduced to a sixth comes out correct and a little flat: the 3 px
# ring on the coin is 0.4 px of green. A light unsharp mask on the small
# frames gives the ring and the letters their edge back. The full frames,
# reduced by a fifth at most, do not need it.
SHARPEN_SMALL = ImageFilter.UnsharpMask(radius=0.7, percent=60, threshold=0)

# Transparent pixels kept round the artwork, in master pixels, so the
# resampling kernel has room and the edge is not cut.
PAD = 4

LAUNCH_MASTER = MASTERS / "ic_anim_splash.json"
LAUNCH_OUT = ROOT / "assets" / "images" / "launch.webp"
LAUNCH_END_OUT = ROOT / "assets" / "images" / "launch_end.webp"

# The worst frame has to stay at 40 dB or better against its JPEG. 80 is on
# the line and 75 is under it; 84 leaves a margin for 1.13 MB. The worst
# frames are the first ten, a full-screen blue field of fine detail.
# Method 6 costs three seconds here and takes 2% off.
LAUNCH_WEBP = {"format": "WEBP", "quality": 84, "method": 6}
# The well on the lock card is 640 px wide and gets a file of its own.
LAUNCH_WELL_OUT = ROOT / "assets" / "images" / "launch_well.webp"
LAUNCH_WELL_WIDTH = 640
# Against the master reduced with Lanczos. The worst frames are again the
# first ten, and there quality buys almost nothing: 80 gives 33.0 dB and
# 0.15 MB, 93 gives 33.8 dB and 0.31 MB. The blue field's detail is a pixel
# wide at this size and VP8 stores colour at half resolution, which no
# quality setting changes. The mean is 43.5 dB. 88 is the 0.2 MB asked for.
LAUNCH_WELL_WEBP = {"format": "WEBP", "quality": 88, "method": 6}
# Plays once and holds its last frame; 0 would loop for ever.
LAUNCH_LOOPS = 1


def _frames(doc: dict) -> list[Image.Image]:
    frames = []
    for asset in doc["assets"]:
        head, data = asset["p"].split(",", 1)
        if not head.startswith("data:image/"):
            raise SystemExit(f"asset {asset['id']} is not an embedded image")
        frames.append(Image.open(io.BytesIO(base64.b64decode(data))).convert("RGBA"))
    return frames


def _union_box(frames: list[Image.Image]) -> tuple[int, int, int, int]:
    """The box every frame's artwork fits in, padded and kept inside the frame."""
    width, height = frames[0].size
    left, top, right, bottom = width, height, 0, 0
    for frame in frames:
        box = frame.getchannel("A").getbbox()
        if box is None:
            continue
        left, top = min(left, box[0]), min(top, box[1])
        right, bottom = max(right, box[2]), max(bottom, box[3])
    return (
        max(0, left - PAD),
        max(0, top - PAD),
        min(width, right + PAD),
        min(height, bottom + PAD),
    )


def _static(prop: dict) -> list[float]:
    if prop.get("a", 0) != 0:
        raise SystemExit("animated layer transform: this script assumes a slide show")
    return prop["k"]


def _variant(
    master: dict,
    frames: list[Image.Image],
    box,
    edge: int,
    quality: int,
    sharpen: ImageFilter.Filter | None,
) -> dict:
    doc = copy.deepcopy(master)
    if doc["w"] != doc["h"]:
        raise SystemExit("square compositions only")
    comp = edge / doc["w"]
    doc["w"] = doc["h"] = edge

    left, top, right, bottom = box
    crop_w, crop_h = right - left, bottom - top

    first = master["layers"][0]["ks"]
    anchor, position, scale = (_static(first[k]) for k in ("a", "p", "s"))
    # What one master pixel covers in the new composition.
    kx, ky = scale[0] / 100 * comp, scale[1] / 100 * comp
    out_w, out_h = max(1, round(crop_w * kx)), max(1, round(crop_h * ky))
    # The frame is a whole number of pixels and the crop times k is not, so
    # the layer keeps a scale within a percent of 100 to make up the rest.
    new_scale = [crop_w * kx / out_w * 100, crop_h * ky / out_h * 100, 100]
    new_anchor = [
        (anchor[0] - left) * out_w / crop_w,
        (anchor[1] - top) * out_h / crop_h,
        0,
    ]
    new_position = [position[0] * comp, position[1] * comp, 0]

    for asset, frame in zip(doc["assets"], frames):
        # Premultiplied, so the colour under a transparent pixel has no
        # weight in the average.
        small = (
            frame.convert("RGBa")
            .crop(box)
            .resize((out_w, out_h), Image.Resampling.LANCZOS)
        )
        if sharpen is not None:
            small = small.filter(sharpen)
        small = small.convert("RGBA")
        buffer = io.BytesIO()
        small.save(buffer, quality=quality, **WEBP)
        asset["p"] = "data:image/webp;base64," + base64.b64encode(
            buffer.getvalue()
        ).decode("ascii")
        asset["w"], asset["h"] = out_w, out_h

    for layer in doc["layers"]:
        ks = layer["ks"]
        if layer["ty"] != 2 or any(
            _static(ks[k]) != v
            for k, v in (("a", anchor), ("p", position), ("s", scale))
        ):
            raise SystemExit(f"layer {layer.get('nm')} is not a plain frame")
        ks["a"]["k"], ks["p"]["k"], ks["s"]["k"] = new_anchor, new_position, new_scale
        layer["cl"] = "webp"
    return doc


def _play_order(doc: dict) -> list[tuple[bytes, int]]:
    """Each frame's image bytes and its time on screen in ms, as played."""
    assets = {asset["id"]: asset for asset in doc["assets"]}
    rate, played = doc["fr"], []
    at = doc["ip"]
    for layer in sorted(doc["layers"], key=lambda layer: layer["ip"]):
        ks = layer["ks"]
        asset = assets[layer["refId"]]
        # A layer that is moved, scaled, faded or overlaps its neighbour is
        # a composition, and flattening it to its image would be wrong.
        if (
            layer["ty"] != 2
            or layer["ip"] != at
            or layer["op"] <= at
            or _static(ks["a"]) != _static(ks["p"])
            or _static(ks["s"])[:2] != [100, 100]
            or _static(ks["o"]) != 100
            or _static(ks["r"]) != 0
            or (asset["w"], asset["h"]) != (doc["w"], doc["h"])
        ):
            raise SystemExit(f"layer {layer.get('nm')} is not a plain full frame")
        head, data = asset["p"].split(",", 1)
        if not head.startswith("data:image/"):
            raise SystemExit(f"asset {asset['id']} is not an embedded image")
        # Rounded start to rounded end, so the sum is the film's length to
        # the millisecond however many frames there are.
        ms = round(layer["op"] * 1000 / rate) - round(at * 1000 / rate)
        played.append((base64.b64decode(data), ms))
        at = layer["op"]
    if at != doc["op"]:
        raise SystemExit("the layers do not cover the composition")
    return played


def _chunk(tag: bytes, payload: bytes) -> bytes:
    return tag + struct.pack("<I", len(payload)) + payload + bytes(len(payload) & 1)


def _u24(value: int) -> bytes:
    return value.to_bytes(3, "little")


def _vp8(image: Image.Image, options: dict) -> bytes:
    """One lossy still, without the RIFF header Pillow wraps it in."""
    buffer = io.BytesIO()
    image.save(buffer, **options)
    data = buffer.getvalue()
    at = 12
    while at < len(data):
        tag, size = data[at : at + 4], int.from_bytes(data[at + 4 : at + 8], "little")
        if tag == b"VP8 ":
            return data[at + 8 : at + 8 + size]
        at += 8 + size + (size & 1)
    raise SystemExit("Pillow wrote no VP8 chunk: is the frame opaque RGB?")


def _psnr(a: Image.Image, b: Image.Image) -> float:
    stat = ImageStat.Stat(ImageChops.difference(a, b))
    mse = sum(stat.sum2) / (a.width * a.height * 3)
    return 99.0 if mse == 0 else 10 * math.log10(255 * 255 / mse)


def _launch(master: dict, width: int, options: dict) -> tuple[bytes, str]:
    """The animated WebP at `width`, and a line on what is in it."""
    played = _play_order(master)
    height = round(master["h"] * width / master["w"])
    # Decoded once and kept: the reduced file is scored against the master
    # reduced the same way, which is what it is meant to be.
    frames = []
    for raw, _ in played:
        frame = Image.open(io.BytesIO(raw)).convert("RGB")
        if frame.size != (master["w"], master["h"]):
            raise SystemExit("a frame is not the size of the composition")
        if frame.width != width:
            frame = frame.resize((width, height), Image.Resampling.LANCZOS)
        frames.append(frame)

    # 0x02 in VP8X: this file is an animation. No alpha, no profile.
    body = _chunk(b"VP8X", bytes([0x02, 0, 0, 0]) + _u24(width - 1) + _u24(height - 1))
    # Background colour (decoders ignore it), then the loop count.
    body += _chunk(b"ANIM", bytes(4) + struct.pack("<H", LAUNCH_LOOPS))

    previous = None
    for frame, (_, ms) in zip(frames, played):
        box = (0, 0, width, height)
        if previous is not None:
            # A frame equal to the last still has to exist, and the format
            # has no empty frame: one pixel is the smallest.
            box = ImageChops.difference(previous, frame).getbbox() or (0, 0, 1, 1)
            # The offset is stored halved.
            box = (box[0] & ~1, box[1] & ~1, box[2], box[3])
        left, top, right, bottom = box
        body += _chunk(
            b"ANMF",
            _u24(left // 2)
            + _u24(top // 2)
            + _u24(right - left - 1)
            + _u24(bottom - top - 1)
            + _u24(ms)
            # Overwrite, do not blend, and leave the canvas for the next
            # frame: the box is opaque and the rest must stay as it was.
            + bytes([0x02])
            + _chunk(b"VP8 ", _vp8(frame.crop(box), options)),
        )
        previous = frame
    data = b"RIFF" + struct.pack("<I", len(body) + 4) + b"WEBP" + body

    # Read back through the decoder, because a container written by hand
    # that only this script can read is worth nothing.
    out = Image.open(io.BytesIO(data))
    if (out.n_frames, out.size) != (len(played), (width, height)):
        raise SystemExit(f"read back {out.n_frames} frames of {out.size}")
    scores, total = [], 0
    for index, (_, ms) in enumerate(played):
        out.seek(index)
        # The duration is only known once the frame is decoded.
        out.load()
        if out.info["duration"] != ms:
            raise SystemExit(f"frame {index} reads back {out.info['duration']} ms")
        total += ms
        scores.append(_psnr(out.convert("RGB"), frames[index]))
    return data, (
        f"{len(played)} frames of {width}x{height}, {total} ms, "
        f"loop {out.info.get('loop')}, "
        f"PSNR worst {min(scores):.2f} dB mean {sum(scores) / len(scores):.2f} dB"
    )


def _launch_ending(data: bytes) -> bytes:
    """Reuse the last independent payload only if it is the final canvas."""
    film = Image.open(io.BytesIO(data))
    width, height = film.size
    candidate = None
    at = 12
    while at < len(data):
        tag = data[at:at + 4]
        size = int.from_bytes(data[at + 4:at + 8], "little")
        body = data[at + 8:at + 8 + size]
        if len(body) != size:
            raise SystemExit("the launch container is incomplete")
        if tag == b"ANMF":
            x, y, w, h = (
                int.from_bytes(body[start:start + 3], "little")
                for start in (0, 3, 6, 9)
            )
            if (x, y, w + 1, h + 1, body[15]) == (0, 0, width, height, 2):
                candidate = body[16:]
        at += 8 + size + (size & 1)
    if at != len(data) or candidate is None:
        raise SystemExit("the launch has no independent ending")
    still = b"RIFF" + struct.pack("<I", len(candidate) + 4) + b"WEBP" + candidate
    ending = Image.open(io.BytesIO(still))
    film.seek(film.n_frames - 1)
    if (ending.n_frames != 1 or ending.size != film.size
            or ImageChops.difference(
                ending.convert("RGB"), film.convert("RGB"),
            ).getbbox() is not None):
        raise SystemExit("the independent ending differs from the final canvas")
    return still


def _dump(doc: dict) -> bytes:
    return json.dumps(doc, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _write(path: Path, data: bytes, check: bool, was: int | None, note: str) -> None:
    before = f"{was / 1e6:6.2f} MB -> " if was is not None else " " * 13
    print(f"  {path.name:34} {before}{len(data) / 1e6:6.2f} MB  {note}")
    if not check:
        path.write_bytes(data)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="write nothing")
    parser.add_argument(
        "--only",
        choices=("lottie", "launch"),
        help="one half of the work: the Lottie files, or the launch WebPs",
    )
    args = parser.parse_args()

    if args.only != "lottie":
        print("launch, from tool/lottie_masters:")
        master = json.loads(LAUNCH_MASTER.read_text(encoding="utf-8"))
        for path, width, options in (
            (LAUNCH_OUT, master["w"], LAUNCH_WEBP),
            (LAUNCH_WELL_OUT, LAUNCH_WELL_WIDTH, LAUNCH_WELL_WEBP),
        ):
            data, note = _launch(master, width, options)
            _write(path, data, args.check, LAUNCH_MASTER.stat().st_size, note)
            if path == LAUNCH_OUT:
                _write(
                    LAUNCH_END_OUT, _launch_ending(data), args.check,
                    len(data), "one pixel-identical ending, original VP8 payload",
                )
    if args.only == "launch":
        return 0

    print("frame sequences, from tool/lottie_masters:")
    for name, (full, small) in VARIANTS.items():
        source = MASTERS / f"ic_anim_{name}.json"
        master = json.loads(source.read_text(encoding="utf-8"))
        frames = _frames(master)
        box = _union_box(frames)
        for edge, suffix, quality, sharpen in (
            (full, "", QUALITY_FULL, None),
            (small, "_small", QUALITY_SMALL, SHARPEN_SMALL),
        ):
            doc = _variant(master, frames, box, edge, quality, sharpen)
            asset = doc["assets"][0]
            _write(
                OUT / f"ic_anim_{name}{suffix}.json",
                _dump(doc),
                args.check,
                source.stat().st_size,
                f"{len(frames)} frames of {asset['w']}x{asset['h']}, "
                f"{len(frames) * asset['w'] * asset['h'] * 4 / 1e6:.0f} MB decoded "
                f"(was {len(frames) * 4:.0f})",
            )

    print("vectors, whitespace only:")
    for name in VECTORS:
        path = OUT / f"ic_anim_{name}.json"
        raw = path.read_bytes()
        doc = json.loads(raw.decode("utf-8"))
        data = _dump(doc)
        if json.loads(data.decode("utf-8")) != doc:
            raise SystemExit(f"{path.name}: the round trip changed a value")
        _write(path, data, args.check, len(raw), "")
    return 0


if __name__ == "__main__":
    sys.exit(main())
