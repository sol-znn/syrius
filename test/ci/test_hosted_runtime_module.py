"""Literal CLI module loading, stopped before environment or transport work."""

import argparse
import contextlib
import importlib
import io
import json
from pathlib import Path
import runpy
import sys
import types
import unittest
from unittest import mock
import warnings

from tool.ci import hosted_chain321 as lab
from tool.ci import restored_wallet_run as restored


class _AdmissionObserved(BaseException):
    pass


class _TransportObserved(BaseException):
    pass


class RuntimeModuleTests(unittest.TestCase):
    def execute(self, *, fresh, parent, inspect=None):
        canonical = 'tool.ci.hosted_chain321'
        package = sys.modules['tool.ci']
        output = io.StringIO()
        observed = {}

        def parse(_parser, *args, **kwargs):
            module = sys.modules['__main__']
            observed['main'] = module
            if inspect is not None:
                def environment(*_args):
                    inspect(module)
                    raise _AdmissionObserved()
                module.require_environment = environment
            return argparse.Namespace(backend='native', admission_only=True)

        with mock.patch.dict(sys.modules), \
                mock.patch.object(package, 'hosted_chain321', parent), \
                mock.patch.object(argparse.ArgumentParser, 'parse_args', parse), \
                mock.patch.object(lab.subprocess, 'Popen') as launch, \
                mock.patch.object(lab.socket, 'create_connection') as connect, \
                warnings.catch_warnings(record=True), \
                contextlib.redirect_stdout(output):
            if fresh:
                sys.modules.pop(canonical)
            try:
                runpy.run_module(canonical, run_name='__main__', alter_sys=True)
            except _AdmissionObserved:
                observed['admission_reached'] = True
            except SystemExit as error:
                observed['exit'] = error.code
            launch.assert_not_called()
            connect.assert_not_called()
            observed['registry'] = sys.modules.get(canonical)
            observed['parent'] = getattr(package, 'hosted_chain321')
        self.assertIs(sys.modules[canonical], lab)
        self.assertIs(package.hosted_chain321, lab)
        observed['output'] = output.getvalue()
        return observed

    def test_literal_cli_owner_reaches_helpers_as_the_identical_native_class(self):
        def inspect(module):
            self.assertIs(importlib.import_module('tool.ci.hosted_chain321'), module)
            runtime = module.Native(mock.Mock(), Path('/synthetic/node'), {})
            for _ in module.ROLES:
                original = mock.Mock()
                original.process.poll.return_value = None
                runtime.originals.append(original)
            with mock.patch.object(module, 'make_transports',
                    side_effect=_TransportObserved()) as allocate:
                with self.assertRaises(_TransportObserved):
                    restored.chain_read(runtime)
                allocate.assert_called_once_with()
        value = self.execute(fresh=True, parent=None, inspect=inspect)
        self.assertTrue(value['admission_reached'])
        self.assertIs(value['registry'], value['main'])
        self.assertIs(value['parent'], value['main'])
        self.assertEqual(value['output'], '')

    def test_normal_import_binding_is_idempotent_without_replacing_classes(self):
        original = lab.Native
        self.assertIs(lab._bind_runtime_module(), lab)
        self.assertIs(lab._bind_runtime_module(), lab)
        self.assertIs(lab.Native, original)

    def test_existing_canonical_module_is_preserved_before_admission(self):
        value = self.execute(fresh=False, parent=lab)
        self.assertEqual(value['exit'], 1)
        self.assertNotIn('admission_reached', value)
        self.assertIs(value['registry'], lab)
        self.assertIs(value['parent'], lab)
        self.assertEqual(json.loads(value['output'])['error_codes'],
                         ['ENVIRONMENT_REFUSED'])

    def test_existing_parent_alias_is_preserved_before_registration(self):
        foreign = types.ModuleType('synthetic_foreign_controller')
        value = self.execute(fresh=True, parent=foreign)
        self.assertEqual(value['exit'], 1)
        self.assertNotIn('admission_reached', value)
        self.assertIsNone(value['registry'])
        self.assertIs(value['parent'], foreign)
        self.assertEqual(json.loads(value['output'])['error_codes'],
                         ['ENVIRONMENT_REFUSED'])
