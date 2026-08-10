#!/bin/bash
# ID29 seq=102: verify third no-pytest preclosure validation and report full-role progress; keep the unsafe manifest held.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOB=202370
OUT="$ROOT/closure_20260810/logs/N22-preclosure-check_${JOB}.out"
ERR="$ROOT/closure_20260810/logs/N22-preclosure-check_${JOB}.err"
SOURCE_RECEIPT="$ROOT/closure_20260810/provenance/numerical_gate_slurm_source_seq101_receipt.json"
JOB_RECEIPT="$ROOT/closure_20260810/provenance/preclosure_validation_seq101_job.txt"

echo "=== VALIDATION STATE ==="
squeue -h -j "$JOB" -o '%i|%T|%r|%j' || true
sacct -n -P -j "$JOB" --format=JobID,JobName,State,ExitCode,Elapsed,Start,End,NodeList | sed '/^[[:space:]]*$/d'
STATE=$(sacct -n -P -j "$JOB" --format=JobIDRaw,State | awk -F'|' -v job="$JOB" '$1 == job {print $2; exit}')
echo "validation_state=$STATE"

if [ "$STATE" = "COMPLETED" ]; then
  test -f "$OUT"
  test -f "$ERR"
  echo "=== VALIDATION STDOUT ==="
  cat "$OUT"
  echo "=== VALIDATION STDERR ==="
  cat "$ERR"
  test ! -s "$ERR"
  grep -q '"ok": true' "$OUT"
  grep -q '"tests": 64' "$OUT"
  grep -q '"unique_file_count": 97' "$OUT"
  grep -q '"file_count": 20' "$OUT"
  grep -q '"dataset_sha256": "a3cb1f81e6b2f25e2b919c0d5b315e46fe82f8ed9c9d8a4bd56671da5500a35f"' "$OUT"
  grep -q 'finished=' "$OUT"
  sha256sum "$OUT" "$ERR" "$SOURCE_RECEIPT" "$JOB_RECEIPT"
elif [ "$STATE" = "RUNNING" ] || [ "$STATE" = "PENDING" ]; then
  echo "validation_pending=1"
else
  echo "=== FAILED STDOUT ==="
  test -f "$OUT" && cat "$OUT"
  echo "=== FAILED STDERR ==="
  test -f "$ERR" && cat "$ERR"
  test -f "$OUT" && test -f "$ERR" && sha256sum "$OUT" "$ERR" "$SOURCE_RECEIPT" "$JOB_RECEIPT"
fi

echo "=== MAIN JOB STATES ==="
JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315
squeue -h -j "$JOBS" -o '%F|%T' | sort | uniq -c
sacct -n -P -j "$JOBS" --format=JobID,State,ExitCode | awk -F'|' '
  NF >= 3 && $1 !~ /\./ {
    parent = $1
    sub(/_.*/, "", parent)
    key = parent "|" $2 "|" $3
    count[key]++
  }
  END { for (key in count) print count[key] "|" key }
' | sort -t'|' -k2,2n -k3,3

echo "=== ACTIVE FAILURE STATES ==="
sacct -n -P -j "$JOBS" --format=JobID,State,ExitCode | awk -F'|' '
  $1 !~ /\./ && $2 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/ { print }
' || true

echo "=== REGISTERED FULL-ROLE ARTIFACT PROGRESS ==="
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python - <<'PY'
from collections import Counter
import json
from pathlib import Path
import sys

import pandas as pd

root = Path('/data1/home/sunyiq/nearing2022_da')
scripts = root / 'src/29_nearing2022_da_ar/scripts'
sys.path.insert(0, str(scripts))
from aggregate_registered_results import _registered_run
from prepare_evaluation_run import resolve_source_run
from verify_registered_closure import (
    EVALUATION_AGGREGATION_FILES,
    HYPERPARAMETER_AGGREGATION_FILES,
    _metrics_path,
)

registry_root = root / 'src/29_nearing2022_da_ar/registry'
training = pd.read_csv(registry_root / 'experiment_registry.csv', keep_default_na=False, dtype=str)
evaluations = pd.read_csv(registry_root / 'evaluation_registry.csv', keep_default_na=False, dtype=str)
hyper = pd.read_csv(registry_root / 'assimilation_hyperparameter_registry.csv', keep_default_na=False, dtype=str)

def require(paths):
    missing = [path for path in paths if not path.is_file()]
    if missing:
        raise FileNotFoundError(missing[0])

training_done = Counter()
training_missing = []
for _, row in training.iterrows():
    try:
        run = resolve_source_run(root, training, row['exp_id'])
        require([run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', run / 'train_data/train_data_scaler.yml'])
        training_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError) as exc:
        training_missing.append(f"{row['exp_id']}:{type(exc).__name__}")

evaluation_done = Counter()
evaluation_missing = []
for _, row in evaluations.iterrows():
    try:
        run = _registered_run(root, training, row)
        result = run / row['result_file']
        reference_run = resolve_source_run(root, training, row['reference_exp_id'])
        reference_result = reference_run / 'test/model_epoch030/test_results.p'
        require([run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', result,
                 _metrics_path(result), reference_result, _metrics_path(reference_result)])
        evaluation_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError) as exc:
        evaluation_missing.append(f"{row['eval_id']}:{type(exc).__name__}")

hyper_done = 0
hyper_missing = []
for _, row in hyper.iterrows():
    try:
        run = Path(row['run_dir'])
        run = run if run.is_absolute() else root / run
        result = run / row['result_file']
        reference_run = resolve_source_run(root, training, row['source_exp_id'])
        reference_result = reference_run / 'test/model_epoch030/test_results.p'
        require([run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', result,
                 _metrics_path(result), reference_result, _metrics_path(reference_result)])
        hyper_done += 1
    except (FileNotFoundError, KeyError, ValueError) as exc:
        hyper_missing.append(f"{row['eval_id']}:{type(exc).__name__}")

evaluation_aggregation = root / 'closure_20260810/aggregation/evaluations'
hyper_aggregation = root / 'closure_20260810/aggregation/hyperparameters'
payload = {
    'training_complete': sum(training_done.values()),
    'training_total': len(training),
    'training_by_family': dict(sorted(training_done.items())),
    'training_missing_first': training_missing[:5],
    'evaluation_complete': sum(evaluation_done.values()),
    'evaluation_total': len(evaluations),
    'evaluation_by_family': dict(sorted(evaluation_done.items())),
    'evaluation_missing_first': evaluation_missing[:5],
    'hyperparameter_complete': hyper_done,
    'hyperparameter_total': len(hyper),
    'hyperparameter_missing_first': hyper_missing[:5],
    'evaluation_aggregation_missing': [name for name in EVALUATION_AGGREGATION_FILES if not (evaluation_aggregation / name).is_file()],
    'hyperparameter_aggregation_missing': [name for name in HYPERPARAMETER_AGGREGATION_FILES if not (hyper_aggregation / name).is_file()],
    'final_gate_exists': (root / 'closure_20260810/aggregation/final_reproduction_gate.json').is_file(),
    'final_manifest_exists': (root / 'closure_20260810/aggregation/final_artifact_manifest.json').is_file(),
    'final_export_exists': (root / 'closure_20260810/export/nearing2022_final_closure.tar.gz').is_file(),
}
print(json.dumps(payload, sort_keys=True))
PY

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"

if [ "$STATE" != "COMPLETED" ] && [ "$STATE" != "RUNNING" ] && [ "$STATE" != "PENDING" ]; then
  exit 4
fi
