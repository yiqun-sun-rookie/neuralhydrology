#!/bin/bash
# ID29 seq=83: report Slurm health and full-role artifact progress; keep final manifest 202293 held.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294

echo "=== SQUEUE COUNTS BY ARRAY PARENT AND STATE ==="
squeue -h -j "$JOBS" -o '%F|%T' | sort | uniq -c

echo "=== SACCT COUNTS BY ARRAY PARENT, STATE, AND EXIT CODE ==="
sacct -n -P -j "$JOBS" --format=JobID,State,ExitCode | awk -F'|' '
  NF >= 3 && $1 !~ /\./ {
    parent = $1
    sub(/_.*/, "", parent)
    key = parent "|" $2 "|" $3
    count[key]++
  }
  END {
    for (key in count) print count[key] "|" key
  }
' | sort -t'|' -k2,2n -k3,3

echo "=== ACTIVE FAILURE STATES ==="
sacct -n -P -j "$JOBS" --format=JobID,State,ExitCode | awk -F'|' '
  $1 !~ /\./ && $2 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/ { print }
' || true

echo "=== EXPECTED CANCELLATIONS ==="
sacct -n -P -j 202242,202280,202281,202289,202290 --format=JobID,JobName,State,ExitCode | sed '/^[[:space:]]*$/d'

echo "=== FINAL DEPENDENCIES AND HOLD ==="
for job in 202229 202230 202293 202294; do
  scontrol show job -o "$job" | sed -n "s/.*Dependency=\([^ ]*\).*/$job|\1/p"
done
HELD_STATE=$(squeue -h -j 202293 -o '%i|%T|%r|%j')
echo "held_manifest=$HELD_STATE"
test "$HELD_STATE" = "202293|PENDING|JobHeldUser|N22-manifest"

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
        require([
            run / 'config.yml',
            run / 'model_epoch030.pt',
            run / 'output.log',
            run / 'train_data/train_data_scaler.yml',
        ])
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
        require([
            run / 'config.yml',
            run / 'model_epoch030.pt',
            run / 'output.log',
            result,
            _metrics_path(result),
            reference_result,
            _metrics_path(reference_result),
        ])
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
        require([
            run / 'config.yml',
            run / 'model_epoch030.pt',
            run / 'output.log',
            result,
            _metrics_path(result),
            reference_result,
            _metrics_path(reference_result),
        ])
        hyper_done += 1
    except (FileNotFoundError, KeyError, ValueError) as exc:
        hyper_missing.append(f"{row['eval_id']}:{type(exc).__name__}")

evaluation_aggregation = root / 'closure_20260810/aggregation/evaluations'
hyper_aggregation = root / 'closure_20260810/aggregation/hyperparameters'
evaluation_aggregation_missing = [
    name for name in EVALUATION_AGGREGATION_FILES if not (evaluation_aggregation / name).is_file()
]
hyper_aggregation_missing = [
    name for name in HYPERPARAMETER_AGGREGATION_FILES if not (hyper_aggregation / name).is_file()
]
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
    'evaluation_aggregation_missing': evaluation_aggregation_missing,
    'hyperparameter_aggregation_missing': hyper_aggregation_missing,
    'final_gate_exists': (root / 'closure_20260810/aggregation/final_reproduction_gate.json').is_file(),
    'final_manifest_exists': (root / 'closure_20260810/aggregation/final_artifact_manifest.json').is_file(),
    'final_export_exists': (root / 'closure_20260810/export/nearing2022_final_closure.tar.gz').is_file(),
}
print(json.dumps(payload, sort_keys=True))
PY
