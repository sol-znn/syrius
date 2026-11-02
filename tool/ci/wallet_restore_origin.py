"""Bounded private observations; these values grant no process or write authority."""

from dataclasses import dataclass
import ntpath
from pathlib import PureWindowsPath
import re


FIELDS = frozenset(('schema', 'scope', 'profile', 'home', 'wallet', 'cache',
    'members', 'selected', 'saved', 'send_hash', 'send_token', 'send_amount',
    'node', 'chain'))
PROFILE = re.compile(r'ci-wallet-[a-f0-9]{24}')


class Refused(Exception):
    def __str__(self):
        return 'WALLET_ORIGIN_REFUSED'


def need(value):
    if not value:
        raise Refused()


def path(value):
    """Require a local drive path without aliases, alternate streams or parents."""
    need(type(value) is str and 0 < len(value) <= 4096
         and all(ord(char) >= 32 for char in value))
    drive, tail = ntpath.splitdrive(value)
    need(re.fullmatch(r'[A-Za-z]:', drive) is not None
         and tail.startswith(('\\', '/')) and ':' not in tail
         and not any(part in ('.', '..') for part in re.split(r'[\\/]', tail)))
    parts = PureWindowsPath(value).parts[1:]
    need(parts and all(part and not part.endswith(('.', ' ')) for part in parts))
    return ntpath.normpath(value)


def within(home, value):
    return (ntpath.normcase(home) != ntpath.normcase(value)
            and ntpath.normcase(ntpath.commonpath((home, value))) == ntpath.normcase(home))


@dataclass(frozen=True, repr=False)
class Origin:
    profile: str
    home: str
    wallet: str
    cache: str
    members: tuple
    selected: str
    saved: str
    send_hash: str
    send_token: str

    def __repr__(self):
        return '<private original wallet observations>'

    def copied_paths(self, restored_home):
        """Map only the captured relative names into a distinct sibling home."""
        restored = path(restored_home)
        need(PROFILE.fullmatch(ntpath.basename(restored)) is not None
             and ntpath.normcase(ntpath.dirname(restored)) == ntpath.normcase(ntpath.dirname(self.home))
             and ntpath.normcase(restored) != ntpath.normcase(self.home))
        wallet = ntpath.join(restored, ntpath.relpath(self.wallet, self.home))
        cache = ntpath.join(restored, ntpath.relpath(self.cache, self.home))
        need(within(restored, wallet) and within(restored, cache))
        return wallet, cache


def parse(value, expected_home):
    """Parse the authenticated reply while its identical original entry is live."""
    try:
        need(type(value) is dict and set(value) == FIELDS)
        need(type(value['schema']) is int and value['schema'] == 1
             and value['scope'] == 'private_owned_wallet_origin'
             and type(value['chain']) is int and value['chain'] == 321
             and value['node'] == 'ws://127.0.0.1:45998'
             and value['send_amount'] == '100000000')
        home, wallet, cache = (path(value[key]) for key in ('home', 'wallet', 'cache'))
        expected = path(expected_home)
        need(type(value['profile']) is str and PROFILE.fullmatch(value['profile']) is not None
             and ntpath.basename(home) == value['profile']
             and ntpath.basename(ntpath.dirname(home)) == '.harness'
             and ntpath.normcase(home) == ntpath.normcase(expected)
             and within(home, wallet) and within(home, cache)
             and ntpath.normcase(wallet) != ntpath.normcase(cache))
        members = value['members']
        need(type(members) is list and 2 <= len(members) <= 128
             and all(type(member) is str and 0 < len(member) <= 128
                     and all(33 <= ord(char) < 127 for char in member) for member in members)
             and len(set(members)) == len(members)
             and type(value['selected']) is str and type(value['saved']) is str
             and value['selected'] == value['saved'] == members[1])
        need(type(value['send_hash']) is str
             and re.fullmatch('[a-f0-9]{64}', value['send_hash']) is not None
             and value['send_hash'] != '0' * 64
             and value['send_token'] == 'zts1znnxxxxxxxxxxxxx9z4ulx')
        # Validate containment with normalized paths, but retain the exact Hive
        # value. The child compares the original stored string before claiming
        # its write; valid mixed separators must not change that string.
        return Origin(value['profile'], home, value['wallet'], cache, tuple(members),
                      value['selected'], value['saved'], value['send_hash'], value['send_token'])
    except (KeyError, TypeError, ValueError, Refused):
        raise Refused() from None
