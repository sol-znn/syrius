"""Snapshot uncertainty controls plus separate real Windows API/helper checks."""

import contextlib
import io
import os
from pathlib import Path
import unittest
from unittest.mock import patch

from tool.ci import windows_process_preflight as preflight
from tool.ci import windows_presentation_smoke as smoke


class OriginalSnapshot:
    def __init__(self, rows):
        self.original = object()
        self.rows = iter(rows)
        self.created = 0
        self.closed = []
        self.failure = None
        self.close_failure = False

    def snapshot(self):
        self.created += 1
        return self.original

    def first(self, original):
        if original is not self.original:
            raise AssertionError()
        return next(self.rows, None)

    def next(self, original):
        if original is not self.original:
            raise AssertionError()
        if self.failure:
            raise self.failure
        return next(self.rows, None)

    def close(self, original):
        if original is not self.original:
            raise AssertionError()
        self.closed.append(original)
        if self.close_failure:
            raise OSError('private-close-detail')


class SnapshotTests(unittest.TestCase):
    def test_complete_snapshot_requires_own_process_and_closes_once(self):
        api = OriginalSnapshot([(0, '[System Process]'), (41, 'python.exe'), (52, 'other.exe')])
        self.assertEqual(preflight.observe(api, 41), 0)
        self.assertEqual(api.created, 1)
        self.assertEqual(api.closed, [api.original])

    def test_existing_name_is_case_insensitive_and_closes_before_refusal(self):
        for image in ('syrius.exe', 'SYRIUS.EXE', 'SyRiUs', 'syrius.com'):
            with self.subTest(image=image):
                api = OriginalSnapshot([(41, 'python.exe'), (52, image)])
                self.assertEqual(preflight.observe(api, 41), 23)
                self.assertEqual(api.closed, [api.original])

    def test_similar_process_names_do_not_adopt_or_block_unrelated_work(self):
        api = OriginalSnapshot([(41, 'python.exe'), (52, 'syrius-updater.exe'),
                                (53, 'other-syrius.exe'), (54, 'syrius.helper.exe')])
        self.assertEqual(preflight.observe(api, 41), 0)
        self.assertEqual(api.closed, [api.original])

    def test_empty_or_missing_original_process_is_not_an_empty_machine(self):
        for rows in ([], [(52, 'other.exe')]):
            with self.subTest(rows=rows):
                api = OriginalSnapshot(rows)
                with self.assertRaises(preflight.Refused):
                    preflight.observe(api, 41)
                self.assertEqual(api.closed, [api.original])

    def test_snapshot_creation_failure_has_no_owned_handle_to_close(self):
        api = OriginalSnapshot([])
        with patch.object(api, 'snapshot', side_effect=OSError('private-create-detail')):
            with self.assertRaises(OSError):
                preflight.observe(api, 41)
        self.assertEqual(api.closed, [])

    def test_first_read_failure_still_closes_only_the_original_snapshot(self):
        api = OriginalSnapshot([])
        with patch.object(api, 'first', side_effect=OSError('private-read-detail')):
            with self.assertRaises(OSError):
                preflight.observe(api, 41)
        self.assertEqual(api.closed, [api.original])

    def test_incomplete_scan_cannot_be_accepted_even_after_a_name_match(self):
        for image in ('python.exe', 'syrius.exe'):
            with self.subTest(image=image):
                api = OriginalSnapshot([(41, image)])
                api.failure = OSError('private-next-detail')
                with self.assertRaises(OSError):
                    preflight.observe(api, 41)
                self.assertEqual(api.closed, [api.original])

    def test_invalid_rows_are_uncertain_and_close_the_original_snapshot(self):
        rows = ([], (41,), (True, 'python.exe'), (-1, 'python.exe'),
                (2**32, 'python.exe'), (41, ''), (41, None),
                (41, 'private/path.exe'), (41, 'private\\path.exe'),
                (41, 'embedded\0suffix'), (41, 'x' * 260))
        for row in rows:
            with self.subTest(row=row):
                api = OriginalSnapshot([row])
                with self.assertRaises(preflight.Refused):
                    preflight.observe(api, 41)
                self.assertEqual(api.closed, [api.original])

    def test_duplicate_pid_is_not_accepted_as_a_complete_snapshot(self):
        api = OriginalSnapshot([(41, 'python.exe'), (41, 'other.exe')])
        with self.assertRaises(preflight.Refused):
            preflight.observe(api, 41)
        self.assertEqual(api.closed, [api.original])

    def test_entry_cap_rejects_partial_results_instead_of_truncating_them(self):
        api = OriginalSnapshot([(41, 'python.exe'), (52, 'other.exe')])
        with patch.object(preflight, 'MAX_ENTRIES', 1):
            with self.assertRaises(preflight.Refused):
                preflight.observe(api, 41)
        self.assertEqual(api.closed, [api.original])

    def test_uncertain_close_cannot_return_success_or_existing_process(self):
        for image in ('python.exe', 'syrius.exe'):
            with self.subTest(image=image):
                api = OriginalSnapshot([(41, image)])
                api.close_failure = True
                with self.assertRaises(OSError):
                    preflight.observe(api, 41)
                self.assertEqual(api.closed, [api.original])

    def test_invalid_owner_refuses_before_any_snapshot(self):
        for owner in (None, True, 0, -1):
            api = OriginalSnapshot([])
            with self.subTest(owner=owner), self.assertRaises(preflight.Refused):
                preflight.observe(api, owner)
            self.assertEqual(api.created, 0)

    def test_unsupported_host_or_arguments_never_load_native_api(self):
        with patch.object(preflight.os, 'name', 'posix'), patch.object(preflight, 'Toolhelp') as api:
            self.assertEqual(preflight.main([]), 1)
        api.assert_not_called()
        with patch.object(preflight.os, 'name', 'nt'), patch.object(preflight, 'Toolhelp') as api:
            self.assertEqual(preflight.main(['unexpected']), 1)
        api.assert_not_called()

    def test_private_native_failure_is_reduced_to_exit_status_only(self):
        for failure in (OSError('private-native-detail'), KeyboardInterrupt()):
            stdout, stderr = io.StringIO(), io.StringIO()
            with patch.object(preflight.os, 'name', 'nt'), \
                    patch.object(preflight, 'Toolhelp', side_effect=failure), \
                    contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                self.assertEqual(preflight.main([]), 1)
            self.assertEqual(stdout.getvalue(), '')
            self.assertEqual(stderr.getvalue(), '')


@unittest.skipUnless(os.name == 'nt', 'requires the original Windows process API')
class NativeWindowsTests(unittest.TestCase):
    def test_actual_snapshot_contains_this_process_and_closes(self):
        self.assertIn(preflight.observe(preflight.Toolhelp(), os.getpid()), (0, 23))

    def test_actual_isolated_helper_completes_under_the_original_deadline(self):
        # Hosted controller tests run before any wallet/lab actor is launched.
        smoke.check_no_existing(Path(__file__).absolute().parents[2], dict(os.environ))


if __name__ == '__main__':
    unittest.main()
