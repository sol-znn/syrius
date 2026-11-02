"""Open the owned closed copies normally, retaining every original attempt."""

import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import time

from . import closed_lab_checkpoint as checkpoint
from . import windows_debug_loop as debug
from . import restored_seed_run as seeds


SCOPE = 'owned_restored_lab_reopen'
OUTPUT_CAP = 2 * 1024**2
OBSERVATION = {'schema', 'scope', 'chain', 'members', 'selected_index',
    'membership_same', 'selection_saved', 'wallet_path_mapped',
    'original_send_confirmed', 'journal_consistent', 'observation_stable'}
PHASES = ('admission', 'origin', 'roots', 'journals', 'ciphers', 'node_inputs',
    'source', 'reservation', 'claim', 'retire_metadata', 'runtime', 'node_ports',
    'node_start', 'node_observe', 'initial_chain', 'profile', 'launch', 'output',
    'start', 'entry_metadata', 'application', 'transport', 'pre_input',
    'unlock_and_observe', 'post_observe', 'seed_workflow', 'seed_journals',
    'ordinary_close', 'finish', 'source_closed', 'close', 'output_close',
    'transport_close', 'nodes_stop', 'post_close', 'complete_record', 'projection')
CHILD_PHASES = ('gate', 'start', 'input', 'startup_window', 'startup', 'unlock', 'observe',
    'seed_admission', 'seed_stake', 'seed_fuse', 'seed_token', 'seed_deposit',
    'seed_project', 'seed_fund-address', 'finish')
OUTPUT_CODES = ('PUB_RESOLUTION', 'PUB_EXECUTABLE_BUILD', 'UNHANDLED_EXCEPTION',
    'COMPILE_OR_USAGE_ERROR', 'VM_SERVICE_LISTENER', 'UNCLASSIFIED_OUTPUT',
    'REOPEN_CHILD_REFUSED')
ERRORS = ('CHECKPOINT_REFUSED', 'LAB_REFUSED', 'WIRE_REFUSED', 'PROCESS_REFUSED', 'TYPE_ERROR',
    'KEY_ERROR', 'OS_ERROR', 'VALUE_ERROR', 'INTERRUPTED', 'OTHER_ERROR')
CHILD_FAILURE_KINDS = frozenset(('WINDOW_REFUSED', 'RECIPE_REFUSED', 'HARNESS_REFUSED',
    'FORMAT_ERROR', 'TYPE_ERROR', 'STATE_ERROR', 'OS_ERROR', 'OTHER_ERROR'))
WINDOW_FAILURE_CODES = frozenset(('WINDOW_RESPONSE_REFUSED', 'WINDOW_CLIENT_REFUSED',
    'WINDOW_STATE_REFUSED'))
UNLOCK_FAILURE_CODES = frozenset(('UNLOCK_STATE_REFUSED', 'UNLOCK_LOCK_REQUIRED',
    'UNLOCK_FIELD_READY_REFUSED',
    'UNLOCK_TYPE_REFUSED', 'UNLOCK_TAP_REFUSED', 'UNLOCK_WAIT_REFUSED',
    'UNLOCK_FAILURE_TREE_REFUSED'))
CHILD_RECIPE_EXTRA_CODES = frozenset(('wallet-recipe-restored-lock-required',
    'wallet-recipe-observation-refused', 'wallet-recipe-controls-unavailable',
    'wallet-recipe-control-ambiguous', 'wallet-recipe-command-uncertain',
    'wallet-recipe-deadline', 'wallet-recipe-retired'))


LOCK_VIEW_BOOLEANS = frozenset(('mounted', 'current', 'window_active', 'visible',
    'route_current', 'focus_allows_input', 'startup_interactive', 'busy', 'opening',
    'incorrect_password', 'attempt_storage_failed', 'has_error_message'))
LOCK_VIEW_LIFECYCLES = frozenset(('resumed', 'inactive', 'hidden', 'paused',
    'detached', 'unknown'))
LOCK_VIEW_STATUSES = frozenset(('observed', 'unavailable', 'replaced', 'retired'))
LOCK_VIEW_UNLOCK_PHASES = frozenset(('capture_requested','capture_returned','attempt_bound','busy_mark_requested','input_clear_requested','capture_preferences','capture_wallet_context','capture_sdk','capture_notifications','capture_resources','capture_initialization','capture_reset','capture_binding','idle', 'entered', 'preflight_refused', 'attempt_unavailable', 'decrypt_requested', 'decrypt_returned', 'view_revoked', 'reset_requested', 'reset_returned', 'reset_refused', 'result_guard_refused', 'init_requested', 'init_returned', 'session_assigned', 'callback_requested', 'callback_returned', 'password_exception', 'ledger_exception', 'other_exception', 'authenticated_exception'))


def lock_view_projection(value):
    """Accept only the fixed genuine-owner observation, never arbitrary state."""
    checkpoint.need(type(value) is dict and set(value) ==
        {'schema', 'status', 'owner_same', 'view'}
        and type(value['schema']) is int and value['schema'] == 1
        and type(value['status']) is str and value['status'] in LOCK_VIEW_STATUSES
        and type(value['owner_same']) is bool)
    view = value['view']
    if value['status'] == 'observed':
        checkpoint.need(value['owner_same'] is True and type(view) is dict
            and set(view) in (LOCK_VIEW_BOOLEANS | {'password_failures', 'lifecycle'},
                LOCK_VIEW_BOOLEANS | {'password_failures', 'lifecycle',
                                     'unlock_phase', 'unlock_requests'})
            and all(type(view[key]) is bool for key in LOCK_VIEW_BOOLEANS)
            and type(view['password_failures']) is int
            and 0 <= view['password_failures'] <= 255
            and type(view['lifecycle']) is str
            and view['lifecycle'] in LOCK_VIEW_LIFECYCLES)
        if 'unlock_phase' in view:
            checkpoint.need(type(view['unlock_phase']) is str
                and view['unlock_phase'] in LOCK_VIEW_UNLOCK_PHASES
                and type(view['unlock_requests']) is int
                and 0 <= view['unlock_requests'] <= 255)
    else:
        checkpoint.need(value['owner_same'] is False and view is None)
    return dict(value, view=None if view is None else dict(view))


SEED_FAILURE_RECIPES = frozenset(('stake', 'fuse', 'token', 'deposit',
                                    'project', 'fund-address'))
SEED_FAILURE_ACTIONS = frozenset(('source', 'begin', 'home', 'check',
                                  'prepare', 'publish', 'command', 'finish'))
SEED_FAILURE_STEPS = frozenset(('read', 'parse', 'resolve', 'owner',
                                'request', 'reply', 'navigation', 'execute'))
SEED_FAILURE_KINDS = frozenset(('refused', 'timeout', 'format', 'type',
                                'filesystem', 'state', 'other'))
SEED_REPLY_CODES = frozenset((
    'advancing-momentum-required',
    'ambiguous-original-publication',
    'bounded-seed-wait-required',
    'close-current-fixture-first',
    'confirmed-token-presentation-required',
    'original-deposit-entry-changed',
    'original-deposit-entry-held',
    'original-deposit-entry-required',
    'original-token-presentation-changed',
    'original-token-presentation-close-pending',
    'original-token-presentation-held',
    'original-token-presentation-required',
    'confirmed-deposit-presentation-required',
    'original-deposit-presentation-changed',
    'original-deposit-presentation-close-pending',
    'original-deposit-presentation-held',
    'original-deposit-presentation-required',
    'confirmed-project-presentation-required',
    'original-project-presentation-changed',
    'original-project-presentation-close-pending',
    'original-project-presentation-held',
    'original-project-presentation-required',
    'earlier-original-unresolved',
    'earlier-seed-attempt-held',
    'enabled-preparation-control-required',
    'enabled-publication-control-required',
    'exact-chain-321-lab-required',
    'exact-confirmation-or-effect-pending',
    'exact-confirmation-pending',
    'exact-confirmation-required',
    'exact-original-lab-transports-required',
    'exact-original-receipt-mismatch',
    'explicit-lab-origins-required',
    'explicit-seed-begin-required',
    'external-lab-counterparty-required',
    'fixture-expired',
    'fixture-publication-refused',
    'fixture-route-changed',
    'fixture-route-unavailable',
    'funded-index-one-required',
    'funded-selected-index-required',
    'invalid-lab-frontier',
    'invalid-original-hash',
    'isolated-checkpoint-prerequisite-required',
    'isolated-unlocked-profile-required',
    'lab-endpoints-disagree',
    'lab-frontier-regressed',
    'lab-http-frontier-incomplete',
    'lab-http-response-refused',
    'lab-http-response-too-large',
    'lab-http-rpc-refused',
    'one-seed-publication-required',
    'original-attempt-held',
    'original-context-changed',
    'original-hash-changed',
    'original-outcome-unknown',
    'original-publication-replaced',
    'original-send-form-changed',
    'original-send-form-required',
    'original-send-review-already-captured',
    'original-send-review-button-changed',
    'original-send-review-center-changed',
    'original-send-review-dialog-changed',
    'original-send-review-draft-changed',
    'original-send-review-intent-changed',
    'original-send-review-required',
    'original-transfer-attempt-held',
    'original-transfer-review-mismatch',
    'original-transfer-review-required',
    'original-transfer-witness-required',
    'owned-isolated-profile-required',
    'recipe-prerequisite-missing',
    'restored-seed-derivation-refused',
    'restored-seed-exact-receipt-required',
    'restored-seed-membership-required',
    'restored-seed-owner-changed',
    'restored-seed-parent-unavailable',
    'restored-seed-session-held',
    'seed-command-refused',
    'seed-journal-held',
    'seed-preparation-selector-refused',
    'seed-preparation-error-widget',
    'seed-preparation-target-covered',
    'seed-preparation-target-disabled',
    'seed-preparation-target-missing',
    'seed-prerequisite-or-read-failed',
    'seed-publication-selector-refused',
    'seed-recipe-prerequisite-missing',
    'seed-script-after-publication-refused',
    'seed-script-command-refused',
    'seed-script-key-refused',
    'seed-script-prerequisite-missing',
    'seed-script-route-refused',
    'seed-script-substitution-refused',
    'token-publication-requires-guarded-publish',
    'unknown-fixture',
    'unknown-recipe',
    'unlocked-wallet-required',
))


SEED_PREPARATION_REPLY_CODES = frozenset((
    'seed-preparation-error-widget',
    'seed-preparation-target-covered',
    'seed-preparation-target-disabled',
    'seed-preparation-target-missing',
))


def seed_confirmation_projection(value):
    """Only eighteen completed negative original rounds; no operation data."""
    fields = {'polls', 'absent', 'unconfirmed', 'effect_pending', 'last'}
    checkpoint.need(type(value) is dict and set(value) == fields
        and type(value['polls']) is int and value['polls'] == 18
        and all(type(value[key]) is int and 0 <= value[key] <= 18
                for key in ('absent', 'unconfirmed', 'effect_pending'))
        and value['absent'] + value['unconfirmed'] + value['effect_pending'] == 18
        and type(value['last']) is str
        and value['last'] in {'absent', 'unconfirmed', 'effect_pending'}
        and value[value['last']] > 0)
    return dict(value)


HOME_PREPARATION_STAGES = (
    'initialState', 'initialReadiness', 'resolveTarget',
    'gotoState', 'gotoTarget', 'gotoTap', 'gotoWait',
    'railState', 'railReadiness', 'railTogglePresence', 'railLabelPresence',
    'railToggle', 'railWait', 'finalState', 'finalReadiness',
)
HOME_TAP_REPLIES = frozenset((
    'targetMissing', 'targetDisabled', 'targetCovered', 'viewAmbiguous', 'unknown',
))
HOME_STATE_STAGES = frozenset((
    'initialReadiness', 'gotoTarget', 'gotoWait',
    'railReadiness', 'finalReadiness',
))


def home_preparation_projection(value):
    """Only finite observations of existing Home calls; no private state."""
    fields = {'stage', 'state', 'target', 'reply'}
    checkpoint.need(type(value) is dict and 'stage' in value
        and set(value) <= fields and type(value['stage']) is str
        and value['stage'] in HOME_PREPARATION_STAGES)
    stage = value['stage']
    result = dict(stage=stage)
    if 'target' in value:
        checkpoint.need(type(value['target']) is str
            and value['target'] in {'home', 'dashboard'}
            and HOME_PREPARATION_STAGES.index(stage) >=
                HOME_PREPARATION_STAGES.index('resolveTarget'))
        result['target'] = value['target']
    if 'state' in value:
        state = value['state']
        checkpoint.need(type(state) is dict
            and set(state) == {'at', 'booted', 'unlocked', 'initialized', 'tab'}
            and type(state['at']) is str and state['at'] in HOME_STATE_STAGES
            and HOME_PREPARATION_STAGES.index(state['at']) <=
                HOME_PREPARATION_STAGES.index(stage)
            and all(type(state[key]) is str and state[key] in {'yes', 'no', 'unknown'}
                    for key in ('booted', 'unlocked', 'initialized'))
            and type(state['tab']) is str
            and state['tab'] in {'home', 'dashboard', 'lock', 'other', 'unknown'})
        result['state'] = dict(state)
    if 'reply' in value:
        checkpoint.need(stage == 'gotoTap' and 'target' in result
            and result.get('state', {}).get('at') == 'gotoTarget'
            and type(value['reply']) is str and value['reply'] in HOME_TAP_REPLIES)
        result['reply'] = value['reply']
    return result


def seed_failure_projection(value, phase):
    """Only the failed original operation is data; no input or authority."""
    fields = {'schema', 'scope', 'recipe', 'action', 'step', 'command_index',
              'publication_call_entered', 'kind', 'reason'}
    checkpoint.need(type(value) is dict and set(value) in
        (fields, fields | {'confirmation'}, fields | {'home'})
        and type(value['schema']) is int and value['schema'] == 1
        and type(value['scope']) is str
        and value['scope'] == 'original_seed_operation_failure'
        and type(value['recipe']) is str and value['recipe'] in SEED_FAILURE_RECIPES
        and type(phase) is str and phase == 'seed_' + value['recipe']
        and type(value['action']) is str and value['action'] in SEED_FAILURE_ACTIONS
        and type(value['step']) is str and value['step'] in SEED_FAILURE_STEPS
        and type(value['command_index']) is int and 0 <= value['command_index'] <= 96
        and type(value['publication_call_entered']) is bool
        and type(value['kind']) is str and value['kind'] in SEED_FAILURE_KINDS
        and type(value['reason']) is str
        and value['reason'] in SEED_REPLY_CODES | {'unknown'})
    action, step = value['action'], value['step']
    pairs = ({'read', 'parse', 'resolve'} if action == 'source' else
             {'navigation'} if action == 'home' else
             {'owner', 'execute'} if action == 'command' else
             {'owner', 'request', 'reply'})
    checkpoint.need(step in pairs)
    checkpoint.need((value['command_index'] == 0) is
                    (action in ('source', 'begin', 'home', 'finish')))
    entered = value['publication_call_entered']
    if action in ('source', 'begin', 'home', 'prepare'):
        checkpoint.need(entered is False)
    elif action == 'publish':
        checkpoint.need(entered is (step != 'owner'))
    elif action == 'finish':
        checkpoint.need(entered is True)
    if value['reason'] != 'unknown':
        checkpoint.need(value['kind'] == 'refused')
    if value['reason'] in SEED_PREPARATION_REPLY_CODES:
        checkpoint.need(action == 'prepare' and step == 'reply' and not entered)
    result = dict(value)
    if 'confirmation' in value:
        checkpoint.need(action == 'publish' and step == 'reply' and entered
            and value['kind'] == 'refused'
            and value['reason'] == 'exact-confirmation-or-effect-pending')
        result['confirmation'] = seed_confirmation_projection(value['confirmation'])
    if 'home' in value:
        checkpoint.need(action == 'home' and step == 'navigation'
            and value['command_index'] == 0 and entered is False)
        result['home'] = home_preparation_projection(value['home'])
    return result


def child_failure_projection(value):
    """Validate data from the original child; it grants no runtime authority."""
    fields = {'schema', 'scope', 'phase', 'kind', 'code', 'recipe'}
    checkpoint.need(type(value) is dict and set(value) in
        (fields, fields | {'lock_view'}, fields | {'seed'})
        and type(value['schema']) is int and value['schema'] == 1
        and value['scope'] == 'owned_reopen_child_failure'
        and type(value['phase']) is str and value['phase'] in CHILD_PHASES
        and type(value['kind']) is str and value['kind'] in CHILD_FAILURE_KINDS)
    from . import windows_wallet_tour as tour
    kind, code, recipe = value['kind'], value['code'], value['recipe']
    if kind == 'WINDOW_REFUSED':
        checkpoint.need(value['phase'] == 'startup_window'
            and type(code) is str and code in WINDOW_FAILURE_CODES)
    elif kind == 'RECIPE_REFUSED':
        checkpoint.need(code is None or type(code) is str
            and code in tour.RECIPE_FAILURE_CODES | CHILD_RECIPE_EXTRA_CODES)
    elif kind == 'HARNESS_REFUSED':
        checkpoint.need(code is None or value['phase'] == 'unlock'
            and type(code) is str and code in UNLOCK_FAILURE_CODES)
    else:
        checkpoint.need(code is None)
    if recipe is not None:
        checkpoint.need(kind == 'RECIPE_REFUSED')
        try:
            tour.entry_failure(dict(stage='onboarding',
                code='wallet-recipe-stage-unsettled', diagnostic=recipe))
        except tour.Refused:
            raise checkpoint.Refused() from None
    result = dict(value, recipe=None if recipe is None else dict(recipe))
    if 'seed' in value:
        checkpoint.need(kind == 'HARNESS_REFUSED' and code is None
            and recipe is None and value['phase'].startswith('seed_'))
        result['seed'] = seed_failure_projection(value['seed'], value['phase'])
    if 'lock_view' in value:
        checkpoint.need(value['phase'] == 'unlock' and kind == 'HARNESS_REFUSED'
            and type(code) is str and code in UNLOCK_FAILURE_CODES)
        result['lock_view'] = lock_view_projection(value['lock_view'])
    return result


def diagnostic_projection(value):
    """Retain a finite active failure location without private error text."""
    fields = {'schema', 'scope', 'phase', 'child_phase', 'output', 'error', 'code'}
    checkpoint.need(type(value) is dict and set(value) in
        (fields, fields | {'child_failure'})
        and type(value['schema']) is int and value['schema'] == 1
        and value['scope'] == 'owned_restored_lab_reopen_diagnostic'
        and type(value['phase']) is str and value['phase'] in PHASES
        and (value['child_phase'] is None or type(value['child_phase']) is str
             and value['child_phase'] in CHILD_PHASES)
        and (value['error'] is None or type(value['error']) is str
             and value['error'] in ERRORS))
    output = value['output']
    if output is not None:
        checkpoint.need(type(output) is dict and set(output) == {'code', 'bytes', 'sha256'}
            and type(output['code']) is str and output['code'] in OUTPUT_CODES
            and type(output['bytes']) is int and 0 < output['bytes'] <= debug.protocol.MAX_LINE + 1
            and type(output['sha256']) is str and re.fullmatch('[a-f0-9]{64}', output['sha256']))
    checkpoint.need((value['child_phase'] is not None) ==
        (output is not None and output['code'] == 'REOPEN_CHILD_REFUSED'))
    if value['code'] is not None:
        from . import hosted_chain321 as lab
        allowed = {'LAB_REFUSED': lab.CODES, 'WIRE_REFUSED': lab.wire_policy.CODES,
                   'PROCESS_REFUSED': debug.CODES}
        checkpoint.need(type(value['code']) is str and value['error'] in allowed
            and value['code'] in allowed[value['error']])
    result = dict(value, output=None if output is None else dict(output))
    if 'child_failure' in value:
        child = child_failure_projection(value['child_failure'])
        checkpoint.need(value['child_phase'] == child['phase']
            and output is not None and output['code'] == 'REOPEN_CHILD_REFUSED')
        result['child_failure'] = child
    return result


class ReopenDiagnostic:
    """Data-only observation; it supplies no process or wallet authority."""

    def __init__(self):
        self.phase = 'admission'
        self.child_phase = self.output = self.error = self.code = None
        self.child_failure = None

    def at(self, phase):
        checkpoint.need(self.error is None and type(phase) is str and phase in PHASES)
        self.phase = phase

    def observe_line(self, raw):
        checkpoint.need(type(raw) is bytes and 0 < len(raw) <= debug.protocol.MAX_LINE + 1)
        if self.output is not None:
            return
        line = raw.replace(b'\r\n', b'\n')
        if line.startswith(b'CI_REOPEN_FAILURE:'):
            observation = debug.probe_line_observation(raw)
            try:
                child = child_failure_projection(json.loads(
                    line[len(b'CI_REOPEN_FAILURE:'):]))
            except (ValueError, UnicodeError, RecursionError, checkpoint.Refused):
                self.output = observation
                return
            self.child_failure = child
            self.child_phase = child['phase']
            observation['code'] = 'REOPEN_CHILD_REFUSED'
            self.output = observation
            return
        match = re.fullmatch(rb'CI_REOPEN_ERROR:([a-z_-]+)\n', line)
        observation = debug.probe_line_observation(raw)
        if match is not None and match[1].decode('ascii') in CHILD_PHASES:
            self.child_phase = match[1].decode('ascii')
            observation['code'] = 'REOPEN_CHILD_REFUSED'
        if (line.startswith(b'CI_REOPEN_ERROR:') or
                observation['code'] != 'UNCLASSIFIED_OUTPUT'):
            self.output = observation

    def failure(self, error):
        if self.error is not None:
            return
        from . import hosted_chain321 as lab
        if type(error) is checkpoint.Refused:
            self.error = 'CHECKPOINT_REFUSED'
        elif type(error) is lab.Failure:
            self.error = 'LAB_REFUSED'
            self.code = error.code if type(error.code) is str and error.code in lab.CODES else None
        elif type(error) is lab.wire_policy.Refused:
            self.error = 'WIRE_REFUSED'
            self.code = (error.code if type(error.code) is str
                         and error.code in lab.wire_policy.CODES else None)
        elif type(error) is debug.ProcessRefused:
            self.error = 'PROCESS_REFUSED'
            code = error.args[0] if len(error.args) == 1 else None
            self.code = code if type(code) is str and code in debug.CODES else None
        elif type(error) is TypeError:
            self.error = 'TYPE_ERROR'
        elif type(error) is KeyError:
            self.error = 'KEY_ERROR'
        elif isinstance(error, OSError):
            self.error = 'OS_ERROR'
        elif type(error) is ValueError:
            self.error = 'VALUE_ERROR'
        elif type(error) is KeyboardInterrupt:
            self.error = 'INTERRUPTED'
        else:
            self.error = 'OTHER_ERROR'

    def snapshot(self):
        value = dict(schema=1,
            scope='owned_restored_lab_reopen_diagnostic', phase=self.phase,
            child_phase=self.child_phase, output=self.output,
            error=self.error, code=self.code)
        if self.child_failure is not None:
            value['child_failure'] = self.child_failure
        return diagnostic_projection(value)


def wallet_observation(value):
    checkpoint.need(type(value) is dict and set(value) == OBSERVATION
        and type(value['schema']) is int and value['schema'] == 1
        and value['scope'] == 'restored_lab_wallet_observation'
        and type(value['chain']) is int and value['chain'] == 321
        and type(value['members']) is int and 2 <= value['members'] <= 128
        and type(value['selected_index']) is int and value['selected_index'] == 1
        and all(value[key] is True for key in OBSERVATION -
            {'schema', 'scope', 'chain', 'members', 'selected_index'}))
    return dict(value)


def bounded_read(path, cap):
    identity = checkpoint.file_identity(path.lstat())
    checkpoint.need(0 < identity[2] <= cap)
    flags = os.O_RDONLY | getattr(os, 'O_BINARY', 0) | getattr(os, 'O_NOFOLLOW', 0)
    with os.fdopen(os.open(path, flags), 'rb') as stream:
        checkpoint.need(checkpoint.file_identity(os.fstat(stream.fileno())) == identity)
        raw = stream.read(cap + 1)
        checkpoint.need(len(raw) == identity[2]
            and checkpoint.file_identity(os.fstat(stream.fileno())) == identity)
    checkpoint.need(checkpoint.file_identity(path.lstat()) == identity)
    return raw


class _CapturedOutput:
    """One pipe reader, with a capped private prefix retained on failure."""
    def __init__(self, stream, write, cap=OUTPUT_CAP):
        checkpoint.need(type(cap) is int and 0 < cap <= OUTPUT_CAP and callable(write))
        self.stream, self.write, self.cap = stream, write, cap
        self.bytes = 0
        self.digest = hashlib.sha256()
        self.overflow = False

    def readline(self, limit):
        raw = self.stream.readline(limit)
        part = raw[:max(0, self.cap-self.bytes)]
        if part:
            checkpoint.need(self.write(part) == len(part))
            self.bytes += len(part)
            self.digest.update(part)
        self.overflow |= len(part) != len(raw)
        return raw


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
    seed_fields = {'seed_workflow'} if 'seed_workflow' in value else set()
    checkpoint.need(set(value) == common | seed_fields | {'claim_once', 'originals_closed',
        'chain_continuity', 'journal_unchanged', 'cipher_unchanged', 'wallet',
        'application_exit', 'entry_exit', 'output', 'job_empty', 'forced',
        'nodes', 'private_manifest_sha256', 'seed_admitted'}
        and all(value[key] is True for key in ('claim_once', 'originals_closed',
            'chain_continuity', 'journal_unchanged', 'cipher_unchanged', 'job_empty'))
        and value['forced'] is value['seed_admitted'] is False
        and all(type(value[key]) is int and value[key] == 0
                for key in ('application_exit', 'entry_exit')))
    wallet_observation(value['wallet'])
    if seed_fields:
        seed_value = seeds.project(value['seed_workflow'])
        checkpoint.need(type(seed_value) is dict and seed_value['complete'] is True)
    output = value['output']
    checkpoint.need(type(output) is dict and set(output) ==
        {'bytes', 'sha256', 'output_complete', 'overflow'}
        and type(output['bytes']) is int and 0 < output['bytes'] <= 2 * 1024**2
        and output['output_complete'] is True and output['overflow'] is False
        and all(type(item) is str and re.fullmatch('[a-f0-9]{64}', item)
                for item in (output['sha256'], value['private_manifest_sha256'])))
    nodes = value['nodes']
    checkpoint.need(type(nodes) is list and len(nodes) == 5)
    for role, node in zip(checkpoint.ROLES[1:], nodes):
        checkpoint.need(type(node) is dict and set(node) ==
            {'role', 'exit_code', 'output_complete', 'forced'}
            and node['role'] == role and type(node['exit_code']) is int
            and node['exit_code'] == 0 and node['output_complete'] is True
            and node['forced'] is False)
    return dict(value)


def notice_frames(summary):
    """Preserve all closed-copy facts in bounded, parent-bound notice frames."""
    from . import restored_lab_paths, closed_wallet_pointer
    validators = {'checkpoint': checkpoint.project, 'path_binding': restored_lab_paths.project,
        'wallet_pointer_binding': closed_wallet_pointer.project, 'wallet_reopen': project}
    value = dict(summary)
    for key, validate in validators.items():
        if key in value:
            value[key] = validate(value[key])
    encode = lambda item: json.dumps(item, sort_keys=True, separators=(',', ':')).encode('ascii')
    if len(encode(value)) <= 3800:
        return [('', value)]
    components = {key: value.pop(key) for key in validators if value.get(key) is not None}
    checkpoint.need(components and len(encode(value)) <= 3800)
    parent_sha = hashlib.sha256(encode(value)).hexdigest()
    header = {key: value[key] for key in ('source_sha', 'source_head', 'source_tree',
        'run_id', 'run_attempt', 'backend', 'archive_sha256', 'manifest_sha256') if key in value}
    frames = [('', value)]
    for key, facts in components.items():
        frame = dict(schema=1, scope='closed_copy_observation_component',
            parent_scope=value['scope'], parent_notice_sha256=parent_sha,
            components=list(components), component=key, facts=facts, **header)
        checkpoint.need(len(encode(frame)) <= 3800)
        frames.append((key, frame))
    return frames


class _ChainAnchor:
    def __init__(self, owner, genesis, frontier):
        self.owner, self.genesis, self.frontier = owner, genesis, frontier

    def __repr__(self):
        return '<original owned chain anchor>'


def chain_read(runtime, original=None):
    """Read both owned loopback transports; no publication endpoint is used."""
    from . import hosted_chain321 as lab
    checkpoint.need(isinstance(runtime, lab.Native))
    checkpoint.need(original is None or
        type(original) is _ChainAnchor and original.owner is not runtime)
    runtime.healthy()
    http_wire, ws_wire = lab.make_transports()
    policy = lab.wire_policy
    deadline = policy._Deadline(time.monotonic, time.monotonic() + 60)
    http = policy.HttpRpc(http_wire, policy.Limits(), deadline, secrets.token_bytes,
        retained_momentum=None if original is None else original.frontier)
    ws = policy.WsRpc(ws_wire, policy.Limits(), deadline, secrets.token_bytes)
    failed_original = False
    try:
        ws.connect()
        def at(height):
            reply = http.call('ledger.getMomentumsByHeight', [height, 1])
            checkpoint.need(type(reply) is dict and type(reply.get('list')) is list
                            and len(reply['list']) == 1)
            return policy.Momentum.parse(reply['list'][0])
        genesis = at(1)
        frontier = policy.Momentum.parse(http.call('ledger.getFrontierMomentum', []))
        checkpoint.need(genesis.height == 1
            and policy.Momentum.parse(ws.call('ledger.getMomentumByHash', [genesis.hash])) == genesis
            and policy.Momentum.parse(ws.call('ledger.getMomentumByHash', [frontier.hash])) == frontier)
        if original is not None:
            checkpoint.need(type(original) is _ChainAnchor
                and original.owner is not runtime and genesis == original.genesis
                and at(original.frontier.height) == original.frontier
                and policy.Momentum.parse(ws.call('ledger.getMomentumByHash',
                    [original.frontier.hash])) == original.frontier
                and frontier.height > original.frontier.height
                and frontier.timestamp > original.frontier.timestamp)
        runtime.healthy()
        return _ChainAnchor(runtime, genesis, frontier)
    except BaseException:
        failed_original = True
        raise
    finally:
        # A failed close is a failed observation, including after a good reply.
        failed = False
        for transport in (ws, http):
            try:
                transport.close()
            except Exception:
                failed = True
        if failed and not failed_original:
            raise checkpoint.Refused()


def retire_metadata(original, copied, retained, closed, deadline):
    """Preserve the verified copied instance receipt under an unused name."""
    checkpoint.need(closed() is True and not retained.exists() and not retained.is_symlink())
    original_id = checkpoint.file_identity(original.lstat())
    copied_id = checkpoint.file_identity(copied.lstat())
    checkpoint.need(0 < copied_id[2] <= 4096 and original_id[2] == copied_id[2]
                    and original_id[:2] != copied_id[:2])
    original_sha = checkpoint.digest_file(original, original_id, deadline)
    checkpoint.need(checkpoint.digest_file(copied, copied_id, deadline) == original_sha)
    raw = bounded_read(copied, 4096)
    checkpoint.need(len(raw) == copied_id[2] and hashlib.sha256(raw).hexdigest() == original_sha
                    and checkpoint.file_identity(copied.lstat()) == copied_id)
    value = json.loads(raw)
    checkpoint.need(type(value) is dict and value.get('mode') == 'release'
        and value.get('harnessMode') == 'wallet' and value.get('presentationScreen') is None
        and type(value.get('token')) is str and re.fullmatch('[a-f0-9]{32}', value['token'])
        and closed() is True)
    copied.rename(retained)
    checkpoint.need(closed() is True and checkpoint.file_identity(retained.lstat()) == copied_id
        and checkpoint.digest_file(retained, copied_id, deadline) == original_sha
        and not copied.exists() and not copied.is_symlink()
        and checkpoint.file_identity(original.lstat()) == original_id
        and checkpoint.digest_file(original, original_id, deadline) == original_sha)
    return value, (original_id, original_sha), (copied_id, original_sha)


def run(repo, parent, wallet, original_runtime, anchor, restored, home, closed, measure, *, diagnostic=None):
    from . import hosted_chain321 as lab, windows_wallet_tour as tour
    trace = ReopenDiagnostic() if diagnostic is None else diagnostic
    checkpoint.need(type(trace) is ReopenDiagnostic)
    trace.at('admission')
    parent, source = debug.entry.require_ci(parent, None, platform=os.name)
    checkpoint.need(parent.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
        and parent.get('SYRIUS_HOSTED_RUNNER') == 'github-hosted'
        and type(wallet) is tour._ClosedWallet and type(anchor) is _ChainAnchor
        and anchor.owner is original_runtime and closed() is True
        and lab.checkpoint_closed(original_runtime, wallet) is True
        and set(restored) == set(checkpoint.ROLES))
    trace.at('origin')
    origin = wallet.restoration_origin()
    trace.at('roots')
    home, repo = Path(home), Path(repo)
    copied_home = Path(restored['wallet_profile'])
    checkpoint.need(all(Path(restored[role]) == home / 'restored' / role
        and Path(restored[role]) != original_runtime.configs[role]
        for role in checkpoint.ROLES[1:]))
    copied_wallet, _ = origin.copied_paths(str(copied_home))
    deadline = time.monotonic() + 2400
    pins = dict(checkpoint.ancestors(home))
    report_pins = dict(pins)
    for root in (wallet.home, *restored.values()):
        pins.update(checkpoint.ancestors(Path(root)))
    snapshot = {}
    trace.at('journals')
    for name in ('seed-lab-send-attempt.json', 'seed-lab-send-accepted.json',
                 'seed-lab-send-confirmed.json'):
        for path in (wallet.home / name, copied_home / name):
            identity = checkpoint.file_identity(path.lstat())
            checkpoint.need(0 < identity[2] <= 2048)
            snapshot[path] = identity, checkpoint.digest_file(path, identity, deadline)
        checkpoint.need(snapshot[wallet.home / name][1] == snapshot[copied_home / name][1]
            and snapshot[wallet.home / name][0][:2] != snapshot[copied_home / name][0][:2])
    trace.at('ciphers')
    for path in (Path(origin.wallet), Path(copied_wallet)):
        pins.update(checkpoint.ancestors(path.parent))
        identity = checkpoint.file_identity(path.lstat())
        checkpoint.need(0 < identity[2] <= 64 * 1024)
        snapshot[path] = identity, checkpoint.digest_file(path, identity, deadline)
    checkpoint.need(snapshot[Path(origin.wallet)][1] == snapshot[Path(copied_wallet)][1])
    trace.at('node_inputs')
    for role in checkpoint.ROLES[1:]:
        for name in ('config.json', 'genesis.json', 'network-private-key'):
            path = Path(restored[role]) / name
            identity = checkpoint.file_identity(path.lstat())
            cap = 1024**2 if name == 'genesis.json' else 64 * 1024
            checkpoint.need(0 < identity[2] <= cap)
            snapshot[path] = identity, checkpoint.digest_file(path, identity, deadline)
        config = json.loads(bounded_read(Path(restored[role]) / 'config.json', 64 * 1024))
        checkpoint.need(config.get('DataPath') == str(restored[role])
            and config.get('GenesisFile') == str(Path(restored[role]) / 'genesis.json')
            and config.get('WalletPath') == str(Path(restored[role]) / 'wallet'))

    def guard():
        return (time.monotonic() < deadline and closed() is True
            and lab.checkpoint_closed(original_runtime, wallet) is True
            and all(checkpoint.directory(path) == identity for path, identity in pins.items()))

    def unchanged():
        checkpoint.need(guard())
        for path, (identity, digest) in snapshot.items():
            checkpoint.need(checkpoint.file_identity(path.lstat()) == identity
                and checkpoint.digest_file(path, identity, deadline) == digest)

    def sample():
        checkpoint.need(guard())
        used = measure()
        checkpoint.need(type(used) is int and 0 <= used <= checkpoint.CAP - OUTPUT_CAP - 64 * 1024
                        and shutil.disk_usage(repo).free >= checkpoint.FLOOR + OUTPUT_CAP + 64 * 1024)

    trace.at('source')
    debug.bounded.verify_source(repo, source, parent)
    trace.at('reservation')
    tree = debug.entry.source_tree(repo, parent)
    sample()
    old_metadata = copied_home / 'instance.json'
    retained_metadata = copied_home / 'instance-before-reopen.json'
    trace.at('claim')
    wallet.claim_reopen()
    claim = home / 'wallet-reopen-claim.json'
    transport_record = home / 'wallet-reopen-transport.json'
    complete = home / 'wallet-reopen-complete.json'
    private_output = home / 'wallet-reopen-output.private'
    checkpoint.need(all(not path.exists() and not path.is_symlink()
                        for path in (claim, transport_record, complete, private_output)))
    claim_raw = checkpoint.encode(dict(schema=1, scope=SCOPE,
        source=source, tree=tree, original_profile=origin.profile,
        run_id=parent['GITHUB_RUN_ID'], run_attempt=parent['GITHUB_RUN_ATTEMPT'],
        copied_profile=copied_home.name,
        anchor_height=anchor.frontier.height, anchor_hash=anchor.frontier.hash))
    checkpoint.write_record(claim, claim_raw, guard=guard)
    snapshot[claim] = (checkpoint.file_identity(claim.lstat()), hashlib.sha256(claim_raw).hexdigest())
    trace.at('retire_metadata')
    prior, original_meta_pin, retained_meta_pin = retire_metadata(
        wallet.home / 'instance.json', old_metadata, retained_metadata, guard, deadline)
    snapshot[wallet.home / 'instance.json'] = original_meta_pin
    snapshot[retained_metadata] = retained_meta_pin
    trace.at('runtime')
    runtime = lab.Native(original_runtime.commands, original_runtime.binary,
        {role: Path(restored[role]) for role in lab.ROLES}, stack_debug=original_runtime.stack_debug)
    original = lines = job = transport = None
    output_file = captured = None
    token = None
    close_attempted = False
    record = dict(schema=1, scope=SCOPE, phase='nodes', complete=False,
        source_sha=source, source_tree=tree, run_id=parent['GITHUB_RUN_ID'],
        run_attempt=parent['GITHUB_RUN_ATTEMPT'], platform='windows',
        claim_sha256=hashlib.sha256(claim_raw).hexdigest(),
        application_exit=None, entry_exit=None, output=None, job_empty=False,
        forced=False, wallet=None, seed_workflow=None, nodes=[])
    try:
        trace.at('node_ports')
        lab.preflight_ports('native', stack_debug=original_runtime.stack_debug)
        trace.at('node_start')
        runtime.start()
        trace.at('node_observe')
        lab.observe(runtime, home, measure=sample)
        trace.at('initial_chain')
        chain_read(runtime, anchor)
        sample()
        trace.at('profile')
        env = debug.profile_environment(parent, wallet._paths[3], 1, secrets.token_hex(16))
        env.update(SYRIUS_CI_WALLET_REOPEN='true', SYRIUS_CI_REOPEN_INSTANCE=copied_home.name,
            GITHUB_EVENT_NAME=parent['GITHUB_EVENT_NAME'],
            GITHUB_REPOSITORY=parent['GITHUB_REPOSITORY'],
            SYRIUS_HOSTED_RUNNER=parent['SYRIUS_HOSTED_RUNNER'])
        dart, _ = debug.sdk(parent)
        trace.at('launch')
        job = debug.WindowsJob()
        original = subprocess.Popen([str(dart), '--disable-dart-dev',
            '--packages=' + str(repo / '.dart_tool/package_config.json'),
            'harness/bin/ci_wallet_reopen.dart'], cwd=repo, env=env, shell=False,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
        job.assign(original)
        checkpoint.need(guard())
        trace.at('output')
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_BINARY', 0)
        descriptor = os.open(private_output, flags | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        output_file = os.fdopen(descriptor, 'wb')
        captured = _CapturedOutput(original.stdout, output_file.write)
        lines = debug.Lines(captured)

        def write(raw):
            checkpoint.need(guard() and original.poll() is None and len(raw) <= 32768)
            runtime.healthy()
            original.stdin.write(raw)
            original.stdin.flush()

        def wait(marker):
            next_sample = 0.0
            while time.monotonic() < deadline:
                checkpoint.need(guard())
                runtime.healthy()
                if time.monotonic() >= next_sample:
                    sample()
                    next_sample = time.monotonic() + 5
                raw = lines.take(.1)
                if raw is None:
                    checkpoint.need(original.poll() is None or not lines.complete)
                    continue
                trace.observe_line(raw)
                line = raw.rstrip(b'\r\n')
                checkpoint.need(not line.startswith((
                    b'CI_REOPEN_ERROR:', b'CI_REOPEN_FAILURE:')))
                if marker == b'CI_REOPEN_DONE' and line.startswith(marker + b':'):
                    return wallet_observation(json.loads(line.partition(b':')[2]))
                if marker == b'CI_SEED_DONE' and line.startswith(marker + b':'):
                    return seeds.private_receipts(json.loads(line.partition(b':')[2]))
                if line == marker:
                    return None
                checkpoint.need(not line.startswith((b'CI_REOPEN_', b'CI_SEED_')))
            raise checkpoint.Refused()

        trace.at('start')
        record['phase'] = 'start'
        write(b'START\n')
        wait(b'CI_REOPEN_READY')
        trace.at('entry_metadata')
        metadata = debug.bounded.plain(old_metadata)
        checkpoint.need(0 < metadata.st_size <= 4096)
        private = json.loads(bounded_read(old_metadata, 4096))
        pid, port, token = private.get('pid'), private.get('port'), private.get('token')
        checkpoint.need(type(pid) is int and 0 < pid < 2**32 and type(port) is int
            and 1024 <= port <= 65535 and type(token) is str
            and re.fullmatch('[a-f0-9]{32}', token) and token != prior['token']
            and private.get('mode') == 'release' and private.get('harnessMode') == 'wallet'
            and private.get('presentationScreen') is None)
        trace.at('application')
        job.bind_application(pid, wallet._paths[1] / 'release/syrius.exe')
        trace.at('transport')
        transport = debug.bounded.LoopbackTransport(port, 32768)
        reply = transport.exchange(dict(cmd='ping'), token, 5)
        body = json.loads(reply.body)
        checkpoint.need(reply.status == 200 and type(body) is dict
            and body.get('ok') is True and body.get('booted') is True
            and type(body.get('pid')) is int and body['pid'] == pid
            and body.get('harnessMode') == 'wallet')
        trace.at('pre_input')
        chain_read(runtime, anchor)
        unchanged()
        trace.at('unlock_and_observe')
        record['phase'] = 'unlock_and_observe'
        write(checkpoint.encode(wallet.reopen_input(copied_home)))
        record['wallet'] = wait(b'CI_REOPEN_DONE')
        trace.at('post_observe')
        unchanged()
        chain_read(runtime, anchor)
        trace.at('seed_workflow')
        record['phase'] = 'seed_workflow'
        chosen = seeds.counterparty(json.loads(bounded_read(
            Path(restored['rpc']) / 'genesis.json', 1024**2)), origin.members)
        unchanged()
        write(checkpoint.encode(dict(action='SEED', counterparty=chosen)))
        seed_receipts = wait(b'CI_SEED_DONE')
        unchanged()
        trace.at('seed_journals')
        for row in seed_receipts['receipts']:
            for state in ('attempt', 'accepted', 'confirmed'):
                path = copied_home / ('seed-' + row['recipe'] + '-' + state + '.json')
                identity = checkpoint.file_identity(path.lstat())
                raw = bounded_read(path, 2048)
                seeds.journal_record(row['recipe'], state, raw, row['hash'])
                checkpoint.need(checkpoint.file_identity(path.lstat()) == identity)
                snapshot[path] = identity, hashlib.sha256(raw).hexdigest()
        record['seed_private_receipts'] = seed_receipts
        record['seed_workflow'] = seeds.completed(seed_receipts)
        unchanged()
        chain_read(runtime, anchor)
        trace.at('ordinary_close')
        record['phase'] = 'ordinary_close'
        close_attempted = True
        debug.request_close(transport, token)
        record['application_exit'] = job.application_exit()
        checkpoint.need(type(record['application_exit']) is int and record['application_exit'] == 0)
        trace.at('finish')
        write(b'FINISH\n')
        record['entry_exit'] = original.wait(timeout=15)
        checkpoint.need(type(record['entry_exit']) is int and record['entry_exit'] == 0
            and lines.finish() and lines.take(0) is None and job.active() == 0)
        trace.at('source_closed')
        unchanged()
        debug.bounded.verify_source(repo, source, parent)
        checkpoint.need(debug.entry.source_tree(repo, parent) == tree)
        record.update(phase='complete', complete=True, job_empty=True)
    finally:
        if not close_attempted and transport is not None and token is not None:
            close_attempted = True
            try:
                debug.request_close(transport, token)
                record['application_exit'] = job.application_exit()
            except Exception:
                record['complete'] = False
        if job is not None:
            try:
                if record['complete']:
                    trace.at('close')
                record['forced'] = job.close()
            except Exception:
                record['forced'] = None
        if original is not None:
            if original.poll() is None:
                try:
                    original.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    pass
            record['entry_exit'] = original.poll()
            try:
                original.stdin.close()
            except OSError:
                record['complete'] = False
        if lines is not None:
            drained = lines.finish()
            record['output'] = lines.public()
            if not drained:
                record['complete'] = False
        if output_file is not None:
            try:
                if record['complete'] and record['forced'] is False:
                    trace.at('output_close')
                output_file.flush()
                os.fsync(output_file.fileno())
                identity = checkpoint.file_identity(os.fstat(output_file.fileno()))
                checkpoint.need(lines is not None and not lines.thread.is_alive()
                    and identity[2] == captured.bytes)
                output_file.close()
                private_output.chmod(0o400)
                digest = captured.digest.hexdigest()
                checkpoint.need(checkpoint.digest_file(private_output, identity,
                    time.monotonic()+15) == digest)
                record['private_output'] = dict(bytes=captured.bytes,
                    sha256=digest, overflow=captured.overflow,
                    complete=lines.complete and not captured.overflow)
                if captured.overflow or not lines.complete:
                    record['complete'] = False
            except Exception:
                record['private_output'] = dict(status='UNKNOWN')
                record['complete'] = False
            finally:
                try:
                    output_file.close()
                except Exception:
                    record['complete'] = False
        if transport is not None:
            try:
                if record['complete'] and record['forced'] is False:
                    trace.at('transport_close')
                transport.close()
            except Exception:
                record['complete'] = False
        try:
            if record['complete'] and record['forced'] is False:
                trace.at('nodes_stop')
            runtime.stop()
        except Exception:
            record['complete'] = False
        record['nodes'] = [dict(role=role, exit_code=item.receipt.get('exit_code'),
            output_complete=item.receipt.get('output_complete'), forced=item.receipt.get('forced'))
            for role, item in zip(lab.ROLES, runtime.originals) if type(item.receipt) is dict]
        record['node_originals'] = [dict(role=role, pid=item.process.pid, receipt=item.receipt)
            for role, item in zip(lab.ROLES, runtime.originals)]
        if record['forced'] is not False:
            record['complete'] = False
        checkpoint.write_record(transport_record, checkpoint.encode(record),
            guard=lambda: all(checkpoint.directory(path) == identity
                              for path, identity in report_pins.items()))
    checkpoint.need(record['complete'])
    trace.at('post_close')
    unchanged()
    sample()
    raw = checkpoint.encode(record)
    trace.at('complete_record')
    checkpoint.write_record(complete, raw, guard=guard)
    trace.at('projection')
    return project(dict(schema=1, scope=SCOPE, complete=True, claim_once=True,
        originals_closed=True, chain_continuity=True, journal_unchanged=True,
        cipher_unchanged=True, wallet=record['wallet'],
        application_exit=record['application_exit'], entry_exit=record['entry_exit'],
        output=record['output'], job_empty=True, forced=False, nodes=record['nodes'],
        private_manifest_sha256=hashlib.sha256(raw).hexdigest(), seed_admitted=False,
        seed_workflow=record['seed_workflow']))
