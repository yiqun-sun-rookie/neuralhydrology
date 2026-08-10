#!/bin/bash
# ID29 seq=84: deploy a two-phase numerical gate, submit it after both aggregations, and report closure health; never release candidate manifest 202293.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/id29-nearing2022-da/gate_preflight_v1.tar.gz
EXPECTED_PAYLOAD_SHA=3a419a201bc6770805704e36c3f80e89d0361d3d963c19796ed7d38b8d546e7c
GATE_SLURM="$IDEA/hpc/run_registered_numerical_gate.slurm"
EVAL_SCRIPT="$IDEA/scripts/evaluate_full_reproduction.py"
ACCEPTANCE="$IDEA/reference/reproduction_acceptance.json"
GATE_OUTPUT="$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
GATE_DETAILS="$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"

echo "=== INSTALL TWO-PHASE NUMERICAL GATE ==="
mkdir -p "$(dirname "$PAYLOAD")"
base64 -d > "$PAYLOAD" <<'PAYLOAD_B64'
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
PAYLOAD_B64
echo "$EXPECTED_PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
test "$(tar -tzf "$PAYLOAD" | wc -l)" -eq 3
tar -xzf "$PAYLOAD" -C "$ROOT"
echo "9c5bfa339b3ed8be3b389cf10f8555a74b278dbf27aa247f7e77abc7b753f254  $GATE_SLURM" | sha256sum -c -
echo "f6548d2c1935093266ddbfcced8f66b5a540a02ce4e52216001526a34d6b4082  $EVAL_SCRIPT" | sha256sum -c -
echo "6125cab8935c3ad0ab498865c661c47ea83c837c7627dff2534ba5a5b9185895  $ACCEPTANCE" | sha256sum -c -
bash -n "$GATE_SLURM"
python - "$ACCEPTANCE" <<'PY'
import json
from pathlib import Path
import sys
payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
assert payload['schema'] == 'nearing2022-reproduction-acceptance-v1'
assert payload['frozen_before_full_matrix_results'] is True
assert payload['expected'] == {
    'time_comparison_rows': 1057,
    'basin_comparison_rows': 21,
    'hyperparameter_coordinates': 660,
}
print('gate_acceptance_contract=OK')
PY

echo "=== SUBMIT TWO-PHASE NUMERICAL GATE ==="
test ! -e "$GATE_OUTPUT"
test ! -e "$GATE_DETAILS"
test -z "$(squeue -h -u "$USER" -n N22-gate -o '%i' 2>/dev/null || true)"
GATE_JOB=$(sbatch --parsable --dependency=afterok:202229:202230 "$GATE_SLURM")
GATE_JOB=${GATE_JOB%%;*}
test -n "$GATE_JOB"
echo "numerical_gate_job=$GATE_JOB"
scontrol show job -o "$GATE_JOB" | sed -n 's/.*Dependency=\([^ ]*\).*/numerical_gate_dependency=\1/p'
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"

JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,$GATE_JOB

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
