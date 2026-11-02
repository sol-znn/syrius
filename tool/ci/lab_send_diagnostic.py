"""Closed original-send diagnostic labels; no wallet or runtime authority."""

PHASES = frozenset((
    'admission',
    'profile',
    'profile_owner',
    'profile_apis',
    'profile_transports',
    'profile_paths',
    'profile_members',
    'profile_layout',
    'profile_wallet',
    'profile_terms',
    'journal',
    'transfer',
    'form',
    'transport',
    'sender',
    'token',
    'recipient',
    'amount',
    'review_open',
    'review',
    'preflight',
    'accept',
    'confirmation',
    'receipt',
))
REASONS = frozenset((
    'advancing-momentum-required',
    'ambiguous-original-publication',
    'earlier-original-unresolved',
    'earlier-seed-attempt-held',
    'exact-chain-321-lab-required',
    'exact-confirmation-or-effect-pending',
    'exact-confirmation-pending',
    'exact-original-lab-transports-required',
    'exact-original-receipt-mismatch',
    'explicit-lab-origins-required',
    'external-lab-counterparty-required',
    'fixed-original-lab-send-required',
    'funded-index-one-required',
    'funded-selected-index-required',
    'invalid-lab-frontier',
    'invalid-original-hash',
    'isolated-unlocked-profile-required',
    'lab-endpoints-disagree',
    'lab-frontier-regressed',
    'lab-http-frontier-incomplete',
    'lab-http-response-refused',
    'lab-http-response-too-large',
    'lab-http-rpc-refused',
    'original-attempt-held',
    'original-context-changed',
    'original-hash-changed',
    'original-lab-control-changed',
    'original-lab-control-unsettled',
    'original-lab-send-context-changed',
    'original-lab-send-transport-required',
    'original-lab-send-ui-or-read-failed',
    'original-lab-sender-choice-required',
    'original-lab-sender-choice-ambiguous',
    'original-lab-sender-choice-missing',
    'original-lab-sender-choice-unsettled',
    'original-lab-sender-form-choice-missing',
    'original-lab-sender-menu-missing',
    'original-lab-sender-menu-choice-missing',
    'original-outcome-unknown',
    'original-publication-replaced',
    'original-send-form-changed',
    'original-send-form-required',
    'original-send-review-already-captured',
    'original-send-review-changed',
    'original-send-review-center-changed',
    'original-send-review-button-changed',
    'original-send-review-dialog-changed',
    'original-send-review-intent-changed',
    'original-send-review-draft-changed',
    'original-send-review-required',
    'original-transfer-attempt-held',
    'original-transfer-review-mismatch',
    'original-transfer-review-required',
    'original-transfer-witness-required',
    'original-ui-control-changed',
    'owned-isolated-profile-required',
    'receipt-shape-refused',
    'recipe-prerequisite-missing',
    'seed-journal-held',
    'unknown-recipe',
    'unlocked-wallet-required',
))


ORIGINAL_STATES = frozenset((
    'not_started',
    'pending',
    'sender_failed',
    'witness_invalid',
    'owner_revoked',
    'detached',
    'result_observed',
))


DISPLAY_ERRORS = frozenset(('node_not_synced', 'generic_failure', 'other'))


CONFIRMATION_STATES = frozenset(('absent', 'unconfirmed'))


FRONTIER_NUMBERS = frozenset((
    'ws_first_height', 'ws_last_height', 'ws_first_timestamp', 'ws_last_timestamp',
    'http_first_height', 'http_last_height', 'http_first_timestamp', 'http_last_timestamp',
))


def _frontier(value):
    if (type(value) is not dict or set(value) != FRONTIER_NUMBERS | {
            'polls', 'ws_hash_changed', 'http_hash_changed'}
            or type(value['polls']) is not int or value['polls'] != 6
            or any(type(value[key]) is not int or not 0 < value[key] <= 9007199254740991
                   for key in FRONTIER_NUMBERS)
            or any(type(value[key]) is not bool for key in (
                'ws_hash_changed', 'http_hash_changed'))):
        return False
    advancing = []
    for endpoint in ('ws', 'http'):
        first_height, last_height = (value[endpoint + '_' + label]
                                     for label in ('first_height', 'last_height'))
        first_time, last_time = (value[endpoint + '_' + label]
                                 for label in ('first_timestamp', 'last_timestamp'))
        changed = value[endpoint + '_hash_changed']
        if last_height < first_height or last_height == first_height and (
                last_time != first_time or changed):
            return False
        advancing.append(last_height > first_height and last_time > first_time and changed)
    return not all(advancing)


def _confirmation(value):
    if (type(value) is not dict or set(value) != {
            'polls', 'absent', 'unconfirmed', 'last'}
            or type(value['polls']) is not int or value['polls'] != 18
            or any(type(value[key]) is not int or not 0 <= value[key] <= 18
                   for key in ('absent', 'unconfirmed'))
            or type(value['last']) is not str
            or value['last'] not in CONFIRMATION_STATES):
        return False
    return (value['absent'] + value['unconfirmed'] == 18
            and value[value['last']] > 0)


def valid(value):
    if (type(value) is not dict or set(value) not in (
            {'phase', 'reason'}, {'phase', 'reason', 'original'},
            {'phase', 'reason', 'original', 'display_error'},
            {'phase', 'reason', 'frontier'},
            {'phase', 'reason', 'confirmation'})
            or type(value['phase']) is not str or type(value['reason']) is not str
            or value['phase'] not in PHASES or value['reason'] not in REASONS):
        return False
    if 'confirmation' in value:
        return (value['phase'] == 'confirmation'
                and value['reason'] == 'exact-confirmation-pending'
                and _confirmation(value['confirmation']))
    if 'frontier' in value:
        return (value['phase'] == 'preflight'
                and value['reason'] == 'advancing-momentum-required'
                and _frontier(value['frontier']))
    if 'display_error' in value and (
            value['original'] != 'sender_failed'
            or type(value['display_error']) is not str
            or value['display_error'] not in DISPLAY_ERRORS):
        return False
    return ('original' not in value or (
        value['phase'] == 'confirmation'
        and value['reason'] == 'original-outcome-unknown'
        and type(value['original']) is str
        and value['original'] in ORIGINAL_STATES))
