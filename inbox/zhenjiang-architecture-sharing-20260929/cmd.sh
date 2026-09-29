#!/bin/bash
set -euo pipefail
ROOT=/data1/home/sunyiq/zhenjiang_architecture_sharing_20260929_001
JOB=231096
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZJ_ARCH_STATUS'
import json
from pathlib import Path

root = Path('/data1/home/sunyiq/zhenjiang_architecture_sharing_20260929_001')
submission = json.loads((root / 'submission/submitted.json').read_bytes())
attempt = json.loads((root / 'submission/attempt.json').read_bytes())
scheduler = json.loads((root / 'submission/scheduler_reply.json').read_bytes())
if (submission['status'] != 'SUBMITTED_ONCE' or submission['job_id'] != '231096'
        or attempt['planned_tasks'] != 114
        or attempt['maximum_simultaneous_gpu_tasks'] != 2
        or scheduler['returncode'] != 0
        or scheduler['stdout'].count('Submitted batch job 231096') != 1):
    raise SystemExit('unique submission receipt differs')
runs = root / 'runs'
run_dirs = sorted(path for path in runs.iterdir() if path.is_dir()) if runs.is_dir() else []
complete = sum((path / 'complete.json').is_file() for path in run_dirs)
failed = sum((path / 'failure.json').is_file() for path in run_dirs)
epoch_records = sum(len(list(path.glob('epoch_*.json'))) for path in run_dirs)
print(json.dumps({'submission': submission, 'scheduler_reply': scheduler,
                  'started_run_directories': len(run_dirs),
                  'complete_runs': complete, 'failed_runs': failed,
                  'epoch_records': epoch_records}, sort_keys=True))
ZJ_ARCH_STATUS
echo '=== squeue array state ==='
squeue -r -j "$JOB" -h -o '%A|%a|%T|%M|%R|%j' | awk 'NR <= 130'
echo '=== sacct bounded state ==='
sacct -j "$JOB" --starttime 2026-09-29 --noheader --parsable2 --format=JobIDRaw,State,ExitCode,Elapsed,NodeList | awk 'NR <= 240'
