"""Memory-only admission controls; no SDK, native process or scratch is created."""

import contextlib
import io
import json
from pathlib import Path
import unittest
from unittest import mock

from tool.ci import prepare_harness_tests as focused


def environment():
    return dict(GITHUB_ACTIONS='true', RUNNER_OS='Windows',
        RUNNER_ENVIRONMENT='github-hosted', GITHUB_EVENT_NAME='workflow_dispatch',
        GITHUB_REPOSITORY='edgepillar/syrius', GITHUB_REF='refs/heads/redesign',
        GITHUB_SHA='a'*40, GITHUB_WORKSPACE='/fixture', SYSTEMROOT='/system',
        GITHUB_RUN_ID='123', GITHUB_RUN_ATTEMPT='1',
        SYRIUS_HOSTED_RUNNER='github-hosted', SYRIUS_HARNESS_TESTS_ONLY='true')


class HarnessAdmissionTests(unittest.TestCase):
    def test_unowned_environment_refuses_before_any_profile_sdk_or_child(self):
        with mock.patch.dict(focused.os.environ, {}, clear=True), \
                mock.patch.object(focused.debug, 'sdk') as sdk, \
                mock.patch.object(focused.baseline, 'fresh_environment') as profile, \
                mock.patch.object(focused.baseline, 'run_bounded') as child, \
                contextlib.redirect_stdout(io.StringIO()) as output:
            result = focused.main([])
        self.assertEqual(result, 1)
        sdk.assert_not_called()
        profile.assert_not_called()
        child.assert_not_called()
        self.assertEqual(json.loads(output.getvalue().splitlines()[0])['code'],
                         'ENVIRONMENT_REFUSED')

    def test_only_the_explicit_hosted_fork_branch_is_admitted(self):
        _, source, repo = focused.admit(environment(), platform='nt', cwd=Path('/fixture'))
        self.assertEqual(source, 'a'*40)
        self.assertEqual(repo, Path('/fixture'))
        for change in (dict(GITHUB_EVENT_NAME='push'), dict(SYRIUS_HARNESS_TESTS_ONLY='false'),
                       dict(SYRIUS_WINDOWS_WALLET_TOUR='true'), dict(GITHUB_REF='refs/heads/dev'),
                       dict(GITHUB_REPOSITORY='sol-znn/syrius'),
                       dict(SYRIUS_HOSTED_RUNNER='self-hosted')):
            with self.subTest(change=change):
                with self.assertRaises(Exception) as refused:
                    focused.admit(dict(environment(), **change), platform='nt', cwd=Path('/fixture'))
                self.assertEqual(getattr(refused.exception, 'code', None) or str(refused.exception),
                                 'ENVIRONMENT_REFUSED')

    def test_wrong_platform_or_workspace_refuses(self):
        for platform, cwd in (('posix', '/fixture'), ('nt', '/other')):
            with self.subTest(platform=platform, cwd=cwd):
                with self.assertRaises(Exception) as refused:
                    focused.admit(environment(), platform=platform, cwd=Path(cwd))
                self.assertEqual(getattr(refused.exception, 'code', None) or str(refused.exception),
                                 'ENVIRONMENT_REFUSED')

    def test_admission_only_checks_source_without_sdk_profile_or_dependency_commands(self):
        admitted = environment(), 'a'*40, Path('/fixture')
        with mock.patch.object(focused, 'admit', return_value=admitted), \
                mock.patch.object(focused.debug.bounded, 'verify_source') as source, \
                mock.patch.object(focused.debug.entry, 'source_tree', return_value='b'*40), \
                mock.patch.object(focused, 'no_native_allocations', return_value=True), \
                mock.patch.object(focused.debug, 'sdk') as sdk, \
                mock.patch.object(focused.baseline, 'fresh_environment') as profile, \
                mock.patch.object(focused.baseline, 'run_bounded') as child, \
                contextlib.redirect_stdout(io.StringIO()) as output:
            result = focused.main(['--admission-only'])
        self.assertEqual(result, 0)
        source.assert_called_once()
        sdk.assert_not_called()
        profile.assert_not_called()
        child.assert_not_called()
        value = json.loads(output.getvalue().splitlines()[0])
        self.assertTrue(value['success'])
        self.assertEqual(value['source_sha'], 'a'*40)
        self.assertEqual(value['native_wallet_executions'], 0)
        self.assertEqual(value['commands'], [])

    def test_native_destination_presence_is_not_a_dependency_restore(self):
        with mock.patch.object(Path, 'exists', return_value=False), \
                mock.patch.object(Path, 'is_symlink', return_value=False):
            self.assertTrue(focused.no_native_allocations(Path('/fixture')))
        for method in ('exists', 'is_symlink'):
            with mock.patch.object(Path, 'exists', return_value=False), \
                    mock.patch.object(Path, 'is_symlink', return_value=False), \
                    mock.patch.object(Path, method, return_value=True):
                self.assertFalse(focused.no_native_allocations(Path('/fixture')))
