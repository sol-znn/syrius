"""Run retained reader suites and discovery regressions without a global package."""

import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import sys
import unittest


FILES = ('test_inspect_chain321.py', 'test_inspect_wallet_inspection.py',
         'test_run_readonly_reader_tests.py', 'test_readonly_viewport_capture.py',
         'test_readonly_settings_capture.py')
EXPECTED = 98
DIRECTORY = Path(__file__).absolute().parents[2] / 'test/ci'


def namespace_observation():
    """Report only a category, never an import origin or private search path."""
    try:
        spec = importlib.util.find_spec('test')
        kind = 'MISSING' if spec is None else 'NAMESPACE' if spec.origin is None else 'REGULAR'
    except (ImportError, ValueError, AttributeError):
        kind = 'UNKNOWN'
    return dict(package=kind, project_namespace=not (DIRECTORY.parent / '__init__.py').is_file())


def load_suite():
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for name in FILES:
        suite.addTests(loader.discover(str(DIRECTORY), pattern=name))
    return suite, len(loader.errors)


def case_label(case):
    value = case.id()
    parts = value.split('.')
    file = parts[0] + '.py' if parts and parts[0] + '.py' in FILES else None
    method = parts[-1] if file is not None and re.fullmatch('test_[a-z0-9_]{1,180}', parts[-1]) else None
    return dict(file=file, method=method)


def run_suite(suite, load_errors=0):
    output = io.StringIO()
    result = unittest.TextTestRunner(stream=output, verbosity=1).run(suite)
    successful = (result.wasSuccessful() and result.testsRun == EXPECTED and load_errors == 0
        and not result.skipped and not result.expectedFailures and not result.unexpectedSuccesses)
    return dict(schema=1, scope='readonly_inspection_reader_cases', success=successful,
        tests=result.testsRun, expected=EXPECTED, failures=len(result.failures),
        errors=len(result.errors), skips=len(result.skipped), load_errors=load_errors,
        expected_failures=len(result.expectedFailures), unexpected_successes=len(result.unexpectedSuccesses),
        failed_cases=[case_label(case) for case, _ in result.failures[:5]],
        error_cases=[case_label(case) for case, _ in result.errors[:5]],
        output_sha256=hashlib.sha256(output.getvalue().encode()).hexdigest(),
        runtime_started=False, native_wallet_executions=0, native_node_executions=0)


def main():
    sys.dont_write_bytecode = True
    observed = namespace_observation()
    suite, errors = load_suite()
    report = run_suite(suite, errors)
    source = os.environ.get('GITHUB_SHA')
    if type(source) is str and re.fullmatch('[a-f0-9]{40}', source):
        report['source_sha'] = source
    report['namespace_observation'] = observed
    public = json.dumps(report, sort_keys=True, separators=(',', ':'))
    print(public)
    if len(public.encode('ascii')) <= 3800:
        print('::notice title=Readonly inspection reader controls::' + public)
    return 0 if report['success'] else 1


if __name__ == '__main__':
    if sys.argv[1:]:
        raise SystemExit(2)
    raise SystemExit(main())
