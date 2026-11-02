"""In-memory lab-source and test-result controls; no Go runtime is started."""

import json
from pathlib import Path
import unittest
from unittest import mock

from tool.ci import hosted_chain321 as lab
from tool.ci import producer_shutdown_patch as patch


def events(*, failing):
    output = ("panic: runtime error: invalid memory address or nil pointer dereference\n"
        + patch.PACKAGE + ".(*manager).processSupervised(0xprivate)\n"
        + "\t/fixture/private/pillar/manager.go:120 +0x123\n") if failing else "PASS\n"
    return [dict(Action="run", Package=patch.PACKAGE, Test=patch.TEST_NAME),
        dict(Action="output", Package=patch.PACKAGE, Test=patch.TEST_NAME, Output=output),
        dict(Action="fail" if failing else "pass", Package=patch.PACKAGE, Test=patch.TEST_NAME),
        dict(Action="fail" if failing else "pass", Package=patch.PACKAGE)]


def encoded(rows):
    return b"\n".join(json.dumps(row).encode() for row in rows)


def verified():
    return dict(patch.pending(), phase="verified", compiled_tree=patch.COMPILED_TREE,
        unpatched_exit=1, patched_exit=0, unpatched_expected_panic=True, patched_test_passed=True)


class ProducerPatchTests(unittest.TestCase):
    def test_red_requires_the_actual_named_test_panic_and_package_failure(self):
        self.assertTrue(patch.result(encoded(events(failing=True)), failing=True))
        self.assertTrue(patch.result(encoded(events(failing=False)), failing=False))

    def test_zero_exit_empty_filter_missing_package_and_skips_cannot_pass(self):
        passed = events(failing=False)
        offered = [[], passed[:-1], passed[1:], passed + [dict(Action="skip", Package=patch.PACKAGE)],
                   passed + [passed[-1]], passed + [dict(Action="fail", Package=patch.PACKAGE)]]
        for rows in offered:
            with self.subTest(rows=len(rows)), self.assertRaises(patch.Refused):
                patch.result(encoded(rows), failing=False)
        with self.assertRaises(patch.Refused):
            patch.result(encoded(passed), failing=True)

    def test_an_unrelated_crash_or_compiler_failure_is_not_the_expected_red(self):
        for text in ("compiler: undefined symbol", "panic: unrelated failure",
                     "panic: runtime error: invalid memory address or nil pointer dereference"):
            rows = events(failing=True)
            rows[1]["Output"] = text
            with self.subTest(text=text), self.assertRaises(patch.Refused):
                patch.result(encoded(rows), failing=True)
        rows = events(failing=True)
        rows[1]["Output"] = rows[1]["Output"].replace("manager.go:120", "manager.go:121")
        with self.assertRaises(patch.Refused):
            patch.result(encoded(rows), failing=True)

    def test_windows_source_separator_is_accepted_without_echoing_its_path(self):
        rows = events(failing=True)
        rows[1]["Output"] = rows[1]["Output"].replace("/fixture/private/pillar/manager.go", "C:\\private\\pillar\\manager.go")
        self.assertIs(patch.result(encoded(rows), failing=True), True)

    def test_malformed_private_text_unknown_tests_and_oversized_output_are_refused(self):
        for raw in (b"private raw error", b"x" * (patch.MAX_BYTES + 1), b"{}"):
            with self.subTest(length=len(raw)), self.assertRaises(patch.Refused) as error:
                patch.result(raw, failing=True)
            self.assertEqual(str(error.exception), "NODE_REGRESSIONS_REFUSED")
        rows = events(failing=False)
        rows[0]["Test"] = "OtherTest"
        with self.assertRaises(patch.Refused):
            patch.result(encoded(rows), failing=False)

    def test_only_verified_both_sides_can_qualify_a_compiled_lab_correction(self):
        self.assertIsNone(patch.validate(None, required=False))
        value = verified()
        result = patch.validate(value, required=True)
        self.assertEqual(result["compiled_tree"], patch.COMPILED_TREE)
        self.assertNotIn("fixture_sha256", result)
        for change in (dict(phase="unpatched_test"), dict(compiled_tree="a" * 40),
                       dict(unpatched_exit=True), dict(patched_exit=False),
                       dict(patch_sha256="b" * 64), dict(unpatched_expected_panic=False),
                       dict(patched_test_passed=False), dict(raw="private")):
            with self.subTest(change=change), self.assertRaises(patch.Refused):
                patch.validate(dict(value, **change), required=True)

    def test_partial_failure_facts_stay_partial_and_cannot_start_a_build(self):
        for phase in ("fixture", "unpatched_test"):
            value = dict(patch.pending(), phase=phase)
            self.assertEqual(patch.validate(value, required=False)["phase"], phase)
            with self.assertRaises(patch.Refused):
                patch.validate(value, required=True)

    def test_changed_head_tree_index_worktree_or_untracked_source_is_refused(self):
        clean = [patch.BASE_SHA, patch.BASE_TREE, patch.COMPILED_TREE, "", ""]
        commands = mock.Mock()
        commands.git.side_effect = clean
        lab.source_matches(commands, Path("fixture"), patch.BASE_SHA, patch.BASE_TREE, patch.COMPILED_TREE)
        for index in range(5):
            offered = list(clean)
            offered[index] = "changed"
            commands.git.side_effect = offered
            with self.subTest(index=index), self.assertRaises(lab.Failure):
                lab.source_matches(commands, Path("fixture"), patch.BASE_SHA, patch.BASE_TREE, patch.COMPILED_TREE)

    def test_changed_fixture_or_patch_is_refused_before_a_go_command(self):
        commands = mock.Mock()
        with mock.patch.object(lab, "directories"), mock.patch.object(lab, "regular", return_value=b"changed"):
            with self.assertRaises(lab.Failure):
                lab.prepare_producer_patch(commands, Path("fixture/repo"), Path("fixture/source"), {})
        commands.run.assert_not_called()
        commands.git.assert_not_called()


if __name__ == "__main__":
    unittest.main()
