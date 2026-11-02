"""Closed deployment-path binding with inert data and small owned fixtures."""

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tool.ci import closed_lab_checkpoint as checkpoint
from tool.ci import restored_lab_paths as paths


KEY = 'z1'+'a'*40


def config(root):
    return dict(DataPath=str(root), GenesisFile=str(root / 'genesis.json'),
        WalletPath=str(root / 'wallet'), Net=dict(ListenHost='127.0.0.1', ListenPort=45991),
        RPC=dict(EnableHTTP=True, HTTPHost='127.0.0.1', HTTPPort=45997),
        Producer=dict(Address='synthetic-owner', Index=1))


def keyfile(root):
    return dict(Path=str(root / 'wallet' / KEY), baseAddress=KEY, version=1, timestamp=123,
        crypto=dict(cipherName='aes-256-gcm', kdf='argon2.IDKey',
            cipherData='synthetic-cipher', nonce='synthetic-nonce', argon2Params=dict(salt='fixture')))


def observation():
    return dict(schema=1, scope='closed_node_path_binding', complete=True,
        configs=5, keyfiles=5, originals_unchanged=True, non_path_values_unchanged=True,
        claim_once=True, private_manifest_sha256='a'*64,
        native_reopen_qualified=False, seed_admitted=False)


class PolicyTests(unittest.TestCase):
    def roots(self):
        return Path('/fixture/original/rpc').absolute(), Path('/fixture/copied/rpc').absolute()

    def test_config_changes_exactly_the_three_original_deployment_fields(self):
        original, restored = self.roots()
        value = config(original)
        raw = checkpoint.encode(value)
        result = json.loads(paths.config_bytes(raw, original, restored))
        self.assertEqual({k: v for k, v in result.items() if k not in
            ('DataPath', 'GenesisFile', 'WalletPath')},
            {k: v for k, v in value.items() if k not in ('DataPath', 'GenesisFile', 'WalletPath')})
        self.assertEqual(result['DataPath'], str(restored))
        self.assertEqual(result['GenesisFile'], str(restored / 'genesis.json'))
        self.assertEqual(result['WalletPath'], str(restored / 'wallet'))
        self.assertEqual(json.loads(raw), value)

    def test_a_foreign_or_partially_rebound_config_is_not_adopted(self):
        original, restored = self.roots()
        for field in ('DataPath', 'GenesisFile', 'WalletPath'):
            value = config(original)
            value[field] = 'synthetic-foreign-path'
            with self.subTest(field=field), self.assertRaises(checkpoint.Refused):
                paths.config_bytes(checkpoint.encode(value), original, restored)

    def test_a_keyfile_keeps_every_encrypted_and_non_path_value(self):
        original, restored = self.roots()
        value = keyfile(original)
        result = json.loads(paths.keyfile_bytes(checkpoint.encode(value), KEY, original, restored))
        self.assertEqual(result['Path'], str(restored / 'wallet' / KEY))
        self.assertEqual({k: v for k, v in result.items() if k != 'Path'},
                         {k: v for k, v in value.items() if k != 'Path'})

    def test_keyfile_schema_and_original_path_must_match_before_rebinding(self):
        original, restored = self.roots()
        for field, wrong in (('Path', 'synthetic-foreign-path'), ('version', True),
                             ('baseAddress', 'synthetic-owner'), ('crypto', {}),
                             ('timestamp', False), ('extra', 'private fixture')):
            value = dict(keyfile(original), **{field: wrong})
            with self.subTest(field=field), self.assertRaises(checkpoint.Refused):
                paths.keyfile_bytes(checkpoint.encode(value), KEY, original, restored)

    def test_duplicate_nonfinite_and_oversized_metadata_is_refused(self):
        for raw in (b'{"Path":1,"Path":2}', b'{"value":NaN}', b'[]',
                    b'x'*(paths.FILE_CAP+1), b'private fixture'):
            with self.subTest(size=len(raw)), self.assertRaises(checkpoint.Refused):
                paths.parse(raw)

    def test_original_and_copy_cannot_overlap_or_be_the_same_root(self):
        original, _ = self.roots()
        for copied in (original, original / 'nested', original.parent):
            with self.subTest(name=copied.name), self.assertRaises(checkpoint.Refused):
                paths.roots(original, copied)

    def test_finite_binding_projection_keeps_absence_and_refusal(self):
        self.assertIsNone(paths.project(None))
        refused = dict(schema=1, scope='closed_node_path_binding', complete=False)
        self.assertEqual(paths.project(refused), refused)
        self.assertEqual(paths.project(observation()), observation())

    def test_metadata_binding_never_claims_reopen_seed_or_private_output(self):
        for key, value in (('native_reopen_qualified', True), ('seed_admitted', True),
                           ('private_path', 'private fixture'), ('configs', True),
                           ('keyfiles', paths.KEY_LIMIT+1), ('private_manifest_sha256', 'private')):
            with self.subTest(key=key), self.assertRaises(checkpoint.Refused):
                paths.project(dict(observation(), **{key: value}))


class FilesystemTests(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(prefix='syrius-node-path-binding-regression-')
        self.addCleanup(self.fixture.cleanup)
        parent = Path(self.fixture.name)
        self.home = parent / 'checkpoint'
        self.original = {role: parent / 'original' / role for role in paths.NODES}
        self.restored = {role: self.home / 'restored' / role for role in paths.NODES}
        self.configs, self.keys, self.before = {}, {}, {}
        for role in paths.NODES:
            original, restored = self.original[role], self.restored[role]
            (original / 'wallet').mkdir(parents=True)
            (restored / 'wallet').mkdir(parents=True)
            for relative, value in ((Path('config.json'), config(original)),
                                    (Path('wallet') / KEY, keyfile(original))):
                raw = checkpoint.encode(value)
                (original / relative).write_bytes(raw)
                (restored / relative).write_bytes(raw)
                self.before[original / relative] = raw
                digest = hashlib.sha256(raw).hexdigest()
                if relative.name == 'config.json':
                    self.configs[role] = digest
                else:
                    self.keys[original / relative] = digest

    def bind(self, **changes):
        return paths.bind_nodes(self.original, self.restored, self.home,
            changes.pop('closed', lambda: True), config_sha256=self.configs,
            keyfile_sha256=self.keys, measure=changes.pop('measure', lambda: 1024**2), **changes)

    def test_only_copied_paths_change_and_original_files_remain_exact(self):
        result = self.bind()
        self.assertEqual(result, dict(observation(), private_manifest_sha256=result['private_manifest_sha256']))
        for path, raw in self.before.items():
            self.assertEqual(path.read_bytes(), raw)
        for role in paths.NODES:
            original, copied = self.original[role], self.restored[role]
            self.assertEqual(json.loads((copied / 'config.json').read_bytes())['DataPath'], str(copied))
            self.assertEqual(json.loads((copied / 'wallet' / KEY).read_bytes())['crypto'], keyfile(original)['crypto'])
        self.assertTrue((self.home / 'node-paths-binding-claim.json').exists())
        self.assertTrue((self.home / 'node-paths-binding-complete.json').exists())

    def test_changed_copied_bytes_refuse_before_any_binding_claim(self):
        (self.restored['rpc'] / 'config.json').write_bytes(b'changed copied fixture')
        with self.assertRaises(checkpoint.Refused):
            self.bind()
        self.assertFalse((self.home / 'node-paths-binding-claim.json').exists())
        self.assertTrue(all(path.read_bytes() == raw for path, raw in self.before.items()))

    def test_interrupted_binding_holds_its_claim_without_undo_or_retry(self):
        original_write = paths.write_copy
        def interrupt(*args):
            original_write(*args)
            raise OSError('synthetic fixture interruption')
        with mock.patch.object(paths, 'write_copy', side_effect=interrupt):
            with self.assertRaises(OSError):
                self.bind()
        self.assertTrue((self.home / 'node-paths-binding-claim.json').exists())
        self.assertFalse((self.home / 'node-paths-binding-complete.json').exists())
        self.assertTrue(all(path.read_bytes() == raw for path, raw in self.before.items()))
        with self.assertRaises(checkpoint.Refused):
            self.bind()

    def test_replaced_copied_directory_is_held_before_any_path_update(self):
        original_write = checkpoint.write_record
        def replace(path, raw, **kwargs):
            original_write(path, raw, **kwargs)
            if path.name == 'node-paths-binding-claim.json':
                copied = self.restored['rpc']
                copied.rename(self.home / 'held-rpc')
                copied.mkdir()
        with mock.patch.object(checkpoint, 'write_record', side_effect=replace):
            with self.assertRaises(checkpoint.Refused):
                self.bind()
        self.assertTrue((self.home / 'held-rpc').exists())
        self.assertFalse((self.home / 'node-paths-binding-complete.json').exists())

    def test_uncertain_closure_refuses_without_a_saved_binding_authority(self):
        measure = mock.Mock()
        with self.assertRaises(checkpoint.Refused):
            self.bind(closed=lambda: False, measure=measure)
        measure.assert_not_called()
        self.assertFalse((self.home / 'node-paths-binding-claim.json').exists())

    def test_aggregate_capacity_and_expected_metadata_growth_are_reserved(self):
        with self.assertRaises(checkpoint.Refused):
            self.bind(measure=lambda: checkpoint.CAP)
        self.assertFalse((self.home / 'node-paths-binding-claim.json').exists())
