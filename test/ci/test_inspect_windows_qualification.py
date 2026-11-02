"""Memory-only original-receipt controls; no network, native process or scratch."""

import base64
import contextlib
import copy
import io
import json
from pathlib import Path
import struct
import unittest
from unittest import mock
import zipfile
import zlib

from tool.ci import inspect_windows_qualification as inspect


HEAD, TREE, RUN = 'a' * 40, 'b' * 40, 123


def receipt():
    return dict(required=True, exit_code=0, exit_observed=True, forced_kill=False,
        output_complete=True, output_overflow=False, output_bytes=50, seconds=1.25,
        success=True, error_codes=[])


def baseline():
    return dict(schema=1, scope='github_hosted_windows_baseline', source_sha=HEAD,
        source_tree=TREE, run=dict(id=str(RUN), attempt='1'), success=True, error_codes=[],
        checks=dict.fromkeys(inspect.baseline.CHECKS, True),
        stages={name: receipt() for names in inspect.CHECK_STAGES.values() for name in names},
        doctor=dict(scope='windows_desktop_only', windows_version='pass', visual_studio='pass'),
        analysis={name: dict(errors=0, warnings=0, infos=3 if name == 'analyze_root' else 0)
                  for name in ('analyze_root', 'analyze_vendored')},
        tests=dict(passed=50, failed=0, skipped=2, hidden=3, terminal_events=55,
                   error_events=0, terminal_success=True),
        localization_correspondence={name: dict(files=3, sha256='d' * 64)
                                     for name in ('before', 'after')},
        libraries={name: dict(sha256='c' * 64, map_exports=True)
                   for name in inspect.baseline.LIBRARIES}, private_context='synthetic-private-context')


def log(report):
    return b'2026-10-26T12:00:00.000Z private tool text\n' + (
        '2026-10-26T12:00:01.0000000Z ' + json.dumps(report) + '\n').encode()


def pixels():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return (b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', 1280, 780, 8, 6, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress((b'\x00' + bytes(1280 * 4)) * 780))
        + chunk(b'IEND', b''))


def entry_report(data):
    value = inspect.entry.Report()
    value.source_sha, value.source_tree = HEAD, TREE
    value.run_id, value.run_attempt = str(RUN), '1'
    value.runner_sha256 = value.dart_kernel_sha256 = 'c' * 64
    value.checks = dict.fromkeys(inspect.entry.CHECKS, True)
    value.caption_checks = dict.fromkeys(inspect.entry.CAPTION_CHECKS, True)
    value.captures = [dict(file=name, sha256=inspect.archive.sha(data), bytes=len(data))
                      for name in inspect.entry.FILES]
    value.exit_code, value.exit_observed, value.output_complete = 0, True, True
    value.output_bytes = 100
    return value.public()


def package(report, data, *, extra=None, omitted=None, duplicate=False):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w', compression=zipfile.ZIP_STORED) as zipped:
        zipped.writestr('manifest.json', json.dumps(report))
        for item in report['captures']:
            if item['file'] != omitted:
                zipped.writestr(item['file'], data)
        if extra is not None:
            zipped.writestr(extra, b'synthetic')
        if duplicate:
            zipped.writestr('manifest.json', json.dumps(report))
    return stream.getvalue()


class WindowsQualificationTests(unittest.TestCase):
    def test_original_baseline_receipts_preserve_counts_infos_and_scope(self):
        report = baseline()
        value = inspect.baseline_projection(report, HEAD, TREE, RUN)
        self.assertTrue(value['artifact_reported_success'])
        self.assertEqual(value['tests']['passed'], 50)
        self.assertEqual(value['tests']['skipped'], 2)
        self.assertEqual(value['analysis']['analyze_root']['infos'], 3)
        self.assertFalse(value['runtime_started'])
        self.assertFalse(value['wallet_qualified'])
        self.assertNotIn('synthetic-private-context', json.dumps(value))
        with contextlib.redirect_stdout(io.StringIO()):
            inspect.emit('Hosted baseline inspection', value)

    def test_original_failed_test_and_forced_exit_stay_negative(self):
        report = baseline()
        report['checks'] = dict.fromkeys(inspect.baseline.CHECKS, False)
        report['success'], report['error_codes'] = False, ['TESTS_FAILED']
        report['stages']['unit_widget_tests'].update(exit_code=1, forced_kill=True,
            success=False, error_codes=['COMMAND_TIMEOUT'])
        report['tests'].update(passed=49, failed=1, terminal_success=False)
        value = inspect.baseline_projection(report, HEAD, TREE, RUN)
        self.assertFalse(value['artifact_reported_success'])
        self.assertEqual(value['original_error_codes'], ['TESTS_FAILED'])
        self.assertEqual(value['commands']['unit_widget_tests']['exit_code'], 1)
        self.assertTrue(value['commands']['unit_widget_tests']['forced_kill'])
        self.assertEqual(value['tests']['failed'], 1)

    def test_failed_root_locations_keep_the_failure_and_refuse_private_fields(self):
        report = baseline()
        report['checks'] = dict.fromkeys(inspect.baseline.CHECKS, False)
        report['success'], report['error_codes'] = False, ['TESTS_FAILED']
        report['tests'].update(passed=49, failed=1, error_events=1,
            terminal_success=False)
        locations = dict(status='OBSERVED', total=1,
            items=[dict(file='welcome_surface_test.dart', line=554,
                kind='ASSERTION', category='ASSERTION')])
        report['test_failures'] = locations
        value = inspect.baseline_projection(report, HEAD, TREE, RUN)
        self.assertEqual(value['test_failures'], locations)
        self.assertFalse(value['artifact_reported_success'])
        self.assertEqual(value['tests']['failed'], 1)
        invalid = [dict(locations, private='private'), dict(locations, total=True),
            dict(locations, status='private'), dict(locations, total=0)]
        for change in (dict(file='private'), dict(line=True), dict(line=0),
                dict(line=1000000), dict(kind='private'), dict(category='private'),
                dict(error='private'), dict(file=None)):
            invalid.append(dict(locations, items=[dict(locations['items'][0], **change)]))
        for item in invalid:
            with self.subTest(fields=len(item)), self.assertRaises(inspect.archive.Refused):
                inspect.baseline_projection(dict(report, test_failures=item), HEAD, TREE, RUN)
        positive = baseline()
        positive['test_failures'] = locations
        with self.assertRaises(inspect.archive.Refused):
            inspect.baseline_projection(positive, HEAD, TREE, RUN)

    def test_baseline_cannot_substitute_identity_exit_stage_or_correspondence(self):
        for change in ('source', 'attempt', 'exit', 'stage', 'analysis', 'library', 'localization'):
            report = baseline()
            if change == 'source':report['source_sha'] = 'e' * 40
            elif change == 'attempt':report['run']['attempt'] = '2'
            elif change == 'exit':report['stages']['build_debug']['exit_code'] = False
            elif change == 'stage':del report['stages']['build_release']
            elif change == 'analysis':report['analysis']['analyze_root']['warnings'] = 1
            elif change == 'library':report['libraries']['source']['sha256'] = 'e' * 64
            else:report['localization_correspondence']['after']['sha256'] = 'e' * 64
            with self.subTest(change=change), self.assertRaises(inspect.archive.Refused):
                inspect.baseline_projection(report, HEAD, TREE, RUN)

    def test_job_log_requires_one_timestamped_original_frame(self):
        raw = log(baseline())
        self.assertEqual(inspect.log_report(raw, 'github_hosted_windows_baseline'), baseline())
        for invalid in (b'', raw + raw, json.dumps(baseline()).encode(),
                        b'2026-10-26T12:00:00Z {}\n', b'x' * (inspect.MAX_LOG + 1)):
            with self.subTest(size=len(invalid)), self.assertRaises(inspect.archive.Refused):
                inspect.log_report(invalid, 'github_hosted_windows_baseline')

    def test_four_entry_pngs_are_checked_without_visual_match_claims(self):
        data = pixels()
        report = entry_report(data)
        raw = package(report, data)
        value = inspect.entry_archive(raw, inspect.archive.sha(raw), len(raw), HEAD, TREE, RUN)
        self.assertTrue(value['artifact_reported_success'])
        self.assertEqual(value['capture_count'], 4)
        self.assertEqual(value['visual_matches'], 0)
        self.assertFalse(value['runtime_started'])
        with contextlib.redirect_stdout(io.StringIO()):
            inspect.emit('Hosted entry inspection', value)

    def test_entry_digest_missing_extra_and_invalid_pixels_are_refused(self):
        data = pixels()
        report = entry_report(data)
        for kind in ('digest', 'missing', 'extra', 'pixels'):
            selected = copy.deepcopy(report)
            body = data
            if kind == 'pixels':
                body = b'not screenshot pixels'
                for item in selected['captures']:
                    item.update(sha256=inspect.archive.sha(body), bytes=len(body))
            raw = package(selected, body,
                omitted=inspect.entry.FILES[0] if kind == 'missing' else None,
                extra='unexpected.txt' if kind == 'extra' else None)
            digest = 'e' * 64 if kind == 'digest' else inspect.archive.sha(raw)
            with self.subTest(kind=kind), self.assertRaises((inspect.archive.Refused, inspect.entry.Failure)):
                inspect.entry_archive(raw, digest, len(raw), HEAD, TREE, RUN)

    def test_entry_cannot_replace_original_process_or_caption_facts(self):
        for change in ('source', 'exit', 'forced', 'caption', 'identity'):
            report = entry_report(pixels())
            if change == 'source':report['source_sha'] = 'e' * 40
            elif change == 'exit':report['exit_code'] = False
            elif change == 'forced':report['forced_kill'] = True
            elif change == 'caption':report['caption']['observations']['native_restored'] = False
            else:report['runner_sha256'] = None
            with self.subTest(change=change), self.assertRaises(inspect.archive.Refused):
                inspect.entry_projection(report, HEAD, TREE, RUN)

    def test_partial_entry_and_nonzero_exit_are_not_completed_by_inspection(self):
        report = entry_report(pixels())
        report.update(captures=[], capture_count=0, exit_code=1, forced_kill=True,
            complete=False, success=False, status='UNKNOWN', error_codes=['ENTRY_UNAVAILABLE'])
        report['checks'] = dict.fromkeys(inspect.entry.CHECKS, False)
        raw = package(report, b'')
        value = inspect.entry_archive(raw, inspect.archive.sha(raw), len(raw), HEAD, TREE, RUN)
        self.assertFalse(value['artifact_reported_success'])
        self.assertEqual(value['capture_count'], 0)
        self.assertEqual(value['exit_code'], 1)
        self.assertTrue(value['forced_kill'])

    def test_local_admission_refuses_before_network(self):
        with mock.patch.dict(inspect.os.environ, {}, clear=True), \
                mock.patch.object(inspect.archive, 'Client') as client, \
                contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(inspect.main(), 1)
        client.assert_not_called()
        lines = output.getvalue().splitlines()
        self.assertEqual(json.loads(lines[0])['phase'], 'environment')
        self.assertEqual(lines[1], '::notice title=Hosted Windows inspection refusal::' + lines[0])

    def _read_original(self, *, entry_change=None, entry_count=1, failed_root=False,
                       baseline_conclusion='success', baseline_change=None, baseline_count=1):
        data = pixels()
        raw = package(entry_report(data), data)
        original_report = baseline()
        if failed_root:
            original_report['success'] = False
            original_report['error_codes'] = ['TESTS_FAILED']
            original_report['checks']['unit_widget_tests'] = False
            original_report['checks']['debug_build'] = False
            original_report['checks']['release_build'] = False
            original_report['tests'].update(passed=49, failed=1, error_events=1,
                                            terminal_success=False)
            original_report['stages']['unit_widget_tests'].update(exit_code=1,
                success=False, error_codes=[])
        original_log = log(original_report)
        calls = []

        class Client:
            def json(self, path):
                calls.append(path)
                if path == '/actions/runs/123':
                    return dict(id=RUN, head_sha=HEAD, run_attempt=1, workflow_id=381413107,
                        event='workflow_dispatch', status='completed', repository=dict(full_name='edgepillar/syrius'))
                if path == '/git/commits/' + HEAD:
                    return dict(sha=HEAD, tree=dict(sha=TREE))
                if path.startswith('/contents/tool/ci/'):
                    name = path.split('/')[-1].partition('?')[0]
                    body = Path(inspect.__file__).with_name(name).read_bytes()
                    return dict(type='file', path='tool/ci/' + name, encoding='base64', size=len(body),
                                content=base64.b64encode(body).decode('ascii'))
                if path == '/actions/runs/123/attempts/1/jobs?per_page=20':
                    original_baseline = dict(id=5, name='Hosted Windows baseline', run_id=RUN,
                        head_sha=HEAD, status='completed', conclusion=baseline_conclusion, steps=[])
                    if baseline_change is not None:
                        original_baseline.update(baseline_change)
                    original_entry = dict(id=6, name='Ordinary Windows entry captures', run_id=RUN,
                        head_sha=HEAD, status='completed', conclusion='success', steps=[])
                    if entry_change is not None:
                        original_entry.update(entry_change)
                    jobs = ([dict(original_baseline) for _ in range(baseline_count)]
                            + [dict(original_entry) for _ in range(entry_count)])
                    return dict(total_count=len(jobs), jobs=jobs)
                if path == '/actions/runs/123/artifacts?per_page=20':
                    return dict(total_count=1, artifacts=[dict(id=7, expired=False,
                        name='windows-entry-capture-' + HEAD + '-123-1',
                        workflow_run=dict(id=RUN, head_sha=HEAD), size_in_bytes=len(raw),
                        digest='sha256:' + inspect.archive.sha(raw))])
                raise AssertionError('unexpected metadata query')

            def read(self, url, *, redirect=False, authenticated=True, cap=262144):
                calls.append(url)
                if redirect:
                    self_url = ('log' if url.endswith('/jobs/5/logs') else
                                'entry' if url.endswith('/artifacts/7/zip') else None)
                    if self_url is None or not authenticated:
                        raise AssertionError('unexpected redirect')
                    return 'https://synthetic.blob.core.windows.net/' + self_url
                if authenticated:
                    raise AssertionError('credentials forwarded to artifact host')
                body = original_log if url.endswith('/log') else raw
                if len(body) > cap:
                    raise AssertionError('unbounded read')
                return body

        environment = dict(GITHUB_ACTIONS='true', SYRIUS_HOSTED_RUNNER='github-hosted',
            GITHUB_EVENT_NAME='workflow_dispatch', GITHUB_REPOSITORY='edgepillar/syrius',
            WINDOWS_INSPECT_RUN='123', WINDOWS_INSPECT_HEAD=HEAD, GH_TOKEN='synthetic')
        with mock.patch.dict(inspect.os.environ, environment, clear=True), \
                mock.patch.object(inspect.archive, 'Client', return_value=Client()), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            status = inspect.main()
        return status, calls, output.getvalue()

    def test_complete_reader_uses_only_original_metadata_and_bounded_memory_reads(self):
        status, calls, output = self._read_original()
        self.assertEqual(status, 0)
        self.assertEqual(len(calls), 8 + len(inspect.PRODUCERS))
        notices = [line for line in output.splitlines() if line.startswith('::notice')]
        self.assertEqual(len(notices), 2)
        self.assertTrue(all(len(line.partition('::')[2].encode()) < 3900 for line in notices))
        self.assertNotIn('synthetic-private-context', output)

    def test_baseline_only_reader_keeps_original_result_without_entry_transport(self):
        status, calls, output = self._read_original(entry_change=dict(conclusion='skipped'))
        self.assertEqual(status, 0)
        self.assertEqual(len(calls), 5 + len(inspect.PRODUCERS))
        self.assertFalse(any('/artifacts' in call for call in calls))
        notices = [line for line in output.splitlines() if line.startswith('::notice')]
        self.assertEqual(len(notices), 2)
        self.assertTrue(notices[0].startswith('::notice title=Hosted baseline inspection::'))
        self.assertTrue(notices[1].startswith('::notice title=Hosted entry not selected::'))
        skipped = json.loads(notices[1].split('::', 2)[2])
        self.assertEqual(skipped, dict(scope='retained_windows_entry_not_selected',
            inspection_only=True, runtime_started=False, wallet_qualified=False,
            source_head=HEAD, source_tree=TREE, source_run_id=RUN, source_attempt=1,
            original_job_id=6, original_job_conclusion='skipped',
            entry_qualified=False, entry_artifacts_read=0))
        self.assertNotIn('synthetic-private-context', output)

    def test_skipped_entry_requires_one_original_completed_source_bound_job(self):
        for options in (dict(entry_count=0), dict(entry_count=2),
                dict(entry_change=dict(conclusion='skipped', head_sha='c' * 40)),
                dict(entry_change=dict(conclusion='skipped', run_id=RUN + 1)),
                dict(entry_change=dict(conclusion='skipped', status='in_progress')),
                dict(entry_change=dict(conclusion='skipped', steps=[dict(name='Started')]))):
            with self.subTest(options=options):
                status, calls, output = self._read_original(**options)
            self.assertEqual(status, 1)
            self.assertFalse(any(call.endswith('/logs') for call in calls))
            self.assertEqual(json.loads(output.splitlines()[0])['phase'], 'job_metadata')
            self.assertNotIn('::notice title=Hosted baseline inspection::', output)

    def test_entry_only_reader_keeps_skipped_baseline_unqualified_and_reads_no_log(self):
        status, calls, output = self._read_original(baseline_conclusion='skipped')
        self.assertEqual(status, 0)
        self.assertEqual(len(calls), 6 + len(inspect.PRODUCERS))
        self.assertFalse(any('/logs' in call for call in calls))
        notices = [line for line in output.splitlines() if line.startswith('::notice')]
        self.assertEqual(len(notices), 2)
        self.assertTrue(notices[0].startswith('::notice title=Hosted baseline not selected::'))
        self.assertTrue(notices[1].startswith('::notice title=Hosted entry inspection::'))
        skipped = json.loads(notices[0].split('::', 2)[2])
        self.assertEqual(skipped, dict(scope='retained_windows_baseline_not_selected',
            inspection_only=True, runtime_started=False, wallet_qualified=False,
            source_head=HEAD, source_tree=TREE, source_run_id=RUN, source_attempt=1,
            original_job_id=5, original_job_conclusion='skipped',
            baseline_qualified=False, baseline_logs_read=0))
        entry = json.loads(notices[1].split('::', 2)[2])
        self.assertTrue(entry['artifact_reported_success'])
        self.assertEqual(entry['capture_count'], 4)
        self.assertEqual(entry['visual_matches'], 0)
        self.assertFalse(entry['runtime_started'])
        self.assertFalse(entry['wallet_qualified'])
        self.assertNotIn('synthetic-private-context', output)

    def test_skipped_baseline_requires_bound_empty_job_and_one_selected_producer(self):
        for options in (dict(baseline_count=0), dict(baseline_count=2),
                dict(baseline_change=dict(head_sha='c' * 40)),
                dict(baseline_change=dict(run_id=RUN + 1)),
                dict(baseline_change=dict(status='in_progress')),
                dict(baseline_change=dict(steps=[dict(name='Started')])),
                dict(entry_change=dict(conclusion='skipped'))):
            with self.subTest(options=options):
                status, calls, output = self._read_original(
                    baseline_conclusion='skipped', **options)
            self.assertEqual(status, 1)
            self.assertFalse(any('/artifacts' in call or '/logs' in call for call in calls))
            self.assertEqual(json.loads(output.splitlines()[0])['phase'], 'job_metadata')
            self.assertNotIn('::notice title=Hosted baseline not selected::', output)
            self.assertNotIn('::notice title=Hosted entry inspection::', output)

    def test_original_skipped_expression_name_keeps_entry_only_scope(self):
        status, calls, output = self._read_original(baseline_conclusion='skipped',
            baseline_change=dict(name=inspect.SKIPPED_BASELINE_JOB))
        self.assertEqual(status, 0)
        self.assertFalse(any('/logs' in call for call in calls))
        notices = [line for line in output.splitlines() if line.startswith('::notice')]
        self.assertEqual(len(notices), 2)
        skipped = json.loads(notices[0].split('::', 2)[2])
        self.assertFalse(skipped['baseline_qualified'])
        self.assertEqual(skipped['baseline_logs_read'], 0)
        self.assertEqual(skipped['original_job_conclusion'], 'skipped')
        self.assertEqual(json.loads(notices[1].split('::', 2)[2])['capture_count'], 4)

    def test_skipped_expression_cannot_alias_an_executed_or_ambiguous_job(self):
        options = [dict(baseline_conclusion=value,
            baseline_change=dict(name=inspect.SKIPPED_BASELINE_JOB))
            for value in ('success', 'failure')]
        options += [dict(baseline_conclusion='skipped', baseline_count=2,
            baseline_change=dict(name=inspect.SKIPPED_BASELINE_JOB)),
            dict(baseline_conclusion='skipped',
                baseline_change=dict(name=inspect.SKIPPED_BASELINE_JOB + ' ')),
            dict(baseline_conclusion='skipped',
                baseline_change=dict(name=inspect.SKIPPED_BASELINE_JOB, steps=[{}]))]
        for change in options:
            with self.subTest(change=change):
                status, calls, output = self._read_original(**change)
            self.assertEqual(status, 1)
            self.assertFalse(any('/artifacts' in call or '/logs' in call for call in calls))
            self.assertEqual(json.loads(output.splitlines()[0])['phase'], 'job_metadata')
            self.assertNotIn('::notice title=Hosted baseline not selected::', output)

    def test_baseline_only_reader_preserves_the_original_failed_suite(self):
        status, calls, output = self._read_original(entry_change=dict(conclusion='skipped'),
            failed_root=True, baseline_conclusion='failure')
        self.assertEqual(status, 0)
        self.assertFalse(any('/artifacts' in call for call in calls))
        original = json.loads(output.splitlines()[0])
        self.assertFalse(original['artifact_reported_success'])
        self.assertEqual(original['original_job_conclusion'], 'failure')
        self.assertEqual(original['original_error_codes'], ['TESTS_FAILED'])
        self.assertEqual(original['tests']['failed'], 1)
        self.assertEqual(original['tests']['error_events'], 1)
        self.assertFalse(original['tests']['terminal_success'])
        self.assertFalse(original['original_checks']['unit_widget_tests'])

    def test_baseline_only_reader_cannot_accept_a_false_success_job(self):
        status, calls, output = self._read_original(entry_change=dict(conclusion='skipped'),
            failed_root=True, baseline_conclusion='success')
        self.assertEqual(status, 1)
        self.assertFalse(any('/artifacts' in call for call in calls))
        self.assertEqual(json.loads(output.splitlines()[0])['phase'], 'baseline_log')
        self.assertNotIn('::notice title=Hosted baseline inspection::', output)
        self.assertNotIn('::notice title=Hosted entry not selected::', output)



def failed_entry_progress_report():
    report = entry_report(pixels())
    report['checks'].update(welcome_dark=False, welcome_light=False,
                           import_dark=False, import_light=False, entry_restored=False)
    report['caption']['observations'] = dict.fromkeys(inspect.entry.CAPTION_CHECKS, False)
    report.update(captures=[], capture_count=0, complete=False, success=False, status='UNKNOWN',
        error_codes=['HTTP_FAILED', 'ENTRY_INVALID'],
        first_command_failure=dict(category='EXCHANGE_FAILED', code='HTTP_FAILED',
            http_status=None, phase='capture_welcome_dark', resize=None),
        cleanup_failures=[dict(category='GUARD_FAILED', code='ENTRY_INVALID',
            http_status=200, phase='entry_verify', resize=None)])
    effect = dict(phase='original-native-frame', future='succeeded',
                  failed=False, milliseconds=21001)
    report['capture_progress'] = dict(schema=1, screen='welcome', theme='dark', scopes=1,
        completedCaptures=1, effects=1, last=effect, slowest=dict(effect),
        artworkCount=2, imageCreated=True, restoring=True, restored=True, held=False)
    report['transport_failure'] = dict(phase='capture_welcome_dark', kind='TIMEOUT')
    return report


class EntryProgressInspectionTests(unittest.TestCase):
    def test_fixed_pipe_trace_cannot_heal_the_original_failed_entry(self):
        report = failed_entry_progress_report()
        event = dict(schema=1, screen='welcome', theme='dark', scopes=1, effects=1,
            phase='original-renderer-image', boundary='begin',
            future='not_returned', failed=False, milliseconds=0)
        report['effect_trace'] = dict(schema=1, status='OBSERVED', events=1,
                                     last=event, last_ended=None)
        value = inspect.entry_projection(report, HEAD, TREE, RUN)
        self.assertEqual(value['effect_trace'], report['effect_trace'])
        self.assertEqual(value['capture_count'], 0)
        self.assertEqual(value['original_error_codes'], report['error_codes'])
        self.assertFalse(value['artifact_reported_success'])
        self.assertEqual(value['visual_matches'], 0)

    def test_private_or_contradictory_pipe_summaries_are_refused(self):
        report = failed_entry_progress_report()
        event = dict(schema=1, screen='welcome', theme='dark', scopes=1, effects=1,
            phase='original-renderer-image', boundary='begin',
            future='not_returned', failed=False, milliseconds=0)
        trace = dict(schema=1, status='OBSERVED', events=1, last=event, last_ended=None)
        invalid = [dict(trace, private='private'), dict(trace, events=True),
            dict(trace, events=2),
            dict(trace, events=0), dict(trace, status='private'),
            dict(trace, last=dict(event, error='private')),
            dict(trace, last=dict(event, phase='private')),
            dict(trace, last_ended=event)]
        for value in invalid:
            with self.subTest(fields=len(value)), self.assertRaises(inspect.archive.Refused):
                inspect.entry_projection(dict(report, effect_trace=value), HEAD, TREE, RUN)

    def test_diagnostics_cannot_replace_received_images_or_heal_original_failure(self):
        report = failed_entry_progress_report()
        value = inspect.entry_projection(report, HEAD, TREE, RUN)
        self.assertEqual(value['capture_count'], 0)
        self.assertEqual(value['capture_progress']['completedCaptures'], 1)
        self.assertEqual(value['transport_failure']['kind'], 'TIMEOUT')
        self.assertEqual(value['first_command_failure'], report['first_command_failure'])
        self.assertEqual(value['original_error_codes'], ['HTTP_FAILED', 'ENTRY_INVALID'])
        self.assertFalse(value['artifact_reported_success'])
        self.assertEqual(value['visual_matches'], 0)
        with contextlib.redirect_stdout(io.StringIO()):
            inspect.emit('Hosted entry inspection', value)

    def test_private_or_coerced_progress_and_unbound_transport_kinds_are_refused(self):
        report = failed_entry_progress_report()
        for field, change in (
                ('capture_progress', dict(owner='private-context')),
                ('capture_progress', dict(scopes=True)),
                ('capture_progress', dict(completedCaptures=2)),
                ('transport_failure', dict(kind='private-context')),
                ('transport_failure', dict(kind=True)),
                ('transport_failure', dict(phase='private-context')),
                ('transport_failure', dict(error='private-context'))):
            invalid = dict(report, **{field: dict(report[field], **change)})
            with self.subTest(field=field), self.assertRaises(inspect.archive.Refused):
                inspect.entry_projection(invalid, HEAD, TREE, RUN)
        invalid = dict(report, error_codes=['ENTRY_INVALID'])
        with self.assertRaises(inspect.archive.Refused):
            inspect.entry_projection(invalid, HEAD, TREE, RUN)


if __name__ == '__main__':
    unittest.main()
