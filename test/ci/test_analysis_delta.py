"""Memory-only source-location, multiplicity and bounded disclosure controls."""

import io
import json
import unittest
from unittest.mock import patch

from tool.ci import analysis_delta as delta


def output(path='lib/view.dart', *, code='prefer_const_constructors', line=10):
    path = path.replace('\\', '\\\\').replace('|', '\\|')
    path = path.replace('\n', '\\n').replace('\r', '\\r')
    return ('INFO|LINT|' + code.upper() + '|' + path + '|' + str(line)
            + '|3|1|synthetic private message\n').encode()


INFO = dict(errors=0, warnings=0, infos=1)


class AnalysisDeltaTests(unittest.TestCase):
    def test_source_declaration_infos_use_the_same_tracked_path_guard(self):
        for path in ('pubspec.yaml', 'analysis_options.yaml',
                     'patched_packages/reown_core-1.3.8/pubspec.yaml'):
            with self.subTest(path=path):
                counts, rows = delta.diagnostics(output(path, code='sort_pub_dependencies'),
                                                '/fixture', {path}, INFO)
                self.assertEqual(counts, INFO)
                self.assertEqual(rows, [('info', path, 'sort_pub_dependencies', 10, 3)])
        with self.assertRaises(delta.Refused):
            delta.diagnostics(output('credentials.yaml'), '/fixture', {'credentials.yaml'}, INFO)

    def test_unqualified_environment_refuses_before_any_child_or_sdk(self):
        out = io.StringIO()
        with patch.dict(delta.os.environ, {'GH_TOKEN': 'synthetic private credential'}, clear=True), \
                patch.object(delta.baseline, 'run_bounded') as child, \
                patch('sys.stdout', new=out):
            result = delta.main()
        self.assertEqual(result, 1)
        child.assert_not_called()
        value = json.loads(out.getvalue().splitlines()[0])
        self.assertFalse(value['success'])
        self.assertEqual(value['code'], 'ENVIRONMENT_REFUSED')
        self.assertEqual(value['commands'], [])
        self.assertNotIn('credential', out.getvalue())

    def test_projection_never_contains_message_or_absolute_source_root(self):
        raw = output('C:\\fixture\\lib\\view.dart').replace(b'message', b'message\xff')
        counts, rows = delta.diagnostics(raw,
                                        'C:/fixture', {'lib/view.dart'}, INFO)
        self.assertEqual(counts, dict(errors=0, warnings=0, infos=1))
        self.assertEqual(rows, [('info', 'lib/view.dart', 'prefer_const_constructors', 10, 3)])
        value = json.dumps(delta.changes([], rows))
        self.assertNotIn('private', value)
        self.assertNotIn('fixture', value)

    def test_outside_untracked_parent_and_uri_paths_are_refused(self):
        for path in ('C:/other/lib/view.dart', '../lib/view.dart',
                     'lib/other.dart', 'https://fixture.invalid/lib/view.dart',
                     '//host/private.dart'):
            with self.subTest(path=path), self.assertRaises(delta.Refused):
                delta.diagnostics(output(path), 'C:/fixture', {'lib/view.dart'}, INFO)

    def test_incomplete_duplicate_and_malformed_output_is_not_attributed(self):
        for raw in (output().replace(b'INFO', b'WARNING'), output() + output(),
                    output(code='private/invalid'), b'INFO|LINT|INCOMPLETE', b'\xff'):
            with self.subTest(size=len(raw)), self.assertRaises(delta.Refused):
                delta.diagnostics(raw, '/fixture', {'lib/view.dart'}, INFO)

    def test_shifted_locations_do_not_invent_new_findings(self):
        before = [('info', 'lib/view.dart', 'lint', 1, 2)]
        after = [('info', 'lib/view.dart', 'lint', 10, 20)]
        self.assertEqual(delta.changes(before, after), [])

    def test_multiplicities_and_removed_groups_preserve_signed_deltas(self):
        old = [('info', 'lib/view.dart', 'old_lint', 1, 1)]
        new = [('info', 'lib/view.dart', 'new_lint', 2, 1)] * 2
        groups = delta.changes(old, new)
        self.assertEqual({row['code']: row['delta'] for row in groups},
                         dict(old_lint=-1, new_lint=2))
        self.assertEqual(sum(row['delta'] for row in groups), len(new) - len(old))

    def test_notice_truncation_is_explicit_and_retains_total_group_count(self):
        rows = [('info', 'lib/view.dart', 'lint_' + str(index), index + 1, 1)
                for index in range(100)]
        value = delta.notice_projection(dict(scope='fixture'), delta.changes([], rows))
        self.assertTrue(value['truncated'])
        self.assertEqual(value['total_groups'], 100)
        self.assertLess(len(value['groups']), 100)
        self.assertLessEqual(len(json.dumps(value, separators=(',', ':'), sort_keys=True).encode()), 3800)

    def test_locations_are_capped_without_changing_group_multiplicity(self):
        rows = [('info', 'lib/view.dart', 'lint', line, 1) for line in range(1, 10)]
        group, = delta.changes([], rows)
        self.assertEqual(group['after'], 9)
        self.assertEqual(len(group['locations']), 3)
        self.assertTrue(group['locations_truncated'])

    def test_clean_analysis_is_an_empty_observation(self):
        self.assertEqual(delta.diagnostics(b'', '/fixture', {'lib/view.dart'},
            dict(errors=0, warnings=0, infos=0)), (dict(errors=0, warnings=0, infos=0), []))


if __name__ == '__main__':
    unittest.main()
