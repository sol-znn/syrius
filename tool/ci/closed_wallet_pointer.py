"""One owned Hive binding child after all original wallet and lab actors close."""

import hashlib
import ntpath
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import time

from . import closed_lab_checkpoint as checkpoint
from . import wallet_restore_origin
from . import windows_debug_loop as debug


SCOPE = 'closed_wallet_pointer_binding'
METADATA = 64 * 1024
PHASES = ('admission', 'origin', 'source', 'paths', 'input_pins',
          'reservation', 'launch', 'start', 'input', 'claim', 'binding',
          'finish', 'close', 'complete')
CHILD_PHASES = ('gate', 'input', 'binding', 'finish', 'unknown')
CHILD_DETAILS = ('path', 'open', 'read', 'claim', 'write', 'flush', 'close', 'unknown')
OUTPUT_CODES = ('PUB_RESOLUTION', 'PUB_EXECUTABLE_BUILD', 'UNHANDLED_EXCEPTION',
                'COMPILE_OR_USAGE_ERROR', 'VM_SERVICE_LISTENER',
                'UNCLASSIFIED_OUTPUT', 'POINTER_CHILD_REFUSED')


def diagnostic_projection(value):
    """Only finite failure location and original line digests leave the child."""
    checkpoint.need(type(value) is dict and set(value) ==
        {'schema', 'scope', 'phase', 'child_phase', 'child_detail', 'output'}
        and type(value['schema']) is int and value['schema'] == 1
        and value['scope'] == 'closed_wallet_pointer_diagnostic'
        and value['phase'] in PHASES
        and (value['child_phase'] is None or value['child_phase'] in CHILD_PHASES)
        and (value['child_detail'] is None or value['child_detail'] in CHILD_DETAILS))
    output = value['output']
    if output is not None:
        checkpoint.need(type(output) is dict and set(output) == {'code', 'bytes', 'sha256'}
            and output['code'] in OUTPUT_CODES and type(output['bytes']) is int
            and 0 < output['bytes'] <= debug.protocol.MAX_LINE + 1
            and type(output['sha256']) is str
            and re.fullmatch('[a-f0-9]{64}', output['sha256']))
    checkpoint.need((value['child_phase'] is not None) ==
        (output is not None and output['code'] == 'POINTER_CHILD_REFUSED')
        and (value['child_phase'] is not None or value['child_detail'] is None))
    return dict(value, output=None if output is None else dict(output))


class PointerDiagnostic:
    """Data-only progress; it creates no process, file or write authority."""

    def __init__(self):
        self.phase = 'admission'
        self.child_phase = self.child_detail = self.output = None

    def at(self, phase):
        checkpoint.need(type(phase) is str and phase in PHASES)
        self.phase = phase
        return phase

    def unexpected_line(self, raw):
        checkpoint.need(self.output is None and type(raw) is bytes
            and 0 < len(raw) <= debug.protocol.MAX_LINE + 1)
        line = raw.replace(b'\r\n', b'\n')
        match = re.fullmatch(rb'CI_POINTER_ERROR:([a-z_]+)(?::([a-z_]+))?\n', line)
        if match is not None:
            phase = match[1].decode('ascii')
            detail = None if match[2] is None else match[2].decode('ascii')
            if phase in CHILD_PHASES and (detail is None or detail in CHILD_DETAILS):
                self.child_phase, self.child_detail = phase, detail
        self.output = debug.probe_line_observation(raw)
        if self.child_phase is not None:
            self.output['code'] = 'POINTER_CHILD_REFUSED'

    def snapshot(self):
        return diagnostic_projection(dict(schema=1,
            scope='closed_wallet_pointer_diagnostic', phase=self.phase,
            child_phase=self.child_phase, child_detail=self.child_detail, output=self.output))


def project(value):
    if value is None:
        return None
    common = {'schema', 'scope', 'complete'}
    checkpoint.need(type(value) is dict and common <= set(value)
        and type(value['schema']) is int and value['schema'] == 1
        and value['scope'] == SCOPE and type(value['complete']) is bool)
    if not value['complete']:
        checkpoint.need(set(value) in (common, common | {'diagnostic'}))
        return (dict(value, diagnostic=diagnostic_projection(value['diagnostic']))
                if 'diagnostic' in value else dict(value))
    checkpoint.need(set(value) == common | {'claim_once', 'originals_unchanged',
        'cipher_unchanged', 'pointer_bound', 'child_exit', 'output_bytes', 'output_sha256',
        'output_complete', 'forced', 'job_empty', 'private_manifest_sha256',
        'native_reopen_qualified', 'seed_admitted'}
        and all(value[key] is True for key in ('claim_once', 'originals_unchanged',
            'cipher_unchanged', 'pointer_bound', 'output_complete', 'job_empty'))
        and value['forced'] is value['native_reopen_qualified'] is value['seed_admitted'] is False
        and type(value['child_exit']) is int and value['child_exit'] == 0
        and type(value['output_bytes']) is int and 0 < value['output_bytes'] <= 2 * 1024**2
        and all(type(value[key]) is str and re.fullmatch('[a-f0-9]{64}', value[key])
                for key in ('output_sha256', 'private_manifest_sha256')))
    return dict(value)


def run(repo, parent, wallet, restored_home, home, closed, measure, *, diagnostic=None):
    """Saved observations never substitute for this attempt's original handles."""
    trace = PointerDiagnostic() if diagnostic is None else diagnostic
    checkpoint.need(type(trace) is PointerDiagnostic)
    trace.at('admission')
    from . import windows_wallet_tour as tour
    parent, source = debug.entry.require_ci(parent, None, platform=os.name)
    checkpoint.need(parent.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
        and parent.get('SYRIUS_HOSTED_RUNNER') == 'github-hosted'
        and type(wallet) is tour._ClosedWallet and callable(closed) and closed() is True
        and callable(measure))
    trace.at('origin')
    origin = wallet.restoration_origin()
    checkpoint.need(type(origin) is wallet_restore_origin.Origin)
    copied_wallet, copied_cache = origin.copied_paths(str(restored_home))
    repo, restored_home, home = Path(repo), Path(restored_home), Path(home)
    trace.at('source')
    debug.bounded.verify_source(repo, source, parent)
    tree = debug.entry.source_tree(repo, parent)
    deadline = time.monotonic() + 180
    trace.at('paths')
    pins = dict(checkpoint.ancestors(home))
    report_pins = dict(pins)
    for directory in (wallet.home, restored_home, Path(origin.cache), Path(copied_cache),
                      Path(origin.wallet).parent, Path(copied_wallet).parent):
        pins.update(checkpoint.ancestors(directory))
    paths = {'original_pointer': Path(origin.cache) / 'key_store_box.hive',
             'copied_pointer': Path(copied_cache) / 'key_store_box.hive',
             'original_cipher': Path(origin.wallet), 'copied_cipher': Path(copied_wallet)}
    trace.at('input_pins')
    snapshots = {}
    for role, path in paths.items():
        identity = checkpoint.file_identity(path.lstat())
        checkpoint.need(0 < identity[2] <= (1024**2 if 'pointer' in role else METADATA))
        snapshots[role] = (identity, checkpoint.digest_file(path, identity, deadline))
    checkpoint.need(snapshots['original_pointer'][1] == snapshots['copied_pointer'][1]
        and snapshots['original_cipher'][1] == snapshots['copied_cipher'][1]
        and snapshots['original_pointer'][0][:2] != snapshots['copied_pointer'][0][:2]
        and snapshots['original_cipher'][0][:2] != snapshots['copied_cipher'][0][:2])

    def guard():
        return (time.monotonic() < deadline and closed() is True
            and all(checkpoint.directory(path) == identity for path, identity in pins.items()))

    def sample():
        checkpoint.need(guard())
        used = measure()
        checkpoint.need(type(used) is int and 0 <= used <= checkpoint.CAP - METADATA
            and shutil.disk_usage(repo).free >= checkpoint.FLOOR + METADATA)

    def unchanged(roles):
        checkpoint.need(guard())
        for role in roles:
            identity, digest = snapshots[role]
            checkpoint.need(checkpoint.file_identity(paths[role].lstat()) == identity
                and checkpoint.digest_file(paths[role], identity, deadline) == digest)

    trace.at('reservation')
    claim = home / 'wallet-pointer-claim.json'
    transport = home / 'wallet-pointer-transport.json'
    complete = home / 'wallet-pointer-complete.json'
    checkpoint.need(all(not path.exists() and not path.is_symlink()
                        for path in (claim, transport, complete)))
    sample()
    env = debug.profile_environment(parent, wallet._paths[3], 1, secrets.token_hex(16))
    env.update(SYRIUS_COPIED_POINTER_BINDING='true',
        GITHUB_EVENT_NAME=parent['GITHUB_EVENT_NAME'],
        GITHUB_REPOSITORY=parent['GITHUB_REPOSITORY'],
        SYRIUS_HOSTED_RUNNER=parent['SYRIUS_HOSTED_RUNNER'])
    dart, _ = debug.sdk(parent)
    original = lines = job = None
    record = dict(schema=1, scope=SCOPE, phase='launch', complete=False,
                  child_exit=None, forced=False, output=None, job_empty=False)
    try:
        trace.at('launch')
        job = debug.WindowsJob()
        original = subprocess.Popen([str(dart), '--disable-dart-dev',
            '--packages=' + str(repo / '.dart_tool/package_config.json'),
            'harness/bin/ci_copied_wallet_pointer.dart'], cwd=repo, env=env, shell=False,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
        job.assign(original)
        lines = debug.Lines(original.stdout)

        def write(raw):
            checkpoint.need(guard() and original.poll() is None and len(raw) <= 32768)
            original.stdin.write(raw)
            original.stdin.flush()

        def wait(marker):
            next_sample = 0.0
            while time.monotonic() < deadline:
                checkpoint.need(guard())
                if time.monotonic() >= next_sample:
                    sample()
                    next_sample = time.monotonic() + 5
                raw = lines.take(.1)
                if raw is not None:
                    if raw.replace(b'\r\n', b'\n') != marker:
                        trace.unexpected_line(raw)
                    checkpoint.need(raw.replace(b'\r\n', b'\n') == marker)
                    return
                checkpoint.need(original.poll() is None or not lines.complete)
            raise checkpoint.Refused()

        record['phase'] = trace.at('start')
        write(b'START\n')
        wait(b'CI_POINTER_READY\n')
        record['phase'] = trace.at('input')
        write(checkpoint.encode(dict(originalHome=origin.home, restoredHome=str(restored_home),
            originalWallet=origin.wallet, cacheRelative=ntpath.relpath(origin.cache, origin.home))))
        wait(b'CI_POINTER_CLAIM\n')
        record['phase'] = trace.at('claim')
        unchanged(paths)
        debug.bounded.verify_source(repo, source, parent)
        sample()
        claim_raw = checkpoint.encode(dict(schema=1, scope=SCOPE,
            source=source, tree=tree, original_home=origin.home, restored_home=str(restored_home),
            original_wallet=origin.wallet, copied_wallet=copied_wallet,
            cache_relative=ntpath.relpath(origin.cache, origin.home)))
        checkpoint.write_record(claim, claim_raw, guard=guard)
        claim_identity = checkpoint.file_identity(claim.lstat())
        write(b'APPROVE\n')
        record['phase'] = trace.at('binding')
        wait(b'CI_POINTER_DONE\n')
        unchanged(('original_pointer', 'original_cipher', 'copied_cipher'))
        pointer = checkpoint.file_identity(paths['copied_pointer'].lstat())
        checkpoint.need(pointer[:2] == snapshots['copied_pointer'][0][:2]
                        and 0 < pointer[2] <= 1024**2)
        write(b'FINISH\n')
        record['phase'] = trace.at('finish')
        record['child_exit'] = original.wait(timeout=15)
        checkpoint.need(type(record['child_exit']) is int and record['child_exit'] == 0
            and lines.finish() and lines.take(0) is None and job.active() == 0)
        unchanged(('original_pointer', 'original_cipher', 'copied_cipher'))
        debug.bounded.verify_source(repo, source, parent)
        checkpoint.need(debug.entry.source_tree(repo, parent) == tree)
        checkpoint.need(checkpoint.digest_file(claim, claim_identity, deadline)
                        == hashlib.sha256(claim_raw).hexdigest())
        sample()
        record.update(phase=trace.at('complete'), complete=True, job_empty=True)
    finally:
        if job is not None:
            try:
                if record['complete']:
                    trace.at('close')
                record['forced'] = job.close()
            except Exception:
                record['forced'] = None
                record['complete'] = False
        if original is not None:
            if original.poll() is None:
                try:
                    original.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    pass
            record['child_exit'] = original.poll()
            try:
                original.stdin.close()
            except OSError:
                record['input_close_unknown'] = True
                record['complete'] = False
        if lines is not None:
            drained = lines.finish()
            record['output'] = dict(**lines.public(), drained=drained)
        if record['forced'] is not False:
            record['complete'] = False
        transport_raw = checkpoint.encode(record)
        # Retaining a failed transport does not require the expired operation
        # deadline or renewed wallet authority. Its owned report root must stay
        # identical, and its small allocation was reserved before launch.
        checkpoint.write_record(transport, transport_raw,
            guard=lambda: all(checkpoint.directory(path) == identity
                              for path, identity in report_pins.items()))
    checkpoint.need(record['complete'] and record['forced'] is False)
    trace.at('complete')
    raw = checkpoint.encode(dict(schema=1, scope=SCOPE, complete=True,
        claim_sha256=hashlib.sha256(claim_raw).hexdigest(),
        transport_sha256=hashlib.sha256(transport_raw).hexdigest()))
    sample()
    checkpoint.write_record(complete, raw, guard=guard)
    return project(dict(schema=1, scope=SCOPE, complete=True, claim_once=True,
        originals_unchanged=True, cipher_unchanged=True, pointer_bound=True, child_exit=0,
        output_bytes=record['output']['bytes'], output_sha256=record['output']['sha256'],
        output_complete=True, forced=False, job_empty=True,
        private_manifest_sha256=hashlib.sha256(raw).hexdigest(),
        native_reopen_qualified=False, seed_admitted=False))
