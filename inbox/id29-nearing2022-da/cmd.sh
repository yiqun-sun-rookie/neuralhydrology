#!/bin/bash
# ID29 seq=280: read-only post-recovery status. Reuses the seq-279 role-count block verbatim;
# the seq-279 PLANNING ESTIMATE block is dropped (it raised ValueError when no task is running).
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

echo "=== EVALUATION ARRAY TASK RECORDS ==="
sacct -n -P -j 202222 --format=JobID,State,ExitCode,ElapsedRaw,Elapsed,Start,End


echo "=== REGISTERED JOB STATES (all main jobs) ==="
sacct -X -n -P -j "$MAIN_JOBS" --format=JobID,JobName,State,ExitCode,Elapsed,End,NodeList

echo "=== REPLACEMENT DIAGNOSTIC JOBS 202510/202511 ==="
sacct -X -n -P -j 202510,202511 --format=JobID,JobName,State,ExitCode,Elapsed,End,Reason || echo 'absent'

echo "=== QUEUE NOW ==="
squeue -u sunyiq -o '%.10i %.9P %.30j %.9T %.11M %R' || true

echo "=== AGGREGATION OUTPUTS ==="
for d in "$AGGREGATION/evaluations" "$AGGREGATION/hyperparameters"; do
  if [ -d "$d" ]; then
    printf 'DIR_EXISTS|%s|files=%s\n' "$d" "$(find "$d" -type f | wc -l)"
    find "$d" -type f -printf '  %p|%s bytes\n' 2>/dev/null | head -20
  else
    printf 'DIR_MISSING|%s\n' "$d"
  fi
done

echo "=== FROZEN NUMERICAL GATE OUTPUT (job 202315) ==="
ls -la "$ROOT/closure_20260810/decision" 2>/dev/null || echo 'decision dir absent'

echo "=== MAILBOX STAGING (leftover results not pushed) ==="
ls -la ~/.hpc_mailbox_staging/id29-nearing2022-da/ 2>/dev/null || echo 'staging empty/absent'

echo "=== RUNNER ==="
pgrep -af hpc_runner_active || echo 'runner NOT running'

echo "=== PLATFORM AFTER UPGRADE ==="
cat /etc/os-release | head -3
bash --version | head -1
git --version
ldd --version | head -1
conda env list | head -10
python -c "import torch;print('torch',torch.__version__,'cuda_avail',torch.cuda.is_available())" 2>&1 | tail -2
sinfo -o '%.12P %.6a %.6D %.20N %.10T' 2>&1 | head -12

echo "=== END seq=280 read_only=true ==="
date --iso-8601=seconds
