"""Rebind only deployment metadata in this attempt's closed independent copies."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import time

from . import closed_lab_checkpoint as checkpoint


NODES = checkpoint.ROLES[1:]
FILE_CAP = 64 * 1024
KEY_LIMIT = 64
METADATA_CAP = 128 * 1024


def project(value):
    if value is None:
        return None
    common = {'schema', 'scope', 'complete'}
    need(type(value) is dict and common <= set(value)
         and type(value['schema']) is int and value['schema'] == 1
         and value['scope'] == 'closed_node_path_binding' and type(value['complete']) is bool)
    if not value['complete']:
        need(set(value) == common)
        return dict(value)
    need(set(value) == common | {'configs', 'keyfiles', 'originals_unchanged',
         'non_path_values_unchanged', 'claim_once', 'private_manifest_sha256',
         'native_reopen_qualified', 'seed_admitted'}
         and type(value['configs']) is int and value['configs'] == len(NODES)
         and type(value['keyfiles']) is int and 0 < value['keyfiles'] <= KEY_LIMIT
         and all(value[key] is True for key in
                 ('originals_unchanged', 'non_path_values_unchanged', 'claim_once'))
         and value['native_reopen_qualified'] is value['seed_admitted'] is False
         and type(value['private_manifest_sha256']) is str
         and re.fullmatch('[a-f0-9]{64}', value['private_manifest_sha256']))
    return dict(value)


def need(value):
    checkpoint.need(value)


def parse(raw):
    need(type(raw) is bytes and 0 < len(raw) <= FILE_CAP)
    def pairs(items):
        value = {}
        for key, item in items:
            need(key not in value)
            value[key] = item
        return value
    def constant(_):
        raise checkpoint.Refused()
    try:
        value = json.loads(raw, object_pairs_hook=pairs, parse_constant=constant)
    except (ValueError, UnicodeError):
        raise checkpoint.Refused() from None
    need(type(value) is dict)
    return value


def roots(original, restored):
    original, restored = Path(original).absolute(), Path(restored).absolute()
    need(original != restored and original not in restored.parents
         and restored not in original.parents
         and all('..' not in root.parts and '\0' not in str(root)
                 and len(str(root)) <= 4096 for root in (original, restored)))
    return original, restored


def config_bytes(raw, original, restored):
    original, restored = roots(original, restored)
    value = parse(raw)
    expected = dict(DataPath=str(original), GenesisFile=str(original / 'genesis.json'),
                    WalletPath=str(original / 'wallet'))
    need(all(value.get(key) == item for key, item in expected.items()))
    updated = dict(value, DataPath=str(restored), GenesisFile=str(restored / 'genesis.json'),
                   WalletPath=str(restored / 'wallet'))
    return checkpoint.encode(updated)


def keyfile_bytes(raw, filename, original, restored):
    original, restored = roots(original, restored)
    need(type(filename) is str and re.fullmatch('z1[a-z0-9]{30,64}', filename))
    value = parse(raw)
    need(set(value) == {'Path', 'baseAddress', 'crypto', 'version', 'timestamp'}
         and value['Path'] == str(original / 'wallet' / filename)
         and type(value['baseAddress']) is str
         and re.fullmatch('z1[a-z0-9]{30,64}', value['baseAddress'])
         and type(value['version']) is int and value['version'] == 1
         and type(value['timestamp']) is int and type(value['crypto']) is dict)
    crypto = value['crypto']
    need(crypto.get('cipherName') == 'aes-256-gcm' and crypto.get('kdf') == 'argon2.IDKey'
         and all(type(crypto.get(key)) is str for key in ('cipherData', 'nonce'))
         and type(crypto.get('argon2Params')) is dict)
    return checkpoint.encode(dict(value, Path=str(restored / 'wallet' / filename)))


def read(path):
    before = checkpoint.file_identity(path.lstat())
    need(before[2] <= FILE_CAP)
    flags = os.O_RDONLY | getattr(os, 'O_BINARY', 0) | getattr(os, 'O_NOFOLLOW', 0)
    with os.fdopen(os.open(path, flags), 'rb') as source:
        need(checkpoint.file_identity(os.fstat(source.fileno())) == before)
        raw = source.read(FILE_CAP + 1)
        need(checkpoint.file_identity(os.fstat(source.fileno())) == before)
    need(len(raw) == before[2] and checkpoint.file_identity(path.lstat()) == before)
    return raw, before


def write_copy(path, raw, expected, guard):
    need(len(raw) <= FILE_CAP and guard() is True
         and checkpoint.file_identity(path.lstat()) == expected)
    flags = os.O_RDWR | getattr(os, 'O_BINARY', 0) | getattr(os, 'O_NOFOLLOW', 0)
    with os.fdopen(os.open(path, flags), 'r+b') as copied:
        need(guard() is True and checkpoint.file_identity(os.fstat(copied.fileno())) == expected)
        copied.seek(0)
        copied.write(raw)
        copied.truncate()
        copied.flush()
        os.fsync(copied.fileno())
    need(guard() is True and read(path)[0] == raw)
    actual = checkpoint.file_identity(path.lstat())
    need(actual[:2] == expected[:2])
    return actual


def bind_nodes(original, restored, home, closed, *, config_sha256, keyfile_sha256, measure):
    """Preserve originals and all non-path values; hold every interrupted claim."""
    need(callable(closed) and closed() is True and callable(measure)
         and type(original) is dict and type(restored) is dict and type(config_sha256) is dict
         and set(original) == set(restored) == set(config_sha256) == set(NODES)
         and type(keyfile_sha256) is dict and 0 < len(keyfile_sha256) <= KEY_LIMIT)
    deadline = time.monotonic() + checkpoint.SECONDS
    original = {role: Path(path).absolute() for role, path in original.items()}
    restored = {role: Path(path).absolute() for role, path in restored.items()}
    home = Path(home).absolute()
    pins = dict(checkpoint.ancestors(home))
    for role in NODES:
        roots(original[role], restored[role])
        need(restored[role] == home / 'restored' / role)
        pins.update(checkpoint.ancestors(original[role]))
        pins.update(checkpoint.ancestors(restored[role]))
    need(all(left != right and left not in right.parents and right not in left.parents
             for left in original.values() for right in restored.values()))
    need(len(set(original.values())) == len(set(restored.values())) == len(NODES)
         and all(home != root and root not in home.parents for root in original.values()))
    plan = []

    def add(role, relative, transform, digest):
        need(time.monotonic() < deadline)
        source, target = original[role] / relative, restored[role] / relative
        pins.update(checkpoint.ancestors(source.parent))
        pins.update(checkpoint.ancestors(target.parent))
        raw, source_id = read(source)
        copied, target_id = read(target)
        need(type(digest) is str and re.fullmatch('[a-f0-9]{64}', digest)
             and hashlib.sha256(raw).hexdigest() == digest and copied == raw
             and source_id[:2] != target_id[:2])
        updated = transform(raw)
        need(len(updated) <= FILE_CAP)
        plan.append((role, relative, source, source_id, target, target_id, raw, updated))

    for role in NODES:
        add(role, Path('config.json'),
            lambda raw: config_bytes(raw, original[role], restored[role]), config_sha256[role])
    for source, digest in keyfile_sha256.items():
        source = Path(source).absolute()
        owners = [role for role in NODES if source.parent == original[role] / 'wallet']
        need(len(owners) == 1)
        role = owners[0]
        add(role, Path('wallet') / source.name,
            lambda raw: keyfile_bytes(raw, source.name, original[role], restored[role]), digest)

    written = {}

    def guard():
        need(closed() is True and time.monotonic() < deadline
             and all(checkpoint.directory(path) == identity for path, identity in pins.items())
             and all(checkpoint.file_identity(source.lstat()) == identity
                     for _, _, source, identity, _, _, _, _ in plan)
             and all(checkpoint.file_identity(path.lstat()) == identity
                     for path, identity in written.items()))
        return True

    rows = [dict(role=role, file=relative.as_posix(), before=hashlib.sha256(raw).hexdigest(),
        after=hashlib.sha256(updated).hexdigest(), before_bytes=len(raw), after_bytes=len(updated))
        for role, relative, _, _, _, _, raw, updated in plan]
    intent = checkpoint.encode(dict(schema=1, scope='closed_node_path_binding', files=rows))
    growth = sum(max(0, len(updated)-len(raw)) for _, _, _, _, _, _, raw, updated in plan)
    reserved = growth + len(intent) + 4096
    measured = measure()
    need(type(measured) is int and 0 <= measured and measured + reserved <= checkpoint.CAP
         and len(intent) <= METADATA_CAP
         and shutil.disk_usage(home).free >= checkpoint.FLOOR + reserved and guard() is True)
    checkpoint.write_record(home / 'node-paths-binding-claim.json', intent, guard=guard)
    for _, _, _, _, target, target_id, _, updated in plan:
        written[target] = write_copy(target, updated, target_id, guard)
    need(guard() is True and all(read(source)[0] == raw
         for _, _, source, _, _, _, raw, _ in plan)
         and all(read(target)[0] == updated for _, _, _, _, target, _, _, updated in plan))
    measured = measure()
    need(type(measured) is int and 0 <= measured <= checkpoint.CAP
         and shutil.disk_usage(home).free >= checkpoint.FLOOR)
    summary = dict(schema=1, scope='closed_node_path_binding', complete=True,
        configs=len(NODES), keyfiles=len(keyfile_sha256), originals_unchanged=True,
        non_path_values_unchanged=True, claim_once=True,
        private_manifest_sha256=hashlib.sha256(intent).hexdigest(),
        native_reopen_qualified=False, seed_admitted=False)
    need(project(summary) == summary)
    checkpoint.write_record(home / 'node-paths-binding-complete.json', checkpoint.encode(summary), guard=guard)
    return summary
