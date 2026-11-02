#!/usr/bin/env python3
"""Build the local redesign comparison without granting visual acceptance.

    python tool/redesign_compare.py
    python tool/redesign_compare.py --actual-dir <shots> --output-dir <report>
    python tool/redesign_compare.py --reviews <reviews.json> --require-reviewed

Requires Pillow, also used by the mockup pipeline. Input images are linked,
never copied. The output is local evidence and may contain wallet screenshots;
keep it private. Relative links require the inputs to remain at their paths.

Manual reviews use screenshot stems as keys. For example:
{
  "reviews": {
    "01-home-rest-dark": {
      "verdict": "match",
      "reviewer": "Reviewer",
      "reviewed_at": "2026-10-22T12:00:00Z",
      "expected_sha256": "<64 lowercase hexadecimal characters>",
      "actual_sha256": "<64 lowercase hexadecimal characters>",
      "note": "Layout, components, colour, type, spacing and frames reviewed."
    }
  }
}

The other verdict is "mismatch". A review applies only to those two exact
images. A pixel score, including 100%, leaves a pair unreviewed. This report
does not update the prompt's Progress table or qualify motion or Windows.
"""

from __future__ import annotations

import argparse
import ast
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from functools import reduce
import hashlib
from html import escape
from html.parser import HTMLParser
import io
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import quote
import warnings

from PIL import Image, ImageChops, ImageOps, ImageStat


ROOT = Path(__file__).resolve().parent.parent
THEMES = ("dark", "light")
SCREEN_COUNT = 47
IMAGE_SIZE = (1280, 780)
MAX_IMAGE_BYTES = 16 * 1024 * 1024
MAX_IMAGE_PIXELS = 4096 * 4096
SHA256 = re.compile(r"[0-9a-f]{64}\Z")


class ReportError(ValueError):
    """A controlled diagnostic that contains no private filesystem paths."""


@dataclass(frozen=True)
class Screen:
    number: int
    id: str
    title: str
    source: Path

    def stem(self, theme: str) -> str:
        return f"{self.number:02d}-{self.id}-{theme}"


class ScreenParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.screens: list[tuple[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag != "section" or "scr" not in (values.get("class") or "").split():
            return
        screen_id = values.get("id") or ""
        if re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", screen_id) is None:
            raise ReportError("A screen has a missing or unsafe id")
        self.screens.append((screen_id, values.get("data-title") or screen_id))


def screen_inventory(src: Path) -> list[Screen]:
    screens: list[Screen] = []
    for source in sorted(src.glob("*.html")):
        parser = ScreenParser()
        parser.feed(source.read_text(encoding="utf-8"))
        for screen_id, title in parser.screens:
            screens.append(Screen(len(screens) + 1, screen_id, title, source))
    if len(screens) != SCREEN_COUNT or len({s.id for s in screens}) != SCREEN_COUNT:
        raise ReportError("Expected 47 unique screens in ordered mockup HTML")
    return screens


def screen_notes(source: Path, screens: list[Screen]) -> dict[str, list[list[str]]]:
    text = source.read_text(encoding="utf-8")
    literal = re.search(r"\bconst\s+NOTES\s*=\s*(\{.*?\n\});", text, re.DOTALL)
    if literal is None:
        raise ReportError("Cannot find the literal mockup NOTES object")
    try:
        notes = ast.literal_eval(literal.group(1))
    except (SyntaxError, ValueError) as error:
        raise ReportError("Mockup NOTES must contain literal strings and lists") from error
    if not isinstance(notes, dict) or set(notes) != {s.id for s in screens}:
        raise ReportError("Mockup NOTES must cover exactly the 47 screen ids")
    for entries in notes.values():
        if not isinstance(entries, list) or any(
            not isinstance(entry, list)
            or len(entry) != 2
            or any(not isinstance(value, str) for value in entry)
            for entry in entries
        ):
            raise ReportError("Each mockup note must be a label and text")
    return notes


def load_reviews(source: Path | None) -> dict[str, object]:
    if source is None:
        return {}
    try:
        data = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        raise ReportError("Cannot read the reviews JSON") from error
    if not isinstance(data, dict) or not isinstance(data.get("reviews"), dict):
        raise ReportError("Reviews JSON must have a reviews object keyed by screenshot stem")
    return data["reviews"]


def relative_url(target: Path, output: Path) -> str:
    return quote(Path(os.path.relpath(target, output)).as_posix(), safe="/")


def read_image(path: Path, output: Path) -> tuple[dict[str, object], Image.Image | None]:
    info: dict[str, object] = {"url": relative_url(path, output)}
    try:
        if path.stat().st_size > MAX_IMAGE_BYTES:
            raise ValueError("PNG exceeds the 16 MiB input limit")
        with path.open("rb") as source:
            data = source.read(MAX_IMAGE_BYTES + 1)
        if len(data) > MAX_IMAGE_BYTES:
            raise ValueError("PNG exceeds the 16 MiB input limit")
        info["sha256"] = hashlib.sha256(data).hexdigest()
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as original:
                if original.format != "PNG" or getattr(original, "n_frames", 1) != 1:
                    raise ValueError("Expected a single-frame PNG")
                if original.width * original.height > MAX_IMAGE_PIXELS:
                    raise ValueError("PNG exceeds the pixel limit")
                info["size"] = [original.width, original.height]
                image = original.convert("RGBA")
        info["state"] = "available"
        return info, image
    except FileNotFoundError:
        info.update(state="missing", reason="Image missing")
    except (OSError, ValueError, SyntaxError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        info.update(state="invalid", reason="Unreadable, unsupported or oversized PNG")
    return info, None


def review_status(
    review: object, expected_sha: str, actual_sha: str
) -> dict[str, object]:
    if review is None:
        return {"state": "none"}
    if not isinstance(review, dict):
        return {"state": "invalid", "reason": "Review must be an object"}
    fields = ("verdict", "reviewer", "reviewed_at", "expected_sha256", "actual_sha256")
    if any(not isinstance(review.get(field), str) for field in fields):
        return {"state": "invalid", "reason": "Review fields are missing"}
    if (
        review["verdict"] not in ("match", "mismatch")
        or not review["reviewer"].strip()
        or SHA256.fullmatch(review["expected_sha256"]) is None
        or SHA256.fullmatch(review["actual_sha256"]) is None
        or not isinstance(review.get("note", ""), str)
    ):
        return {"state": "invalid", "reason": "Review fields are invalid"}
    try:
        reviewed_at = datetime.fromisoformat(review["reviewed_at"].replace("Z", "+00:00"))
        if reviewed_at.utcoffset() != timedelta(0):
            raise ValueError("UTC required")
    except ValueError:
        return {"state": "invalid", "reason": "Review time must be an ISO timestamp in UTC"}
    if review["expected_sha256"] != expected_sha or review["actual_sha256"] != actual_sha:
        return {"state": "stale", "reason": "Image hashes changed; visual review required"}
    return {"state": "current", **{key: review[key] for key in fields}, "note": review.get("note", "")}


def compare_pair(
    screen: Screen,
    theme: str,
    expected_dir: Path,
    actual_dir: Path,
    output: Path,
    reviews: dict[str, object],
    required_size: tuple[int, int] = IMAGE_SIZE,
) -> dict[str, object]:
    stem = screen.stem(theme)
    expected, before = read_image(expected_dir / f"{stem}.png", output)
    actual, after = read_image(actual_dir / f"{stem}.png", output)
    pair: dict[str, object] = {
        "id": stem,
        "screen": screen.id,
        "number": screen.number,
        "title": screen.title,
        "theme": theme,
        "source_url": relative_url(screen.source, output),
        "expected": expected,
        "actual": actual,
        "diff_url": None,
        "score": None,
        "review": {"state": "none"},
    }
    try:
        states = (expected["state"], actual["state"])
        if "invalid" in states or "missing" in states:
            pair["state"] = "invalid" if "invalid" in states else "missing"
            pair["reason"] = "; ".join(
                f"{label.capitalize()}: {info['reason']}"
                for label, info in (("mockup", expected), ("actual", actual))
                if info["state"] != "available"
            )
            return pair
        if before.size != required_size or after.size != required_size:
            pair.update(
                state="size-mismatch",
                reason=f"Both images must be {required_size[0]} by {required_size[1]}; images were not resized",
            )
            return pair
        review = review_status(reviews.get(stem), expected["sha256"], actual["sha256"])
        pair["review"] = review
        pair["state"] = (
            f"reviewed-{review['verdict']}" if review["state"] == "current" else "unreviewed"
        )
        diff = ImageChops.difference(before, after)
        mean = sum(ImageStat.Stat(diff).mean) / 4
        mask = reduce(ImageChops.lighter, diff.split())
        pixels = before.width * before.height
        changed = pixels - mask.histogram()[0]
        pair["score"] = {
            "similarity_pct": round(100 * (1 - mean / 255), 4),
            "mean_absolute_error_rgba": round(mean, 4),
            "changed_pixels": changed,
            "changed_pct": round(100 * changed / pixels, 4),
        }
        # Hashes in the filename keep a new report from showing a cached old diff.
        diff_name = f"{stem}-{expected['sha256'][:16]}-{actual['sha256'][:16]}.png"
        diff_path = output / "diffs" / diff_name
        diff_path.parent.mkdir(parents=True, exist_ok=True)
        ImageOps.colorize(mask, "#000000", "#ff557f").save(diff_path)
        pair["diff_url"] = relative_url(diff_path, output)
        return pair
    finally:
        for image in (before, after):
            if image is not None:
                image.close()


def render_html(manifest: dict[str, object]) -> str:
    def image_cell(label: str, info: dict[str, object]) -> str:
        if info.get("state") != "available":
            return f"<figure><figcaption>{label}</figcaption><p>{escape(str(info.get('reason', 'Unavailable')))}</p></figure>"
        url = escape(str(info["url"]), quote=True)
        size = info.get("size")
        caption = f"{label} ({size[0]} by {size[1]})" if size else label
        return f'<figure><figcaption>{caption}</figcaption><a href="{url}"><img loading="lazy" src="{url}" alt="{label}"></a></figure>'

    sections: list[str] = []
    for pair in manifest["pairs"]:
        stem = escape(pair["id"], quote=True)
        score = pair["score"]
        description = (
            "No pixel score"
            if score is None
            else f"Pixel similarity {score['similarity_pct']:.4f}%; changed pixels {score['changed_pct']:.4f}%"
        )
        figures = image_cell("Mockup", pair["expected"]) + image_cell("Actual", pair["actual"])
        diff = {"state": "available", "url": pair["diff_url"]} if pair["diff_url"] else {}
        figures += image_cell("Difference (max RGBA channel)", diff)
        notes = "".join(f"<li><b>{escape(label)}</b> {escape(text)}</li>" for label, text in pair["notes"])
        review = pair["review"]
        review_text = str(review.get("reason", "Visual review required"))
        if review["state"] == "current":
            review_text = f"Reviewed by {review['reviewer']} at {review['reviewed_at']}. {review['note']}"
        reason = f"<p>{escape(pair['reason'])}</p>" if "reason" in pair else ""
        sections.append(
            f'<section id="{stem}"><h2>{pair["number"]:02d}. {escape(pair["title"])} '
            f'({escape(pair["theme"])})</h2><p class="state">{escape(pair["state"])}</p>'
            f"<p>{description}. Scores are diagnostic; acceptance requires visual review.</p>{reason}"
            f"<p>{escape(review_text)}</p><div class=\"images\">{figures}</div>"
            f'<details><summary>Screen notes</summary><ul>{notes}</ul>'
            f'<a href="{escape(pair["source_url"], quote=True)}">Mockup source</a></details></section>'
        )
    counts = ", ".join(f"{state}: {count}" for state, count in sorted(manifest["summary"]["states"].items()))
    return (
        "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\">"
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
        "<title>Syrius redesign comparison</title><style>"
        "body{margin:24px;font:15px/1.5 system-ui,sans-serif;background:#11151b;color:#e1e5eb}"
        "a{color:#8abaff}section{padding:20px 0;border-top:1px solid #4d5560}h2{margin-bottom:4px}"
        ".state{font-weight:bold}.images{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}"
        "figure{margin:0;min-width:0}img{width:100%;height:auto}figcaption{margin-bottom:8px}"
        "details{margin-top:16px}li{margin:8px 0}@media(max-width:900px){.images{grid-template-columns:1fr}}"
        "</style><h1>Syrius redesign comparison</h1>"
        f"<p>{escape(counts)}</p><p>Visual review: {manifest['summary']['visual_review']}. "
        "A screenshot does not qualify motion, chain actions or Windows builds. "
        "This local report may contain wallet data; keep it private.</p>"
        "<p>Difference images show the largest absolute RGBA channel difference. "
        "Pixel similarity is 100 minus mean absolute RGBA error as a percentage of 255. "
        "Live data, font hinting and animation frames can change scores.</p>"
        + "".join(sections)
        + "</html>\n"
    )


def generate_report(
    repo: Path,
    actual_dir: Path,
    output: Path,
    reviews_path: Path | None = None,
    *,
    required_size: tuple[int, int] = IMAGE_SIZE,
) -> dict[str, object]:
    src = repo / "mockups" / "redesign" / "src"
    expected_dir = src.parent / "shots"
    screens = screen_inventory(src)
    notes = screen_notes(src / "90-tail.html", screens)
    reviews = load_reviews(reviews_path)
    output.mkdir(parents=True, exist_ok=True)
    pairs = []
    for screen in screens:
        for theme in THEMES:
            pair = compare_pair(
                screen, theme, expected_dir, actual_dir, output, reviews, required_size
            )
            pair["notes"] = notes[screen.id]
            pairs.append(pair)
    states = dict(Counter(pair["state"] for pair in pairs))
    summary = {
        "screens": len(screens),
        "pairs": len(pairs),
        "required_image_size": list(required_size),
        "states": states,
        "visual_review": "COMPLETE" if states.get("reviewed-match", 0) == 94 else "INCOMPLETE",
        "unrecognized_review_ids": sorted(set(reviews) - {pair["id"] for pair in pairs}),
    }
    manifest = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "summary": summary,
        "pairs": pairs,
    }
    for name, data in (("manifest.json", manifest), ("summary.json", summary)):
        (output / name).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (output / "index.html").write_text(render_html(manifest), encoding="utf-8")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--actual-dir", type=Path, default=ROOT / ".harness" / "shots")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "mockups" / "redesign" / "compare")
    parser.add_argument("--reviews", type=Path, help="Manual, image-hash-bound visual review JSON")
    parser.add_argument("--require-reviewed", action="store_true", help="Exit 1 unless all 94 pairs are reviewed matches")
    args = parser.parse_args()
    try:
        manifest = generate_report(ROOT, args.actual_dir.resolve(), args.output_dir.resolve(), args.reviews)
    except (OSError, UnicodeError, ValueError) as error:
        # Paths and raw diagnostics can contain private profile information.
        message = str(error) if isinstance(error, ReportError) else "Cannot read inputs or write report"
        print(f"Comparison generation failed: {message}", file=sys.stderr)
        return 2
    summary = manifest["summary"]
    print(f"Comparison generated: 47 screens, 94 pairs; visual review {summary['visual_review']}")
    print(", ".join(f"{state}: {count}" for state, count in sorted(summary["states"].items())))
    return int(args.require_reviewed and summary["visual_review"] != "COMPLETE")


if __name__ == "__main__":
    sys.exit(main())
