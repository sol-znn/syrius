"""Private protocol policy only; no files, native processes, RPC or wallet access."""

from dataclasses import FrozenInstanceError
import ntpath
from pathlib import PureWindowsPath
import unittest
from unittest import mock

from tool.ci import wallet_restore_origin as origin
from tool.ci import windows_wallet_tour as tour


HOME = r'C:\fixture\.harness\ci-wallet-' + '1' * 24
RESTORED = r'C:\fixture\.harness\ci-wallet-' + '2' * 24


def observations():
    return dict(schema=1, scope='private_owned_wallet_origin',
        profile=ntpath.basename(HOME), home=HOME,
        wallet=HOME + r'\AppData\Roaming\fixture\wallet\one.json',
        cache=HOME + r'\AppData\Roaming\fixture\cache',
        members=['synthetic-member-zero', 'synthetic-member-one'],
        selected='synthetic-member-one', saved='synthetic-member-one',
        send_hash='a' * 64, send_token='zts1znnxxxxxxxxxxxxx9z4ulx',
        send_amount='100000000', node='ws://127.0.0.1:45998', chain=321)


def quiescence():
    return dict(schema=1, scope='owned_lab_quiescence', chain=321, complete=True,
        admission_closed=True, original_send_confirmed=True, originals_positive=True,
        file_operations=2, sdk_publications=2, receive_reads=1, receive_publications=1)


class OriginPolicyTests(unittest.TestCase):
    def parse(self, **changes):
        return origin.parse(dict(observations(), **changes), HOME)

    def test_only_exact_original_observations_are_retained(self):
        value = observations()
        parsed = origin.parse(value, HOME)
        self.assertEqual(parsed.home, HOME)
        self.assertEqual(parsed.wallet, value['wallet'])
        self.assertEqual(parsed.cache, value['cache'])
        self.assertEqual(parsed.send_hash, value['send_hash'])
        self.assertEqual(parsed.members, tuple(value['members']))

    def test_protocol_dictionaries_cannot_mutate_the_retained_origin(self):
        value = observations()
        parsed = origin.parse(value, HOME)
        value['members'].append('later-private-value')
        value['wallet'] = 'later-private-path'
        self.assertEqual(len(parsed.members), 2)
        self.assertTrue(parsed.wallet.endswith('one.json'))
        with self.assertRaises(FrozenInstanceError):
            parsed.send_hash = 'b' * 64

    def test_mixed_separator_wallet_spelling_stays_exact_for_the_hive_comparison(self):
        wallet = (HOME.replace('C:', 'c:').replace('\\', '/')
                  + '/AppData\\Roaming/fixture\\wallet/one.json')
        parsed = self.parse(wallet=wallet)
        self.assertEqual(parsed.wallet, wallet)
        self.assertNotEqual(parsed.wallet, ntpath.normpath(wallet))
        copied, _ = parsed.copied_paths(RESTORED)
        self.assertEqual(copied, ntpath.join(RESTORED,
            'AppData', 'Roaming', 'fixture', 'wallet', 'one.json'))

    def test_rendering_never_contains_private_observations(self):
        parsed = self.parse()
        self.assertEqual(repr(parsed), '<private original wallet observations>')
        self.assertEqual(str(parsed), repr(parsed))
        with self.assertRaises(origin.Refused) as failure:
            self.parse(wallet='private-invalid-path')
        self.assertEqual(str(failure.exception), 'WALLET_ORIGIN_REFUSED')
        self.assertEqual(failure.exception.args, ())

    def test_missing_extra_or_non_mapping_protocol_is_refused(self):
        value = observations()
        for candidate in (None, [], dict(value, password='private'),
                          {key: item for key, item in value.items() if key != 'send_hash'}):
            with self.subTest(kind=type(candidate).__name__), self.assertRaises(origin.Refused):
                origin.parse(candidate, HOME)

    def test_coercion_or_another_lab_cannot_supply_original_facts(self):
        for field, value in (('schema', True), ('schema', 1.0), ('chain', 321.0),
                ('chain', 1), ('scope', 'owned_lab_quiescence'),
                ('node', 'ws://localhost:45998'), ('send_amount', 100000000),
                ('send_amount', '100000001'), ('send_token', 'zts1other'),
                ('send_hash', '0' * 64), ('send_hash', 'A' * 64)):
            with self.subTest(field=field), self.assertRaises(origin.Refused):
                self.parse(**{field: value})

    def test_another_valid_home_cannot_replace_the_original_profile(self):
        for expected in (RESTORED, r'C:\fixture\.harness\default',
                         ntpath.join(r'D:\fixture\.harness', ntpath.basename(HOME))):
            with self.subTest(expected=expected), self.assertRaises(origin.Refused):
                origin.parse(observations(), expected)

    def test_profile_name_must_be_the_exact_captured_named_home(self):
        for profile in ('default', 'ci-wallet-' + '2' * 24, 'CI-WALLET-' + '1' * 24, ''):
            with self.subTest(profile=profile), self.assertRaises(origin.Refused):
                self.parse(profile=profile)

    def test_paths_refuse_network_device_relative_parent_and_stream_aliases(self):
        for path in (r'\\server\share\wallet', r'\\?\C:\fixture\wallet',
                r'C:relative', '/fixture/wallet', HOME + r'\wallet\..\one.json',
                HOME + r'\wallet\.\one.json', HOME + r'\wallet\one.json:stream',
                HOME + '\\wallet\\one\x00.json', HOME + r'\wallet\one.json.',
                HOME + '\\wallet\\one.json ', HOME + '\\' + 'x' * 4096):
            for field in ('wallet', 'cache'):
                with self.subTest(field=field, vector=path[:24]), self.assertRaises(origin.Refused):
                    self.parse(**{field: path})

    def test_wallet_and_cache_must_stay_within_the_original_home(self):
        for field in ('wallet', 'cache'):
            for path in (HOME, RESTORED + r'\wallet', r'C:\foreign\wallet',
                         r'D:\foreign\wallet'):
                with self.subTest(field=field, path=path), self.assertRaises(origin.Refused):
                    self.parse(**{field: path})
        with self.assertRaises(origin.Refused):
            self.parse(cache=observations()['wallet'])

    def test_membership_requires_unique_bounded_ordered_original_members(self):
        for members in ([], ['one'], ['same', 'same'], ['zero', None],
                ['zero', 'with space'], ['zero', 'x' * 129],
                ['member-' + str(index) for index in range(129)]):
            with self.subTest(length=len(members)), self.assertRaises(origin.Refused):
                self.parse(members=members)

    def test_only_persisted_index_one_selection_is_accepted(self):
        for change in (dict(selected='synthetic-member-zero'),
                dict(saved='synthetic-member-zero'), dict(selected=None),
                dict(members=['synthetic-member-one', 'synthetic-member-zero'])):
            with self.subTest(change=change), self.assertRaises(origin.Refused):
                self.parse(**change)

    def test_mapping_uses_only_the_captured_relative_wallet_and_cache(self):
        parsed = self.parse()
        wallet, cache = parsed.copied_paths(RESTORED)
        self.assertEqual(wallet, ntpath.join(RESTORED, ntpath.relpath(parsed.wallet, HOME)))
        self.assertEqual(cache, ntpath.join(RESTORED, ntpath.relpath(parsed.cache, HOME)))
        self.assertEqual(parsed.home, HOME)

    def test_mapping_refuses_original_default_foreign_and_nested_homes(self):
        parsed = self.parse()
        for restored in (HOME, ntpath.dirname(HOME) + r'\default',
                ntpath.join(r'C:\foreign', ntpath.basename(RESTORED)), RESTORED + r'\nested',
                ntpath.join(r'\\server\share', ntpath.basename(RESTORED))):
            with self.subTest(restored=restored), self.assertRaises(origin.Refused):
                parsed.copied_paths(restored)


class OriginalHandoffTests(unittest.TestCase):
    def witness(self):
        entry = mock.Mock(poll=mock.Mock(return_value=None))
        parsed = origin.parse(observations(), HOME)
        witness = tour._QuiescenceHandoff(entry, quiescence(), parsed)
        return entry, parsed, witness

    def test_saved_data_cannot_supply_a_live_original_handoff(self):
        for candidate in (observations(), dict(closed=True)):
            with self.subTest(candidate=type(candidate).__name__), self.assertRaises(tour.Refused):
                tour._QuiescenceHandoff(mock.Mock(poll=mock.Mock(return_value=None)),
                                       quiescence(), candidate)

    def test_origin_requires_the_identical_normal_closed_original_and_home(self):
        entry, parsed, witness = self.witness()
        with self.assertRaises(tour.Refused):
            witness.origin_for(entry, PureWindowsPath(HOME))
        entry.poll.return_value = 0
        self.assertIs(witness.origin_for(entry, PureWindowsPath(HOME)), parsed)
        for other_entry, home in ((mock.Mock(poll=mock.Mock(return_value=0)), HOME),
                                  (entry, RESTORED)):
            with self.subTest(home=home), self.assertRaises(tour.Refused):
                witness.origin_for(other_entry, PureWindowsPath(home))

    def test_legacy_or_missing_private_origin_cannot_authorize_restore(self):
        entry = mock.Mock(poll=mock.Mock(return_value=None))
        witness = tour._QuiescenceHandoff(entry, quiescence())
        entry.poll.return_value = 0
        self.assertTrue(witness.closed_for(entry))
        with self.assertRaises(tour.Refused):
            witness.origin_for(entry, PureWindowsPath(HOME))

    def test_a_replaced_closed_home_refuses_before_returning_private_facts(self):
        entry, _, witness = self.witness()
        entry.poll.return_value = 0
        wallet = tour._ClosedWallet(PureWindowsPath(HOME), entry, (1, 2),
            'synthetic-password', (), (3, 4), witness)
        with mock.patch.object(wallet, 'closed', return_value=False):
            with self.assertRaises(tour.Refused):
                wallet.restoration_origin()
        with mock.patch.object(wallet, 'closed', return_value=True):
            self.assertIs(wallet.restoration_origin(), witness.origin_for(entry, wallet.home))


if __name__ == '__main__':
    unittest.main()
