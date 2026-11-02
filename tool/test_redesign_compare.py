#!/usr/bin/env python3
"""Exercise comparison evidence rules with tiny synthetic PNGs.

The caller supplies an existing, disposable directory in approved scratch:

    python tool/test_redesign_compare.py --temp-root <approved-scratch>

No real wallet, mockup screenshot or existing report is changed. These tests
qualify report behaviour only; they do not establish any screen's match.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

from redesign_compare import generate_report, screen_inventory, screen_notes


TEST_ROOT: Path | None = None


class CompareTests(unittest.TestCase):
    def setUp(self) -> None:
        if TEST_ROOT is None:
            raise RuntimeError("Run this test script with --temp-root pointing to approved scratch")
        self.temporary = tempfile.TemporaryDirectory(prefix="compare-", dir=TEST_ROOT)
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        self.src = self.repo / "mockups" / "redesign" / "src"
        self.src.mkdir(parents=True)
        self.expected = self.src.parent / "shots"
        self.expected.mkdir()
        self.actual = self.repo / "actual"
        self.actual.mkdir()
        self.output = self.repo / "report"
        self.ids = ["screen-z", "screen-a"] + [f"screen-{n}" for n in range(3, 48)]
        sections = "\n".join(
            f'<section class="scr" id="{screen_id}" data-title="{html.escape(screen_id + " < & >", quote=True)}"></section>'
            for screen_id in self.ids
        )
        (self.src / "10-screens.html").write_text(sections, encoding="utf-8")
        notes = {screen_id: [["At rest", "A <note> & text"]] for screen_id in self.ids}
        # Put the closing brace on its own line, as in the actual mockup source.
        (self.src / "90-tail.html").write_text("const NOTES = " + repr(notes)[:-1] + "\n};", encoding="utf-8")
        for number, screen_id in enumerate(self.ids, 1):
            for theme in ("dark", "light"):
                self.save_png(self.expected / f"{number:02d}-{screen_id}-{theme}.png")
        self.stem = "01-screen-z-dark"

    @staticmethod
    def save_png(path: Path, size: tuple[int, int] = (4, 3)) -> None:
        with Image.new("RGBA", size, (12, 34, 56, 255)) as image:
            image.save(path)

    def add_actual(self, size: tuple[int, int] = (4, 3)) -> None:
        self.save_png(self.actual / f"{self.stem}.png", size)

    def review_file(self, verdict: str = "match", stale_field: str | None = None) -> Path:
        record = {
            "verdict": verdict,
            "reviewer": "Reviewer <test>",
            "reviewed_at": "2026-10-22T12:00:00Z",
            "note": "Reviewed <layout> & frames",
            "expected_sha256": hashlib.sha256((self.expected / f"{self.stem}.png").read_bytes()).hexdigest(),
            "actual_sha256": hashlib.sha256((self.actual / f"{self.stem}.png").read_bytes()).hexdigest(),
        }
        if stale_field:
            record[stale_field] = "0" * 64
        path = self.repo / "reviews.json"
        path.write_text(json.dumps({"reviews": {self.stem: record}}), encoding="utf-8")
        return path

    def report(self, reviews: Path | None = None) -> dict[str, object]:
        return generate_report(
            self.repo, self.actual, self.output, reviews, required_size=(4, 3)
        )

    def test_missing_actual_remains_visible(self) -> None:
        result = self.report()
        self.assertEqual(len(result["pairs"]), 94)
        self.assertEqual(result["pairs"][0]["state"], "missing")
        self.assertEqual(result["pairs"][0]["actual"]["state"], "missing")
        self.assertIsNone(result["pairs"][0]["score"])
        self.assertEqual(result["summary"]["visual_review"], "INCOMPLETE")

    def test_wrong_size_is_not_rescaled_or_scored(self) -> None:
        self.add_actual((3, 4))
        pair = self.report()["pairs"][0]
        self.assertEqual(pair["state"], "size-mismatch")
        self.assertIsNone(pair["score"])
        self.assertIsNone(pair["diff_url"])

    def test_default_requires_1280_by_780_even_if_tiny_images_agree(self) -> None:
        self.add_actual()
        pair = generate_report(self.repo, self.actual, self.output)["pairs"][0]
        self.assertEqual(pair["state"], "size-mismatch")

    def test_corrupt_png_is_invalid(self) -> None:
        (self.actual / f"{self.stem}.png").write_bytes(b"not a PNG")
        pair = self.report()["pairs"][0]
        self.assertEqual(pair["state"], "invalid")
        self.assertNotIn(str(self.repo), pair["actual"]["reason"])

    def test_equal_pixels_still_require_visual_review(self) -> None:
        self.add_actual()
        pair = self.report()["pairs"][0]
        self.assertEqual(pair["score"]["similarity_pct"], 100)
        self.assertEqual(pair["state"], "unreviewed")

    def test_stale_review_on_either_image_is_invalidated(self) -> None:
        self.add_actual()
        for field in ("expected_sha256", "actual_sha256"):
            with self.subTest(field=field):
                pair = self.report(self.review_file(stale_field=field))["pairs"][0]
                self.assertEqual(pair["state"], "unreviewed")
                self.assertEqual(pair["review"]["state"], "stale")

    def test_inventory_and_report_keep_source_order(self) -> None:
        result = self.report()
        pairs = result["pairs"]
        self.assertEqual([pair["id"] for pair in pairs[:4]], [
            "01-screen-z-dark", "01-screen-z-light", "02-screen-a-dark", "02-screen-a-light"
        ])
        page = (self.output / "index.html").read_text(encoding="utf-8")
        self.assertLess(page.index('id="01-screen-z-dark"'), page.index('id="02-screen-a-dark"'))
        self.assertIn("A &lt;note&gt; &amp; text", page)
        self.assertIn("screen-z &lt; &amp; &gt;", page)

    def test_valid_match_requires_hashes_and_review_metadata(self) -> None:
        self.add_actual()
        pair = self.report(self.review_file())["pairs"][0]
        self.assertEqual(pair["state"], "reviewed-match")
        self.assertEqual(pair["review"]["state"], "current")
        self.assertIsNotNone(pair["diff_url"])
        page = (self.output / "index.html").read_text(encoding="utf-8")
        self.assertIn("Reviewer &lt;test&gt;", page)
        self.assertIn("Reviewed &lt;layout&gt; &amp; frames", page)

    def test_reviewed_mismatch_does_not_follow_pixel_score(self) -> None:
        self.add_actual()
        pair = self.report(self.review_file(verdict="mismatch"))["pairs"][0]
        self.assertEqual(pair["score"]["similarity_pct"], 100)
        self.assertEqual(pair["state"], "reviewed-mismatch")

    def test_bad_review_metadata_cannot_grant_acceptance(self) -> None:
        self.add_actual()
        reviews = self.review_file()
        data = json.loads(reviews.read_text(encoding="utf-8"))
        data["reviews"][self.stem]["reviewed_at"] = "2026-10-22T12:00:00"
        reviews.write_text(json.dumps(data), encoding="utf-8")
        pair = self.report(reviews)["pairs"][0]
        self.assertEqual(pair["state"], "unreviewed")
        self.assertEqual(pair["review"]["state"], "invalid")

    def test_notes_never_execute_javascript_or_python(self) -> None:
        source = self.src / "90-tail.html"
        source.write_text("const NOTES = { 'screen-z': object()\n};", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "literal strings and lists"):
            screen_notes(source, screen_inventory(self.src))

    def test_generation_preserves_unknown_output_files_and_links_inputs(self) -> None:
        self.add_actual()
        self.output.mkdir()
        retained = self.output / "keep.txt"
        retained.write_text("retained", encoding="utf-8")
        self.report()
        self.assertEqual(retained.read_text(encoding="utf-8"), "retained")
        self.assertEqual({path.name for path in self.output.iterdir()}, {
            "keep.txt", "diffs", "index.html", "manifest.json", "summary.json"
        })
        manifest = json.loads((self.output / "manifest.json").read_text(encoding="utf-8"))
        self.assertFalse(manifest["pairs"][0]["expected"]["url"].startswith("/"))
        self.assertFalse(manifest["pairs"][0]["actual"]["url"].startswith("/"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--temp-root", required=True, type=Path)
    arguments, test_arguments = parser.parse_known_args()
    if not arguments.temp_root.is_dir():
        parser.error("--temp-root must be an existing approved scratch directory")
    TEST_ROOT = arguments.temp_root
    unittest.main(argv=[__file__, *test_arguments])
