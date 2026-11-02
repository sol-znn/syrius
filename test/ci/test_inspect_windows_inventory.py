"""In-memory negative-evidence projection; no network, native process or scratch."""

import contextlib
import copy
import io
import json
import unittest
from unittest import mock

from tool.ci import inspect_windows_inventory as inspect


def manifest():
    return dict(scope='github_hosted_windows_inventory', schema=1,
        source_sha='a' * 40, source_tree='b' * 40, run=dict(id='123', attempt='1'),
        baseline_qualified=False, wallet_qualified=False, success=False,
        inventory=inspect.baseline.inventory_projection({}),
        checks=dict(source=True, source_unchanged=True, inventory=False),
        error_codes=['INVENTORY_INCOMPLETE'], stages=dict(inventory_windows=dict(
            required=False, exit_code=1, exit_observed=True, forced_kill=True,
            output_complete=True, output_overflow=False, output_bytes=0, seconds=30.1,
            success=False, error_codes=['COMMAND_TIMEOUT'])),
        private_context='synthetic-private-context')


class InventoryInspectionTests(unittest.TestCase):
    def test_original_timeout_remains_negative_after_successful_projection(self):
        value = inspect.project(manifest(), 'a' * 40, 'b' * 40, 123)
        self.assertFalse(value['artifact_reported_success'])
        self.assertTrue(value['probes']['inventory_windows']['forced_kill'])
        self.assertEqual(value['probes']['inventory_windows']['error_codes'], ['COMMAND_TIMEOUT'])
        self.assertFalse(value['runtime_started'])
        self.assertFalse(value['wallet_qualified'])
        self.assertNotIn('synthetic-private-context', json.dumps(value))
        self.assertLess(len(json.dumps(value).encode()), 3800)

    def test_source_scope_and_original_exit_facts_cannot_be_replaced(self):
        for change in ('source', 'tree', 'attempt', 'wallet', 'exit', 'raw', 'success'):
            report = copy.deepcopy(manifest())
            if change == 'source':report['source_sha'] = 'c' * 40
            elif change == 'tree':report['source_tree'] = 'c' * 40
            elif change == 'attempt':report['run']['attempt'] = '2'
            elif change == 'wallet':report['wallet_qualified'] = True
            elif change == 'exit':report['stages']['inventory_windows']['exit_code'] = False
            elif change == 'raw':report['stages']['inventory_windows']['raw'] = 'private'
            else:report['success'] = True
            with self.subTest(change=change), self.assertRaises(inspect.archive.Refused):
                inspect.project(report, 'a' * 40, 'b' * 40, 123)

    def test_local_admission_refuses_before_an_api_client(self):
        with mock.patch.dict(inspect.os.environ, {}, clear=True), \
                mock.patch.object(inspect.archive, 'Client') as client, \
                contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(inspect.main(), 1)
        client.assert_not_called()
        self.assertEqual(json.loads(output.getvalue())['code'], 'INSPECTION_REFUSED')
