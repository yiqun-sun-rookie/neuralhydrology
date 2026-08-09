#!/bin/bash
# ID18 seq=13: submit the twelve frozen formal model jobs and one after-ok score/audit job.
set -eo pipefail

TARGET=/data1/home/sunyiq/id18_e04_20260809
RESULT=$TARGET/results/18_lstm_fair_531/E04_daymet_post2008_objective_confirmation_482
RECORD_JSONL=$RESULT/protocol/formal_submission_20260809.jsonl
RECORD_JSON=$RESULT/protocol/formal_submission_20260809.json

cd "$TARGET"
test -f src/loss_mechanism_531/hpc/e04_conceptual.slurm
test -f src/loss_mechanism_531/hpc/e04_neural.slurm
test -f src/loss_mechanism_531/hpc/e04_score.slurm
test ! -e "$RECORD_JSONL"
test ! -e "$RECORD_JSON"
if find "$RESULT/conceptual" -name completion.json -print -quit 2>/dev/null | grep -q .; then
    echo "Formal conceptual completion already exists" >&2
    exit 1
fi
if find "$RESULT/protocol/neural_completions" -name '*.json' -print -quit 2>/dev/null | grep -q .; then
    echo "Formal neural completion already exists" >&2
    exit 1
fi
test ! -e "$RESULT/analysis_confirmation_20260809"
test "$(sacct -n -X -j 202067 --format=State -P | head -1 | cut -d'|' -f1 | xargs)" = "COMPLETED"
grep -Fxq "E04_SMOKE_PASS" "$TARGET/logs/smoke-202067.out"

python - "$RECORD_JSONL" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
with path.open('x', encoding='utf-8') as handle:
    handle.write(json.dumps({
        'record_type': 'submission_start',
        'experiment_id': 'E04_daymet_post2008_objective_confirmation_482',
        'smoke_job_id': 202067,
        'scope': 'twelve frozen model jobs plus dependent score and independent audit',
    }) + '\n')
PY

ALL_JOB_IDS=()
MODEL_JOB_IDS=()
LAST_JOB_ID=

submit_job() {
    local label="$1"
    local job_name="$2"
    shift 2
    local submitted_at raw_job_id job_id arg_text
    submitted_at=$(date -Is)
    raw_job_id=$(sbatch --parsable --job-name="$job_name" "$@")
    job_id=${raw_job_id%%;*}
    case "$job_id" in
        ''|*[!0-9]*)
            echo "Invalid sbatch job id for $label: $raw_job_id" >&2
            exit 1
            ;;
    esac
    printf -v arg_text '%q ' "$@"
    python - "$RECORD_JSONL" "$label" "$job_name" "$job_id" "$raw_job_id" "$submitted_at" "$arg_text" <<'PY'
import json
import pathlib
import sys

path, label, job_name, job_id, raw_job_id, submitted_at, command_args = sys.argv[1:]
with pathlib.Path(path).open('a', encoding='utf-8') as handle:
    handle.write(json.dumps({
        'record_type': 'job',
        'label': label,
        'job_name': job_name,
        'job_id': int(job_id),
        'raw_job_id': raw_job_id,
        'submitted_at': submitted_at,
        'sbatch_args': command_args.strip(),
    }) + '\n')
PY
    echo "SUBMITTED label=$label job_id=$job_id"
    LAST_JOB_ID="$job_id"
    ALL_JOB_IDS+=("$job_id")
}

for model in gr4j xaj hbv_lite; do
    for arm in nse flow_regime_nse; do
        short_arm=nse
        if test "$arm" = flow_regime_nse; then short_arm=frnse; fi
        submit_job "conceptual:${model}:${arm}" "id18-c-${model}-${short_arm}" \
            src/loss_mechanism_531/hpc/e04_conceptual.slurm "$model" "$arm"
        MODEL_JOB_IDS+=("$LAST_JOB_ID")
    done
done

for arm in nse flow_regime_nse; do
    short_arm=nse
    if test "$arm" = flow_regime_nse; then short_arm=frnse; fi
    for seed in 100 200 300; do
        submit_job "neural:${arm}:s${seed}" "id18-lstm-${short_arm}-s${seed}" \
            src/loss_mechanism_531/hpc/e04_neural.slurm "$arm" "$seed"
        MODEL_JOB_IDS+=("$LAST_JOB_ID")
    done
done

DEPENDENCY=$(IFS=:; echo "${MODEL_JOB_IDS[*]}")
submit_job "score_and_independent_audit" "id18-e04-score" \
    "--dependency=afterok:${DEPENDENCY}" src/loss_mechanism_531/hpc/e04_score.slurm
SCORE_JOB_ID="$LAST_JOB_ID"

export RECORD_JSONL RECORD_JSON SCORE_JOB_ID DEPENDENCY
python - <<'PY'
import json
import os
import pathlib

records = [json.loads(line) for line in pathlib.Path(os.environ['RECORD_JSONL']).read_text(encoding='utf-8').splitlines()]
jobs = [record for record in records if record['record_type'] == 'job']
assert len(jobs) == 13, len(jobs)
job_ids = [job['job_id'] for job in jobs]
assert len(set(job_ids)) == 13, job_ids
payload = {
    'experiment_id': 'E04_daymet_post2008_objective_confirmation_482',
    'model_job_count': 12,
    'score_job_count': 1,
    'job_ids': job_ids,
    'model_job_ids': job_ids[:12],
    'score_job_id': int(os.environ['SCORE_JOB_ID']),
    'score_dependency': os.environ['DEPENDENCY'],
    'jobs': jobs,
}
with pathlib.Path(os.environ['RECORD_JSON']).open('x', encoding='utf-8') as handle:
    json.dump(payload, handle, indent=2)
    handle.write('\n')
print(json.dumps(payload, indent=2))
PY

JOB_LIST=$(IFS=,; echo "${ALL_JOB_IDS[*]}")
echo "=== SQUEUE ==="
squeue -j "$JOB_LIST" -o "%.10i %.28j %.10P %.9T %.11M %.6D %R" 2>&1
echo "E04_FORMAL_SUBMISSION_PASS model_jobs=12 score_jobs=1"
