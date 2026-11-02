"""Finite asset-helper phases; output text and deployment paths stay private."""

PREFIX = b'SYRIUS_LAB_ASSET_PHASE:'
PHASES = ('STARTED', 'GENESIS_READ_STARTED', 'GENESIS_WRITTEN',
    'PILLAR_COPY_STARTED', 'PILLAR_CONFIG_WRITTEN',
    'PILLAR2_COPY_STARTED', 'PILLAR2_CONFIG_WRITTEN',
    'PILLAR3_COPY_STARTED', 'PILLAR3_CONFIG_WRITTEN',
    'OBSERVER_COPY_STARTED', 'OBSERVER_CONFIG_WRITTEN',
    'RPC_COPY_STARTED', 'RPC_CONFIG_WRITTEN', 'COMPLETE')


def validate(value):
    def need(condition):
        if not condition:
            raise ValueError('ASSET_PROGRESS_REFUSED')
    need(type(value) is dict and set(value) == {'status', 'phase', 'events', 'script_complete'})
    need(value['status'] in ('OBSERVED', 'NOT_OBSERVED', 'REFUSED')
         and type(value['events']) is int and 0 <= value['events'] <= len(PHASES)
         and type(value['script_complete']) is bool)
    if value['status'] == 'OBSERVED':
        need(value['events'] > 0 and value['phase'] == PHASES[value['events'] - 1]
             and value['script_complete'] is (value['events'] == len(PHASES)))
    else:
        need(value['phase'] is None and value['events'] == 0
             and value['script_complete'] is False)
    return dict(value)


def project(raw):
    refused = dict(status='REFUSED', phase=None, events=0, script_complete=False)
    if type(raw) is not bytes or len(raw) > 8192:
        return refused
    phases = []
    for line in raw.splitlines():
        if not line.startswith(PREFIX):
            continue
        index = len(phases)
        if index >= len(PHASES) or line != PREFIX + PHASES[index].encode('ascii'):
            return refused
        phases.append(PHASES[index])
    return dict(status='OBSERVED' if phases else 'NOT_OBSERVED',
        phase=phases[-1] if phases else None, events=len(phases),
        script_complete=len(phases) == len(PHASES))
