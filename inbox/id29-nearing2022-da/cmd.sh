#!/bin/bash
# ID29 seq=281: clean read-only health poll (must exit 0). No large directory dumps.
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


echo "=== EVAL ARRAY 202222 SUMMARY ==="
sacct -X -n -P -j 202222 --format=State | sort | uniq -c

echo "=== HYPER ARRAY 202228 SUMMARY ==="
sacct -X -n -P -j 202228 --format=State | sort | uniq -c

echo "=== TRAIN ARRAY 202215 SUMMARY ==="
sacct -X -n -P -j 202215 --format=State | sort | uniq -c

echo "=== NON-ARRAY JOB STATES ==="
sacct -X -n -P -j 202214,202216,202226,202227,202229,202230,202238,202293,202294,202315,202510,202511 \
  --format=JobID,JobName,State,ExitCode,Elapsed,End

echo "=== RUNNING NOW ==="
squeue -u sunyiq -h -o '%i|%j|%T|%M|%R'

echo "=== PENDING REASONS ==="
squeue -u sunyiq -h -o '%i|%T|%R' | grep -i pending || echo 'none pending'

echo "=== AGGREGATION AND DECISION OUTPUTS ==="
for d in "$AGGREGATION/evaluations" "$AGGREGATION/hyperparameters" "$ROOT/closure_20260810/decision"; do
  if [ -d "$d" ]; then printf 'EXISTS|%s|files=%s\n' "$d" "$(find "$d" -type f | wc -l)"
  else printf 'MISSING|%s\n' "$d"; fi
done

echo "=== ENTRY-GATE DIAGNOSTIC OUTPUTS (202510/202511) ==="
for d in "$DIAGNOSTICS/author_v13_training_data_port_all531_v2" "$DIAGNOSTICS/author_v13_warmup_isolation_all531_v2"; do
  if [ -d "$d" ]; then
    printf 'EXISTS|%s\n' "$d"
    find "$d" -type f -printf '  %f|%s bytes\n' 2>/dev/null | head -10
  else printf 'MISSING|%s\n' "$d"; fi
done

echo "=== PLATFORM VERIFIED ==="
grep -E '^(NAME|VERSION)=' /etc/os-release
bash --version | head -1
git --version
ldd --version | head -1

echo "=== END seq=281 read_only=true ==="
date --iso-8601=seconds
exit 0
