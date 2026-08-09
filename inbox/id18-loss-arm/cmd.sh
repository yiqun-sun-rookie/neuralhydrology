#!/bin/bash
# ID18 seq=7: submit the approved E04 one-basin smoke job.
set -eo pipefail

TARGET=/data1/home/sunyiq/id18_e04_20260809
RESULT=$TARGET/results/18_lstm_fair_531/E04_daymet_post2008_objective_confirmation_482
RECORD=$RESULT/protocol/smoke_submission.json

cd "$TARGET"
test -f src/loss_mechanism_531/hpc/e04_smoke.slurm
test -f "$RESULT/protocol/preflight.json"
test ! -e "$RECORD"

SUBMITTED_AT=$(date -Is)
RAW_JOB_ID=$(sbatch --parsable src/loss_mechanism_531/hpc/e04_smoke.slurm)
JOB_ID=${RAW_JOB_ID%%;*}
case "$JOB_ID" in
    ''|*[!0-9]*)
        echo "Invalid sbatch job id: $RAW_JOB_ID" >&2
        exit 1
        ;;
esac

export JOB_ID RAW_JOB_ID SUBMITTED_AT RECORD
python - <<'PY'
import json
import os
import pathlib

record = pathlib.Path(os.environ['RECORD'])
payload = {
    'job_id': int(os.environ['JOB_ID']),
    'raw_job_id': os.environ['RAW_JOB_ID'],
    'submitted_at': os.environ['SUBMITTED_AT'],
    'script': 'src/loss_mechanism_531/hpc/e04_smoke.slurm',
    'scope': 'one-basin technical smoke only',
}
with record.open('x', encoding='utf-8') as handle:
    json.dump(payload, handle, indent=2)
    handle.write('\n')
print(json.dumps(payload, indent=2))
PY

echo "=== SQUEUE ==="
squeue -j "$JOB_ID" -o "%.10i %.24j %.10P %.9T %.11M %.6D %R" 2>&1
echo "E04_SMOKE_SUBMITTED job_id=$JOB_ID"
