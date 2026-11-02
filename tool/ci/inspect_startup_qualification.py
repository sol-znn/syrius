"""Validate two retained startup reports without starting another process."""

import base64
import io
import json
from pathlib import Path
import re
import stat
import zipfile

from . import inspect_chain321 as archive
from . import windows_startup_probe as startup


MAX_ARCHIVE = 256 * 1024
PRODUCERS = ('windows_startup_probe.py', 'windows_presentation_smoke.py',
             'windows_entry_capture_smoke.py', 'windows_wallet_tour.py')
JOB_NAME = 'Observe original Windows Release startup'


def startup_archive(raw, expected_sha, expected_size, head, tree, run_id, *,
                    natural_only=False, prior_manifest_sha256=None,
                    runner_sha256=None, payload_sha256=None):
    """Consume one bounded manifest and keep its original positive or negative."""
    archive.need(type(raw) is bytes and type(expected_size) is int
        and 0 < len(raw) == expected_size <= MAX_ARCHIVE
        and type(expected_sha) is str
        and re.fullmatch('[a-f0-9]{64}', expected_sha) is not None
        and archive.sha(raw) == expected_sha)
    with zipfile.ZipFile(io.BytesIO(raw)) as zipped:
        members = zipped.infolist()
        archive.need(len(members) == 1)
        member = members[0]
        archive.need(member.filename == 'manifest.json' and not member.is_dir()
            and not member.flag_bits & 1
            and member.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
            and stat.S_IFMT(member.external_attr >> 16) in (0, stat.S_IFREG)
            and 0 < member.file_size <= startup.MAX_MANIFEST)
        with zipped.open(member) as stream:
            manifest = stream.read(startup.MAX_MANIFEST + 1)
        archive.need(len(manifest) == member.file_size)
    report = json.loads(manifest)
    archive.need(type(report) is dict)
    if not natural_only:
        runner_sha256 = report.get('runner_sha256')
        payload_sha256 = report.get('payload_sha256')
    projected = startup.observation_projection(
        report, head=head, tree=tree, run_id=str(run_id), run_attempt='1',
        runner_sha256=runner_sha256, payload_sha256=payload_sha256,
        natural_only=natural_only, prior_manifest_sha256=prior_manifest_sha256,
    )
    archive.need(projected is not None)
    samples = projected['samples']
    summary = dict(
        schema=1,
        scope=('retained_natural_release_startup_observation' if natural_only
               else 'retained_release_startup_observation'),
        inspection_only=True, runtime_started=False, wallet_qualified=False,
        chain_qualified=False, source_head=head, source_tree=tree,
        source_run_id=run_id, source_attempt=1,
        archive_sha256=archive.sha(raw), archive_bytes=len(raw),
        manifest_sha256=archive.sha(manifest), manifest_bytes=len(manifest),
        artifact_reported_success=projected['success'],
        checks=projected['checks'], sample_count=len(samples),
        samples_valid=projected['samples_valid'],
        first_sample=samples[0] if samples else None,
        last_sample=samples[-1] if samples else None,
        handoff=projected['handoff'], key_attempts=projected['key_attempts'],
        startup_deadline_seconds=projected['startup_deadline_seconds'],
        startup_deadline_expired=projected['startup_deadline_expired'],
        exit_code=projected['exit_code'], exit_observed=projected['exit_observed'],
        forced_kill=projected['forced_kill'], output_complete=projected['output_complete'],
        output_overflow=projected['output_overflow'],
        original_error_codes=projected['error_codes'],
        runner_sha256=projected['runner_sha256'],
        payload_sha256=projected['payload_sha256'],
        original_skip_qualified=projected['original_skip_qualified'],
        original_natural_qualified=projected.get('original_natural_qualified', False),
        visual_matches=0, financial_actions_requested=0, node_cluster_started=False,
    )
    if natural_only:
        summary['prior_manifest_sha256'] = projected['prior_manifest_sha256']
    return summary


def inspect_run(client, *, head, tree, run_id, job):
    """Read the exact producer sources, job and two original finite archives."""
    archive.need(job['name'] == JOB_NAME and job['head_sha'] == head
        and job['run_id'] == run_id and job['status'] == 'completed'
        and job['conclusion'] in ('success', 'failure'))
    for name in PRODUCERS:
        selected = client.json('/contents/tool/ci/' + name + '?ref=' + head)
        archive.need(selected['type'] == 'file' and selected['encoding'] == 'base64'
            and selected['path'] == 'tool/ci/' + name)
        data = base64.b64decode(selected['content'].replace('\n', ''), validate=True)
        archive.need(len(data) == selected['size']
            and data == Path(__file__).with_name(name).read_bytes())
    listing = client.json('/actions/runs/' + str(run_id) + '/artifacts?per_page=20')
    archive.need(listing['total_count'] == len(listing['artifacts']) <= 20)
    summaries = []
    for natural, prefix in ((False, 'windows-startup-probe-'),
                            (True, 'windows-natural-startup-probe-')):
        name = prefix + head + '-' + str(run_id) + '-1'
        selected = [item for item in listing['artifacts'] if item['name'] == name]
        archive.need(len(selected) == 1)
        item = selected[0]
        archive.need(item['expired'] is False and item['workflow_run']['id'] == run_id
            and item['workflow_run']['head_sha'] == head
            and type(item['id']) is int and item['id'] > 0
            and type(item['size_in_bytes']) is int
            and 0 < item['size_in_bytes'] <= MAX_ARCHIVE
            and re.fullmatch('sha256:[a-f0-9]{64}', item.get('digest', '')) is not None)
        location = client.read(archive.API + '/actions/artifacts/' + str(item['id'])
                               + '/zip', redirect=True)
        raw = client.read(location, authenticated=False, cap=MAX_ARCHIVE)
        prior = summaries[0] if summaries else {}
        if natural:
            archive.need(prior['artifact_reported_success'])
        summary = startup_archive(
            raw, item['digest'][7:], item['size_in_bytes'], head, tree, run_id,
            natural_only=natural, prior_manifest_sha256=prior.get('manifest_sha256'),
            runner_sha256=prior.get('runner_sha256'),
            payload_sha256=prior.get('payload_sha256'),
        )
        archive.need(job['conclusion'] != 'success'
                     or summary['artifact_reported_success'])
        summary.update(original_job_id=job['id'],
            original_job_conclusion=job['conclusion'], producer_sources_equal=True)
        summaries.append(summary)
    return summaries
