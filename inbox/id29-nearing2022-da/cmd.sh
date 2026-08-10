#!/bin/bash
# ID29 seq=175: prove every seq=171 numerical-audit source is covered by the final closure-manifest enumerator.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
AUDIT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq171.json"
SCRIPT="$IDEA/scripts/verify_registered_closure.py"

test -f "$AUDIT"
test -f "$SCRIPT"
test "$(sha256sum "$AUDIT" | awk '{print $1}')" = \
  672a679fe8a32fa30e7d4001fe0cb6e73a889d988171295745c60217aa5a64a1

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

python - "$ROOT" "$IDEA" "$AUDIT" "$SCRIPT" <<'PY'
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys

root = Path(sys.argv[1]).resolve()
idea = Path(sys.argv[2]).resolve()
source_audit_path = Path(sys.argv[3]).resolve()
script_path = Path(sys.argv[4]).resolve()
sys.path.insert(0, str(script_path.parent))

from verify_registered_closure import audit_registered_closure, extra_tree_files

source_audit_bytes = source_audit_path.read_bytes()
source_audit = json.loads(source_audit_bytes)
if source_audit['schema'] != 'nearing2022-partial-numerical-audit-v2':
    raise ValueError(source_audit['schema'])
if source_audit['complete_coordinates'] != 12 or source_audit['comparison_rows'] != 84:
    raise ValueError('Unexpected partial-audit dimensions')
if source_audit['registered_matrix_modified'] or source_audit['frozen_acceptance_modified']:
    raise ValueError('Frozen boundary was not preserved')

# Match the final Slurm command's tree inclusion for all present source/protocol files.
# The run-role enumerator independently contributes configs, checkpoints, logs,
# predictions, metrics, and reference artifacts for every registered coordinate.
extra_files = [
    *extra_tree_files(idea),
    *extra_tree_files(root / 'neuralhydrology'),
    *extra_tree_files(root / 'closure_20260810' / 'provenance'),
    root / 'test' / 'test_assimilation.py',
    root / 'test' / 'test_nearing2022_reproduction_contract.py',
    root / 'setup.cfg',
    root / 'requirements-gpu.txt',
]
closure_audit = audit_registered_closure(
    root,
    idea / 'registry' / 'experiment_registry.csv',
    idea / 'registry' / 'evaluation_registry.csv',
    idea / 'registry' / 'assimilation_hyperparameter_registry.csv',
    root / 'closure_20260810' / 'aggregation' / 'evaluations',
    root / 'closure_20260810' / 'aggregation' / 'hyperparameters',
    extra_files=extra_files,
)
if closure_audit['counts'] != {'training': 46, 'evaluations': 180, 'hyperparameters': 660}:
    raise ValueError(f"Unexpected registry counts: {closure_audit['counts']}")
if closure_audit['complete']:
    raise ValueError('Preflight unexpectedly reports a complete still-running matrix')

enumerated = {Path(row['path']).resolve(): row['bindings'] for row in closure_audit['artifacts']}
source_artifacts = source_audit['source_artifacts']
if len(source_artifacts) != 66:
    raise ValueError(f'Expected 66 source artifacts, found {len(source_artifacts)}')

coverage = []
missing_coverage = []
covered_bytes = 0
binding_type_counts = Counter()
for relative, expected in sorted(source_artifacts.items()):
    pure = PurePosixPath(relative)
    if pure.is_absolute() or '..' in pure.parts:
        raise ValueError(f'Unsafe source path: {relative}')
    path = (root / Path(*pure.parts)).resolve()
    if root not in path.parents:
        raise ValueError(f'Outside-root source path: {relative}')
    payload = path.read_bytes()
    actual_hash = hashlib.sha256(payload).hexdigest()
    if len(payload) != expected['bytes'] or actual_hash != expected['sha256']:
        raise ValueError(f'Source identity mismatch: {relative}')
    bindings = enumerated.get(path)
    if not bindings:
        missing_coverage.append(relative)
        continue
    covered_bytes += len(payload)
    types = sorted({f"{item['coordinate_type']}:{item['role']}" for item in bindings})
    binding_type_counts.update(types)
    coverage.append({
        'path': relative,
        'bytes': len(payload),
        'sha256': actual_hash,
        'binding_count': len(bindings),
        'binding_types': types,
    })

if missing_coverage:
    raise ValueError(f'Source artifacts omitted by closure enumerator: {missing_coverage}')
if len(coverage) != 66 or covered_bytes != 631590173:
    raise ValueError(f'Unexpected coverage totals: files={len(coverage)}, bytes={covered_bytes}')

print(json.dumps({
    'schema': 'nearing2022-partial-source-final-manifest-coverage-v1',
    'source_audit_bytes': len(source_audit_bytes),
    'source_audit_sha256': hashlib.sha256(source_audit_bytes).hexdigest(),
    'registry_counts': closure_audit['counts'],
    'final_manifest_preflight_complete': closure_audit['complete'],
    'final_manifest_preflight_missing_role_count': len(closure_audit['missing']),
    'final_manifest_preflight_existing_artifact_count': len(enumerated),
    'source_artifacts_checked': len(source_artifacts),
    'source_artifacts_covered': len(coverage),
    'source_artifact_bytes_covered': covered_bytes,
    'source_artifacts_missing_coverage': missing_coverage,
    'binding_type_counts': dict(sorted(binding_type_counts.items())),
    'coverage': coverage,
    'manifest_written': False,
    'registered_matrix_modified': False,
}, indent=2, sort_keys=True))
PY

test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "registered_matrix_modified=false"
