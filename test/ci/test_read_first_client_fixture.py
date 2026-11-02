"""Fixture integrity and normal/uncertain restoration; no process or scratch."""

import contextlib
import hashlib
from pathlib import Path
import unittest
from unittest import mock

from tool.ci import hosted_chain321 as lab
from tool.ci import read_first_client_fixture as fixture


class ClientFixtureTests(unittest.TestCase):
    def test_only_the_helper_changes_and_all_seven_test_bodies_stay_exact(self):
        suffix = b''.join(('func TestSynthetic%d(t *testing.T) { preserveAssertion() }\n' % i).encode()
                          for i in range(7))
        original = b'func helper() {\n' + fixture.OLD + b'}\n' + suffix
        expected = original.replace(fixture.OLD, fixture.NEW)
        patch = b'synthetic patch'
        with mock.patch.multiple(fixture, ORIGINAL_SHA256=hashlib.sha256(original).hexdigest(),
                PATCHED_SHA256=hashlib.sha256(expected).hexdigest(),
                PATCH_SHA256=hashlib.sha256(patch).hexdigest(), TEST_BODIES_SHA256=hashlib.sha256(suffix).hexdigest()):
            self.assertEqual(fixture.patched(original, patch), expected)
            for data, supplied in ((original + b'changed', patch), (original, patch+b'changed')):
                with self.assertRaises(fixture.Refused):fixture.patched(data, supplied)
            with mock.patch.object(fixture, 'TEST_BODIES_SHA256', '0'*64), self.assertRaises(fixture.Refused):
                fixture.patched(original, patch)

    def test_restored_failure_or_held_state_cannot_become_success(self):
        for changed in ('held', 'failure', 'incomplete', 'forced', 'bool_exit'):
            value = fixture.pending()
            value.update(phase='restored', all_seven_test_bodies_unchanged=True,
                original_restored=True, test_exit=0, test_output_complete=True, test_forced=False)
            self.assertTrue(fixture.validate(value, required=True)['original_restored'])
            if changed == 'held':value.update(phase='held', original_restored=False)
            elif changed == 'failure':value['test_exit'] = 1
            elif changed == 'incomplete':value['test_output_complete'] = False
            elif changed == 'forced':value['test_forced'] = True
            else:value['test_exit'] = False
            with self.subTest(changed=changed), self.assertRaises(fixture.Refused):
                fixture.validate(value, required=True)

    def run_fixture(self, *, failure=False, forced=False, changed=False):
        state = dict(content=b'original')
        report, commands = {}, mock.Mock(originals=[])
        commands.run.return_value = b''  # read-only gofmt check
        target = Path('/fixture/node') / fixture.TEST_PATH
        def regular(path, *args):
            return state['content'] if path == target else b'patch'
        def git(source, *args):
            if args[:2] == ('diff', '--name-only'):return fixture.TEST_PATH
            if args[0] == 'apply' and '--check' not in args:
                state['content'] = b'original' if '--reverse' in args else b'adapted'
            return ''
        commands.git.side_effect = git
        original_failure = lab.Failure('COMMAND_FAILED')
        def run(*args):
            commands.originals.append(mock.Mock(receipt=dict(exit_code=1 if failure else 0,
                output_complete=True, forced=forced)))
            if changed:state['content'] = b'unrelated change'
            if failure:
                report['upstream_stop_failure'] = dict(exit_code=1, output_complete=True, forced=forced)
                raise original_failure
            report['upstream_stop_regressions'] = dict(passed=True, tests=list(lab.SHUTDOWN_TESTS), skips=0)
        with contextlib.ExitStack() as stack:
            stack.enter_context(mock.patch.object(lab, 'regular', side_effect=regular))
            stack.enter_context(mock.patch.object(fixture, 'patched', return_value=b'adapted'))
            stack.enter_context(mock.patch.object(lab, 'source_matches'))
            stack.enter_context(mock.patch.object(lab, 'run_shutdown_tests', side_effect=run))
            caught = None
            try:lab.run_wallet_shutdown_tests(commands, Path('/fixture/repo'), Path('/fixture/node'), report)
            except lab.Failure as error:caught = error
        reverse = [call for call in commands.git.call_args_list if '--reverse' in call.args]
        return state, report, caught, original_failure, reverse

    def test_normal_success_and_failure_restore_only_the_exact_fixture(self):
        for failure in (False, True):
            state, report, caught, original_failure, reverse = self.run_fixture(failure=failure)
            with self.subTest(failure=failure):
                self.assertEqual(state['content'], b'original')
                self.assertEqual(len(reverse), 2)
                self.assertTrue(report['upstream_client_fixture']['original_restored'])
                self.assertIs(caught, original_failure if failure else None)
                if failure:self.assertEqual(report['upstream_stop_failure']['exit_code'], 1)

    def test_forced_or_changed_input_is_held_without_reverse_apply(self):
        for offered in (dict(failure=True, forced=True), dict(changed=True)):
            state, report, caught, _, reverse = self.run_fixture(**offered)
            with self.subTest(offered=offered):
                self.assertIsNotNone(caught)
                self.assertEqual(reverse, [])
                self.assertFalse(report['upstream_client_fixture']['original_restored'])
                self.assertEqual(report['upstream_client_fixture']['phase'], 'held')
                self.assertEqual(state['content'], b'unrelated change' if offered.get('changed') else b'adapted')
