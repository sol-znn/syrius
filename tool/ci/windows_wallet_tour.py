"""A gated ordinary wallet tour while the original owned chain-321 lab runs.

Only a finite manifest leaves this controller. The public lab mnemonic, generated
password, private instance receipt, profile, captures and raw output stay private.
"""

from __future__ import annotations

import base64
import hashlib
import json
import ntpath
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import subprocess
import time

from . import lab_send_diagnostic
from . import wallet_restore_origin
from . import windows_debug_loop as debug


PAGES = ('dashboard', 'transfer', 'pillars', 'sentinels', 'staking', 'plasma',
         'tokens', 'p2pSwap', 'accelerator', 'notifications', 'settings', 'walletConnect')
CHECKS = ('environment', 'source', 'unused_destinations', 'job_owned', 'entry_gate', 'entry_ready',
          'application_owned', 'lab_revalidated', 'input_released', 'tour_complete',
          'captures', 'close_ack', 'application_exit', 'entry_exit', 'output_complete',
          'source_unchanged', 'auxiliary_cleanup')
CURRENT_CHECKS = (*CHECKS, 'quiescence')
CODES = frozenset(('ENVIRONMENT_REFUSED', 'SOURCE_REFUSED', 'PROFILE_REFUSED',
    'STORAGE_REFUSED', 'JOB_REFUSED', 'PROCESS_REFUSED', 'ENTRY_REFUSED',
    'ENTRY_FAILED', 'TOUR_REFUSED', 'CAPTURE_REFUSED', 'FIXTURE_REFUSED',
    'LAB_REFUSED', 'INPUT_REFUSED', 'CLOSE_UNCONFIRMED', 'OUTPUT_REFUSED',
    'EXISTING_PROCESS', 'PREFLIGHT_FAILED', 'PREFLIGHT_TIMEOUT', 'PREFLIGHT_OUTPUT_REFUSED',
    'APPLICATION_EXIT_UNCONFIRMED', 'PNG_INVALID', 'TOOL_REFUSED',
    'TOTAL_DEADLINE', 'HELPER_IMAGE_REFUSED', 'HELPER_IDENTITY_REFUSED',
    'HELPER_CLOSE_UNCONFIRMED', 'QUIESCENCE_REFUSED', 'INTERNAL_ERROR'))
WORK_CAP = 4 * 1024**3
FIXTURE_FLOOR = 2 * 1024**3
ENTRY_LIMIT = 100000
STORAGE_ROLES = ('wallet_profile', 'application', 'native_build', 'tool_profile')
PROFILE_PARTS = {name.casefold(): name.replace(' ', '_').lower() for name in
    ('AppData', 'Local', 'Roaming', 'Temp', 'Application Data', 'Local Settings',
     'Microsoft', 'VSCommon', 'VisualStudio', 'Telemetry', '.dotnet', '.nuget',
     'NuGet', 'Packages', 'Pub', 'Cache', 'Dart')}
ALIAS_LIMIT = 16
RECIPE_ACTIONS = frozenset(('observe', 'tap', 'type', 'scroll', 'key', 'unknown'))
RECIPE_CONTROLS = frozenset((
    'none', 'unknown', 'launch_skip_hint', 'welcome_import', 'import_words_12', 'import_words_24',
    'import_seed_field', 'import_continue', 'import_new_password',
    'import_confirm_password', 'import_password_continue', 'node_settings_add',
    'node_settings_endpoint', 'node_settings_endpoint_save', 'node_settings_select',
    'node_onboarding_continue', 'node_settings_question_accept',
    'node_settings_chain_toggle', 'node_settings_client_chain', 'node_settings_chain_save',
    'wallet_ready_open', 'nav_settings', 'nav_dashboard', 'settings_node',
    'settings_addresses', 'settings_add_address', 'addresses_select',
))
RECIPE_FAILURE_CODES = frozenset((
    'wallet-recipe-action-refused', 'wallet-recipe-control-refused',
    'wallet-recipe-input-refused', 'wallet-recipe-node-view-ambiguous',
    'wallet-recipe-original-control-changed', 'wallet-recipe-original-owner-changed',
    'wallet-recipe-original-address-context-changed',
    'wallet-recipe-original-control-replaced', 'wallet-recipe-original-control-moved',
    'wallet-recipe-original-control-moved-subpixel', 'wallet-recipe-original-control-resized',
    'wallet-recipe-original-question-changed', 'wallet-recipe-original-ready-changed',
    'wallet-recipe-original-ready-unavailable', 'wallet-recipe-private-input-refused',
    'wallet-recipe-question-already-used', 'wallet-recipe-question-facts-refused',
    'wallet-recipe-question-replaced', 'wallet-recipe-question-unowned',
    'wallet-recipe-refused', 'wallet-recipe-scroll-refused',
    'wallet-recipe-selection-origin-refused', 'wallet-recipe-transition-held',
    'wallet-recipe-visible-error',
    'wallet-recipe-stage-unsettled', 'wallet-recipe-control-absent',
    'wallet-recipe-control-disabled',
    'wallet-recipe-control-widget-disabled',
    'wallet-recipe-address-backend-blocked',
    'wallet-recipe-address-mounted-blocked',
    'wallet-recipe-address-hidden-blocked',
    'wallet-recipe-address-window-blocked',
    'wallet-recipe-address-section-blocked',
    'wallet-recipe-address-focus-blocked',
    'wallet-recipe-address-route-blocked',
    'wallet-recipe-address-ticker-blocked',
    'wallet-recipe-address-busy-blocked',
    'wallet-recipe-control-entrance-pending',
    'wallet-recipe-control-layout-pending',
    'wallet-recipe-control-not-reachable',
    'wallet-recipe-startup-key-unconfirmed',
))
RECIPE_ENTRY_PHASES = frozenset((
    'startup', 'welcome', 'import', 'ready', 'node', 'error', 'unknown',
    'startup-before-initialization', 'startup-initialization-started',
    'startup-initialization-refused', 'startup-filesystem-error',
    'startup-platform-error', 'startup-hive-error', 'startup-other-error',
))
RECIPE_STARTUP_HANDOFFS = frozenset((
    'observing', 'key-sent', 'key-confirmed', 'natural-welcome', 'natural-initialization',
))
RECIPE_STARTUP_FILM_STATES = frozenset((
    'opening', 'first-frame-pending', 'frame-visible', 'last-frame', 'ended',
    'frames-suspended', 'ticker-muted',
    'skip-ticker-stopped', 'skip-display-pending', 'skip-next-pending',
    'skip-previous-pending', 'skip-asset-pending', 'skip-codec-pending',
    'skip-frame-pending', 'skip-resize-pending',
    'skip-first-frame-pending', 'skip-middle-frame-pending',
    'skip-last-frame-pending',
    'skip-display-wait-pending', 'skip-dispose-pending',
))


class Refused(Exception):
    def __init__(self, code):
        self.code = code if code in CODES else 'INTERNAL_ERROR'
        super().__init__(self.code)


def need(value, code):
    if not value:
        raise Refused(code)


TOUR_FAILURE_STEPS = frozenset((
    'beforePage', 'railNavigation', 'sectionControlWait', 'sectionControlTap',
    'sectionPageWait', 'pointerNeutral', 'nodeRestingTap', 'settle', 'tree',
    'logs', 'capture', 'afterPage',
    'bellClose', 'bellGone', 'afterBell', 'returnHome',
))
TOUR_FAILURE_KINDS = frozenset(('refused', 'timeout', 'replyShape', 'filesystem', 'other'))


def tour_failure_diagnostic(value):
    """Only catalog metadata survives an original failed tour operation."""
    need(type(value) is dict and set(value) == {'schema', 'scope', 'page', 'step', 'kind'}
         and type(value['schema']) is int and value['schema'] == 1
         and value['scope'] == 'original_wallet_page_tour_failure'
         and type(value['page']) is str and value['page'] in (*PAGES, 'unknown')
         and type(value['step']) is str and value['step'] in TOUR_FAILURE_STEPS
         and type(value['kind']) is str and value['kind'] in TOUR_FAILURE_KINDS,
         'ENTRY_REFUSED')
    return value


def entry_failure(value):
    """Keep fixed onboarding labels; reject raw reply fields before recording."""
    need(type(value) is dict and set(value) in ({'stage', 'code'}, {'stage', 'code', 'diagnostic'})
         and value['stage'] in ('unused_destinations', 'build', 'start', 'input', 'onboarding',
             'signing_policy', 'onboarding_logs', 'window', 'address_selection',
             'lab_send', 'tour', 'finish')
         and (value['code'] is None or type(value['code']) is str
              and re.fullmatch('wallet-recipe-[a-z-]{1,80}', value['code'])), 'ENTRY_REFUSED')
    if 'diagnostic' in value:
        diagnostic = value['diagnostic']
        if value['stage'] == 'tour':
            need(value['code'] is None, 'ENTRY_REFUSED')
            tour_failure_diagnostic(diagnostic)
            return value
        if value['stage'] == 'lab_send':
            need(value['code'] is None and lab_send_diagnostic.valid(diagnostic),
                 'ENTRY_REFUSED')
            return value
        need(value['stage'] in ('onboarding', 'address_selection')
             and value['code'] in ('wallet-recipe-command-refused', 'wallet-recipe-stage-unsettled')
             and type(diagnostic) is dict and {'action', 'control', 'reason'} <= set(diagnostic)
             and set(diagnostic) <= {'action', 'control', 'reason', 'entry', 'startup', 'film'}
             and all(type(item) is str for item in diagnostic.values())
             and diagnostic['action'] in RECIPE_ACTIONS and diagnostic['control'] in RECIPE_CONTROLS
             and diagnostic['reason'] in RECIPE_FAILURE_CODES
             and ('entry' not in diagnostic or diagnostic['entry'] in RECIPE_ENTRY_PHASES)
             and ('startup' not in diagnostic or diagnostic['startup'] in RECIPE_STARTUP_HANDOFFS)
             and ('film' not in diagnostic or diagnostic['film'] in RECIPE_STARTUP_FILM_STATES), 'ENTRY_REFUSED')
    return value


def address_selection_receipt(value):
    """Keep only finite P09 preparation facts, never members or addresses."""
    need(type(value) is dict and set(value) ==
         {'index', 'members', 'generated', 'selected', 'persisted'}
         and type(value['index']) is int and value['index'] == 1
         and type(value['members']) is int and 2 <= value['members'] <= 128
         and type(value['generated']) is bool
         and value['selected'] is value['persisted'] is True, 'ENTRY_REFUSED')
    return value


def public_fixture(text):
    """Read only the explicitly committed public devnet example, never a profile."""
    need(type(text) is str and 0 < len(text.encode()) <= 65536, 'FIXTURE_REFUSED')
    offered = re.findall(r'^```\r?\n([a-z]+(?: [a-z]+){11}|[a-z]+(?: [a-z]+){23})\r?\n```$', text, re.M)
    need(len(offered) == 1 and len(offered[0]) <= 512, 'FIXTURE_REFUSED')
    return offered[0]


def lab_send_receipt(value):
    """Accept only finite original P09 send facts, with no address/hash fields."""
    expected = dict(schema=1, scope='original_lab_ui_send', chain=321,
        from_index=1, to_index=0, amount='100000000', token='ZNN',
        original_request=True, confirmed=True)
    need(type(value) is dict and set(value) == set(expected)
         and all(type(value[key]) is type(item) and value[key] == item
                 for key, item in expected.items()), 'ENTRY_REFUSED')
    return value


def tour_receipt(value):
    need(type(value) is dict and set(value) == {'schema', 'scope', 'complete', 'requested', 'visited'}
         and type(value['schema']) is int and value['schema'] == 1
         and value['scope'] == 'wallet_page_tour' and type(value['complete']) is bool
         and value['requested'] == list(PAGES) and type(value['visited']) is list
         and len(value['visited']) <= len(PAGES), 'TOUR_REFUSED')
    for index, page in enumerate(value['visited']):
        need(type(page) is dict and set(page) == {'page', 'nodes', 'error_widgets', 'severe_logs', 'captured'}
             and page['page'] == PAGES[index] and type(page['captured']) is bool
             and all(type(page[key]) is int and 0 <= page[key] <= 100000
                     for key in ('nodes', 'error_widgets', 'severe_logs')), 'TOUR_REFUSED')
    return value


def tour_complete(value):
    return (value['complete'] is True and len(value['visited']) == len(PAGES)
            and all(page['captured'] and page['error_widgets'] == page['severe_logs'] == 0
                    for page in value['visited']))


def quiescence_receipt(value):
    """A finite projection cannot supply the original process or wallet owner."""
    need(type(value) is dict and set(value) == {'schema', 'scope', 'chain', 'complete',
         'admission_closed', 'original_send_confirmed', 'originals_positive',
         'file_operations', 'sdk_publications', 'receive_reads', 'receive_publications'}
         and type(value['schema']) is int and value['schema'] == 1
         and value['scope'] == 'owned_lab_quiescence'
         and type(value['chain']) is int and value['chain'] == 321
         and all(value[key] is True for key in ('complete', 'admission_closed',
             'original_send_confirmed', 'originals_positive'))
         and all(type(value[key]) is int and lower <= value[key] <= upper
             for key, lower, upper in (('file_operations', 1, 512),
                 ('sdk_publications', 1, 128), ('receive_reads', 0, 256),
                 ('receive_publications', 0, 127)))
         and value['sdk_publications'] == value['receive_publications'] + 1
         and value['receive_reads'] >= value['receive_publications']
         and value['file_operations'] >= value['sdk_publications'], 'QUIESCENCE_REFUSED')
    return value


def completed(report):
    """A good page receipt cannot heal uncertain original exits or cleanup."""
    try:
        version = report.get('schema', 1)
        if type(version) is not int or version not in (1, 2):
            return False
        if version == 2:
            quiescence_receipt(report.get('quiescence'))
        elif 'quiescence' in report:
            return False
        if 'address_selection' in report:
            address_selection_receipt(report['address_selection'])
        if 'lab_send' in report:
            lab_send_receipt(report['lab_send'])
        checks = report['checks']
        expected = CHECKS if version == 1 else CURRENT_CHECKS
        if (type(checks) is not dict or set(checks) != set(expected)
                or not all(value is True for value in checks.values())
                or report.get('entry_failure') is not None
                or report['errors'] != [] or report['required_actor_forced_cleanup'] is not False
                or any(type(report.get(key)) is not int or report[key] != 0
                       for key in ('application_exit', 'entry_exit', 'owned_job_active_at_close'))
                or report['entry_output']['output_complete'] is not True
                or report['entry_output']['overflow'] is not False
                or not debug.helper_cleanup_complete(report['auxiliary_cleanup'])
                or report['forced_cleanup'] is not report['auxiliary_cleanup']['forced']
                or not tour_complete(tour_receipt(report['tour']))):
            return False
        captures = report['captures']
        if type(captures) is not list or len(captures) != len(PAGES):
            return False
        return all(type(item) is dict and set(item) == {'page', 'bytes', 'sha256', 'width', 'height'}
            and item['page'] == page and type(item['bytes']) is int
            and 0 < item['bytes'] <= debug.entry.MAX_PNG
            and debug.bounded.safe_digest(item['sha256'])
            and type(item['width']) is type(item['height']) is int
            and item['width'] == 1280 and item['height'] == 780
            for item, page in zip(captures, PAGES))
    except (KeyError, TypeError, Refused):
        return False


def directory_identity(info):
    fields = (getattr(info, 'st_dev', None), getattr(info, 'st_ino', None), getattr(info, 'st_mode', None),
              getattr(info, 'st_file_attributes', 0), getattr(info, 'st_reparse_tag', 0))
    if (not all(type(value) is int for value in fields) or info.st_ino <= 0
            or not stat.S_ISDIR(info.st_mode) or fields[3] & 0x400 or fields[4] != 0):
        return None
    return (fields[0], fields[1], stat.S_IFMT(fields[2]), fields[3] & 0x400, fields[4])


def plain_profile_target(profile, target, expected_profile):
    """Check canonical directories in order; never cross a reparse ancestor."""
    if expected_profile is None:
        return False
    try:
        target = type(profile)(target)
        relative = target.relative_to(profile)
        need(len(relative.parts) <= 12 and all(part not in ('.','..') for part in relative.parts),
             'STORAGE_REFUSED')
        chain = [profile] + [profile.joinpath(*relative.parts[:index])
                             for index in range(1, len(relative.parts)+1)]
        observed = []
        for index, path in enumerate(chain):
            identity = directory_identity(os.lstat(path))
            if (identity is None or identity[0] != expected_profile[0]
                    or index == 0 and identity != expected_profile):
                return False
            observed.append((path, identity))
        return all(directory_identity(os.lstat(path)) == identity
                   for path, identity in reversed(observed))
    except (Exception, KeyboardInterrupt):
        return False


def reparse_observation(path, profile, before, *, expected_profile=None):
    """Read link metadata without traversal; optionally check its owned canonical target."""
    result = dict(status='UNKNOWN', observation='readlink_metadata_only')
    fields = ('st_dev', 'st_ino', 'st_mode', 'st_size', 'st_mtime_ns',
              'st_file_attributes', 'st_reparse_tag')
    try:
        identity = tuple(getattr(before, key) for key in fields)
        need(all(type(item) is int for item in identity) and before.st_ino > 0,
             'STORAGE_REFUSED')
        relative = path.relative_to(profile)
        need(0 < len(relative.parts) <= 12, 'STORAGE_REFUSED')
        target = os.readlink(path)
        after = os.lstat(path)
        if tuple(getattr(after, key) for key in fields) != identity:
            result['status'] = 'CHANGED'
            return result
        separator = chr(92)
        for prefix in (separator * 2 + '?' + separator, separator + '??' + separator):
            if target.startswith(prefix):
                target = target[len(prefix):]
                break
        if before.st_reparse_tag == 0xA0000003:
            need(ntpath.isabs(target) and bool(ntpath.splitdrive(target)[0]), 'STORAGE_REFUSED')
        target = ntpath.normcase(ntpath.normpath(ntpath.join(str(path.parent), target)))
        root = ntpath.normcase(ntpath.normpath(str(profile)))
        try:
            inside = ntpath.commonpath((root, target)) == root
        except ValueError:
            inside = False
        result.update(status='OBSERVED', stable_metadata=True, tag=before.st_reparse_tag,
            entry_parts=[PROFILE_PARTS.get(part.casefold(), 'other') for part in relative.parts],
            target_lexically_inside_profile=inside)
        if inside:
            parts = ntpath.relpath(target, root).split(separator)
            need(len(parts) <= 12, 'STORAGE_REFUSED')
            result['target_parts'] = [PROFILE_PARTS.get(part.casefold(), 'other') for part in parts]
            result['target_profile_verified'] = (before.st_reparse_tag == 0xA0000003
                and stat.S_ISDIR(before.st_mode)
                and plain_profile_target(profile, target, expected_profile))
            final = os.lstat(path)
            if tuple(getattr(final, key) for key in fields) != identity:
                return dict(status='CHANGED', observation='readlink_metadata_only')
    except (Exception, KeyboardInterrupt):
        result = dict(status='UNKNOWN', observation='readlink_metadata_only')
    return result


def sample_workspace(paths, *, receipt=None, expected_profile=None):
    """Sample only this attempt's explicit new output paths on its fresh runner."""
    need(len(paths) == len(STORAGE_ROLES), 'STORAGE_REFUSED')
    sample = {} if receipt is None else receipt
    sample.update(status='SAMPLING', reason=None, role=None, logical_bytes=0, entries=0,
        by_role=dict.fromkeys(STORAGE_ROLES, 0), verified_aliases=0, alias_metadata=[])

    def refuse(reason, role):
        sample.update(status='REFUSED', reason=reason, role=role)
        raise Refused('STORAGE_REFUSED')

    if expected_profile is not None:
        try:
            valid = directory_identity(paths[3].lstat()) == expected_profile
        except (OSError, AttributeError):
            valid = False
        if not valid:
            refuse('profile_identity_changed', 'tool_profile')
    pending = [(role, path) for role, path in zip(STORAGE_ROLES, paths)
               if path.exists() or path.is_symlink()]
    while pending:
        role, path = pending.pop()
        try:
            info = path.lstat()
        except FileNotFoundError:
            continue
        sample['entries'] += 1
        if sample['entries'] > ENTRY_LIMIT:
            refuse('entry_limit', role)
        if stat.S_ISLNK(info.st_mode):
            refuse('linked_entry', role)
        if getattr(info, 'st_file_attributes', 0) & 0x400:
            sample['reparse'] = (reparse_observation(path, paths[3], info, expected_profile=expected_profile)
                if role == 'tool_profile' else dict(status='NOT_INSPECTED'))
            observed = sample['reparse']
            if (role == 'tool_profile' and observed.get('status') == 'OBSERVED'
                    and observed.get('target_profile_verified') is True):
                sample['verified_aliases'] += 1
                if sample['verified_aliases'] > ALIAS_LIMIT:
                    refuse('alias_limit', role)
                if not sample['alias_metadata']:
                    sample['alias_metadata'].append(dict(tag=observed['tag'], stable_metadata=True,
                        target_profile_verified=True, observation='contained_alias_not_traversed'))
                del sample['reparse']
                sample['logical_bytes'] += info.st_size
                sample['by_role'][role] += info.st_size
                if sample['logical_bytes'] > WORK_CAP:
                    refuse('workspace_cap', role)
                # Its canonical target is already inside this same tree walk.
                # Count the metadata once, without walking through the alias.
                continue
            refuse('reparse_entry', role)
        if stat.S_ISDIR(info.st_mode):
            try:
                pending.extend((role, child) for child in path.iterdir())
            except FileNotFoundError:
                continue
        else:
            if not stat.S_ISREG(info.st_mode):
                refuse('non_regular_entry', role)
            sample['logical_bytes'] += info.st_size
            sample['by_role'][role] += info.st_size
            if sample['logical_bytes'] > WORK_CAP:
                refuse('workspace_cap', role)
    if expected_profile is not None:
        try:
            valid = directory_identity(paths[3].lstat()) == expected_profile
        except (OSError, AttributeError):
            valid = False
        if not valid:
            refuse('profile_identity_changed', 'tool_profile')
    sample['status'] = 'COMPLETE'
    return sample['logical_bytes']


class _QuiescenceHandoff:
    """Created from one live authenticated reply, never loaded from a report."""

    def __init__(self, entry, receipt, origin=None):
        need(callable(getattr(entry, 'poll', None)) and entry.poll() is None,
             'QUIESCENCE_REFUSED')
        self._entry = entry
        self._facts = tuple(sorted(quiescence_receipt(receipt).items()))
        need(origin is None or type(origin) is wallet_restore_origin.Origin,
             'QUIESCENCE_REFUSED')
        self._origin = origin

    def closed_for(self, entry):
        return (entry is self._entry and type(entry.poll()) is int and entry.poll() == 0
                and quiescence_receipt(dict(self._facts)) is not None)

    def origin_for(self, entry, home):
        need(self.closed_for(entry) and type(self._origin) is wallet_restore_origin.Origin
             and ntpath.normcase(self._origin.home) == ntpath.normcase(str(home)),
             'QUIESCENCE_REFUSED')
        return self._origin


class _ClosedWallet:
    """An in-memory handoff created only by the original successful close path."""

    def __init__(self, home, original, identity, password, paths, tool_identity,
                 quiescence=None):
        self.home, self._entry, self._identity = home, original, identity
        self._password, self._paths, self._tool_identity = password, paths, tool_identity
        self._checkpoint_claimed = False
        self._reopen_claimed = False
        self._reopen_input_claimed = False
        self._quiescence = quiescence

    def __repr__(self):
        return '<closed isolated hosted wallet>'

    def closed(self):
        return (type(self._entry.poll()) is int and self._entry.poll() == 0
                and self._identity is not None
                and directory_identity(self.home.lstat()) == self._identity)

    def measured_bytes(self):
        need(self.closed(), 'CLOSE_UNCONFIRMED')
        return sample_workspace(self._paths,
            expected_profile=self._tool_identity)

    def claim_checkpoint(self):
        need(not self._checkpoint_claimed and self.closed() and self.quiescent(),
             'CLOSE_UNCONFIRMED')
        self._checkpoint_claimed = True

    def quiescent(self):
        try:
            return (isinstance(self._quiescence, _QuiescenceHandoff)
                    and self._quiescence.closed_for(self._entry))
        except (Exception, KeyboardInterrupt):
            return False

    def restoration_origin(self):
        need(self.closed() and self.quiescent()
             and isinstance(self._quiescence, _QuiescenceHandoff), 'CLOSE_UNCONFIRMED')
        return self._quiescence.origin_for(self._entry, self.home)

    def claim_reopen(self):
        need(self._checkpoint_claimed and not self._reopen_claimed,
             'CLOSE_UNCONFIRMED')
        self.restoration_origin()
        self._reopen_claimed = True

    def reopen_input(self, home):
        need(self._reopen_claimed and not self._reopen_input_claimed,
             'CLOSE_UNCONFIRMED')
        self._reopen_input_claimed = True
        origin = self.restoration_origin()
        wallet, _ = origin.copied_paths(str(home))
        need(type(self._password) is str and 0 < len(self._password) <= 512,
             'INPUT_REFUSED')
        return dict(password=self._password, originalProfile=origin.profile,
            wallet=wallet, members=list(origin.members), hash=origin.send_hash)

    def copied_home_bytes(self, home):
        need(self.closed() and home.parent == self.home.parent and home != self.home
             and re.fullmatch('ci-wallet-[a-f0-9]{24}', home.name), 'PROFILE_REFUSED')
        receipt = {}
        sample_workspace((home, *self._paths[1:]), receipt=receipt,
            expected_profile=self._tool_identity)
        return receipt['by_role']['wallet_profile']


def run(repo, parent, runtime, lab_root, observation, revalidate, *, retain_closed=None):
    report = dict(schema=2, scope='owned_chain321_wallet_tour', success=False,
        wallet_qualified=False, seed_admitted=False, visual_matches=0,
        checks=dict.fromkeys(CURRENT_CHECKS, False), errors=[], captures=[], tour=None,
        address_selection=None, lab_send=None, quiescence=None,
        forced_cleanup=False, required_actor_forced_cleanup=False,
        auxiliary_cleanup=None, phase='admission', min_free_bytes=FIXTURE_FLOOR,
        workspace_cap_bytes=WORK_CAP,
        storage=dict(samples=0, peak_logical_bytes=0, minimum_free_bytes=None,
                     last_sample=None, refusal=None),
        storage_scope='isolated_hosted_regression_fixture_cooperative_samples',
        cleanup='runner_lifecycle_not_qualified')
    original = lines = job = output = transport = None
    token = password = wallet_identity = None
    quiescence = None
    close_attempted = False
    try:
        parent, source = debug.entry.require_ci(parent, None, platform=os.name)
        need(parent.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
             and parent.get('SYRIUS_HOSTED_RUNNER') == 'github-hosted'
             and parent.get('SYRIUS_LAB_NODE_SOURCE') == 'lab-fix'
             and parent.get('SYRIUS_NATIVE_STACK_DIAGNOSTIC') == 'true', 'ENVIRONMENT_REFUSED')
        report['checks']['environment'] = True
        debug.bounded.verify_source(repo, source, parent)
        tree = debug.entry.source_tree(repo, parent)
        report.update(source_sha=source, source_tree=tree,
            run_id=parent['GITHUB_RUN_ID'], run_attempt=parent['GITHUB_RUN_ATTEMPT'])
        report['checks']['source'] = True
        root = debug.entry.private_root(repo)
        output = root / 'ci-wallet-tour'
        output.mkdir(mode=0o700)
        free = shutil.disk_usage(repo).free
        report['storage']['minimum_free_bytes'] = free
        if free < FIXTURE_FLOOR + WORK_CAP:
            report['storage']['refusal'] = 'admission_free_space'
            raise Refused('STORAGE_REFUSED')
        debug.bounded.check_no_existing(repo, parent)
        name = 'ci-wallet-' + secrets.token_hex(12)
        home, app = root / name, root / 'app'
        native_build = repo / 'build/windows/x64'
        need(not any(path.exists() or path.is_symlink() for path in (home, app, native_build)),
             'PROFILE_REFUSED')
        report['checks']['unused_destinations'] = True
        tool_profile = debug.entry.new_profile(repo)
        profile_identity = directory_identity(tool_profile.lstat())
        need(profile_identity is not None, 'PROFILE_REFUSED')
        env = debug.profile_environment(parent, tool_profile, 1, secrets.token_hex(16))
        env.update(SYRIUS_CI_WALLET_TOUR='true', SYRIUS_CI_WALLET_INSTANCE=name)
        dart, _ = debug.sdk(parent)
        job = debug.WindowsJob()
        original = subprocess.Popen([str(dart), '--disable-dart-dev',
            '--packages=' + str(repo / '.dart_tool/package_config.json'),
            'harness/bin/ci_wallet_tour.dart'], cwd=repo, env=env, shell=False,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
        job.assign(original)
        report['checks']['job_owned'] = True
        lines = debug.Lines(original.stdout)
        deadline, next_sample = time.monotonic() + 900, 0.0
        used = set()

        def write(data):
            need(original.poll() is None and len(data) <= 4096, 'INPUT_REFUSED')
            original.stdin.write(data)
            original.stdin.flush()

        def wait(marker, seconds=None):
            nonlocal next_sample
            limit = deadline if seconds is None else min(deadline, time.monotonic() + seconds)
            while True:
                runtime.healthy()
                now = time.monotonic()
                need(now < limit, 'TOTAL_DEADLINE')
                if now >= next_sample:
                    storage = report['storage']
                    sample = {}
                    storage['last_sample'] = sample
                    storage['samples'] += 1
                    try:
                        sample_workspace((home, app, native_build, tool_profile), receipt=sample,
                                         expected_profile=profile_identity)
                    finally:
                        storage['peak_logical_bytes'] = max(storage['peak_logical_bytes'],
                                                           sample.get('logical_bytes', 0))
                        if sample.get('status') == 'REFUSED':
                            storage['refusal'] = sample['reason']
                    free = shutil.disk_usage(repo).free
                    storage['minimum_free_bytes'] = min(storage['minimum_free_bytes'], free)
                    if free < FIXTURE_FLOOR:
                        storage['refusal'] = 'runtime_free_space'
                        raise Refused('STORAGE_REFUSED')
                    next_sample = now + 5
                raw = lines.take(.1)
                if raw is None:
                    need(original.poll() is None or not lines.complete, 'ENTRY_FAILED')
                    continue
                line = raw.rstrip(b'\r\n')
                if line.startswith(b'CI_WALLET_STAGE:'):
                    stage = line.partition(b':')[2]
                    need(stage in (b'gate', b'build', b'start') and line not in used, 'ENTRY_REFUSED')
                    used.add(line)
                    report['entry_stage'] = stage.decode('ascii')
                    if line == marker:
                        return
                elif line.startswith(b'SYRIUS_LAB_ADDRESS:'):
                    need('address' not in used and 'tour' not in used
                         and marker == b'CI_WALLET_DONE', 'ENTRY_REFUSED')
                    used.add('address')
                    report['address_selection'] = address_selection_receipt(
                        json.loads(line.partition(b':')[2]))
                elif line.startswith(b'SYRIUS_LAB_SEND:'):
                    need('address' in used and 'send' not in used
                         and 'tour' not in used and marker == b'CI_WALLET_DONE',
                         'ENTRY_REFUSED')
                    used.add('send')
                    report['lab_send'] = lab_send_receipt(
                        json.loads(line.partition(b':')[2]))
                elif line.startswith(b'SYRIUS_WALLET_TOUR:'):
                    need('tour' not in used and marker == b'CI_WALLET_DONE', 'TOUR_REFUSED')
                    used.add('tour')
                    report['tour'] = tour_receipt(json.loads(line.partition(b':')[2]))
                elif line.startswith(b'CI_WALLET_ERROR:'):
                    failure = entry_failure(json.loads(line.partition(b':')[2]))
                    report['entry_failure'] = failure
                    raise Refused('ENTRY_FAILED')
                elif line in (b'CI_WALLET_READY', b'CI_WALLET_DONE', b'CI_WALLET_ERROR'):
                    need(line == marker and line not in used, 'ENTRY_FAILED')
                    used.add(line)
                    return

        report['phase'] = 'build_and_start'
        write(b'START\n')
        wait(b'CI_WALLET_STAGE:gate', seconds=30)
        report['checks']['entry_gate'] = True
        wait(b'CI_WALLET_READY')
        report['checks']['entry_ready'] = True
        instance = home / 'instance.json'
        debug.bounded.plain(home)
        info = debug.bounded.plain(instance)
        need(0 < info.st_size <= 4096, 'PROFILE_REFUSED')
        private = json.loads(instance.read_bytes())
        pid, port, token = private.get('pid'), private.get('port'), private.get('token')
        need(type(pid) is int and 0 < pid < 2**32 and type(port) is int and 1024 <= port <= 65535
             and type(token) is str and re.fullmatch('[0-9a-f]{32}', token)
             and private.get('mode') == 'release' and private.get('harnessMode') == 'wallet'
             and private.get('presentationScreen') is None, 'ENTRY_REFUSED')
        job.bind_application(pid, app / 'release/syrius.exe')
        transport = debug.bounded.LoopbackTransport(port, 32768)
        ping = transport.exchange(dict(cmd='ping'), token, 5)
        body = json.loads(ping.body)
        need(ping.status == 200 and body.get('ok') is True and body.get('booted') is True
             and type(body.get('pid')) is int and body['pid'] == pid
             and body.get('harnessMode') == 'wallet', 'ENTRY_REFUSED')
        report['checks']['application_owned'] = True
        wallet_identity = directory_identity(home.lstat())
        need(wallet_identity is not None, 'PROFILE_REFUSED')
        report['phase'] = 'lab_revalidation'
        runtime.healthy()
        current = revalidate()
        need(current['chain'] == observation['chain'] == 321
             and current['genesis_hash'] == observation['genesis_hash']
             and current['last_height'] >= observation['last_height']
             and current['cross_transport_hash_equal'] is observation['cross_transport_hash_equal'] is True,
             'LAB_REFUSED')
        report['checks']['lab_revalidated'] = True
        fixture = public_fixture((repo / 'tools/devnet/lab/README.md').read_text(encoding='utf-8'))
        report['phase'] = 'onboarding_and_tour'
        # Reserve before the single private-input write; no retry is admitted.
        report['input_attempted'] = True
        password = secrets.token_hex(16) + 'A!1'
        write((json.dumps(dict(chain='321', node='ws://127.0.0.1:45998',
            mnemonic=fixture, password=password)) + '\n').encode())
        report['checks']['input_released'] = True
        wait(b'CI_WALLET_DONE')
        address_selection_receipt(report['address_selection'])
        lab_send_receipt(report['lab_send'])
        need(report['tour'] is not None and tour_complete(report['tour']), 'TOUR_REFUSED')
        report['checks']['tour_complete'] = True
        for page in PAGES:
            path = home / 'tour' / (page + '.png')
            info = debug.bounded.plain(path)
            need(0 < info.st_size <= debug.entry.MAX_PNG, 'CAPTURE_REFUSED')
            raw = path.read_bytes()
            debug.entry.png_bytes(base64.b64encode(raw).decode('ascii'))
            report['captures'].append(dict(page=page, bytes=len(raw),
                sha256=hashlib.sha256(raw).hexdigest(), width=1280, height=780))
        report['checks']['captures'] = True
        report['phase'] = 'publication_quiescence'
        runtime.healthy()
        need(original.poll() is None, 'ENTRY_FAILED')
        reply = transport.exchange(dict(cmd='lab-quiesce', profile=name), token, 30)
        value = json.loads(reply.body)
        need(reply.status == 200 and type(value) is dict and set(value) == {'ok', 'receipt', 'origin'}
             and value['ok'] is True, 'QUIESCENCE_REFUSED')
        report['quiescence'] = quiescence_receipt(value['receipt'])
        try:
            origin = wallet_restore_origin.parse(value['origin'], str(home))
        except wallet_restore_origin.Refused:
            raise Refused('QUIESCENCE_REFUSED') from None
        quiescence = _QuiescenceHandoff(original, report['quiescence'], origin)
        runtime.healthy()
        report['checks']['quiescence'] = True
        report['phase'] = 'ordinary_close'
        close_attempted = True
        debug.request_close(transport, token)
        report['checks']['close_ack'] = True
        report['application_exit'] = job.application_exit()
        need(report['application_exit'] == 0, 'CLOSE_UNCONFIRMED')
        report['checks']['application_exit'] = True
        write(b'FINISH\n')
        need(original.wait(timeout=15) == 0, 'ENTRY_FAILED')
        report['checks']['entry_exit'] = True
        need(lines.finish(), 'OUTPUT_REFUSED')
        report['checks']['output_complete'] = True
        debug.bounded.verify_source(repo, source, parent)
        need(debug.entry.source_tree(repo, parent) == tree, 'SOURCE_REFUSED')
        report['checks']['source_unchanged'] = True
        report['phase'] = 'auxiliary_cleanup'
        report['auxiliary_cleanup'] = job.finish_known_helpers(
            dart, lambda: debug.compiler_telemetry_image(repo))
        report['forced_cleanup'] = report['auxiliary_cleanup']['forced']
        need(debug.helper_cleanup_complete(report['auxiliary_cleanup']),
             report['auxiliary_cleanup']['code'] or 'HELPER_CLOSE_UNCONFIRMED')
        report['checks']['auxiliary_cleanup'] = True
        report['phase'] = 'complete'
    except (Exception, KeyboardInterrupt) as error:
        code = getattr(error, 'code', None) or str(error)
        report['errors'].append(code if code in CODES else 'INTERNAL_ERROR')
    finally:
        if job is not None:
            if job.application is not None and not close_attempted:
                close_attempted = True
                try:
                    debug.request_close(transport, token)
                    report['cleanup_application_exit'] = job.application_exit()
                except Exception:
                    report['errors'].append('CLOSE_UNCONFIRMED')
            report['owned_job_images_before_close'] = job.remaining_images()
            job.close()
            report['owned_job_active_at_close'] = job.active_at_close
            report['forced_cleanup'] |= job.forced
            report['required_actor_forced_cleanup'] |= job.forced
        if original is not None:
            if original.poll() is None:
                report['required_actor_forced_cleanup'] = report['forced_cleanup'] = True
                original.kill()
            try:
                report['entry_exit'] = original.wait(timeout=10)
            except Exception:
                report['entry_exit'] = None
                report['errors'].append('CLOSE_UNCONFIRMED')
        if lines is not None:
            lines.finish()
            report['entry_output'] = lines.public()
        report['success'] = completed(report)
        if output is not None:
            with (output / 'manifest.json').open('x', encoding='ascii') as stream:
                json.dump(report, stream, sort_keys=True, separators=(',', ':'))
                stream.write('\n')
        # Capture digests are in the explicit manifest; keep annotations compact.
        public = {key: value for key, value in report.items() if key not in ('captures', 'tour')}
        public['captured_pages'] = len(report['captures'])
        public['visited_pages'] = 0 if report['tour'] is None else len(report['tour']['visited'])
        text = json.dumps(public, sort_keys=True, separators=(',', ':'))
        print(text)
        if len(text.encode()) <= 3800:
            print('::notice title=Windows wallet tour outcome::' + text)
    if retain_closed is not None and report['success']:
        # This callback is never reconstructed from the public report or disk.
        # The password stays only in this controller's owned runtime memory.
        need(callable(retain_closed) and password is not None, 'INPUT_REFUSED')
        handoff = _ClosedWallet(home, original, wallet_identity, password,
            (home, app, native_build, tool_profile), profile_identity, quiescence)
        need(handoff.closed() and handoff.quiescent(), 'CLOSE_UNCONFIRMED')
        retain_closed(handoff)
    return report
