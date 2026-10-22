"""Expand CPU partitions on the existing RDS04 job, without changing science."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from datetime import datetime, timezone

ROOT = Path('/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001')
JOB = '246090'


def run(*args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=35, check=True)
    return result.stdout.strip()


def fields(raw):
    return dict(re.findall(r'\b([A-Za-z][A-Za-z0-9:/]*)=([^ ]*)', raw))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(partitions):
    allowed = {'hcpu48', 'hcpu48y', 'hgpu2p'}
    parts = partitions.split(',')
    if 'hcpu48' not in parts or len(set(parts)) != len(parts) or not set(parts) <= allowed:
        raise ValueError('Require an explicit unique approved CPU-execution partition list retaining hcpu48')
    stage = ROOT / 'resource_compatibility_v003'
    stage.mkdir(exist_ok=True)
    result_path = stage / 'apply_result.json'
    if result_path.exists():
        raise RuntimeError('Adaptation already has a receipt; inspect it instead of replaying')
    raw = run('scontrol', '-o', 'show', 'job', JOB)
    before = fields(raw)
    if (ROOT / 'job_id.txt').read_text().strip() != JOB or before.get('JobName') != 'id25_rds04_261021':
        raise ValueError('Wrong experiment job identity')
    if before.get('UserId', '').split('(')[0] != 'sunyiq':
        raise ValueError('Unexpected owner')
    if before.get('JobState') != 'PENDING':
        result_path.write_text(json.dumps({'state': 'NO_CHANGE_JOB_NO_LONGER_PENDING',
            'job_id': JOB, 'job': before}, indent=2))
        print(result_path.read_text())
        return
    for part in parts:
        state = fields(run('scontrol', '-o', 'show', 'partition', part))
        if state.get('State') != 'UP':
            raise ValueError('Candidate partition is not UP: ' + part)
    manifest = json.loads((ROOT / 'source_manifest.json').read_text())
    protected = ['config.json', 'source_manifest.json', 'submissions.tsv', 'job_id.txt'] + list(manifest['code_sha256'])
    hashes = {name: digest(ROOT / name) for name in protected}
    script = ROOT / 'hpc/train.slurm'
    original = script.read_bytes()
    (stage / 'original_train.slurm').write_bytes(original)
    (stage / 'job_before.txt').write_text(raw + '\n')
    run('scontrol', 'update', 'JobId=' + JOB, 'Partition=' + partitions)
    after_raw = run('scontrol', '-o', 'show', 'job', JOB)
    after = fields(after_raw)
    (stage / 'job_after.txt').write_text(after_raw + '\n')
    for key in ['JobId', 'SubmitTime', 'TimeLimit', 'NumTasks', 'CPUs/Task', 'Command', 'WorkDir']:
        if before.get(key) != after.get(key):
            raise ValueError('Unexpected job setting change: ' + key)
    if set(after.get('Partition', '').split(',')) != set(parts) and after.get('JobState') == 'PENDING':
        raise ValueError('Pending job did not retain the requested candidate partition list')
    if {name: digest(ROOT / name) for name in protected} != hashes:
        raise ValueError('Protected science files or submission ledger changed')
    # sbatch already captured the original script body; this header only guides a technical resume.
    new_script = re.sub(br'(?m)^#SBATCH -p [^\r\n]+', b'#SBATCH -p ' + partitions.encode(), original)
    pending = script.with_suffix('.slurm.resource_pending')
    pending.write_bytes(new_script)
    pending.replace(script)
    result = {'state': 'CPU_EXECUTION_PARTITIONS_EXPANDED', 'job_id': JOB, 'before': before, 'after': after,
              'requested_partitions': parts, 'science_code_fingerprint': manifest['code_fingerprint'],
              'protected_sha256': hashes, 'slurm_script_before_sha256': hashlib.sha256(original).hexdigest(),
              'slurm_script_after_sha256': digest(script), 'new_submissions': 0, 'cancellations': 0,
              'preflights_repeated': 0, 'other_jobs_modified': [], 'applied_at': datetime.now(timezone.utc).isoformat()}
    result_path.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--partitions', required=True)
    main(parser.parse_args().partitions)
