"""Inspect one retained finite inventory in Actions without repeating a probe."""

import json
import math
import os
import re

from . import inspect_chain321 as archive
from . import windows_baseline as baseline


PHASE = 'environment'
OUTCOME_KEYS = {'required', 'exit_code', 'exit_observed', 'forced_kill', 'output_complete',
                'output_overflow', 'output_bytes', 'seconds', 'success', 'error_codes'}


def outcome(value):
    archive.need(type(value) is dict and set(value) == OUTCOME_KEYS)
    archive.need(all(type(value[key]) is bool for key in
        ('required', 'exit_observed', 'forced_kill', 'output_complete', 'output_overflow', 'success')))
    code = value['exit_code']
    archive.need(code is None or type(code) is int and -(2**31) <= code < 2**32)
    archive.need(type(value['output_bytes']) is int and 0 <= value['output_bytes'] <= 64 * 1024**2)
    archive.need(type(value['seconds']) in (int, float) and math.isfinite(value['seconds'])
                 and 0 <= value['seconds'] <= 5400)
    errors = value['error_codes']
    archive.need(type(errors) is list and len(errors) <= 16 and all(code in baseline.CODES for code in errors))
    complete = (value['exit_observed'] and value['output_complete'] and not value['forced_kill']
                and not value['output_overflow'] and not errors)
    archive.need(value['success'] is (complete and type(code) is int and code == 0))
    return dict(value)


def project(report, head, tree, run_id):
    archive.need(type(report) is dict and report.get('scope') == 'github_hosted_windows_inventory'
        and type(report.get('schema')) is int and report['schema'] == 1 and report.get('source_sha') == head
        and report.get('source_tree') == tree and report.get('run') == dict(id=str(run_id), attempt='1')
        and report.get('baseline_qualified') is False and report.get('wallet_qualified') is False)
    inventory = report.get('inventory')
    archive.need(type(inventory) is dict and set(inventory) == baseline.INVENTORY
                 and baseline.inventory_projection(inventory) == inventory)
    checks, errors, stages = report.get('checks'), report.get('error_codes'), report.get('stages')
    archive.need(type(checks) is dict and set(checks) == {'source', 'source_unchanged', 'inventory'}
        and all(type(value) is bool for value in checks.values())
        and type(errors) is list and len(errors) <= 16 and all(code in baseline.CODES for code in errors)
        and type(stages) is dict and set(stages) <= baseline.STAGES)
    for value in stages.values():
        outcome(value)
    archive.need(type(report.get('success')) is bool
        and report['success'] is (all(checks.values()) and not errors))
    return dict(scope='retained_windows_inventory_observation', source_head=head,
        source_tree=tree, source_run_id=run_id, source_attempt=1,
        artifact_reported_success=report['success'], original_checks=checks,
        original_error_codes=errors,
        probes={key: outcome(stages[key]) for key in
                ('inventory_windows', 'inventory_git_bash', 'inventory_pillow') if key in stages},
        unknown_fields=sorted(key for key, value in inventory.items() if value['status'] == 'unknown'),
        inspection_only=True, runtime_started=False, baseline_qualified=False, wallet_qualified=False)


def main():
    global PHASE
    try:
        parent = os.environ
        archive.need(parent.get('GITHUB_ACTIONS') == 'true'
            and parent.get('SYRIUS_HOSTED_RUNNER') == 'github-hosted'
            and parent.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
            and parent.get('GITHUB_REPOSITORY') == 'edgepillar/syrius')
        run_text, head = parent.get('INVENTORY_INSPECT_RUN', ''), parent.get('INVENTORY_INSPECT_HEAD', '')
        archive.need(re.fullmatch('[1-9][0-9]{0,19}', run_text) is not None
                     and re.fullmatch('[a-f0-9]{40}', head) is not None)
        run_id = int(run_text)
        client = archive.Client(parent.get('GH_TOKEN'))
        PHASE = 'source_metadata'
        run = client.json('/actions/runs/' + run_text)
        archive.need(run['id'] == run_id and run['head_sha'] == head and run['run_attempt'] == 1
            and run['workflow_id'] == 381413107 and run['event'] == 'workflow_dispatch'
            and run['status'] == 'completed' and run['repository']['full_name'] == 'edgepillar/syrius')
        commit = client.json('/git/commits/' + head)
        tree = commit['tree']['sha']
        archive.need(commit['sha'] == head and re.fullmatch('[a-f0-9]{40}', tree) is not None)
        PHASE = 'artifact_metadata'
        listing = client.json('/actions/runs/' + run_text + '/artifacts?per_page=20')
        archive.need(listing['total_count'] == len(listing['artifacts']) <= 20)
        name = 'windows-inventory-' + head + '-' + run_text + '-1'
        selected = [item for item in listing['artifacts'] if item['name'] == name]
        archive.need(len(selected) == 1)
        item = selected[0]
        archive.need(item['expired'] is False and item['workflow_run']['id'] == run_id
            and item['workflow_run']['head_sha'] == head
            and re.fullmatch('sha256:[a-f0-9]{64}', item.get('digest', '')) is not None)
        PHASE = 'download'
        location = client.read(archive.API + '/actions/artifacts/' + str(item['id']) + '/zip', redirect=True)
        raw = client.read(location, authenticated=False, cap=archive.MAX_ARCHIVE)
        PHASE = 'manifest'
        report, manifest_sha = archive.unpack(raw, item['digest'][7:], item['size_in_bytes'])
        summary = project(report, head, tree, run_id)
        summary.update(archive_sha256=archive.sha(raw), manifest_sha256=manifest_sha)
        encoded = json.dumps(summary, sort_keys=True, separators=(',', ':'))
        archive.need(encoded.isascii() and len(encoded.encode()) <= 3800)
        print(encoded)
        print('::notice title=Hosted inventory inspection::' + encoded)
        return 0
    except (Exception, KeyboardInterrupt):
        print(json.dumps(dict(scope='retained_windows_inventory_observation',
            inspection_success=False, code='INSPECTION_REFUSED', phase=PHASE,
            runtime_started=False, wallet_qualified=False), sort_keys=True))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
