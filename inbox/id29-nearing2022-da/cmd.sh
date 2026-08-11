#!/bin/bash
# ID29 seq=195: read-only matrix, replacement-audit, and frozen-boundary refresh.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
REGISTRY="$IDEA/registry"
AGGREGATION="$ROOT/closure_20260810/aggregation"
DIAGNOSTICS="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
MAIN_JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

echo "=== REGISTERED COMPLETE-ROLE COUNTS ==="
python - "$ROOT" "$IDEA" "$REGISTRY" "$AGGREGATION" <<'PY'
from collections import Counter
import json
from pathlib import Path
import sys

import pandas as pd

root = Path(sys.argv[1]).resolve()
idea = Path(sys.argv[2]).resolve()
registry = Path(sys.argv[3]).resolve()
aggregation = Path(sys.argv[4]).resolve()
sys.path.insert(0, str(idea / 'scripts'))

from verify_registered_closure import audit_registered_closure

training = pd.read_csv(registry / 'experiment_registry.csv', keep_default_na=False, dtype=str)
evaluations = pd.read_csv(registry / 'evaluation_registry.csv', keep_default_na=False, dtype=str)
hyperparameters = pd.read_csv(
    registry / 'assimilation_hyperparameter_registry.csv', keep_default_na=False, dtype=str,
)
closure = audit_registered_closure(
    root,
    registry / 'experiment_registry.csv',
    registry / 'evaluation_registry.csv',
    registry / 'assimilation_hyperparameter_registry.csv',
    aggregation / 'evaluations',
    aggregation / 'hyperparameters',
)
missing = {
    coordinate_type: {
        row['coordinate_id'] for row in closure['missing']
        if row['coordinate_type'] == coordinate_type
    }
    for coordinate_type in ('training', 'evaluation', 'hyperparameter')
}


def family_counts(frame, identifier, coordinate_type):
    return dict(sorted(Counter(
        row['family'] for _, row in frame.iterrows()
        if row[identifier] not in missing[coordinate_type]
    ).items()))


print(json.dumps({
    'training_complete': len(training) - len(missing['training']),
    'training_total': len(training),
    'training_by_family': family_counts(training, 'exp_id', 'training'),
    'evaluation_complete': len(evaluations) - len(missing['evaluation']),
    'evaluation_total': len(evaluations),
    'evaluation_by_family': family_counts(evaluations, 'eval_id', 'evaluation'),
    'hyperparameter_complete': len(hyperparameters) - len(missing['hyperparameter']),
    'hyperparameter_total': len(hyperparameters),
    'hyperparameter_by_family': family_counts(hyperparameters, 'eval_id', 'hyperparameter'),
    'missing_roles_total': len(closure['missing']),
    'registered_matrix_complete': closure['complete'],
}, sort_keys=True))
PY

echo "=== MAIN JOB STATES AND FAILURE GATE ==="
squeue -h -j "$MAIN_JOBS" -o '%i|%T|%M|%l|%R|%j' | sort
sacct -n -X -P -j "$MAIN_JOBS" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList
MAIN_FAILURES=$(sacct -n -X -P -j "$MAIN_JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$MAIN_FAILURES"
test -z "$MAIN_FAILURES"

echo "=== REPLACEMENT AUDIT STATES AND OUTPUTS ==="
sacct -n -X -P -j 202510,202511 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList,Reason
squeue -h -j 202510,202511 -o '%i|%j|%T|%M|%R|%E' | sort
find "$DIAGNOSTICS" -maxdepth 1 -mindepth 1 \
  \( -name 'author_v13_training_data_port_all531_v2*' \
  -o -name 'author_v13_warmup_isolation_all531_v2*' \
  -o -name 'warmup_target_replacement_verification_v1*' \) -printf '%f|%y\n' | sort

echo "=== PAIR AND FROZEN SAFETY BOUNDARY ==="
PAIR_PRESENT=0
for relative in \
  src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py \
  src/29_nearing2022_da_ar/scripts/analyze_warmup_target_pair.py \
  src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm \
  src/29_nearing2022_da_ar/hpc/analyze_warmup_target_pair.slurm \
  test/test_nearing2022_warmup_pair.py; do
  if test -e "$ROOT/$relative"; then PAIR_PRESENT=$((PAIR_PRESENT + 1)); fi
done
echo "paired_training_payload_present=$PAIR_PRESENT"
test "$PAIR_PRESENT" -eq 0
PAIR_QUEUE=$(squeue -h -n N22-repl-verify,N22-warm-pair,N22-warm-analysis -o '%i|%j|%T|%M|%R')
printf '%s\n' "$PAIR_QUEUE"
test -z "$PAIR_QUEUE"
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
test ! -e "$AGGREGATION/final_reproduction_gate.json"
test ! -e "$AGGREGATION/final_reproduction_differences.csv"
echo "verification_job_submitted=false"
echo "pair_training_submitted=false"
echo "registered_matrix_modified=false"
