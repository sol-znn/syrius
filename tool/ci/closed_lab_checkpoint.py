"""One closed, owned hosted lab snapshot and one independent bytewise restore.

This is a fresh CI fixture operation. It never adopts saved manifests, reopens
processes, rewinds a live chain, removes originals or retries a publication.
Private file names and contents remain on the isolated runner.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import time


ROLES = ('wallet_profile', 'pillar', 'pillar2', 'pillar3', 'observer', 'rpc')
CAP = 4 * 1024**3
FLOOR = 2 * 1024**3  # Fresh hosted regression fixture; never local production.
METADATA_CAP = 8 * 1024**2
ENTRY_CAP = 20000
CHUNK = 64 * 1024
SECONDS = 180


class Refused(Exception):
    code = 'CHECKPOINT_REFUSED'

    def __init__(self):
        super().__init__(self.code)


def need(condition):
    if not condition:
        raise Refused()


def encode(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode('ascii')


def project(value):
    """A finite copy observation cannot authorize native reopen or seed."""
    if value is None:
        return None
    common = {'schema', 'scope', 'complete'}
    need(type(value) is dict and common <= set(value)
         and type(value['schema']) is int and value['schema'] == 1
         and value['scope'] == 'closed_owned_lab_checkpoint'
         and type(value['complete']) is bool)
    if not value['complete']:
        need(set(value) == common)
        return dict(value)
    integers = {'roots', 'files', 'entries', 'source_bytes', 'object_bytes',
                'restored_bytes', 'objects', 'reserved_bytes', 'manifest_bytes'}
    flags = {'independent_copies', 'source_unchanged', 'single_restore_claim'}
    optional = {'canonical_wallet_home', 'external_wallet_bytes'}
    required = common | integers | flags | {'manifest_sha256', 'retention',
                                          'native_reopen_qualified', 'seed_admitted'}
    need(set(value) in (required, required | optional))
    if optional <= set(value):
        need(value['canonical_wallet_home'] is True
             and type(value['external_wallet_bytes']) is int
             and type(value['source_bytes']) is int
             and 0 <= value['external_wallet_bytes'] <= value['source_bytes'])
    need(all(type(value[key]) is int and 0 <= value[key] <= CAP for key in integers)
         and all(value[key] is True for key in flags)
         and value['native_reopen_qualified'] is value['seed_admitted'] is False
         and value['retention'] == 'isolated_runner_lifecycle'
         and type(value['manifest_sha256']) is str
         and re.fullmatch('[a-f0-9]{64}', value['manifest_sha256']))
    need(value['roots'] == len(ROLES) and value['files'] <= value['entries'] - len(ROLES)
         and value['entries'] <= ENTRY_CAP and value['objects'] <= value['files']
         and bool(value['objects']) == bool(value['files'])
         and value['object_bytes'] <= value['source_bytes'] == value['restored_bytes']
         and (value['source_bytes'] == 0 or value['object_bytes'] > 0)
         and value['reserved_bytes'] == value['source_bytes'] + value['object_bytes'] + METADATA_CAP
         and 0 < value['manifest_bytes'] <= METADATA_CAP - 4096)
    return dict(value)


def directory(path):
    info = path.lstat()
    need(stat.S_ISDIR(info.st_mode) and info.st_ino > 0
         and not stat.S_ISLNK(info.st_mode)
         and not getattr(info, 'st_file_attributes', 0) & 0x400
         and not getattr(info, 'st_reparse_tag', 0))
    return info.st_dev, info.st_ino


def ancestors(path):
    return [(parent, directory(parent)) for parent in reversed((path, *path.parents))]


def file_identity(info):
    need(stat.S_ISREG(info.st_mode) and info.st_ino > 0 and info.st_nlink == 1
         and type(info.st_size) is int and info.st_size >= 0
         and not getattr(info, 'st_file_attributes', 0) & 0x400
         and not getattr(info, 'st_reparse_tag', 0))
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)


def part(value):
    need(type(value) is str and 0 < len(value) <= 240
         and value not in ('.', '..') and not value.endswith((' ', '.'))
         and not any(ord(char) < 32 or char in ':\\/*?"<>|' for char in value)
         and not re.fullmatch(r'(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?', value))


def digest_file(path, expected, deadline):
    need(file_identity(path.lstat()) == expected)
    digest = hashlib.sha256()
    count = 0
    flags = os.O_RDONLY | getattr(os, 'O_BINARY', 0) | getattr(os, 'O_NOFOLLOW', 0)
    with os.fdopen(os.open(path, flags), 'rb') as source:
        need(file_identity(os.fstat(source.fileno())) == expected)
        while True:
            need(time.monotonic() < deadline)
            data = source.read(CHUNK)
            if not data:
                break
            count += len(data)
            need(count <= expected[2])
            digest.update(data)
        need(file_identity(os.fstat(source.fileno())) == expected)
    need(count == expected[2] and file_identity(path.lstat()) == expected)
    return digest.hexdigest()


def catalog(roots, deadline):
    rows, files, directories, seen = [], {}, {}, set()
    total, metadata = 0, 4096
    pending = [(role, roots[role], ()) for role in reversed(ROLES)]
    while pending:
        need(time.monotonic() < deadline and len(rows) < ENTRY_CAP)
        role, path, relative = pending.pop()
        need(len(relative) <= 32)
        key = (role, '/'.join(relative))
        folded = (role, key[1].casefold())
        need(folded not in seen)
        seen.add(folded)
        info = path.lstat()
        if stat.S_ISDIR(info.st_mode):
            directories[key] = (path, directory(path))
            rows.append(dict(role=role, path=key[1], kind='directory'))
            with os.scandir(path) as children:
                names = []
                for entry in children:
                    names.append(entry.name)
                    need(len(rows) + len(pending) + len(names) <= ENTRY_CAP)
            for name in sorted(names, reverse=True):
                part(name)
                pending.append((role, path / name, relative + (name,)))
        else:
            identity = file_identity(info)
            total += identity[2]
            need(total <= CAP)
            digest = digest_file(path, identity, deadline)
            files[key] = (path, identity, digest)
            rows.append(dict(role=role, path=key[1], kind='file',
                             bytes=identity[2], sha256=digest))
        metadata += len(encode(rows[-1]))
        need(metadata <= METADATA_CAP)
    return rows, files, directories, total


def write_record(path, raw, *, guard=None):
    need(len(raw) <= METADATA_CAP)
    need(guard is None or guard() is True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_BINARY', 0)
    descriptor = os.open(path, flags | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    with os.fdopen(descriptor, 'wb') as output:
        need(guard is None or guard() is True)
        output.write(raw)
        output.flush()
        os.fsync(output.fileno())
    path.chmod(0o400)
    need(guard is None or guard() is True)


def copy_file(source, destination, expected, digest, deadline, guard):
    need(guard() is True and file_identity(source.lstat()) == expected)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_BINARY', 0)
    descriptor = os.open(destination, flags | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    with os.fdopen(descriptor, 'wb') as output:
        need(guard() is True)
        flags = os.O_RDONLY | getattr(os, 'O_BINARY', 0) | getattr(os, 'O_NOFOLLOW', 0)
        with os.fdopen(os.open(source, flags), 'rb') as original:
            need(file_identity(os.fstat(original.fileno())) == expected)
            actual, size = hashlib.sha256(), 0
            while True:
                need(time.monotonic() < deadline)
                data = original.read(CHUNK)
                if not data:
                    break
                size += len(data)
                need(size <= expected[2])
                actual.update(data)
                output.write(data)
            need(file_identity(os.fstat(original.fileno())) == expected)
        output.flush()
        os.fsync(output.fileno())
    need(size == expected[2] and actual.hexdigest() == digest
         and guard() is True and file_identity(source.lstat()) == expected)
    copied = file_identity(destination.lstat())
    need(copied[:2] != expected[:2] and copied[2] == expected[2])
    need(digest_file(destination, copied, deadline) == digest)
    need(guard() is True)


def canonical_target(original, offered):
    original, offered = Path(original).absolute(), Path(offered).absolute()
    need(original.parent == offered.parent and original.parent.name == '.harness'
         and original != offered
         and all('..' not in path.parts
                 and re.fullmatch('ci-wallet-[a-f0-9]{24}', path.name)
                 for path in (original, offered)))
    return offered


def capture_restore(roots, destination, closed, *, base_bytes, binding, wallet_home=None):
    """Use current original-process closure authority, never a saved receipt.

    The caller owns all six data roots and the fresh destination's parent.
    The returned directories are inert copies: path rebinding, ordinary reopen,
    journal admission and real seed effects still need separate qualification.
    """
    try:
        return _capture_restore(roots, destination, closed,
                                base_bytes=base_bytes, binding=binding, wallet_home=wallet_home)
    except (OSError, ValueError, TypeError, OverflowError):
        raise Refused() from None


def _capture_restore(roots, destination, closed, *, base_bytes, binding, wallet_home):
    need(callable(closed) and closed() is True)
    need(type(roots) is dict and set(roots) == set(ROLES)
         and type(base_bytes) is int and 0 <= base_bytes <= CAP)
    need(type(binding) is dict and set(binding) ==
         {'source_sha', 'source_tree', 'node_sha', 'node_tree',
          'genesis_sha256', 'run_id', 'attempt'})
    for key in ('source_sha', 'source_tree', 'node_sha', 'node_tree'):
        need(type(binding[key]) is str and re.fullmatch('[a-f0-9]{40}', binding[key]))
    need(type(binding['genesis_sha256']) is str
         and re.fullmatch('[a-f0-9]{64}', binding['genesis_sha256'])
         and type(binding['run_id']) is str and re.fullmatch('[1-9][0-9]{0,19}', binding['run_id'])
         and type(binding['attempt']) is int and 0 < binding['attempt'] <= 100)
    roots = {role: Path(path).absolute() for role, path in roots.items()}
    destination = Path(destination).absolute()
    paths = [*roots.values(), destination]
    if wallet_home is not None:
        wallet_home = canonical_target(roots['wallet_profile'], wallet_home)
        need(not os.path.lexists(wallet_home))
        paths.append(wallet_home)
    need(all('..' not in path.parts for path in paths))
    need(all(left != right and left not in right.parents and right not in left.parents
             for i, left in enumerate(paths) for right in paths[i+1:]))
    pins = {path: ancestors(path) for path in roots.values()}
    parent_pins = ancestors(destination.parent)
    if wallet_home is not None:
        need(directory(wallet_home.parent)[0] == directory(destination.parent)[0])
    need(not os.path.lexists(destination))
    deadline = time.monotonic() + SECONDS
    rows, files, directories, source_bytes = catalog(roots, deadline)
    unique = {}
    for path, identity, digest in files.values():
        if digest in unique:
            need(unique[digest][1][2] == identity[2])
        else:
            unique[digest] = (path, identity)
    object_bytes = sum(identity[2] for _, identity in unique.values())
    reservation = object_bytes + source_bytes + METADATA_CAP
    need(base_bytes >= source_bytes and base_bytes + reservation <= CAP
         and shutil.disk_usage(destination.parent).free >= FLOOR + reservation)
    manifest = encode(dict(schema=1, scope='closed_owned_lab_data', binding=binding, entries=rows))
    need(len(manifest) + 4096 <= METADATA_CAP and closed() is True)
    owned, object_pins = {}, {}
    expected_directories = dict(parent_pins)
    for chain in pins.values():
        expected_directories.update(chain)
    expected_directories.update({path: identity for path, identity in directories.values()})

    def parents_intact(*paths):
        for path in paths:
            need(all(directory(parent) == owned.get(parent, expected_directories.get(parent))
                     for parent in (path.parent, *path.parent.parents)))
        return True

    def stable():
        need(closed() is True and time.monotonic() < deadline)
        need(shutil.disk_usage(destination.parent).free >= FLOOR)
        for chain in [*pins.values(), parent_pins]:
            need(all(directory(path) == identity for path, identity in chain))
        need(all(directory(path) == identity for path, identity in directories.values()))
        need(all(file_identity(path.lstat()) == identity for path, identity, _ in files.values()))
        need(all(directory(path) == identity for path, identity in owned.items()))
        need(all(file_identity(path.lstat()) == identity for path, identity in object_pins.values()))

    stable()
    destination.mkdir(mode=0o700)
    owned[destination] = directory(destination)
    objects, restored = destination / 'objects', destination / 'restored'
    need(parents_intact(objects))
    objects.mkdir(mode=0o700)
    owned[objects] = directory(objects)
    need(parents_intact(restored))
    restored.mkdir(mode=0o700)
    owned[restored] = directory(restored)
    record_guard = lambda: parents_intact(destination / 'record.json')
    write_record(destination / 'capture-intent.json', encode(dict(
        schema=1, binding=binding, source_bytes=source_bytes,
        object_bytes=object_bytes, reserved_bytes=reservation)), guard=record_guard)
    for digest, (path, identity) in unique.items():
        need(closed() is True and time.monotonic() < deadline)
        need(shutil.disk_usage(destination.parent).free >= FLOOR + identity[2])
        target = objects / digest
        copy_file(path, target, identity, digest, deadline,
                  lambda: parents_intact(path, target))
        target.chmod(0o400)
        object_pins[digest] = (target, file_identity(target.lstat()))
    stable()
    write_record(destination / 'manifest.json', manifest, guard=record_guard)
    # This durable exclusive claim is outside the immutable baseline objects.
    # A partial restore is held; no entry point can load a manifest and retry it.
    write_record(destination / 'restore-claim.json', encode(dict(schema=1, binding=binding)),
                 guard=record_guard)
    restored_roots = {role: restored / role for role in ROLES}
    if wallet_home is not None:
        restored_roots['wallet_profile'] = wallet_home
    for row in rows:
        target = restored_roots[row['role']]
        if row['path']:
            target = target.joinpath(*row['path'].split('/'))
        if row['kind'] == 'directory':
            need(parents_intact(target))
            target.mkdir(mode=0o700)
            owned[target] = directory(target)
        else:
            original = objects / row['sha256']
            need(closed() is True
                 and shutil.disk_usage(destination.parent).free >= FLOOR + row['bytes'])
            copy_file(original, target, object_pins[row['sha256']][1], row['sha256'], deadline,
                      lambda: parents_intact(original, target))
    stable()
    need(catalog(restored_roots, deadline)[0] == rows
         and catalog(roots, deadline)[0] == rows)
    stable()
    summary = dict(schema=1, scope='closed_owned_lab_checkpoint', complete=True,
        roots=len(ROLES), files=len(files), entries=len(rows), source_bytes=source_bytes,
        object_bytes=object_bytes, restored_bytes=source_bytes,
        objects=len(unique), reserved_bytes=reservation,
        manifest_bytes=len(manifest), manifest_sha256=hashlib.sha256(manifest).hexdigest(),
        independent_copies=True, source_unchanged=True, single_restore_claim=True,
        retention='isolated_runner_lifecycle',
        native_reopen_qualified=False, seed_admitted=False)
    if wallet_home is not None:
        summary.update(canonical_wallet_home=True,
            external_wallet_bytes=sum(row['bytes'] for row in rows
                if row['role'] == 'wallet_profile' and row['kind'] == 'file'))
    need(project(summary) == summary)
    write_record(destination / 'complete.json', encode(summary), guard=record_guard)
    return restored_roots, summary
