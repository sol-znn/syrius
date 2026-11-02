"""Finite protocol policies; actual Hive and owned-process execution are separate."""

from pathlib import Path
import hashlib
import json
import unittest
from unittest import mock

from tool.ci import closed_wallet_pointer as pointer


def completed():
    return dict(schema=1, scope=pointer.SCOPE, complete=True, claim_once=True,
        originals_unchanged=True, cipher_unchanged=True, pointer_bound=True,
        child_exit=0, output_bytes=52, output_sha256='a' * 64, output_complete=True,
        forced=False, job_empty=True, private_manifest_sha256='b' * 64,
        native_reopen_qualified=False, seed_admitted=False)


class PointerPolicyTests(unittest.TestCase):
    def test_complete_binding_observations_do_not_qualify_native_reopen_or_seed(self):
        value = pointer.project(completed())
        self.assertTrue(value['complete'])
        self.assertFalse(value['native_reopen_qualified'])
        self.assertFalse(value['seed_admitted'])

    def test_absence_or_incomplete_binding_stays_unqualified(self):
        self.assertIsNone(pointer.project(None))
        value = dict(schema=1, scope=pointer.SCOPE, complete=False)
        self.assertEqual(pointer.project(value), value)
        with self.assertRaises(pointer.checkpoint.Refused):
            pointer.project(dict(value, pointer_bound=True))

    def test_private_or_missing_projection_fields_are_refused(self):
        value = completed()
        for candidate in (dict(value, wallet='private'),
                          {key: item for key, item in value.items() if key != 'child_exit'}):
            with self.subTest(fields=len(candidate)), self.assertRaises(pointer.checkpoint.Refused):
                pointer.project(candidate)

    def test_failed_forced_or_unclosed_child_cannot_supply_positive_binding(self):
        for change in (dict(child_exit=1), dict(child_exit=None), dict(child_exit=False),
                dict(forced=True), dict(job_empty=False), dict(output_complete=False),
                dict(claim_once=False), dict(cipher_unchanged=False),
                dict(originals_unchanged=False), dict(pointer_bound=False)):
            with self.subTest(change=change), self.assertRaises(pointer.checkpoint.Refused):
                pointer.project(dict(completed(), **change))

    def test_coerced_or_malformed_public_observations_are_refused(self):
        for change in (dict(schema=True), dict(output_bytes=True), dict(output_bytes=0),
                dict(output_bytes=2 * 1024**2 + 1), dict(output_sha256='private'),
                dict(private_manifest_sha256='A' * 64), dict(complete=1)):
            with self.subTest(change=change), self.assertRaises(pointer.checkpoint.Refused):
                pointer.project(dict(completed(), **change))

    def test_binding_data_cannot_be_promoted_to_reopened_wallet_or_seed_authority(self):
        for change in (dict(native_reopen_qualified=True), dict(seed_admitted=True)):
            with self.subTest(change=change), self.assertRaises(pointer.checkpoint.Refused):
                pointer.project(dict(completed(), **change))

    def test_unowned_local_execution_refuses_before_process_or_path_discovery(self):
        with mock.patch.object(pointer.subprocess, 'Popen') as launch, \
                mock.patch.object(pointer.checkpoint, 'ancestors') as discover:
            with self.assertRaises(Exception):
                pointer.run(Path('/fixture'), {}, mock.Mock(), Path('/copy'),
                            Path('/checkpoint'), lambda: True, lambda: 0)
        launch.assert_not_called()
        discover.assert_not_called()


class PointerDiagnosticTests(unittest.TestCase):
    def diagnostic(self, raw=b'CI_POINTER_ERROR:binding:read\r\n'):
        trace = pointer.PointerDiagnostic()
        trace.at('binding')
        trace.unexpected_line(raw)
        return trace

    def test_fixed_child_markers_retain_only_stage_detail_and_original_line_digest(self):
        for raw, phase, detail in (
                (b'CI_POINTER_ERROR:binding:read\r\n', 'binding', 'read'),
                (b'CI_POINTER_ERROR:gate\n', 'gate', None),
                (b'CI_POINTER_ERROR:unknown:unknown\n', 'unknown', 'unknown')):
            with self.subTest(phase=phase):
                value = self.diagnostic(raw).snapshot()
                self.assertEqual(value['child_phase'], phase)
                self.assertEqual(value['child_detail'], detail)
                self.assertEqual(value['output'], dict(code='POINTER_CHILD_REFUSED',
                    bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest()))

    def test_private_unhandled_output_is_classified_and_hashed_without_text(self):
        raw = b'Unhandled exception: synthetic private path and password\n'
        value = self.diagnostic(raw).snapshot()
        self.assertEqual(value['output']['code'], 'UNHANDLED_EXCEPTION')
        self.assertEqual(value['output']['sha256'], hashlib.sha256(raw).hexdigest())
        self.assertIsNone(value['child_phase'])
        self.assertNotIn('private', json.dumps(value))
        self.assertNotIn('password', json.dumps(value))

    def test_foreign_child_labels_cannot_supply_an_observed_step(self):
        for raw in (b'CI_POINTER_ERROR:private:read\n',
                    b'CI_POINTER_ERROR:binding:private\n',
                    b'CI_POINTER_ERROR:binding:read:private\n'):
            with self.subTest(size=len(raw)):
                value = self.diagnostic(raw).snapshot()
                self.assertIsNone(value['child_phase'])
                self.assertIsNone(value['child_detail'])
                self.assertEqual(value['output']['code'], 'UNCLASSIFIED_OUTPUT')

    def test_projection_refuses_private_fields_coercions_and_unknown_vocabulary(self):
        original = self.diagnostic().snapshot()
        changes = [dict(original, private='synthetic private'), dict(original, schema=True),
            dict(original, phase='private'), dict(original, child_detail='private'),
            dict(original, output=dict(original['output'], bytes=True)),
            dict(original, output=dict(original['output'], code='private')),
            dict(original, output=dict(original['output'], sha256='private'))]
        for value in changes:
            with self.subTest(fields=len(value)), self.assertRaises(pointer.checkpoint.Refused):
                pointer.diagnostic_projection(value)

    def test_diagnostic_cannot_promote_an_incomplete_binding_to_live_authority(self):
        value = dict(schema=1, scope=pointer.SCOPE, complete=False,
                     diagnostic=self.diagnostic().snapshot())
        self.assertFalse(pointer.project(value)['complete'])
        self.assertNotIn('seed_admitted', pointer.project(value))
        with self.assertRaises(pointer.checkpoint.Refused):
            pointer.project(dict(completed(), diagnostic=value['diagnostic']))
        with self.assertRaises(pointer.checkpoint.Refused):
            pointer.project(dict(value, pointer_bound=True))

    def test_phase_and_first_output_are_retained_without_mutable_snapshot_aliases(self):
        trace = self.diagnostic()
        original = trace.snapshot()
        copy = trace.snapshot()
        copy['output']['bytes'] = 1
        self.assertEqual(trace.snapshot(), original)
        with self.assertRaises(pointer.checkpoint.Refused):
            trace.unexpected_line(b'CI_POINTER_ERROR:binding:write\n')
        with self.assertRaises(pointer.checkpoint.Refused):
            trace.at('synthetic private phase')
        self.assertEqual(trace.snapshot(), original)

    def test_empty_nonbyte_and_oversized_output_cannot_enter_the_record(self):
        for raw in (None, '', b'', bytearray(b'input'),
                    b'a' * (pointer.debug.protocol.MAX_LINE + 2)):
            trace = pointer.PointerDiagnostic()
            with self.subTest(kind=type(raw).__name__), self.assertRaises(pointer.checkpoint.Refused):
                trace.unexpected_line(raw)
            self.assertIsNone(trace.snapshot()['output'])


if __name__ == '__main__':
    unittest.main()
