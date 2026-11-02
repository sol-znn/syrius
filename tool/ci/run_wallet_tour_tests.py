"""Finite policy tests and a hosted-only full controller suite."""

import argparse
import json
import os
from pathlib import Path
import unittest

from .run_debug_tests import execute_suite


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--all-controllers', action='store_true')
    options = parser.parse_args()
    directory = str(Path(__file__).absolute().parents[2] / 'test/ci')
    if options.all_controllers:
        from .windows_debug_loop import entry
        try:
            parent, _ = entry.require_ci(os.environ, None, platform=os.name)
            if (parent.get('GITHUB_EVENT_NAME') != 'workflow_dispatch'
                    or parent.get('SYRIUS_HOSTED_RUNNER') != 'github-hosted'):
                raise ValueError()
        except Exception:
            print(json.dumps(dict(scope='hosted_controller_admission', success=False,
                                  code='ENVIRONMENT_REFUSED')))
            return 1
        suite = unittest.TestLoader().discover(directory, pattern='test_*.py')
        return execute_suite(suite, scope='hosted_controller_cases',
            title='Hosted controller tests', wallet_node_scope=True)
    suite = unittest.TestLoader().discover(directory, pattern='test_windows_wallet_tour.py')
    return execute_suite(suite, scope='wallet_tour_inmemory_cases',
                         title='Wallet tour policy tests')


if __name__ == '__main__':
    raise SystemExit(main())
