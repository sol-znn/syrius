"""Observe one original Release startup without a node, wallet import or retry.

Only a fresh hosted-Windows profile is admitted. The existing wallet recipe
owns the optional Skip key and confirms its effect. Progress reads never ask
the decoder for another frame. A missed deadline stays failed during cleanup.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import secrets
import socket
import stat
import subprocess
import sys

from . import windows_entry_capture_smoke as entry
from . import windows_presentation_smoke as bounded
from .windows_wallet_tour import RECIPE_ENTRY_PHASES, RECIPE_STARTUP_FILM_STATES


BINARY = Path('build/windows/x64/runner/Release/syrius.exe')
PAYLOAD = BINARY.parent / 'data/app.so'
OUTPUT = Path('.harness/ci-startup-probe/manifest.json')
NATURAL_OUTPUT = Path('.harness/ci-natural-startup-probe/manifest.json')
MAX_MANIFEST = 128 * 1024
LIMITS = bounded.Limits(total=90, ready=45, request=20, poll=.25)
STARTUP_SECONDS = 20
MAX_SAMPLES = 96
CHECKS = ('environment', 'source', 'profile', 'preflight', 'identity', 'auth',
          'window_saved', 'window_shown', 'startup_ready', 'window_restored',
          'close_ack', 'exit', 'payload_stable')
CODES = bounded.CODES | frozenset((
    'ENTRY_UNAVAILABLE', 'ENTRY_HELD', 'ENTRY_INVALID', 'WINDOW_INVALID',
    'WINDOW_RESTORE_FAILED', 'STARTUP_OBSERVATION_REFUSED', 'STARTUP_DEADLINE',
    'PROGRESS_REFUSED', 'ARTIFACT_FAILED', 'PRIOR_STARTUP_REFUSED',
))
STAGES = frozenset(('idle', 'previous', 'asset', 'codec', 'frame', 'resize',
                    'display', 'disposing', 'complete'))


class Failure(bounded.SmokeFailure):
    def __init__(self, code):
        self.code = code if code in CODES else 'INTERNAL_ERROR'
        Exception.__init__(self, self.code)


def integer(value, low, high):
    return type(value) is int and low <= value <= high


def progress_projection(value):
    """Only finite facts read from the same registered original film State."""
    fields = {'frames', 'shown', 'decoding', 'stage', 'skip', 'pending',
              'ticking', 'done'}
    if (type(value) is not dict or set(value) != fields
            or not integer(value['frames'], 0, 4096)
            or not integer(value['shown'], -1, max(-1, value['frames'] - 1))
            or type(value['stage']) is not str or value['stage'] not in STAGES
            or any(type(value[name]) is not bool
                   for name in ('skip', 'pending', 'ticking', 'done'))):
        return None
    index = value['decoding']
    if index is not None and not integer(index, 0, value['frames'] - 1):
        return None
    return {name: value[name] for name in sorted(fields)}


def sample_projection(value):
    if (type(value) is not dict or not {'at_ms', 'phase'} <= set(value)
            or not set(value) <= {'at_ms', 'phase', 'film', 'progress'}
            or not integer(value['at_ms'], 0, 90000)
            or type(value['phase']) is not str
            or value['phase'] not in RECIPE_ENTRY_PHASES):
        return None
    result = {name: value[name] for name in ('at_ms', 'phase')}
    if 'film' in value:
        if (type(value['film']) is not str
                or value['film'] not in RECIPE_STARTUP_FILM_STATES):
            return None
        result['film'] = value['film']
    if 'progress' in value:
        progress = progress_projection(value['progress'])
        if progress is None:
            return None
        result['progress'] = progress
    return result


class Report(bounded.Report):
    def __init__(self, *, natural_only=False):
        if type(natural_only) is not bool:
            raise Failure('ARGUMENTS_REFUSED')
        super().__init__()
        self.natural_only = natural_only
        self.prior_manifest_sha256 = None
        self.checks = dict.fromkeys(CHECKS, False)
        self.source_tree = self.run_id = self.run_attempt = None
        self.payload_sha256 = None
        self.samples = []
        self.handoff = None
        self.key_attempts = 0
        self.startup_deadline_expired = False

    def fail(self, code, original=None):
        code = code if code in CODES else 'INTERNAL_ERROR'
        if code not in self.errors:
            self.errors.append(code)
        if original is not None:
            self.original_errors.append(original)

    def public(self):
        samples = [sample_projection(value) for value in self.samples[:MAX_SAMPLES]]
        samples_valid = (len(self.samples) <= MAX_SAMPLES
                         and all(value is not None for value in samples)
                         and all(a['at_ms'] <= b['at_ms']
                                 for a, b in zip(samples, samples[1:])
                                 if a is not None and b is not None))
        complete = (all(self.checks.get(name) is True for name in CHECKS)
                    and samples_valid and bool(samples)
                    and bounded.valid_sha(self.source_sha)
                    and bounded.valid_sha(self.source_tree)
                    and entry.anonymous_number(self.run_id) is not None
                    and entry.anonymous_number(self.run_attempt, 6) is not None
                    and bounded.safe_digest(self.runner_sha256) is not None
                    and bounded.safe_digest(self.payload_sha256) is not None
                    and self.handoff in ('key-confirmed', 'natural')
                    and integer(self.key_attempts, 0, 1)
                    and self.key_attempts == (self.handoff == 'key-confirmed')
                    and (not self.natural_only or (
                        self.handoff == 'natural' and self.key_attempts == 0
                        and bounded.safe_digest(self.prior_manifest_sha256) is not None
                        and all(not value.get('progress', {}).get('skip', False)
                                for value in samples if value is not None)))
                    and not self.startup_deadline_expired and not self.errors
                    and self.exit_observed and type(self.exit_code) is int
                    and self.exit_code == 0 and not self.forced_kill
                    and self.output_complete and not self.output_overflow)
        public = dict(
            schema=1, scope='original_release_startup_observation',
            source_sha=self.source_sha if bounded.valid_sha(self.source_sha) else None,
            source_tree=self.source_tree if bounded.valid_sha(self.source_tree) else None,
            run_id=entry.anonymous_number(self.run_id),
            run_attempt=entry.anonymous_number(self.run_attempt, 6),
            runner_sha256=bounded.safe_digest(self.runner_sha256),
            payload_sha256=bounded.safe_digest(self.payload_sha256),
            checks={name: self.checks.get(name) is True for name in CHECKS},
            samples=[value for value in samples if value is not None],
            samples_valid=samples_valid,
            handoff=self.handoff if self.handoff in ('key-confirmed', 'natural') else None,
            key_attempts=self.key_attempts if integer(self.key_attempts, 0, 1) else None,
            startup_deadline_seconds=STARTUP_SECONDS,
            startup_deadline_expired=self.startup_deadline_expired is True,
            exit_code=self.exit_code if type(self.exit_code) is int else None,
            exit_observed=self.exit_observed is True,
            forced_kill=self.forced_kill is True,
            output_complete=self.output_complete is True,
            output_overflow=self.output_overflow is True,
            error_codes=[code for code in self.errors if code in CODES],
            complete=complete, success=complete,
            original_skip_qualified=complete and self.handoff == 'key-confirmed',
            wallet_qualified=False, chain_qualified=False, visual_matches=0,
            financial_actions_requested=0, node_cluster_started=False,
        )
        if self.natural_only:
            public.update(
                scope='original_release_natural_startup_observation',
                prior_manifest_sha256=bounded.safe_digest(self.prior_manifest_sha256),
                original_natural_qualified=complete,
            )
        return public

    def summary(self):
        public = self.public()
        encoded = json.dumps(public, sort_keys=True, separators=(',', ':')).encode('ascii')
        samples = public['samples']
        summary = {key: value for key, value in public.items() if key != 'samples'}
        summary.update(
            scope=('original_release_natural_startup_summary' if self.natural_only
                   else 'original_release_startup_summary'),
            report_sha256=hashlib.sha256(encoded).hexdigest(),
            sample_count=len(samples),
            first_sample=samples[0] if samples else None,
            last_sample=samples[-1] if samples else None,
            error_count=len(public['error_codes']),
            errors_truncated=len(public['error_codes']) > 16,
            error_codes=public['error_codes'][:16],
        )
        return summary


def observation_projection(value, *, head, tree, run_id, run_attempt,
                           runner_sha256, payload_sha256, natural_only=False,
                           prior_manifest_sha256=None):
    """Validate a closed original report without starting or polling anything."""
    if type(natural_only) is not bool or type(value) is not dict:
        return None
    observed = Report(natural_only=natural_only)
    if set(value) != set(observed.public()):
        return None
    boolean_fields = ('samples_valid', 'startup_deadline_expired', 'exit_observed',
                      'forced_kill', 'output_complete', 'output_overflow',
                      'complete', 'success', 'original_skip_qualified',
                      'wallet_qualified', 'chain_qualified', 'node_cluster_started')
    if (any(type(value[name]) is not bool for name in boolean_fields)
            or (natural_only and type(value['original_natural_qualified']) is not bool)
            or any(type(value[name]) is not int or value[name] != expected
                   for name, expected in (('schema', 1),
                       ('startup_deadline_seconds', STARTUP_SECONDS),
                       ('visual_matches', 0), ('financial_actions_requested', 0)))
            or type(value['checks']) is not dict or set(value['checks']) != set(CHECKS)
            or any(type(flag) is not bool for flag in value['checks'].values())
            or type(value['samples']) is not list or len(value['samples']) > MAX_SAMPLES
            or type(value['error_codes']) is not list
            or any(type(code) is not str or code not in CODES
                   for code in value['error_codes'])
            or len(value['error_codes']) != len(set(value['error_codes']))
            or (value['key_attempts'] is not None
                and not integer(value['key_attempts'], 0, 1))
            or (value['exit_code'] is not None
                and not integer(value['exit_code'], -(2 ** 31), 2 ** 32 - 1))):
        return None
    expected = dict(source_sha=head, source_tree=tree, run_id=run_id,
                    run_attempt=run_attempt, runner_sha256=runner_sha256,
                    payload_sha256=payload_sha256)
    if (not bounded.valid_sha(head) or not bounded.valid_sha(tree)
            or entry.anonymous_number(run_id) is None
            or entry.anonymous_number(run_id) != run_id
            or entry.anonymous_number(run_attempt, 6) is None
            or entry.anonymous_number(run_attempt, 6) != run_attempt
            or bounded.safe_digest(runner_sha256) is None
            or bounded.safe_digest(runner_sha256) != runner_sha256
            or bounded.safe_digest(payload_sha256) is None
            or bounded.safe_digest(payload_sha256) != payload_sha256
            or any(value[name] != item for name, item in expected.items())
            or (natural_only and (
                bounded.safe_digest(prior_manifest_sha256) is None
                or value['prior_manifest_sha256'] != prior_manifest_sha256))):
        return None
    for name, item in expected.items():
        setattr(observed, name, item)
    for name in ('checks', 'samples', 'handoff', 'key_attempts',
                 'startup_deadline_expired', 'exit_code', 'exit_observed',
                 'forced_kill', 'output_complete', 'output_overflow'):
        setattr(observed, name, value[name])
    observed.errors = list(value['error_codes'])
    observed.prior_manifest_sha256 = prior_manifest_sha256
    projected = observed.public()
    return projected if projected == value else None


def require_prior_observation(repo, report):
    """Bind the first normal complete exit before allocating a second profile."""
    try:
        for relative in (Path('.harness'), OUTPUT.parent):
            if not stat.S_ISDIR(bounded.plain(repo / relative).st_mode):
                raise Failure('PRIOR_STARTUP_REFUSED')
        source = repo / OUTPUT
        info = bounded.plain(source)
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_MANIFEST:
            raise Failure('PRIOR_STARTUP_REFUSED')
        with source.open('rb') as stream:
            raw = stream.read(MAX_MANIFEST + 1)
        if len(raw) != info.st_size:
            raise Failure('PRIOR_STARTUP_REFUSED')
        prior = observation_projection(
            json.loads(raw), head=report.source_sha, tree=report.source_tree,
            run_id=report.run_id, run_attempt=report.run_attempt,
            runner_sha256=report.runner_sha256,
            payload_sha256=report.payload_sha256,
        )
        if prior is None or prior['success'] is not True:
            raise Failure('PRIOR_STARTUP_REFUSED')
        return hashlib.sha256(raw).hexdigest()
    except (Exception, KeyboardInterrupt):
        raise Failure('PRIOR_STARTUP_REFUSED') from None


class StartupProbe(bounded.PresentationSmoke):
    def __init__(self, *args, natural_only=False, **kwargs):
        if type(natural_only) is not bool:
            raise Failure('ARGUMENTS_REFUSED')
        super().__init__(*args, **kwargs)
        if self.report.natural_only != natural_only:
            raise Failure('ARGUMENTS_REFUSED')
        self.natural_only = natural_only
        self.authenticated = self.window_changed = False
        self.original_window = None
        self.started = self.clock()

    def _rpc(self, command, *, until=None, allow_exit=False):
        status, body = self._exchange(command, until=until, allow_exit=allow_exit)
        if status != 200 or body['ok'] is not True:
            raise Failure('COMMAND_FAILED')
        return body

    def _ready(self):
        until = min(self.deadline, self.clock() + self.limits.ready)
        while self.clock() < until:
            try:
                body = self._rpc({'cmd': 'ping'}, until=until)
            except ConnectionRefusedError:
                body = None
            if body is not None:
                if type(body.get('pid')) is not int or body['pid'] != self.process.pid:
                    raise Failure('IDENTITY_REFUSED')
                if body.get('harnessMode') != 'wallet':
                    raise Failure('MODE_REFUSED')
                if type(body.get('booted')) is not bool:
                    raise Failure('RESPONSE_INVALID')
                if body['booted']:
                    self.report.checks['identity'] = True
                    break
            self.sleep(min(self.limits.poll, max(0, until - self.clock())))
        else:
            raise Failure('READINESS_TIMEOUT')
        status, body = self._exchange({'cmd': 'ping'},
            token='invalid-startup-probe-token', until=until)
        if status != 400 or body != {'ok': False, 'error': 'bad token'}:
            raise Failure('AUTH_REFUSAL_INVALID')
        self.authenticated = self.report.checks['auth'] = True

    def _observe(self, until):
        body = self._rpc({'cmd': 'wallet-recipe', 'action': 'observe'}, until=until)
        if (body.get('harnessMode') != 'wallet' or body.get('booted') is not True
                or body.get('walletPresent') is not False or body.get('hasError') is not False
                or type(body.get('entryPhase')) is not str
                or body['entryPhase'] not in RECIPE_ENTRY_PHASES
                or not integer(body.get('owner'), 1, 2**31 - 1)
                or not integer(body.get('revision'), 0, 2**31 - 1)):
            raise Failure('STARTUP_OBSERVATION_REFUSED')
        sample = dict(at_ms=int((self.clock() - self.started) * 1000),
                      phase=body['entryPhase'])
        for source, field in (('startupFilmState', 'film'),
                              ('startupFilmProgress', 'progress')):
            if source in body:
                sample[field] = body[source]
        projected = sample_projection(sample)
        if projected is None or len(self.report.samples) >= MAX_SAMPLES:
            raise Failure('PROGRESS_REFUSED')
        self.report.samples.append(projected)
        return body

    def _entry_ready(self, until):
        body = self._rpc({'cmd': 'entry-state'}, until=until)
        return entry.EntrySmoke._entry(self, body, count=0)

    def _startup(self):
        until = min(self.deadline, self.clock() + STARTUP_SECONDS)
        try:
            while self.clock() < until:
                view = self._observe(until)
                progress = view.get('startupFilmProgress')
                if (self.natural_only
                        and type(progress) is dict and progress.get('skip') is True):
                    raise Failure('STARTUP_OBSERVATION_REFUSED')
                if self._entry_ready(until):
                    self.report.handoff = self.report.handoff or 'natural'
                    self.report.checks['startup_ready'] = True
                    return
                controls = view.get('controls')
                if type(controls) is not list or len(controls) > 128:
                    raise Failure('STARTUP_OBSERVATION_REFUSED')
                hints = [row for row in controls if type(row) is dict
                         and row.get('key') == 'launch_skip_hint']
                if len(hints) > 1:
                    raise Failure('STARTUP_OBSERVATION_REFUSED')
                if (not self.natural_only and self.report.key_attempts == 0
                        and view['entryPhase'] == 'startup-before-initialization'
                        and type(view.get('startupFilmProgress')) is dict
                        and view['startupFilmProgress'].get('skip') is False
                        and hints and hints[0].get('enabled') is True):
                    self.report.key_attempts = 1  # Reserve before the only input.
                    reply = self._rpc(dict(cmd='wallet-recipe', action='key',
                        key='launch_skip_hint', owner=view['owner'],
                        revision=view['revision']), until=until)
                    if reply.get('acted') is not True:
                        raise Failure('COMMAND_FAILED')
                    self.report.handoff = 'key-confirmed'
                self.sleep(min(self.limits.poll, max(0, until - self.clock())))
        except bounded.SmokeFailure as error:
            if self.clock() < until:
                raise
            self.report.fail(error.code, error)
        self.report.startup_deadline_expired = True
        raise Failure('STARTUP_DEADLINE')

    def _show(self):
        self.original_window = entry.EntrySmoke._window(
            self, self._rpc({'cmd': 'window'}))
        self.report.checks['window_saved'] = True
        self.window_changed = True
        body = self._rpc({'cmd': 'window', 'do': 'show', 'width': 1280, 'height': 780})
        actual = entry.EntrySmoke._window(self, body)
        if (body.get('clientMatched') is not True or actual['minimized']
                or actual['maximized'] or any(abs(a - b) >= .01
                    for a, b in zip(actual['client'], (1280, 780)))):
            raise Failure('WINDOW_INVALID')
        self.report.checks['window_shown'] = True

    def _restore(self):
        if self.window_changed:
            body = self._rpc({'cmd': 'window', 'restoreState': self.original_window})
            actual = entry.EntrySmoke._window(self, body)
            if (body.get('restored') is not True
                    or not entry.EntrySmoke._same_window(actual, self.original_window)):
                raise Failure('WINDOW_RESTORE_FAILED')
            self.report.checks['window_restored'] = True

    def _quit(self):
        self.quit_sent = True
        if self._rpc({'cmd': 'quit'}, allow_exit=True) != {'ok': True}:
            raise Failure('CLOSE_FAILED')
        self.report.checks['close_ack'] = True
        try:
            code = self.process.wait(timeout=min(
                self.limits.exit, self._health(allow_exit=True)))
        except subprocess.TimeoutExpired:
            raise Failure('EXIT_TIMEOUT') from None
        self.report.exit_code, self.report.exit_observed = code, type(code) is int
        if type(code) is not int or code != 0:
            raise Failure('EXIT_FAILED')
        self.report.checks['exit'] = True

    def _record(self, action):
        try:
            action()
        except bounded.SmokeFailure as error:
            self.report.fail(error.code, error)
        except (Exception, KeyboardInterrupt) as error:
            self.report.fail('INTERNAL_ERROR', error)

    def run(self):
        try:
            self._ready()
            self._show()
            self._startup()
        except bounded.SmokeFailure as error:
            self.report.fail(error.code, error)
        except (Exception, KeyboardInterrupt) as error:
            self.report.fail('INTERNAL_ERROR', error)
        finally:
            if self.authenticated and self.process.poll() is None:
                self._record(self._restore)
                self._record(self._quit)
            grace = min(self.limits.exit, max(0, self.deadline - self.clock())) if self.quit_sent else 0
            bounded.finish_original(self.process, self.drain, self.report,
                                    self.limits, grace=grace)
        return self.report.public()


def main(arguments=None):
    report = Report()
    process = drain = destination = None
    try:
        arguments = sys.argv[1:] if arguments is None else arguments
        if type(arguments) is not list or arguments not in ([], ['--natural-only']):
            raise Failure('ARGUMENTS_REFUSED')
        natural_only = arguments == ['--natural-only']
        report = Report(natural_only=natural_only)
        parent, expected = entry.require_ci(os.environ, None, platform=os.name)
        if (parent.get('GITHUB_EVENT_NAME') != 'workflow_dispatch'
                or parent.get('SYRIUS_WINDOWS_STARTUP_PROBE') != 'true'):
            raise Failure('ENVIRONMENT_REFUSED')
        repo = Path(parent['GITHUB_WORKSPACE'])
        bounded.plain(repo)
        if repo.resolve() != Path.cwd().resolve():
            raise Failure('ENVIRONMENT_REFUSED')
        report.checks['environment'] = True
        report.source_sha, report.run_id = expected, parent['GITHUB_RUN_ID']
        report.run_attempt = parent['GITHUB_RUN_ATTEMPT']
        bounded.verify_source(repo, expected, parent)
        report.source_tree = entry.source_tree(repo, parent)
        report.checks['source'] = True
        binary, report.runner_sha256, binary_identity = bounded.binary_hash(repo, BINARY)
        payload, report.payload_sha256, payload_identity = bounded.binary_hash(repo, PAYLOAD)
        if natural_only:
            report.prior_manifest_sha256 = require_prior_observation(repo, report)
        bounded.check_no_existing(repo, parent)
        report.checks['preflight'] = True
        profile = entry.new_profile(repo)
        report.checks['profile'] = True
        output = NATURAL_OUTPUT if natural_only else OUTPUT
        directory = repo / output.parent
        directory.mkdir(mode=0o700)
        destination = directory / output.name
        token = secrets.token_urlsafe(32)
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as reservation:
            reservation.bind(('127.0.0.1', 0))
            port = reservation.getsockname()[1]
        env = entry.child_environment(parent, profile, port, token)
        for selected, original in ((binary, binary_identity), (payload, payload_identity)):
            info = bounded.plain(selected)
            if (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns) != original:
                raise Failure('BINARY_REFUSED')
        process = subprocess.Popen([str(binary)], cwd=binary.parent, env=env,
            shell=False, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, bufsize=0)
        drain = bounded.OutputDrain(process.stdout, LIMITS.output_bytes)
        session = StartupProbe(process, bounded.LoopbackTransport(
            port, LIMITS.response_bytes), token, drain, report, limits=LIMITS,
            natural_only=natural_only)
        process = None  # The session keeps the original handle through cleanup.
        session.run()
        for relative, digest, original in (
            (BINARY, report.runner_sha256, binary_identity),
            (PAYLOAD, report.payload_sha256, payload_identity),
        ):
            _, current_digest, current = bounded.binary_hash(repo, relative)
            if current_digest != digest or current != original:
                raise Failure('BINARY_REFUSED')
        bounded.verify_source(repo, expected, parent)
        if entry.source_tree(repo, parent) != report.source_tree:
            raise Failure('SOURCE_REFUSED')
        report.checks['payload_stable'] = True
    except bounded.SmokeFailure as error:
        report.fail(error.code, error)
    except (Exception, KeyboardInterrupt) as error:
        report.fail('INTERNAL_ERROR', error)
    finally:
        if process is not None:
            bounded.finish_original(process, drain, report, LIMITS)
    if destination is not None:
        try:
            raw = (json.dumps(report.public(), sort_keys=True) + '\n').encode('ascii')
            fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
            with os.fdopen(fd, 'wb') as output:
                output.write(raw)
        except (Exception, KeyboardInterrupt) as error:
            report.fail('ARTIFACT_FAILED', error)
    public = report.public()
    text = json.dumps(public, sort_keys=True, separators=(',', ':'))
    print(text)
    summary = json.dumps(report.summary(), sort_keys=True, separators=(',', ':'))
    if len(summary.encode('ascii')) <= 3800:
        title = ('Original natural Release startup summary' if report.natural_only
                 else 'Original Release startup summary')
        print('::notice title=' + title + '::' + summary)
    return 0 if public['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
