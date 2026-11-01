"""Exercise discovery under a foreign package and retain finite failure facts."""

import importlib.machinery
import json
import sys
import types
import unittest
from unittest import mock

from tool.ci import run_readonly_reader_tests as controls


class ReaderControlTests(unittest.TestCase):
    def test_exact_suites_do_not_depend_on_an_external_regular_test_package(self):
        foreign = types.ModuleType('test')
        foreign.__path__ = []
        foreign.__spec__ = importlib.machinery.ModuleSpec('test', loader=None,
            origin='/fixture/runtime/test/__init__.py', is_package=True)
        with mock.patch.dict(sys.modules, {'test': foreign}):
            for name in list(sys.modules):
                if name.startswith('test.') or name in (
                        'test_inspect_chain321', 'test_inspect_wallet_inspection',
                        'test_windows_wallet_inspection'):
                    sys.modules.pop(name)
            suite, errors = controls.load_suite()
            self.assertIs(sys.modules['test'], foreign)
        self.assertEqual(errors, 0)
        self.assertEqual(suite.countTestCases(), 98)

    def test_original_failures_keep_counts_without_private_messages_or_paths(self):
        def failed():
            raise AssertionError('Synthetic private wallet input')

        def errored():
            raise ValueError('Synthetic private profile path')

        suite = unittest.TestSuite([unittest.FunctionTestCase(failed), unittest.FunctionTestCase(errored)])
        value = controls.run_suite(suite)
        self.assertFalse(value['success'])
        self.assertEqual((value['tests'], value['failures'], value['errors']), (2, 1, 1))
        self.assertEqual(value['expected'], 98)
        self.assertNotIn('private', json.dumps(value))
        self.assertEqual(value['failed_cases'], [dict(file=None, method=None)])
        for stale in (95, 96, 97, 99):
            suite = unittest.TestSuite(unittest.FunctionTestCase(lambda: None)
                for _ in range(stale))
            observed = controls.run_suite(suite)
            self.assertEqual(observed['tests'], stale)
            self.assertEqual(observed['failures'], 0)
            self.assertFalse(observed['success'])

    def test_namespace_observation_never_exports_the_original_import_origin(self):
        spec = importlib.machinery.ModuleSpec('test', loader=None,
            origin='/fixture/private/runtime/test/__init__.py', is_package=True)
        with mock.patch.object(controls.importlib.util, 'find_spec', return_value=spec):
            value = controls.namespace_observation()
        self.assertEqual(value['package'], 'REGULAR')
        self.assertNotIn('private', json.dumps(value))
        self.assertNotIn('origin', value)


if __name__ == '__main__':
    unittest.main()
