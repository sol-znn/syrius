"""Isolated inspection controls. No SDK, node, process or native wallet runs."""

import base64
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
import stat
import struct
from types import SimpleNamespace
import unittest
from unittest import mock
import zlib

from tool.ci import hosted_chain321 as lab
from tool.ci import windows_wallet_inspection as inspection
import test_readonly_viewport_capture as viewport_fixtures


def sdk():
    return dict(schema=1, scope='readonly_native_sdk_admission', status='CURRENT',
        publicationAdmissionPaused=True, automaticReceiveDisabled=True)


def wallet():
    return dict(schema=1, scope='readonly_native_wallet_admission', status='CURRENT',
        chain=321, selectedIndex=1, nativeFrameObserved=True)


def layout():
    rows = [dict(key=key, status='MISSING') for key in ('window-caption', 'window-body', 'home_hero', 'home_send', 'nodes_tab_pillars', 'nodes_tab_sentinels', 'staking_stake_button', 'plasma_open_fuse', 'tokens_filter_held', 'p2p_start_swap', 'node_settings_add', 'apps_settings_web_switch', 'transfer_card', 'accelerator_strip', 'bell_panel')]
    return dict(schema=1, scope='readonly_shot_layout_observation',
        boundaries=['before_raster', 'after_encoding'], before=rows,
        after=copy.deepcopy(rows), unchanged=True)


def tour(theme):
    return dict(theme=theme, tour=dict(schema=1, scope='readonly_native_page_tour',
        complete=True, requested=list(inspection.PAGES), visited=[dict(page=p,
            nodes=1, error_widgets=0, severe_logs=0, captured=True,
            layout=layout()) for p in inspection.PAGES]))


def home_receipt():
    return dict(schema=1, scope='readonly_native_home_catalog_capture',
        screen='home-rest', number=1, themes=['dark', 'light'],
        files=['01-home-rest-dark.png', '01-home-rest-light.png'],
        width=1280, height=780, scale=1, capture_returned=True)


def home_reference(digest='e' * 64):
    return dict(schema=1, scope='readonly_native_home_catalog_reference',
        screen='home-rest', captured=2, manifest_sha256=digest)


def home_manifest(pixels, script=b'synthetic public script'):
    return dict(schema=1, scope='readonly_native_home_catalog_capture_bundle',
        source_sha='a' * 40, source_tree='b' * 40, run_id='1', run_attempt='1',
        script_sha256=hashlib.sha256(script).hexdigest(), capture=home_receipt(),
        captures=[dict(theme=theme, file='01-home-rest-' + theme + '.png',
            bytes=len(pixels), sha256=hashlib.sha256(pixels).hexdigest(),
            width=1280, height=780, scale=1) for theme in ('dark', 'light')],
        inspection_only=True, parent_closure_qualified=False,
        atomic_frame_qualified=False, wallet_qualified=False, seed_admitted=False,
        financial_send_qualified=False, visual_matches=0)


def report():
    return dict(schema=1, scope='owned_chain321_wallet_inspection', success=True,
        inspection_qualified=True, wallet_qualified=False, seed_admitted=False, visual_matches=0,
        checks=dict.fromkeys(inspection.CHECKS, True), errors=[], phase='complete',
        captures=[dict(theme=t, page=p, bytes=100, sha256='c' * 64, width=1280, height=780)
                  for t in inspection.THEMES for p in inspection.PAGES],
        tours={t: tour(t) for t in inspection.THEMES},
        locales={t: dict(schema=1, scope='readonly_native_locale_observation', theme=t,
            language='en', direction='ltr', stable=True) for t in inspection.THEMES},
        stalls={t: dict(schema=1, scope='readonly_native_stalls_observation', theme=t,
            events=0, longest_ms=0) for t in inspection.THEMES},
        sdk_admission=sdk(), wallet_admission=wallet(), home_catalog=home_reference(),
        viewport=dict(schema=1, scope='readonly_native_viewport_reference',
                      captured=4, manifest_sha256='e' * 64),
        address_selection=dict(index=1, members=2, generated=False, selected=True, persisted=True),
        lab_revalidations=2, forced_cleanup=False, required_actor_forced_cleanup=False,
        auxiliary_cleanup=dict(scope=inspection.debug.HELPER_SCOPE, status='PASSED',
            code=None, forced=False, remaining=0, receipts=[], observation=dict(
                stage='complete', image_class=None, image_bytes=None, path_match=None)),
        min_free_bytes=inspection.shared.FIXTURE_FLOOR,
        workspace_cap_bytes=inspection.shared.WORK_CAP,
        storage_scope='isolated_hosted_regression_fixture_cooperative_samples',
        storage=dict(samples=1, peak_logical_bytes=2400, minimum_free_bytes=8 * 1024**3, refusal=None),
        cleanup='runner_lifecycle_not_qualified', financial_send_qualified=False,
        motion_baseline_compared=False, arabic_or_minimum_window_qualified=False,
        source_sha='a' * 40, source_tree='b' * 40, run_id='1', run_attempt='1',
        input_attempted=True, application_exit=0, entry_exit=0,
        owned_job_images_before_close=dict(status='OBSERVED', listed=0, observed=0, counts={}),
        owned_job_active_at_close=0, entry_output=dict(bytes=1, sha256='d' * 64,
            output_complete=True, overflow=False))


def png():
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack(
            '>I', zlib.crc32(kind + body) & 0xffffffff)
    row = b'\0' + b'\0\0\0\xff' * 1280
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB',
        1280, 780, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(row * 780)) + chunk(b'IEND', b''))


class _Output(io.StringIO):
    def close(self):
        pass


class InspectionTests(unittest.TestCase):
    def test_lab_failure_projection_retains_only_fixed_codes_and_refuses_success(self):
        labels = []
        for code in inspection.LAB_CODES:
            error = RuntimeError('Synthetic private exception text')
            error.code = code
            self.assertEqual(inspection.inspection_failure_code(error,
                'lab_revalidation'), code)
            labels.append(code)
        for error, label in ((TimeoutError('private'), 'LAB_REVALIDATION_TIMEOUT_ERROR'),
            (ConnectionError('private'), 'LAB_REVALIDATION_CONNECTION_ERROR'),
            (KeyError('private'), 'LAB_REVALIDATION_KEY_ERROR'),
            (TypeError('private'), 'LAB_REVALIDATION_TYPE_ERROR'),
            (ValueError('private'), 'LAB_REVALIDATION_VALUE_ERROR'),
            (OSError('private'), 'LAB_REVALIDATION_OS_ERROR')):
            observed = inspection.inspection_failure_code(error, 'lab_revalidation')
            self.assertEqual(observed, label)
            self.assertEqual(inspection.inspection_failure_code(error,
                'onboarding_and_inspection'), 'INTERNAL_ERROR')
            self.assertFalse(inspection.completed({**report(), 'errors': [observed]}))
            labels.append(observed)
        class PrivateCode(ValueError):
            @property
            def code(self):
                raise RuntimeError('Synthetic private code lookup')
        self.assertEqual(inspection.inspection_failure_code(PrivateCode('private'),
            'lab_revalidation'), 'LAB_REVALIDATION_VALUE_ERROR')
        self.assertEqual(inspection.inspection_failure_code(
            inspection.debug.ProcessRefused('TOOL_REFUSED'), 'admission'), 'TOOL_REFUSED')
        for error in (RuntimeError('private'), KeyboardInterrupt('private')):
            self.assertEqual(inspection.inspection_failure_code(error,
                'lab_revalidation'), 'INTERNAL_ERROR')
        self.assertNotIn('private', json.dumps(labels))

    def test_home_catalog_privacy_geometry_and_fixed_files_are_independent(self):
        pixels = png()
        original = home_manifest(pixels)
        self.assertIs(inspection.home_capture_receipt(original['capture']), original['capture'])
        self.assertIs(inspection.public_home_catalog(original), original)
        self.assertFalse(original['parent_closure_qualified'])
        self.assertFalse(original['atomic_frame_qualified'])
        self.assertEqual(original['visual_matches'], 0)
        missing = report()
        missing['home_catalog'] = None
        self.assertFalse(inspection.completed(missing))
        with self.assertRaises(inspection.Refused):
            inspection.public_manifest(missing)
        for change in ({'schema': True}, {'scope': 'ordinary'},
                       {'source_sha': 'Synthetic private origin'},
                       {'parent_closure_qualified': True}, {'atomic_frame_qualified': True},
                       {'wallet_qualified': True}, {'visual_matches': 1},
                       {'private_profile': 'Synthetic private path'}):
            with self.subTest(change=change), self.assertRaises(inspection.Refused):
                inspection.public_home_catalog(dict(copy.deepcopy(original), **change))
        for change in ({'files': ['dashboard.png', '01-home-rest-light.png']},
                       {'themes': ['dark', 'dark']}, {'number': True},
                       {'capture_returned': False}, {'width': 1279}, {'scale': True}):
            value = copy.deepcopy(original)
            value['capture'].update(change)
            with self.subTest(capture=change), self.assertRaises(inspection.Refused):
                inspection.public_home_catalog(value)
        for change in ({'file': '../private.png'}, {'theme': 'light'}, {'bytes': True},
                       {'bytes': inspection.MAX_HOME_CAPTURE_TOTAL + 1},
                       {'sha256': 'Synthetic private value'}, {'width': 1279},
                       {'path': 'Synthetic private path'}):
            value = copy.deepcopy(original)
            value['captures'][0].update(change)
            with self.subTest(image=change), self.assertRaises(inspection.Refused):
                inspection.public_home_catalog(value)
        # The duplicated field is refused before script or pixel consumption.
        duplicate = b'{"schema":1,' + json.dumps(original).encode('ascii')[1:]
        owner = report()
        owner['home_catalog'] = home_reference(hashlib.sha256(duplicate).hexdigest())
        with mock.patch.object(inspection, 'home_output_bytes', return_value=len(duplicate)), \
                mock.patch.object(inspection, 'read_original', return_value=duplicate) as read:
            with self.assertRaises(inspection.Refused):
                inspection.home_artifact_paths(Path('/fixture'), owner)
            self.assertEqual(read.call_count, 1)
        output = Path('/fixture/home')
        with mock.patch.object(Path, 'exists', return_value=True), \
                mock.patch.object(Path, 'iterdir', return_value=iter([output / 'unregistered.bin'])), \
                mock.patch.object(inspection.debug.bounded, 'plain',
                    return_value=SimpleNamespace(st_mode=stat.S_IFDIR)):
            with self.assertRaises(inspection.Refused):
                inspection.home_output_bytes(output)

    def test_complete_finite_controls_do_not_grant_financial_or_catalog_acceptance(self):
        value = report()
        self.assertTrue(inspection.completed(value))
        self.assertIs(inspection.public_manifest(value), value)
        for key in ('wallet_qualified', 'financial_send_qualified', 'seed_admitted',
                    'motion_baseline_compared', 'arabic_or_minimum_window_qualified'):
            self.assertIs(value[key], False)
        self.assertEqual(value['visual_matches'], 0)
        self.assertEqual(tuple(inspection.LAYOUT_KEYS), ('window-caption', 'window-body', 'home_hero', 'home_send', 'nodes_tab_pillars', 'nodes_tab_sentinels', 'staking_stake_button', 'plasma_open_fuse', 'tokens_filter_held', 'p2p_start_swap', 'node_settings_add', 'apps_settings_web_switch', 'transfer_card', 'accelerator_strip', 'bell_panel'))
        observed = layout()
        for boundary in ('before', 'after'):
            observed[boundary][1] = dict(key='window-body', status='OBSERVED',
                                        rect=[0, 32, 1280, 780])
        self.assertIs(inspection.layout_observation(observed), observed)
        changed = copy.deepcopy(observed)
        changed['after'][1]['rect'][1] = 0
        changed['unchanged'] = False
        self.assertIs(inspection.layout_observation(changed), changed)
        malformed = []
        for change in ({'schema': True}, {'extra': 'Synthetic private data'},
                       {'unchanged': False}, {'boundaries': ['tree', 'after_encoding']}):
            malformed.append(dict(copy.deepcopy(observed), **change))
        for change in ({'key': 'Synthetic private key'}, {'status': 'OTHER'},
                       {'extra': 'Synthetic private value'}, {'status': 'LIMIT'},
                       {'rect': [False, 32, 1280, 780]},
                       {'rect': [0, 32, 32769, 780]}, {'rect': [2, 32, 1, 780]}):
            bad = copy.deepcopy(observed)
            bad['before'][1].update(change)
            malformed.append(bad)
        for bad in malformed:
            with self.subTest(layout=bad), self.assertRaises(inspection.Refused):
                inspection.layout_observation(bad)
        partial = tour('dark')
        partial['tour']['complete'] = False
        page = partial['tour']['visited'][0]
        page.update(captured=False, layout=None)
        inspection.tour_receipt(partial)
        page['captured'] = True
        with self.assertRaises(inspection.Refused):
            inspection.tour_receipt(partial)


    def test_sdk_and_wallet_receipts_refuse_expansion_coercion_and_old_scopes(self):
        for original, validate, changes in (
            (sdk(), inspection.sdk_receipt, ({'schema': True}, {'status': 'PENDING'},
                {'automaticReceiveDisabled': False}, {'extra': 'synthetic private data'})),
            (wallet(), inspection.wallet_receipt, ({'chain': 321.0}, {'selectedIndex': True},
                {'nativeFrameObserved': False}, {'scope': 'original_lab_ui_send'}))):
            self.assertIs(validate(original), original)
            for change in changes:
                with self.subTest(change=change), self.assertRaises(inspection.Refused):
                    validate(dict(original, **change))

    def test_ready_scope_requires_actual_integer_process_and_port(self):
        value = dict(schema=1, scope='readonly_native_inspection_ready', pid=44, port=45000)
        self.assertIs(inspection.ready_receipt(value), value)
        for change in ({'pid': True}, {'port': '45000'}, {'pid': 0}, {'port': 65536},
                       {'scope': 'wallet'}, {'token': 'synthetic private token'}):
            with self.subTest(change=change), self.assertRaises(inspection.Refused):
                inspection.ready_receipt(dict(value, **change))

    def test_replies_cannot_borrow_ordinary_or_foreign_process_admission(self):
        value = dict(ok=True, pid=44, booted=True, readOnly=True, harnessMode='readonly-native',
                     readonlyAdmission=sdk(), readonlyWallet=wallet())
        self.assertIs(inspection.readonly_reply(value, 44, wallet=True), value)
        for change in ({'pid': 45}, {'harnessMode': 'wallet'}, {'readonlyAdmission': None},
                       {'readonlyWallet': None}, {'readOnly': 1}):
            with self.subTest(change=change), self.assertRaises(inspection.Refused):
                inspection.readonly_reply(dict(value, **change), 44, wallet=True)

    def test_tours_keep_all_original_pages_and_their_separate_inspection_scope(self):
        value = tour('dark')
        self.assertTrue(inspection.tour_complete(value))
        ordinary = copy.deepcopy(value)
        ordinary['tour']['scope'] = 'wallet_page_tour'
        with self.assertRaises(inspection.Refused):
            inspection.tour_receipt(ordinary)
        for fault in ('missing', 'reordered', 'uncaptured', 'widget', 'log'):
            bad = copy.deepcopy(value)
            if fault == 'missing':
                bad['tour']['visited'].pop()
            elif fault == 'reordered':
                bad['tour']['visited'].reverse()
            else:
                bad['tour']['visited'][0][{'uncaptured': 'captured',
                    'widget': 'error_widgets', 'log': 'severe_logs'}[fault]] = False if fault == 'uncaptured' else 1
            try:
                result = inspection.tour_complete(bad)
            except inspection.Refused:
                result = False
            self.assertFalse(result, fault)

    def test_locale_and_stalls_are_finite_observations_not_baseline_acceptance(self):
        value = report()
        for theme in inspection.THEMES:
            inspection.locale_receipt(value['locales'][theme])
            inspection.stalls_receipt(value['stalls'][theme])
        for key, change, validate in (
            ('locales', {'language': 'ar'}, inspection.locale_receipt),
            ('locales', {'stable': False}, inspection.locale_receipt),
            ('stalls', {'events': True}, inspection.stalls_receipt),
            ('stalls', {'longest_ms': -1}, inspection.stalls_receipt)):
            with self.subTest(change=change), self.assertRaises(inspection.Refused):
                validate(dict(value[key]['dark'], **change))

    def test_missing_originals_unknown_output_and_forced_actors_never_complete(self):
        changes = [lambda v: v['checks'].pop('wallet_bound'),
            lambda v: v['checks'].update(close_ack=False),
            lambda v: v.update(application_exit=True), lambda v: v.update(entry_exit=None),
            lambda v: v.update(wallet_admission=None), lambda v: v.update(lab_revalidations=1),
            lambda v: v.update(required_actor_forced_cleanup=True),
            lambda v: v.update(owned_job_active_at_close=1),
            lambda v: v['owned_job_images_before_close'].update(status='UNKNOWN'),
            lambda v: v['entry_output'].update(output_complete=False),
            lambda v: v['entry_output'].update(overflow=True)]
        for change in changes:
            value = report()
            change(value)
            self.assertFalse(inspection.completed(value))

    def test_exact_auxiliary_termination_remains_separate_from_required_actors(self):
        value = report()
        value['forced_cleanup'] = value['auxiliary_cleanup']['forced'] = True
        value['auxiliary_cleanup']['receipts'] = [dict(role='sdk_dart', image_sha256='e' * 64,
            forced=True, termination_requested=True, termination_succeeded=True,
            actual_exit=inspection.debug.HELPER_EXIT_MARKER, exit_observed=True, stdio_captured=False)]
        self.assertTrue(inspection.completed(value))
        inspection.public_manifest(value)
        value['required_actor_forced_cleanup'] = True
        self.assertFalse(inspection.completed(value))

    def test_private_or_unknown_fields_cannot_enter_public_manifests(self):
        changes = [lambda v: v.update(credentials='synthetic private value'),
            lambda v: v['sdk_admission'].update(path='synthetic private path'),
            lambda v: v['wallet_admission'].update(members=['synthetic private member']),
            lambda v: v['captures'][0].update(filename='synthetic private path'),
            lambda v: v['entry_output'].update(text='synthetic private output'),
            lambda v: v['auxiliary_cleanup']['observation'].update(path='synthetic private path'),
            lambda v: v['errors'].append('synthetic private failure'),
            lambda v: v['storage'].update(path='synthetic private path'),
            lambda v: v['owned_job_images_before_close']['counts'].update(private_image=1),
            lambda v: v.update(run_id='synthetic private identifier'),
            lambda v: v.update(motion_baseline_compared=True)]
        for change in changes:
            value = report()
            change(value)
            with self.assertRaises(inspection.Refused):
                inspection.public_manifest(value)

    def test_negative_manifest_keeps_partial_and_unknown_original_outcomes(self):
        value = report()
        value.update(success=False, inspection_qualified=False, phase='onboarding_and_inspection',
            errors=['ENTRY_FAILED'], application_exit=None, entry_exit=1,
            captures=value['captures'][:1], tours={}, locales={}, stalls={},
            wallet_admission=None, auxiliary_cleanup=None)
        value['owned_job_images_before_close']['status'] = 'UNKNOWN'
        self.assertIs(inspection.public_manifest(value), value)
        self.assertFalse(inspection.completed(value))
        self.assertIsNone(value['application_exit'])

    def test_inspection_default_off_and_explicit_native_lab_requirements(self):
        workflow = Path('.github/workflows/public-contribution-qualification.yml').read_text(encoding='utf-8')
        self.assertIn('- name: Retain the admitted Home catalog captures', workflow)
        self.assertIn("steps.inspection_paths.outputs.catalog_paths != ''", workflow)
        self.assertIn('path: ${{ steps.inspection_paths.outputs.catalog_paths }}', workflow)
        self.assertNotIn('path: .harness/ci-home-catalog/**', workflow)
        self.assertFalse(lab.wallet_inspection_requested('native', {}))
        parent = dict(SYRIUS_WINDOWS_WALLET_INSPECTION='true',
            SYRIUS_WINDOWS_WALLET_TOUR='false', SYRIUS_LAB_NODE_SOURCE='lab-fix',
            SYRIUS_NATIVE_STACK_DIAGNOSTIC='true')
        self.assertTrue(lab.wallet_inspection_requested('native', parent))
        for change in ({'SYRIUS_WINDOWS_WALLET_TOUR': 'true'},
                       {'SYRIUS_LAB_NODE_SOURCE': 'original'},
                       {'SYRIUS_NATIVE_STACK_DIAGNOSTIC': 'false'},
                       {'SYRIUS_WINDOWS_WALLET_INSPECTION': True}):
            with self.assertRaises(lab.Failure):
                lab.wallet_inspection_requested('native', dict(parent, **change))
        with self.assertRaises(lab.Failure):
            lab.wallet_inspection_requested('docker', parent)

    def test_entry_failures_keep_only_original_finite_diagnostics(self):
        value = dict(stage='onboarding', code='wallet-recipe-command-refused', diagnostic=dict(
            action='type', control='import_seed_field', reason='wallet-recipe-control-disabled', entry='import'))
        self.assertIs(inspection.entry_failure(value), value)
        for change in ({'stage': 'lab_send'}, {'code': 'synthetic private diagnostic'},
                       {'stack': 'synthetic private path'}):
            with self.assertRaises(inspection.Refused):
                inspection.entry_failure(dict(value, **change))

    def test_non_ci_admission_refuses_before_profile_sdk_or_process_allocation(self):
        with mock.patch.object(inspection.subprocess, 'Popen', side_effect=AssertionError('No process')) as process, \
                mock.patch.object(Path, 'mkdir', side_effect=AssertionError('No scratch')) as mkdir, \
                mock.patch.object(inspection.debug, 'sdk', side_effect=AssertionError('No SDK')) as sdk_call, \
                contextlib.redirect_stdout(io.StringIO()):
            value = inspection.run(Path('/fixture'), {}, None, None, {}, lambda: None)
        self.assertFalse(value['success'])
        self.assertEqual(value['errors'], ['ENVIRONMENT_REFUSED'])
        process.assert_not_called()
        mkdir.assert_not_called()
        sdk_call.assert_not_called()

    def test_original_artifact_reads_refuse_aliases_growth_and_changed_identity(self):
        class Original(io.BytesIO):
            def fileno(self):
                return 59

        path = Path('/fixture/capture.png')
        raw = b'observed'
        info = SimpleNamespace(st_mode=stat.S_IFREG, st_nlink=1,
            st_size=len(raw), st_dev=1, st_ino=2, st_mtime_ns=3)
        for fault in (None, 'alias', 'growth', 'replaced', 'short'):
            before = copy.copy(info)
            after = copy.copy(info)
            pixels = raw
            if fault == 'alias':
                before.st_nlink = 2
            elif fault == 'growth':
                pixels *= 4
            elif fault == 'replaced':
                after.st_ino = 4
            elif fault == 'short':
                pixels = raw[:-1]
            with self.subTest(fault=fault), \
                    mock.patch.object(inspection.debug.bounded, 'plain',
                        side_effect=lambda p: before if p == path else
                            SimpleNamespace(st_mode=stat.S_IFDIR)), \
                    mock.patch.object(inspection.os, 'fstat', side_effect=[before, after]), \
                    mock.patch.object(Path, 'open', return_value=Original(pixels)):
                if fault is None:
                    self.assertEqual(inspection.read_original(path, 16), raw)
                else:
                    with self.assertRaises(inspection.Refused):
                        inspection.read_original(path, 16)

    def artifact_case(self, value, *, pixels=None):
        parent = dict(GITHUB_WORKSPACE='/fixture', GITHUB_RUN_ID='1', GITHUB_RUN_ATTEMPT='1',
                      GITHUB_OUTPUT='/fixture-output')
        value = copy.deepcopy(value)
        script = Path('harness/screens/home-rest.txt').read_bytes()
        home = home_manifest(pixels or b'x', script)
        home_raw = json.dumps(home).encode('ascii')
        viewport_manifest, viewport_images = viewport_fixtures.fixture()
        viewport_manifest['probe_sha256'] = hashlib.sha256(script).hexdigest()
        viewport_raw = json.dumps(viewport_manifest).encode('ascii')
        if value['success']:
            value['home_catalog'] = home_reference(hashlib.sha256(home_raw).hexdigest())
            value['viewport']['manifest_sha256'] = hashlib.sha256(viewport_raw).hexdigest()
        manifest = json.dumps(value).encode()
        output = _Output()
        reads = []

        def read(path, cap):
            reads.append(path)
            if path in (Path('/fixture') / inspection.HOME_SCRIPT,
                        Path('/fixture') / inspection.viewport.PROBE):
                self.assertEqual(cap, 65536)
                return script
            if path.parent == Path('/fixture') / inspection.viewport.OUTPUT:
                return viewport_raw if path.name == 'manifest.json' else viewport_images[path.name]
            if path.parent == Path('/fixture') / inspection.HOME_OUTPUT:
                if path.name == 'manifest.json':
                    self.assertEqual(cap, inspection.MAX_HOME_MANIFEST)
                    return home_raw
                self.assertEqual(cap, inspection.MAX_HOME_CAPTURE_TOTAL)
                self.assertIn(path.name, inspection.HOME_FILES)
                return pixels
            if path.name == 'manifest.json':
                self.assertEqual(cap, inspection.MAX_MANIFEST)
                return manifest
            self.assertIsNotNone(pixels)
            self.assertEqual(cap, inspection.debug.entry.MAX_PNG)
            self.assertIn(path.name, {p + '.png' for p in inspection.PAGES})
            return pixels

        with mock.patch.object(inspection.debug.entry, 'require_ci', return_value=(parent, 'a' * 40)), \
                mock.patch.object(inspection.debug.bounded, 'verify_source'), \
                mock.patch.object(inspection.debug.entry, 'source_tree', return_value='b' * 40), \
                mock.patch.object(inspection.debug.bounded, 'plain', side_effect=lambda path:
                    SimpleNamespace(st_size=len(manifest) if path.name == 'manifest.json' else len(pixels or b''))), \
                mock.patch.object(inspection, 'read_original', side_effect=read), \
                mock.patch.object(Path, 'open', return_value=output), \
                mock.patch.object(inspection, 'output_bytes', return_value=len(pixels or b'') * 24), \
                mock.patch.object(inspection, 'home_output_bytes', return_value=len(home_raw) + len(pixels or b'') * 2), \
                mock.patch.object(inspection.viewport, 'output_bytes', return_value=0):
            paths = inspection.artifact_paths(parent)
        return paths, reads, output.getvalue()

    def test_failed_inspection_exports_only_its_finite_manifest(self):
        value = report()
        value.update(success=False, inspection_qualified=False, errors=['ENTRY_FAILED'])
        paths, reads, output = self.artifact_case(value)
        self.assertEqual(paths, ['.harness/ci-wallet-inspection/manifest.json'])
        for flavor in (PurePosixPath, PureWindowsPath):
            expected = flavor(inspection.OUTPUT.as_posix()) / 'manifest.json'
            self.assertEqual(str(expected).replace('\\', '/'), paths[0])
        self.assertEqual(len(reads), 1)
        self.assertNotIn('.png', output)

    def test_successful_artifact_selection_verifies_every_original_png_reference(self):
        pixels = png()
        value = report()
        for row in value['captures']:
            row.update(bytes=len(pixels), sha256=hashlib.sha256(pixels).hexdigest())
        paths, reads, output = self.artifact_case(value, pixels=pixels)
        self.assertEqual(len(paths), 25)
        self.assertEqual(len(set(paths)), 25)
        self.assertEqual(len(reads), 35)
        self.assertIn('captures/dark/dashboard.png', output)
        self.assertIn('captures/light/walletConnect.png', output)
        self.assertIn('catalog_paths<<HOME_CATALOG_PATHS_V1', output)
        self.assertIn('ci-home-catalog/01-home-rest-dark.png', output)
        self.assertIn('ci-home-catalog/01-home-rest-light.png', output)
        self.assertIn('viewport_paths<<VIEWPORT_PATHS_V1', output)
        for filename in inspection.viewport.FILES:
            self.assertIn('ci-viewport-observations/' + filename, output)

    def test_artifacts_cannot_borrow_another_source_run_or_private_manifest(self):
        for change in ({'source_sha': 'c' * 40}, {'run_attempt': '2'},
                       {'private': 'synthetic private data'}):
            value = report()
            value.update(success=False, inspection_qualified=False, errors=['ENTRY_FAILED'], **change)
            with self.assertRaises(inspection.Refused):
                self.artifact_case(value)


if __name__ == '__main__':
    unittest.main()
