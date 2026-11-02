"""Finite checkpoint policy and small isolated filesystem regression fixtures."""

import os
from pathlib import Path
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

from tool.ci import closed_lab_checkpoint as checkpoint


def binding():
    return dict(source_sha='a'*40, source_tree='b'*40, node_sha='c'*40,
                node_tree='d'*40, genesis_sha256='e'*64, run_id='123', attempt=1)


def observation():
    return dict(schema=1, scope='closed_owned_lab_checkpoint', complete=True,
        roots=6, files=6, entries=12, source_bytes=6, object_bytes=1,
        restored_bytes=6, objects=1, reserved_bytes=7+checkpoint.METADATA_CAP,
        manifest_bytes=2000, manifest_sha256='a'*64, independent_copies=True,
        source_unchanged=True, single_restore_claim=True,
        retention='isolated_runner_lifecycle', native_reopen_qualified=False,
        seed_admitted=False)


class PolicyTests(unittest.TestCase):
    def test_canonical_restore_is_a_new_named_instance_under_the_original_parent(self):
        parent = Path('/fixture/.harness')
        original, offered = parent / ('ci-wallet-'+'1'*24), parent / ('ci-wallet-'+'2'*24)
        self.assertEqual(checkpoint.canonical_target(original, offered), offered.absolute())

    def test_canonical_restore_refuses_stale_default_nested_or_foreign_targets(self):
        parent = Path('/fixture/.harness')
        original = parent / ('ci-wallet-'+'1'*24)
        for offered in (original, parent / 'default', parent / 'ci-wallet-short',
                        parent / 'nested' / ('ci-wallet-'+'2'*24),
                        parent.parent / ('ci-wallet-'+'2'*24)):
            with self.subTest(name=offered.name), self.assertRaises(checkpoint.Refused):
                checkpoint.canonical_target(original, offered)

    def test_copy_projection_retains_absence_refusal_and_finite_positive_facts(self):
        self.assertIsNone(checkpoint.project(None))
        refused = dict(schema=1, scope='closed_owned_lab_checkpoint', complete=False)
        self.assertEqual(checkpoint.project(refused), refused)
        self.assertEqual(checkpoint.project(observation()), observation())

    def test_projection_refuses_private_fields_coercion_and_inconsistent_accounting(self):
        for key, value in (('private_path', 'private fixture'), ('files', True),
                           ('restored_bytes', 0), ('objects', 7),
                           ('reserved_bytes', 0), ('manifest_sha256', 'private')):
            with self.subTest(key=key), self.assertRaises(checkpoint.Refused):
                checkpoint.project(dict(observation(), **{key: value}))

    def test_a_copy_receipt_never_claims_native_reopen_or_seed_authority(self):
        for key in ('native_reopen_qualified', 'seed_admitted'):
            with self.subTest(key=key), self.assertRaises(checkpoint.Refused):
                checkpoint.project(dict(observation(), **{key: True}))

    def test_saved_receipts_cannot_replace_current_closure_authority(self):
        with mock.patch.object(checkpoint, 'catalog') as catalog:
            for closed in ({'all_closed': True}, None, True):
                with self.subTest(closed=type(closed)), self.assertRaises(checkpoint.Refused):
                    checkpoint.capture_restore({}, Path('unused'), closed,
                                               base_bytes=0, binding=binding())
            catalog.assert_not_called()

    def test_closure_requires_an_exact_true_before_filesystem_discovery(self):
        with mock.patch.object(checkpoint, 'catalog') as catalog:
            for result in (False, None, 1, 'true', {'closed': True}):
                with self.subTest(result=type(result)), self.assertRaises(checkpoint.Refused):
                    checkpoint.capture_restore({}, Path('unused'), lambda: result,
                                               base_bytes=0, binding=binding())
            catalog.assert_not_called()

    def test_only_the_complete_six_data_roots_are_accepted(self):
        with mock.patch.object(checkpoint, 'catalog') as catalog:
            for roles in ({}, {'wallet_profile': Path('unused')},
                          {role: Path('unused') for role in (*checkpoint.ROLES, 'tool_profile')}):
                with self.assertRaises(checkpoint.Refused):
                    checkpoint.capture_restore(roles, Path('unused'), lambda: True,
                                               base_bytes=0, binding=binding())
            catalog.assert_not_called()

    def test_source_and_run_binding_refuses_extra_or_malformed_values(self):
        roots = dict.fromkeys(checkpoint.ROLES, Path('unused'))
        with mock.patch.object(checkpoint, 'catalog') as catalog:
            for key, value in (('source_sha', 'dev'), ('run_id', 123),
                               ('attempt', True), ('genesis_sha256', None),
                               ('private_path', 'private fixture')):
                offered = dict(binding(), **{key: value})
                with self.subTest(key=key), self.assertRaises(checkpoint.Refused):
                    checkpoint.capture_restore(roots, Path('unused'), lambda: True,
                                               base_bytes=0, binding=offered)
            catalog.assert_not_called()

    def test_base_accounting_requires_a_bounded_exact_integer(self):
        roots = dict.fromkeys(checkpoint.ROLES, Path('unused'))
        for value in (-1, True, '0', checkpoint.CAP+1):
            with self.subTest(value=value), self.assertRaises(checkpoint.Refused):
                checkpoint.capture_restore(roots, Path('unused'), lambda: True,
                                           base_bytes=value, binding=binding())

    def test_portable_names_refuse_traversal_devices_and_shell_characters(self):
        for value in ('.', '..', 'a/b', 'a\\b', 'C:', 'NUL', 'CON.txt',
                      'com1', 'file.', 'file ', 'a\0b', 'a|b', 'a'*241):
            with self.subTest(value=value), self.assertRaises(checkpoint.Refused):
                checkpoint.part(value)
        checkpoint.part('key_store_box.hive')
        checkpoint.part('Application Data')

    def test_linked_or_reparse_files_are_never_regular_checkpoint_inputs(self):
        plain = dict(st_mode=stat.S_IFREG | 0o600, st_ino=1, st_dev=1,
                     st_nlink=1, st_size=2, st_mtime_ns=3)
        for changes in (dict(st_nlink=2), dict(st_ino=0),
                        dict(st_mode=stat.S_IFLNK | 0o777),
                        dict(st_file_attributes=0x400), dict(st_reparse_tag=0xA0000003)):
            with self.subTest(changes=changes), self.assertRaises(checkpoint.Refused):
                checkpoint.file_identity(SimpleNamespace(**dict(plain, **changes)))
        self.assertEqual(checkpoint.file_identity(SimpleNamespace(**plain)), (1, 1, 2, 3))


class FilesystemTests(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(prefix='syrius-closed-checkpoint-regression-')
        self.addCleanup(self.fixture.cleanup)
        self.parent = Path(self.fixture.name)
        self.roots = {role: self.parent / role for role in checkpoint.ROLES}
        for path in self.roots.values():
            path.mkdir()
            (path / 'same.bin').write_bytes(b'synthetic shared bytes')
        home = self.roots['wallet_profile']
        (home / 'empty').mkdir()
        (home / 'zero.bin').write_bytes(b'')
        self.destination = self.parent / 'closed'
        self.base = sum(path.stat().st_size for root in self.roots.values()
                        for path in root.iterdir() if path.is_file())

    def capture(self, **changes):
        return checkpoint.capture_restore(self.roots, self.destination,
            changes.pop('closed', lambda: True), base_bytes=changes.pop('base_bytes', self.base),
            binding=changes.pop('binding', binding()), **changes)

    def canonical_source(self):
        original = self.roots['wallet_profile']
        parent = self.parent / '.harness'
        parent.mkdir()
        named = parent / ('ci-wallet-'+'1'*24)
        original.rename(named)
        self.roots['wallet_profile'] = named
        return parent / ('ci-wallet-'+'2'*24)

    def test_wallet_is_restored_directly_to_its_canonical_home_without_a_third_copy(self):
        offered = self.canonical_source()
        restored, result = self.capture(wallet_home=offered)
        self.assertEqual(restored['wallet_profile'], offered)
        self.assertTrue(result['canonical_wallet_home'])
        self.assertEqual(result['external_wallet_bytes'], len(b'synthetic shared bytes'))
        self.assertFalse((self.destination / 'restored/wallet_profile').exists())
        self.assertEqual((offered / 'same.bin').read_bytes(), b'synthetic shared bytes')
        self.assertTrue((self.roots['wallet_profile'] / 'same.bin').exists())

    def test_preexisting_canonical_home_is_held_before_any_checkpoint_allocation(self):
        offered = self.canonical_source()
        offered.mkdir()
        (offered / 'held.bin').write_bytes(b'held fixture')
        with self.assertRaises(checkpoint.Refused):
            self.capture(wallet_home=offered)
        self.assertFalse(self.destination.exists())
        self.assertEqual((offered / 'held.bin').read_bytes(), b'held fixture')

    def test_bytewise_restore_deduplicates_objects_and_keeps_independent_files(self):
        restored, result = self.capture()
        self.assertTrue(result['complete'])
        self.assertEqual(result['source_bytes'], self.base)
        self.assertEqual(result['restored_bytes'], self.base)
        self.assertEqual(result['objects'], 2)
        self.assertEqual(result['object_bytes'], len(b'synthetic shared bytes'))
        self.assertFalse(result['native_reopen_qualified'])
        self.assertFalse(result['seed_admitted'])
        self.assertTrue((restored['wallet_profile'] / 'empty').is_dir())
        self.assertEqual((restored['wallet_profile'] / 'zero.bin').read_bytes(), b'')
        for role in checkpoint.ROLES:
            source, copied = self.roots[role] / 'same.bin', restored[role] / 'same.bin'
            self.assertEqual(source.read_bytes(), copied.read_bytes())
            self.assertNotEqual(source.stat().st_ino, copied.stat().st_ino)
            self.assertEqual(copied.stat().st_nlink, 1)
        before = (restored['rpc'] / 'same.bin').read_bytes()
        (self.roots['rpc'] / 'same.bin').write_bytes(b'changed original fixture')
        self.assertEqual((restored['rpc'] / 'same.bin').read_bytes(), before)

    def test_existing_destination_is_held_without_reuse_or_overwrite(self):
        self.destination.mkdir()
        marker = self.destination / 'held.bin'
        marker.write_bytes(b'held original fixture')
        with self.assertRaises(checkpoint.Refused):
            self.capture()
        self.assertEqual(marker.read_bytes(), b'held original fixture')
        self.assertEqual(list(self.destination.iterdir()), [marker])

    def test_floor_and_expected_allocations_refuse_before_creating_a_destination(self):
        with mock.patch.object(checkpoint.shutil, 'disk_usage',
                               return_value=SimpleNamespace(free=checkpoint.FLOOR)):
            with self.assertRaises(checkpoint.Refused):
                self.capture()
        self.assertFalse(self.destination.exists())

    def test_aggregate_cap_includes_existing_bytes_objects_restore_and_metadata(self):
        with self.assertRaises(checkpoint.Refused):
            self.capture(base_bytes=checkpoint.CAP)
        self.assertFalse(self.destination.exists())

    def test_a_hard_link_is_refused_without_adoption(self):
        original = self.roots['rpc'] / 'same.bin'
        alias = self.parent / 'outside-hard-link.bin'
        os.link(original, alias)
        with self.assertRaises(checkpoint.Refused):
            self.capture()
        self.assertFalse(self.destination.exists())
        self.assertEqual(alias.read_bytes(), b'synthetic shared bytes')

    def test_new_source_entries_during_copy_prevent_a_complete_checkpoint(self):
        original_copy = checkpoint.copy_file
        changed = False
        def copy(*args):
            nonlocal changed
            original_copy(*args)
            if not changed:
                changed = True
                (self.roots['rpc'] / 'new.bin').write_bytes(b'changed original fixture')
        with mock.patch.object(checkpoint, 'copy_file', side_effect=copy):
            with self.assertRaises(checkpoint.Refused):
                self.capture()
        self.assertTrue((self.roots['rpc'] / 'new.bin').exists())
        self.assertFalse((self.destination / 'complete.json').exists())
        self.assertTrue((self.destination / 'restore-claim.json').exists())

    def test_corrupted_object_cannot_be_restored_or_heal_its_original(self):
        original_write = checkpoint.write_record
        def write(path, raw, **kwargs):
            original_write(path, raw, **kwargs)
            if path.name == 'manifest.json':
                for item in (self.destination / 'objects').iterdir():
                    if item.stat().st_size:
                        item.chmod(0o600)
                        item.write_bytes(b'x'*item.stat().st_size)
        with mock.patch.object(checkpoint, 'write_record', side_effect=write):
            with self.assertRaises(checkpoint.Refused):
                self.capture()
        self.assertFalse((self.destination / 'complete.json').exists())
        self.assertEqual((self.roots['rpc'] / 'same.bin').read_bytes(), b'synthetic shared bytes')

    def test_replaced_object_directory_is_held_before_writing_into_its_replacement(self):
        original_copy = checkpoint.copy_file
        def copy(*args):
            objects = self.destination / 'objects'
            objects.rename(self.destination / 'held-objects')
            objects.mkdir()
            original_copy(*args)
        with mock.patch.object(checkpoint, 'copy_file', side_effect=copy):
            with self.assertRaises(checkpoint.Refused):
                self.capture()
        self.assertEqual(list((self.destination / 'objects').iterdir()), [])
        self.assertTrue((self.destination / 'held-objects').exists())
        self.assertFalse((self.destination / 'complete.json').exists())

    def test_changed_closure_authority_refuses_before_destination_allocation(self):
        closed = mock.Mock(side_effect=[True, False])
        with self.assertRaises(checkpoint.Refused):
            self.capture(closed=closed)
        self.assertFalse(self.destination.exists())

    def test_entry_bound_refuses_without_partial_allocation(self):
        with mock.patch.object(checkpoint, 'ENTRY_CAP', len(checkpoint.ROLES)):
            with self.assertRaises(checkpoint.Refused):
                self.capture()
        self.assertFalse(self.destination.exists())
