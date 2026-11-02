"""Memory-only phase and privacy controls; no runtime or disk scratch."""

import json
import unittest

from tool.ci import lab_asset_progress as progress


class AssetProgressTests(unittest.TestCase):
    def test_every_original_prefix_keeps_its_last_phase_without_implying_process_success(self):
        for count in range(len(progress.PHASES) + 1):
            raw = b''.join(progress.PREFIX + phase.encode() + b'\n'
                           for phase in progress.PHASES[:count])
            value = progress.project(raw)
            self.assertEqual(progress.validate(value), value)
            self.assertEqual(value['events'], count)
            self.assertEqual(value['phase'], progress.PHASES[count - 1] if count else None)
            self.assertEqual(value['script_complete'], count == len(progress.PHASES))
            self.assertNotIn('exit_code', value)

    def test_unknown_duplicate_reordered_and_oversized_events_cannot_be_published(self):
        for raw in (None, b'x' * 8193, progress.PREFIX + b'/fixture/private\n',
                    progress.PREFIX + b'COMPLETE\n', (progress.PREFIX + b'STARTED\n') * 2):
            value = progress.project(raw)
            self.assertEqual(value['status'], 'REFUSED')
            self.assertIsNone(value['phase'])
            self.assertNotIn('private', json.dumps(value))

    def test_unrelated_stderr_never_enters_the_finite_projection(self):
        value = progress.project(b'/fixture/private/error\n' + progress.PREFIX + b'STARTED\n')
        self.assertEqual(value['phase'], 'STARTED')
        self.assertNotIn('private', json.dumps(value))
        self.assertEqual(progress.project(b'/fixture/private/error\n')['status'], 'NOT_OBSERVED')

    def test_retained_values_reject_boolean_counts_raw_fields_and_false_completion(self):
        original = progress.project(progress.PREFIX + b'STARTED\n')
        for change in (dict(events=True), dict(events=2), dict(phase='/fixture/private'),
                       dict(script_complete=True), dict(status='private'), dict(raw='private')):
            with self.subTest(change=change), self.assertRaises(ValueError):
                progress.validate(dict(original, **change))
