"""Synthetic in-memory reader cases; no native producer, SDK or network runs."""

import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import stat
import unittest
from unittest import mock
import warnings
import zipfile

from tool.ci import inspect_wallet_inspection as reader
import test_inspect_chain321 as lab_fixtures
import test_windows_wallet_inspection as wallet_fixtures


def lab_report():
    value = lab_fixtures.InspectionTests.wallet_stop_report()
    value.update(application_tree='b' * 40, run_id='1', success=True,
        commands=[], error_codes=[],
        wallet_tour_requested=False, wallet_tour=None,
        runtime_phase='wallet_inspection',
        wallet_inspection_requested=True, wallet_inspection=None,
        wallet_qualified=False, seed_admitted=False)
    value['checks'] = dict.fromkeys(reader.archive.CHECKS, True)
    value['node_exits'] = [dict(exit_code=0, output_complete=True, forced=False,
        stack_role=role, node_diagnostics=[], private_log_projection=dict(status='READ'))
        for role in reader.archive.ROLES]
    return value


def child_report(*, positive=True):
    value = wallet_fixtures.report()
    if not positive:
        value.update(success=False, inspection_qualified=False, phase='onboarding_and_inspection',
            errors=['ENTRY_FAILED'], application_exit=None, entry_exit=1,
            captures=value['captures'][:1], tours={}, locales={}, stalls={},
            wallet_admission=None, auxiliary_cleanup=None, owned_job_active_at_close=None)
        value['checks'].update(wallet_bound=False, tours_complete=False, captures=False,
            application_exit=False, auxiliary_cleanup=False)
        value['owned_job_images_before_close']['status'] = 'UNKNOWN'
    return value


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode('ascii')


def bind(lab, child):
    lab['wallet_inspection'] = dict(success=child['success'], phase=child['phase'],
        checks=copy.deepcopy(child['checks']), errors=list(child['errors']),
        captured_pages=len(child['captures']),
        visited_pages=sum(len(v['tour']['visited']) for v in child['tours'].values()),
        manifest_sha256=reader.archive.sha(encode(child)))
    return lab


def packed(files):
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_STORED) as zipped:
        for name, raw, mode in files:
            info = zipfile.ZipInfo(name)
            info.external_attr = (mode | 0o600) << 16
            zipped.writestr(info, raw)
    return out.getvalue()


def pair(*, positive=True):
    child, lab = child_report(positive=positive), lab_report()
    pixels = wallet_fixtures.png()
    for row in child['captures']:
        row.update(bytes=len(pixels), sha256=reader.archive.sha(pixels))
    if not positive:
        lab.update(success=False, error_codes=['WALLET_INSPECTION_FAILED'])
    bind(lab, child)
    files = [('manifest.json', encode(child), stat.S_IFREG)]
    if positive:
        files += [('captures/' + row['theme'] + '/' + row['page'] + '.png', pixels, stat.S_IFREG)
                  for row in child['captures']]
    return child, lab, files


def jobs(*, positive=True):
    steps = [dict(name=name, number=i + 1, status='completed', conclusion='success')
             for i, name in enumerate((*reader.PREFLIGHT, reader.RUNTIME))]
    if not positive:
        steps[-1]['conclusion'] = 'failure'
    return dict(total_count=1, jobs=[dict(id=44, name=reader.JOB, head_sha='a' * 40,
        run_id=1, run_attempt=1, status='completed', conclusion='success' if positive else 'failure',
        steps=steps)])


class ReaderTests(unittest.TestCase):
    def inspect(self, child, lab, files):
        raw = packed(files)
        parent = reader.owned_lab(lab, 'a' * 40, 'b' * 40, 1)
        return reader.unpack(raw, reader.archive.sha(raw), len(raw),
            'a' * 40, 'b' * 40, 1, lab, parent)

    def test_literal_home_archive_cannot_borrow_generic_or_foreign_state(self):
        pixels = wallet_fixtures.png()
        script = b'synthetic public script'
        manifest = wallet_fixtures.home_manifest(pixels, script)
        originals = [('manifest.json', encode(manifest), stat.S_IFREG)] + [
            (row['file'], pixels, stat.S_IFREG) for row in manifest['captures']]

        def inspect(files, *, head='a' * 40, tree='b' * 40, run=1,
                    script_digest=None, reference=None, digest=None, size=None):
            raw = packed(files)
            ref = reference or wallet_fixtures.home_reference(reader.archive.sha(files[0][1]))
            return reader.unpack_home_catalog(raw, digest or reader.archive.sha(raw),
                len(raw) if size is None else size, head, tree, run, ref,
                script_digest or reader.archive.sha(script))

        observed = inspect(originals)
        self.assertEqual(observed['verified_png_count'], 2)
        self.assertEqual(observed['filenames'],
            ['01-home-rest-dark.png', '01-home-rest-light.png'])
        self.assertFalse(observed['catalog_capture_qualified'])
        self.assertFalse(observed['parent_closure_qualified'])
        self.assertFalse(observed['atomic_frame_qualified'])
        self.assertEqual(observed['visual_matches'], 0)
        for change in ({'head': 'c' * 40}, {'tree': 'c' * 40}, {'run': 2},
                       {'script_digest': 'd' * 64}, {'digest': 'f' * 64}, {'size': 1},
                       {'reference': wallet_fixtures.home_reference('f' * 64)}):
            with self.subTest(change=change), self.assertRaises(reader.archive.Refused):
                inspect(originals, **change)
        bad_files = [originals[:2], originals + [('unregistered.bin', b'x', stat.S_IFREG)],
            [originals[0], originals[1], originals[1]],
            [originals[0], originals[1], (originals[2][0], pixels, stat.S_IFLNK)],
            [originals[0], (originals[1][0], pixels[:-1], stat.S_IFREG), originals[2]],
            pair()[2]]
        for files in bad_files:
            with self.subTest(names=[f[0] for f in files]), self.assertRaises(reader.archive.Refused):
                with warnings.catch_warnings():
                    warnings.simplefilter('ignore', UserWarning)
                    inspect(files)
        duplicate = b'{"scope":"Synthetic private value",' + encode(manifest)[1:]
        files = [('manifest.json', duplicate, stat.S_IFREG), *originals[1:]]
        with self.assertRaises(reader.archive.Refused):
            inspect(files)
        for change in ({'schema': True}, {'wallet_qualified': True},
                       {'private_profile': 'Synthetic private path'}):
            value = dict(copy.deepcopy(manifest), **change)
            files = [('manifest.json', encode(value), stat.S_IFREG), *originals[1:]]
            with self.subTest(manifest=change), self.assertRaises(reader.producer.Refused):
                inspect(files)

    def test_readonly_parent_needs_explicit_scope_and_cannot_adopt_financial_owners(self):
        lab = lab_report()
        with self.assertRaises(reader.archive.Refused):
            reader.archive.project(lab, 'native', 'a' * 40, 1,
                reader.archive.UPSTREAM_NODE_SHA, expected_patched=True)
        for change in (dict(wallet_tour_requested=True), dict(wallet_tour={}),
                       dict(seed_admitted=True), dict(wallet_reopen={}),
                       dict(native_stack_diagnostic=False), dict(wallet_inspection_requested=False)):
            with self.subTest(change=change), self.assertRaises(reader.archive.Refused):
                reader.owned_lab(dict(lab, **change), 'a' * 40, 'b' * 40, 1)

    def test_parent_success_needs_all_five_original_normal_complete_exits(self):
        lab = lab_report()
        value = reader.owned_lab(lab, 'a' * 40, 'b' * 40, 1)
        self.assertTrue(value['original_lab_closure_qualified'])
        for fault in ('forced', 'unknown', 'missing', 'incomplete'):
            changed = copy.deepcopy(lab)
            if fault == 'missing':
                changed['node_exits'].pop()
            else:
                changed['node_exits'][0].update({
                    'forced': dict(forced=True), 'unknown': dict(exit_code=None),
                    'incomplete': dict(output_complete=False)}[fault])
            with self.subTest(fault=fault), self.assertRaises(reader.archive.Refused):
                reader.owned_lab(changed, 'a' * 40, 'b' * 40, 1)

    def test_twenty_four_original_pngs_are_bound_but_do_not_grant_visual_matches(self):
        child, lab, files = pair()
        value = self.inspect(child, lab, files)
        self.assertEqual(value['verified_png_count'], 24)
        self.assertTrue(value['artifact_reported_success'])
        self.assertFalse(value['native_inspection_qualified'])
        self.assertFalse(value['runtime_started'])
        self.assertFalse(value['wallet_qualified'])
        self.assertFalse(value['financial_send_qualified'])
        self.assertEqual(value['visual_matches'], 0)
        self.assertEqual(value['visited_pages'], dict(dark=12, light=12))
        observed = value['_layout_observation']
        self.assertEqual(observed['scope'], 'retained_readonly_shot_layout_observation')
        self.assertEqual(observed['pages'], list(reader.producer.PAGES))
        self.assertEqual(observed['targets'], list(reader.LAYOUT_TARGETS))
        self.assertEqual(observed['sample_count'], 24)
        self.assertFalse(observed['atomic_frame_qualified'])
        self.assertEqual(observed['visual_matches'], 0)
        self.assertEqual(observed['original_layout_or_raster_cause'], 'NOT_ESTABLISHED')
        self.assertEqual(observed['rows']['dark'][0], [0, None] * 6 + [True])
        richer = child_report()
        for theme in reader.producer.THEMES:
            for page in richer['tours'][theme]['tour']['visited']:
                for boundary in ('before', 'after'):
                    for row in page['layout'][boundary]:
                        row.update(status='OBSERVED', rect=[-32768, -32768, 32768, 32768])
        measured = reader.layout_projection(richer, 'a' * 40, 'b' * 40, 1)
        self.assertEqual(measured['rows']['dark'][0],
            [1, -32768, 1, 32768, 1, -32768] * 2 + [True])
        measured.update(archive_sha256='c' * 64, manifest_sha256='d' * 64,
            producer_job_id=44, metadata_revalidated=True,
            producer_source_files_verified=len(reader.SOURCE_FILES), all_original_png_digests_verified=True)
        self.assertLessEqual(len(encode(measured)), 3800)
        for bad_head, bad_tree, bad_run in (('c' * 40, 'b' * 40, 1),
                ('a' * 40, 'd' * 40, 1), ('a' * 40, 'b' * 40, 2)):
            with self.assertRaises(reader.archive.Refused):
                reader.layout_projection(richer, bad_head, bad_tree, bad_run)

        for change in ({'extra': 'Synthetic private content'}, {'schema': True},
                       {'unchanged': False}):
            child, lab, files = pair()
            child['tours']['dark']['tour']['visited'][0]['layout'].update(change)
            bind(lab, child)
            files[0] = ('manifest.json', encode(child), stat.S_IFREG)
            with self.subTest(change=change), self.assertRaises(reader.producer.Refused):
                self.inspect(child, lab, files)


    def test_failed_manifest_retains_partial_and_unknown_outcomes_without_pixels(self):
        child, lab, files = pair(positive=False)
        value = self.inspect(child, lab, files)
        self.assertEqual(value['reported_capture_count'], 1)
        self.assertEqual(value['verified_png_count'], 0)
        self.assertIsNone(value['application_exit'])
        self.assertFalse(value['artifact_reported_success'])
        self.assertEqual(value['original_errors'], ['ENTRY_FAILED'])
        self.assertFalse(value['original_lab_closure_qualified'])

    def test_unknown_duplicate_directory_and_link_members_are_refused(self):
        child, lab, files = pair(positive=False)
        for extra in (('profile.json', b'private fixture', stat.S_IFREG),
                      ('manifest.json', encode(child), stat.S_IFREG),
                      ('captures/', b'x', stat.S_IFDIR),
                      ('captures/dark/dashboard.png', b'x', stat.S_IFLNK)):
            with self.subTest(name=extra[0]), self.assertRaises(reader.archive.Refused):
                with warnings.catch_warnings():
                    warnings.simplefilter('ignore', UserWarning)
                    self.inspect(child, lab, files + [extra])

    def test_missing_or_changed_original_pixels_cannot_complete_the_archive(self):
        child, lab, files = pair()
        for fault in ('missing', 'hash', 'extra'):
            changed = list(files)
            if fault == 'missing':
                changed.pop()
            elif fault == 'hash':
                changed[-1] = (changed[-1][0], b'changed image', stat.S_IFREG)
            else:
                changed.append(('captures/dark/unknown.png', b'x', stat.S_IFREG))
            with self.subTest(fault=fault), self.assertRaises(reader.archive.Refused):
                self.inspect(child, lab, changed)

    def test_archive_digest_size_and_coerced_metadata_are_refused_before_consumption(self):
        child, lab, files = pair(positive=False)
        raw = packed(files)
        parent = reader.owned_lab(lab, 'a' * 40, 'b' * 40, 1)
        for digest, size in (('c' * 64, len(raw)), (reader.archive.sha(raw), True),
                             (reader.archive.sha(raw), len(raw) + 1)):
            with self.subTest(size=size), self.assertRaises(reader.archive.Refused):
                reader.unpack(raw, digest, size, 'a' * 40, 'b' * 40, 1, lab, parent)

    def test_private_expanded_or_foreign_wallet_receipts_are_refused(self):
        for change in (dict(private_profile='synthetic private data'),
                       dict(source_sha='c' * 40), dict(source_tree='c' * 40),
                       dict(run_id='2'), dict(run_attempt='2')):
            child, lab, files = pair(positive=False)
            child.update(change)
            bind(lab, child)
            files[0] = ('manifest.json', encode(child), stat.S_IFREG)
            with self.subTest(change=change), self.assertRaises((reader.archive.Refused, reader.producer.Refused)):
                self.inspect(child, lab, files)

    def test_parent_receipt_cannot_borrow_another_manifest_or_page_count(self):
        for change in (dict(manifest_sha256='e' * 64), dict(captured_pages=True),
                       dict(visited_pages=1), dict(success=True)):
            child, lab, files = pair(positive=False)
            lab['wallet_inspection'].update(change)
            with self.subTest(change=change), self.assertRaises(reader.archive.Refused):
                self.inspect(child, lab, files)

    def test_false_owner_mode_or_closure_cannot_be_hidden_by_all_page_metadata(self):
        for fault in ('wallet', 'sdk', 'locale', 'exit', 'empty_page'):
            child, lab, files = pair()
            if fault == 'wallet':
                child['wallet_admission']['nativeFrameObserved'] = False
            elif fault == 'sdk':
                child['sdk_admission']['status'] = 'PENDING'
            elif fault == 'locale':
                child['locales']['dark']['language'] = 'ar'
            elif fault == 'exit':
                child['application_exit'] = None
            else:
                child['tours']['dark']['tour']['visited'][0]['nodes'] = 0
            bind(lab, child)
            files[0] = ('manifest.json', encode(child), stat.S_IFREG)
            with self.subTest(fault=fault), self.assertRaises((reader.archive.Refused, reader.producer.Refused)):
                self.inspect(child, lab, files)

    def test_source_blob_compatibility_refuses_partial_changed_or_truncated_trees(self):
        raw = b'synthetic source'
        blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
        tree = dict(sha='b' * 40, truncated=False, tree=[dict(path=n, mode='100644',
            type='blob', sha=blob) for n in reader.SOURCE_FILES])
        with mock.patch.object(reader.producer, 'read_original', return_value=raw):
            reader.source_files(Path('/fixture'), tree, 'b' * 40)
            for fault in ('partial', 'changed', 'truncated', 'alias'):
                value = copy.deepcopy(tree)
                if fault == 'partial':
                    value['tree'].pop()
                elif fault == 'truncated':
                    value['truncated'] = True
                elif fault == 'alias':
                    value['tree'][0]['mode'] = '120000'
                else:
                    value['tree'][0]['sha'] = 'e' * 40
                with self.subTest(fault=fault), self.assertRaises(reader.archive.Refused):
                    reader.source_files(Path('/fixture'), value, 'b' * 40)

    def test_job_metadata_cannot_borrow_another_attempt_or_skipped_preflight(self):
        value = jobs()
        reader.selected_job(value, 'a' * 40, 1)
        for fault in ('attempt', 'source', 'preflight', 'duplicate', 'order', 'other_job'):
            changed = copy.deepcopy(value)
            job = changed['jobs'][0]
            if fault == 'attempt':
                job['run_attempt'] = True
            elif fault == 'source':
                job['head_sha'] = 'c' * 40
            elif fault == 'preflight':
                job['steps'][0]['conclusion'] = 'skipped'
            elif fault == 'duplicate':
                changed['jobs'].append(copy.deepcopy(job)); changed['total_count'] += 1
            elif fault == 'order':
                job['steps'][1]['number'] = job['steps'][0]['number']
            else:
                changed['jobs'].append(dict(name='another active producer', status='completed',
                    conclusion='success')); changed['total_count'] += 1
            with self.subTest(fault=fault), self.assertRaises(reader.archive.Refused):
                reader.selected_job(changed, 'a' * 40, 1)

    def test_artifact_metadata_binds_original_digest_attempt_and_head(self):
        item = dict(id=1, name='expected', expired=False, digest='sha256:' + 'c' * 64,
            size_in_bytes=100, workflow_run=dict(id=1, head_sha='a' * 40))
        reader.artifact(dict(total_count=1, artifacts=[item]), 'expected', 'a' * 40, 1)
        for change in (dict(expired=True), dict(size_in_bytes=True), dict(digest='private value'),
                       dict(workflow_run=dict(id=2, head_sha='a' * 40))):
            with self.subTest(change=change), self.assertRaises(reader.archive.Refused):
                reader.artifact(dict(total_count=1, artifacts=[dict(item, **change)]),
                    'expected', 'a' * 40, 1)

    def run_main(self, *, positive=True, parent_failed=False, mutate_after=False,
                 child_missing=False, auxiliary_forced=False):
        child, lab, files = pair(positive=positive)
        if auxiliary_forced:
            child['forced_cleanup'] = child['auxiliary_cleanup']['forced'] = True
            child['auxiliary_cleanup']['receipts'] = [dict(role='msvc_telemetry',
                image_sha256='e' * 64, forced=True, termination_requested=True,
                termination_succeeded=True, actual_exit=reader.producer.debug.HELPER_EXIT_MARKER,
                exit_observed=True, stdio_captured=False)]
            child['auxiliary_cleanup']['observation'] = dict(stage='complete',
                image_class='VCTIP', image_bytes=514528, path_match=True)
            bind(lab, child)
            files[0] = ('manifest.json', encode(child), stat.S_IFREG)
        if parent_failed:
            lab.update(success=False, error_codes=['STOP_UNKNOWN'])
            lab['checks']['stopped'] = False
            lab['node_exits'][0].update(exit_code=None, output_complete=False, forced=True)
        if child_missing:
            lab.update(success=False, error_codes=['WALLET_INSPECTION_FAILED'], wallet_inspection=None)
        source = b'synthetic source'
        home_pixels = wallet_fixtures.png()
        home = wallet_fixtures.home_manifest(home_pixels, source)
        home_manifest = encode(home)
        if not child_missing:
            child['home_catalog'] = (wallet_fixtures.home_reference(reader.archive.sha(home_manifest))
                                     if positive else None)
            bind(lab, child)
            files[0] = ('manifest.json', encode(child), stat.S_IFREG)
        original_success = positive and not parent_failed and not child_missing
        wallet_raw = packed(files)
        root_raw = packed([('manifest.json', encode(lab), stat.S_IFREG)])
        home_raw = packed([('manifest.json', home_manifest, stat.S_IFREG)] +
            [(row['file'], home_pixels, stat.S_IFREG) for row in home['captures']])
        blobs = {1: root_raw, 2: wallet_raw, 3: home_raw}
        artifact_ids = (1,) if child_missing else (1, 2, 3) if positive else (1, 2)
        listing = dict(total_count=len(artifact_ids), artifacts=[dict(id=i,
            name={1: 'chain321-native-', 2: 'wallet-inspection-', 3: 'home-catalog-'}[i] + 'a' * 40 + '-1-1',
            expired=False, size_in_bytes=len(blobs[i]), digest='sha256:' + reader.archive.sha(blobs[i]),
            workflow_run=dict(id=1, head_sha='a' * 40)) for i in artifact_ids])
        blob = hashlib.sha1(b'blob ' + str(len(source)).encode() + b'\0' + source).hexdigest()
        tree = dict(sha='b' * 40, truncated=False, tree=[dict(path=n, mode='100644', type='blob', sha=blob)
            for n in reader.SOURCE_FILES])
        calls = []
        observed_runs = 0

        class Client:
            def __init__(self, token):
                self.token = token

            def json(self, path):
                nonlocal observed_runs
                calls.append(('json', path))
                if path == '/actions/runs/1':
                    observed_runs += 1
                    return dict(id=1, head_sha='a' * 40, run_attempt=2 if mutate_after and observed_runs > 1 else 1,
                        workflow_id=381413107, event='workflow_dispatch', status='completed',
                        conclusion='success' if original_success else 'failure',
                        repository=dict(full_name='edgepillar/syrius'))
                if path == '/git/commits/' + 'a' * 40:
                    return dict(sha='a' * 40, tree=dict(sha='b' * 40))
                if path.endswith('/jobs?per_page=50'):
                    return jobs(positive=original_success)
                if path.endswith('/artifacts?per_page=20'):
                    return copy.deepcopy(listing)
                raise AssertionError('Unexpected metadata endpoint')

            def read(self, url, **options):
                calls.append(('read', url, options))
                if '?recursive=1' in url:
                    return encode(tree)
                if url.startswith(reader.archive.API + '/actions/artifacts/'):
                    self_id = int(url.split('/')[-2])
                    return 'https://fixture.blob.core.windows.net/' + str(self_id)
                self_id = int(url.rsplit('/', 1)[1])
                return blobs[self_id]

        parent = dict(GITHUB_ACTIONS='true', SYRIUS_HOSTED_RUNNER='github-hosted',
            GITHUB_EVENT_NAME='workflow_dispatch', GITHUB_REPOSITORY='edgepillar/syrius',
            GITHUB_WORKSPACE='/fixture', WALLET_INSPECT_RUN='1', WALLET_INSPECT_HEAD='a' * 40,
            GH_TOKEN='synthetic private token')
        output = io.StringIO()
        with mock.patch.object(reader.archive, 'Client', Client), \
                mock.patch.object(reader.producer, 'read_original', return_value=source), \
                contextlib.redirect_stdout(output):
            value = reader.main(parent)
        return value, calls, output.getvalue()

    def test_full_reader_binds_both_archives_metadata_and_all_twenty_four_pngs(self):
        for forced in (False, True):
            with self.subTest(auxiliary_forced=forced):
                value, calls, text = self.run_main(auxiliary_forced=forced)
                self.assertTrue(value['native_inspection_qualified'])
                self.assertEqual(value['verified_png_count'], 24)
                self.assertEqual(value['producer_source_files_verified'], len(reader.SOURCE_FILES))
                self.assertTrue(value['metadata_revalidated'])
                messages = [line.split('::', 2)[-1] for line in text.splitlines()
                            if line.startswith('::notice title=Retained readonly shot layout::')]
                self.assertEqual(len(messages), 1)
                measured = json.loads(messages[0])
                self.assertEqual(measured['source_head'], 'a' * 40)
                self.assertEqual(measured['producer_job_id'], 44)
                self.assertTrue(measured['all_original_png_digests_verified'])
                self.assertTrue(measured['metadata_revalidated'])
                self.assertEqual(measured['producer_source_files_verified'], len(reader.SOURCE_FILES))

                self.assertEqual(value['verified_catalog_png_count'], 2)
                home_notices = [line.split('::', 2)[-1] for line in text.splitlines()
                    if line.startswith('::notice title=Retained readonly Home catalog::')]
                self.assertEqual(len(home_notices), 1)
                home_observed = json.loads(home_notices[0])
                self.assertTrue(home_observed['catalog_capture_qualified'])
                self.assertTrue(home_observed['parent_closure_qualified'])
                self.assertTrue(home_observed['metadata_revalidated'])
                self.assertEqual(home_observed['verified_png_count'], 2)
                self.assertFalse(home_observed['atomic_frame_qualified'])
                self.assertFalse(home_observed['wallet_qualified'])
                self.assertEqual(home_observed['visual_matches'], 0)
                self.assertFalse(value['runtime_started'])
                self.assertIs(value['forced_cleanup'], forced)
                self.assertIs(value['required_actor_forced_cleanup'], False)
                self.assertLessEqual(len(calls), 14)
                self.assertNotIn('private_profile', text)
                self.assertNotIn('synthetic private token', text)
                self.assertNotIn('/fixture', text)

    def test_failed_parent_cannot_be_healed_by_a_successful_wallet_archive(self):
        value, _, _ = self.run_main(parent_failed=True)
        self.assertTrue(value['artifact_reported_success'])
        self.assertEqual(value['verified_png_count'], 24)
        self.assertFalse(value['original_lab_closure_qualified'])
        self.assertFalse(value['native_inspection_qualified'])

    def test_negative_reader_keeps_original_failure_and_does_not_admit_pixels(self):
        value, _, _ = self.run_main(positive=False)
        self.assertFalse(value['native_inspection_qualified'])
        self.assertEqual(value['verified_png_count'], 0)
        self.assertEqual(value['original_errors'], ['ENTRY_FAILED'])

    def test_mutated_attempt_after_transport_is_refused_before_emitting_acceptance(self):
        with self.assertRaises(reader.archive.Refused):
            self.run_main(mutate_after=True)

    def test_unavailable_child_archive_preserves_failure_without_inventing_coverage(self):
        value, calls, _ = self.run_main(child_missing=True)
        self.assertEqual(value['wallet_artifact_status'], 'UNAVAILABLE')
        self.assertFalse(value['native_inspection_qualified'])
        self.assertEqual(value['verified_png_count'], 0)
        cloud = [row for row in calls if row[0] == 'read' and 'fixture.blob.core.windows.net' in row[1]]
        self.assertEqual(len(cloud), 1)

    def test_non_ci_environment_refuses_before_network_client_allocation(self):
        with mock.patch.object(reader.archive, 'Client') as client, self.assertRaises(reader.archive.Refused):
            reader.main({})
        client.assert_not_called()

    def test_duplicate_json_fields_cannot_override_an_original_receipt(self):
        with self.assertRaises(reader.archive.Refused):
            reader.decode(b'{"success":false,"success":true}')


if __name__ == '__main__':
    unittest.main()
