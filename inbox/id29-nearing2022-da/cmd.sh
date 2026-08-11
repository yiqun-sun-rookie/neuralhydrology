#!/bin/bash
# ID29 seq=209: diagnose the seq207/208 two-role preflight-count delta without writes.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
REGISTRY="$IDEA/registry"
AGGREGATION="$ROOT/closure_20260810/aggregation"
SCRIPT="$IDEA/scripts/verify_registered_closure.py"

test -f "$SCRIPT"
test ! -L "$SCRIPT"
test "$(sha256sum "$SCRIPT" | awk '{print $1}')" = 3b0caef6076d457e303864227e6748ab947e39da01c0c1faea15795807ce8945

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

python - "$ROOT" "$IDEA" "$REGISTRY" "$AGGREGATION" "$SCRIPT" <<'PY'
from collections import Counter
import json
from pathlib import Path
import sys

import pandas as pd

root = Path(sys.argv[1]).resolve()
idea = Path(sys.argv[2]).resolve()
registry = Path(sys.argv[3]).resolve()
aggregation = Path(sys.argv[4]).resolve()
script_path = Path(sys.argv[5]).resolve()
sys.path.insert(0, str(script_path.parent))

from verify_registered_closure import audit_registered_closure, extra_tree_files

training_path = registry / 'experiment_registry.csv'
evaluation_path = registry / 'evaluation_registry.csv'
hyperparameter_path = registry / 'assimilation_hyperparameter_registry.csv'
evaluations = pd.read_csv(evaluation_path, keep_default_na=False, dtype=str)


def run(extra_files=()):
    return audit_registered_closure(
        root,
        training_path,
        evaluation_path,
        hyperparameter_path,
        aggregation / 'evaluations',
        aggregation / 'hyperparameters',
        extra_files=extra_files,
    )


def missing_signature(payload):
    return sorted(
        (
            row['coordinate_type'],
            row['coordinate_id'],
            row['role'],
            row.get('path', ''),
            row.get('error', ''),
        )
        for row in payload['missing']
    )


first = run()
second = run()
if missing_signature(first) != missing_signature(second):
    raise ValueError('Two immediate registered-closure audits disagree')

extra_files = [
    *extra_tree_files(idea),
    *extra_tree_files(root / 'neuralhydrology'),
    *extra_tree_files(root / 'closure_20260810' / 'provenance'),
    root / 'test' / 'test_assimilation.py',
    root / 'test' / 'test_nearing2022_reproduction_contract.py',
    root / 'setup.cfg',
    root / 'requirements-gpu.txt',
]
if any(not path.is_file() for path in extra_files):
    raise ValueError('An enumerated provenance extra file disappeared')
with_extras = run(extra_files)
if missing_signature(first) != missing_signature(with_extras):
    raise ValueError('Existing provenance extras changed the registered-role missing set')

targets = [
    'N22-EVAL-TS-DA-L04-TE025-S0',
    'N22-EVAL-TS-DA-L04-TE050-S0',
]
details = {}
for target in targets:
    rows = evaluations[evaluations['eval_id'] == target]
    if len(rows) != 1:
        raise ValueError(f'Expected one registry row for {target}')
    missing = [
        {
            'role': row['role'],
            'path': row.get('path', ''),
            'error': row.get('error', ''),
        }
        for row in first['missing']
        if row['coordinate_type'] == 'evaluation' and row['coordinate_id'] == target
    ]
    present = []
    for artifact in first['artifacts']:
        bindings = [
            binding for binding in artifact['bindings']
            if binding['coordinate_type'] == 'evaluation' and binding['coordinate_id'] == target
        ]
        if not bindings:
            continue
        path = Path(artifact['path'])
        present.append({
            'roles': sorted(binding['role'] for binding in bindings),
            'path': str(path),
            'bytes': path.stat().st_size,
            'modified_time_ns': path.stat().st_mtime_ns,
        })
    details[target] = {
        'registered_run_dir': rows.iloc[0]['run_dir'],
        'missing': sorted(missing, key=lambda row: (row['role'], row['path'])),
        'present': sorted(present, key=lambda row: row['path']),
    }

missing_evaluation_ids = {
    row['coordinate_id'] for row in first['missing']
    if row['coordinate_type'] == 'evaluation'
}
complete_evaluation_ids = sorted(set(evaluations['eval_id']) - missing_evaluation_ids)
print(json.dumps({
    'schema': 'nearing2022-live-missing-role-delta-diagnostic-v1',
    'registry_counts': first['counts'],
    'registered_closure_complete': first['complete'],
    'missing_roles_total': len(first['missing']),
    'missing_by_coordinate_type': dict(sorted(Counter(
        row['coordinate_type'] for row in first['missing']
    ).items())),
    'evaluation_complete': len(complete_evaluation_ids),
    'time_split_complete': sum(eval_id.startswith('N22-EVAL-TS-') for eval_id in complete_evaluation_ids),
    'target_details': details,
    'extra_files_checked': len(extra_files),
    'immediate_repeated_audits_identical': True,
    'no_extra_vs_existing_extras_missing_set_identical': True,
    'sequence_207_reported_missing_roles': 5467,
    'sequence_208_reported_missing_roles': 5469,
    'registered_matrix_modified': False,
}, indent=2, sort_keys=True))
PY

echo "=== ACTIVE EVALUATION RECORDS ==="
sacct -n -P -j 202222_16,202222_17 --format=JobID,State,ExitCode,Elapsed,Start,End
echo "=== FROZEN STATES ==="
sacct -n -X -P -j 202510,202511 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Reason
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "registered_matrix_modified=false"
