#!/usr/bin/env python3
"""Derive the missing 600 face from the mockup's pinned Space Grotesk font.

Run with the approved private converter environment, outside the app's
dependencies. The caller owns scratch allocation and promotion of the result.

    python tool/redesign_fonts.py --output <existing-scratch>/SpaceGrotesk-SemiBold.ttf
    python tool/redesign_fonts.py --check --output assets/fonts/SpaceGrotesk-SemiBold.ttf

Generation never replaces different existing bytes. Check mode only reads the
asset, pinned source and provenance; it does not instantiate or save a font.
Both modes print compact metadata without filesystem paths.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import importlib.metadata
import io
import json
from pathlib import Path
import platform
import re
import sys


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "mockups" / "home" / "index.html"
INPUT_SHA256 = "0640890476fc1198ab4de571fb658de443c4d85b66466ec09534a8737ab1ce9d"
VERSIONS = {"fonttools": "4.67.0", "brotli": "1.2.0"}
WEIGHT = 600
MAX_BYTES = 4 * 1024 * 1024
VARIATION_TABLES = {"fvar", "avar", "gvar", "cvar", "HVAR", "VVAR", "MVAR", "VARC", "STAT"}
NAMES = {
    # The full bundled Medium face also uses a style-specific legacy family
    # with Regular style, and an unsuffixed typographic family with its weight.
    1: "Space Grotesk SemiBold",
    2: "Regular",
    3: "2.000;FK;SpaceGrotesk-SemiBold",
    4: "Space Grotesk SemiBold",
    6: "SpaceGrotesk-SemiBold",
    13: "This Font Software is licensed under the SIL Open Font License, Version 1.1.",
    16: "Space Grotesk",
    17: "SemiBold",
}


class FontError(ValueError):
    """A controlled diagnostic without private paths or library tracebacks."""


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_capped(path: Path) -> bytes:
    with path.open("rb") as source:
        data = source.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise FontError("Input exceeds the 4 MiB limit")
    return data


def converter_versions() -> dict[str, str]:
    for distribution, expected in VERSIONS.items():
        try:
            actual = importlib.metadata.version(distribution)
        except importlib.metadata.PackageNotFoundError as error:
            raise FontError("Use the pinned private fontTools and Brotli converter") from error
        if actual != expected:
            raise FontError("Converter versions differ from the pinned provenance")
    return {**VERSIONS, "python": platform.python_version()}


def source_bytes() -> bytes:
    text = read_capped(SOURCE).decode("utf-8")
    matches = re.findall(
        r'@font-face\{font-family:"Space Grotesk";[^}]*base64,([A-Za-z0-9+/=]+)\)',
        text,
    )
    if len(matches) != 1:
        raise FontError("Expected one embedded Space Grotesk source face")
    data = base64.b64decode(matches[0], validate=True)
    if digest(data) != INPUT_SHA256:
        raise FontError("Embedded font hash differs from the pinned source")
    return data


def source_metadata(data: bytes) -> dict[str, object]:
    from fontTools.ttLib import TTFont

    with TTFont(io.BytesIO(data), recalcTimestamp=False) as font:
        axes = font["fvar"].axes
        if len(axes) != 1 or (
            axes[0].axisTag,
            axes[0].minValue,
            axes[0].defaultValue,
            axes[0].maxValue,
        ) != ("wght", 300, 300, 700):
            raise FontError("Unexpected source variation axes")
        return {
            "created": font["head"].created,
            "modified": font["head"].modified,
            "glyph_order": font.getGlyphOrder(),
            "cmap": font.getBestCmap(),
            "notices": {
                (record.nameID, record.platformID, record.platEncID, record.langID): record.toUnicode()
                for record in font["name"].names
                if record.nameID in (0, 14)
            },
        }


def derive(data: bytes, original: dict[str, object]) -> bytes:
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont, setRibbiBits

    with TTFont(io.BytesIO(data), recalcTimestamp=False) as variable:
        static = instantiateVariableFont(
            variable, {"wght": WEIGHT}, inplace=False, updateFontNames=False, static=True
        )
        with static:
            # The pinned source has one axis, now fixed. Its axis descriptions
            # and container metadata have no meaning in the static face.
            for table in VARIATION_TABLES:
                if table in static:
                    del static[table]
            static.flavor = None
            static.flavorData = None
            static.recalcTimestamp = False
            static["head"].created = original["created"]
            static["head"].modified = original["modified"]
            static["OS/2"].usWeightClass = WEIGHT
            names = static["name"]
            names.names = [record for record in names.names if record.nameID < 256]
            platforms = sorted({
                (record.platformID, record.platEncID, record.langID) for record in names.names
            })
            for name_id, text in NAMES.items():
                for font_platform, encoding, language in platforms:
                    names.setName(text, name_id, font_platform, encoding, language)
            setRibbiBits(static)
            output = io.BytesIO()
            static.save(output, reorderTables=True)
            return output.getvalue()


def inspect_static(data: bytes, original: dict[str, object]) -> dict[str, object]:
    from fontTools.ttLib import TTFont

    with TTFont(io.BytesIO(data), recalcTimestamp=False, checkChecksums=2) as font:
        if font.flavor is not None or font.sfntVersion != "\x00\x01\x00\x00":
            raise FontError("Output must be an unwrapped TrueType font")
        if VARIATION_TABLES.intersection(font.keys()):
            raise FontError("Output still contains variation metadata")
        if font["OS/2"].usWeightClass != WEIGHT:
            raise FontError("Output weight is not 600")
        if (font["head"].created, font["head"].modified) != (
            original["created"], original["modified"]
        ):
            raise FontError("Output timestamps differ from the original source")
        if font.getGlyphOrder() != original["glyph_order"] or font.getBestCmap() != original["cmap"]:
            raise FontError("Output glyph coverage differs from the source subset")
        for name_id, text in NAMES.items():
            records = [record for record in font["name"].names if record.nameID == name_id]
            if not records or any(record.toUnicode() != text for record in records):
                raise FontError("Output family, style or license metadata differs")
        for key, text in original["notices"].items():
            record = font["name"].getName(*key)
            if record is None or record.toUnicode() != text:
                raise FontError("Original copyright or license URL was not preserved")
        return {
            "input_sha256": INPUT_SHA256,
            "output_sha256": digest(data),
            "weight": WEIGHT,
            "glyphs": len(font.getGlyphOrder()),
            "characters": len(font.getBestCmap()),
            "family": NAMES[16],
            "style": NAMES[17],
            "postscript_name": NAMES[6],
            "head_created": font["head"].created,
            "head_modified": font["head"].modified,
        }


def check_provenance(path: Path, output_sha256: str) -> None:
    text = read_capped(path).decode("utf-8")
    input_hash = re.search(r"(?m)^- Input SHA-256: `([0-9a-f]{64})`\.$", text)
    output_hash = re.search(r"(?m)^- Output SHA-256: `([0-9a-f]{64})`\.$", text)
    if input_hash is None or input_hash.group(1) != INPUT_SHA256:
        raise FontError("Provenance input hash is missing or differs")
    if output_hash is None:
        raise FontError("Provenance output hash is pending or missing")
    if output_hash.group(1) != output_sha256:
        raise FontError("Provenance output hash differs from the asset")
    if "- Coordinate: `wght=600`." not in text:
        raise FontError("Provenance coordinate is missing")
    if "- Converter: fontTools 4.67.0; Brotli 1.2.0." not in text:
        raise FontError("Provenance converter versions differ")


def write_new_or_identical(path: Path, data: bytes) -> str:
    if not path.parent.is_dir() or path.is_symlink():
        raise FontError("Output needs an existing directory and must not be a symbolic link")
    try:
        with path.open("xb") as destination:
            destination.write(data)
        return "created"
    except FileExistsError:
        if read_capped(path) != data:
            raise FontError("Refusing to replace different existing output bytes")
        return "existing-identical"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--provenance", type=Path, default=ROOT / "assets" / "fonts" / "REDESIGN.md")
    args = parser.parse_args()
    try:
        versions = converter_versions()
        source = source_bytes()
        original = source_metadata(source)
        if args.check:
            data = read_capped(args.output)
            result = inspect_static(data, original)
            check_provenance(args.provenance, result["output_sha256"])
            result.update(mode="check", provenance="verified")
        else:
            data = derive(source, original)
            result = inspect_static(data, original)
            result.update(mode="derive", output=write_new_or_identical(args.output, data))
        result["converter"] = versions
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
        return 0
    except FontError as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
    except Exception:
        # Library and filesystem diagnostics may contain private paths.
        print(json.dumps({"error": "Font operation failed; inspect the private converter environment and inputs"}), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
