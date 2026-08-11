#!/bin/bash
# ID29 seq=247: independently rehash and closure-enumerator-cover all 102 seq=245 audit sources.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
AUDIT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq245_v1/audit_1.json"
OLD_AUDIT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq234_v1/audit_1.json"
ROLE="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq245_v1/role_snapshot.json"
SCRIPT="$IDEA/scripts/verify_registered_closure.py"

for path in "$AUDIT" "$OLD_AUDIT" "$ROLE" "$SCRIPT"; do
  test -f "$path"
  test ! -L "$path"
done
test "$(stat -c '%s' "$AUDIT")" = 75160
test "$(sha256sum "$AUDIT" | awk '{print $1}')" = 2c02a4c6a67f657775cc0938aa248c5737cea2d7d3c02a3082d8498ce2f3869f
test "$(stat -c '%s' "$OLD_AUDIT")" = 71434
test "$(sha256sum "$OLD_AUDIT" | awk '{print $1}')" = aa4459c76f15b894e67a97e26e15df707766ed1504d2b8ed24054d59c8a3318e
test "$(stat -c '%s' "$ROLE")" = 2934
test "$(sha256sum "$ROLE" | awk '{print $1}')" = 74ed2acb8f59a6d51f561081581b9bcbbd0d7af831789a74d2580d63a812eeee
test "$(sha256sum "$SCRIPT" | awk '{print $1}')" = 3b0caef6076d457e303864227e6748ab947e39da01c0c1faea15795807ce8945

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

python - "$ROOT" "$IDEA" "$AUDIT" "$OLD_AUDIT" "$ROLE" "$SCRIPT" <<'PY'
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys

root = Path(sys.argv[1]).resolve()
idea = Path(sys.argv[2]).resolve()
audit_path = Path(sys.argv[3]).resolve()
old_audit_path = Path(sys.argv[4]).resolve()
role_path = Path(sys.argv[5]).resolve()
script_path = Path(sys.argv[6]).resolve()
sys.path.insert(0, str(script_path.parent))

from verify_registered_closure import audit_registered_closure, extra_tree_files

audit_bytes = audit_path.read_bytes()
audit = json.loads(audit_bytes)
old_audit = json.loads(old_audit_path.read_bytes())
role = json.loads(role_path.read_bytes())
if audit['schema'] != 'nearing2022-partial-numerical-audit-v3':
    raise ValueError(audit['schema'])
if audit['complete_coordinates'] != 19 or audit['comparison_rows'] != 133:
    raise ValueError('Unexpected current audit dimensions')
if old_audit['complete_coordinates'] != 18 or old_audit['comparison_rows'] != 126:
    raise ValueError('Unexpected predecessor audit dimensions')
if audit['registered_matrix_modified'] or audit['frozen_acceptance_modified']:
    raise ValueError('Frozen boundary was not preserved')
if role['slurm_job_id'] != '202752' or role['slurm_node'] != 'ngu102':
    raise ValueError('Role snapshot execution identity differs')
if role['partial_complete_count'] != 19 or role['closure_complete_count'] != 19:
    raise ValueError('Role snapshot count differs')
if role['target'] != 'N22-EVAL-TS-DA-L04-TE075-S0':
    raise ValueError('Role snapshot target differs')
if not role['target_partial_complete'] or not role['target_closure_complete']:
    raise ValueError('Target is incomplete in role snapshot')
if any(not item['is_file'] or item['is_symlink'] for item in role['target_roles'].values()):
    raise ValueError('A target role is not a regular file')

old_coordinates = {row['eval_id']: row for row in old_audit['coordinates']}
coordinates = {row['eval_id']: row for row in audit['coordinates']}
if not old_coordinates.keys() < coordinates.keys():
    raise ValueError('Current coordinate set does not strictly extend the predecessor')
if any(old_coordinates[key] != coordinates[key] for key in old_coordinates):
    raise ValueError('A predecessor coordinate changed')

artifacts = audit['source_artifacts']
old_artifacts = old_audit['source_artifacts']
if len(artifacts) != 102 or len(old_artifacts) != 97:
    raise ValueError(f'Unexpected source counts: current={len(artifacts)}, old={len(old_artifacts)}')
if not old_artifacts.keys() < artifacts.keys():
    raise ValueError('Current source set does not strictly extend the predecessor')
if any(old_artifacts[key] != artifacts[key] for key in old_artifacts):
    raise ValueError('A predecessor source record changed')

verified_bytes = 0
verified_hashes = set()
for relative, expected in sorted(artifacts.items()):
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
    verified_bytes += len(payload)
    verified_hashes.add(actual_hash)
if verified_bytes != 969763336 or len(verified_hashes) != 84:
    raise ValueError(f'Unexpected source totals: bytes={verified_bytes}, hashes={len(verified_hashes)}')

for coordinate in audit['coordinates']:
    for path_key, hash_key in (('result_path', 'result_sha256'), ('reference_path', 'reference_sha256')):
        relative = coordinate[path_key]
        if relative not in artifacts or artifacts[relative]['sha256'] != coordinate[hash_key]:
            raise ValueError(f"{coordinate['eval_id']} {path_key} binding mismatch")

extra_files = [
    *extra_tree_files(idea),
    *extra_tree_files(root / 'neuralhydrology'),
    *extra_tree_files(root / 'closure_20260810' / 'provenance'),
    root / 'test' / 'test_assimilation.py',
    root / 'test' / 'test_nearing2022_reproduction_contract.py',
    root / 'setup.cfg',
    root / 'requirements-gpu.txt',
]
closure = audit_registered_closure(
    root,
    idea / 'registry' / 'experiment_registry.csv',
    idea / 'registry' / 'evaluation_registry.csv',
    idea / 'registry' / 'assimilation_hyperparameter_registry.csv',
    root / 'closure_20260810' / 'aggregation' / 'evaluations',
    root / 'closure_20260810' / 'aggregation' / 'hyperparameters',
    extra_files=extra_files,
)
if closure['counts'] != {'training': 46, 'evaluations': 180, 'hyperparameters': 660}:
    raise ValueError(f"Unexpected registry counts: {closure['counts']}")
if closure['complete']:
    raise ValueError('Preflight unexpectedly reports a complete still-running matrix')

enumerated = {Path(row['path']).resolve(): row['bindings'] for row in closure['artifacts']}
missing_coverage = []
binding_type_counts = Counter()
for relative in sorted(artifacts):
    pure = PurePosixPath(relative)
    path = (root / Path(*pure.parts)).resolve()
    bindings = enumerated.get(path)
    if not bindings:
        missing_coverage.append(relative)
        continue
    binding_type_counts.update(
        {f"{item['coordinate_type']}:{item['role']}" for item in bindings}
    )
if missing_coverage:
    raise ValueError(f'Source artifacts omitted by closure enumerator: {missing_coverage}')

added_coordinates = sorted(coordinates.keys() - old_coordinates.keys())
added_sources = sorted(artifacts.keys() - old_artifacts.keys())
expected_added_coordinates = ['N22-EVAL-TS-DA-L04-TE075-S0']
if added_coordinates != expected_added_coordinates:
    raise ValueError(f'Unexpected added coordinates: {added_coordinates}')
added_source_bytes = sum(artifacts[key]['bytes'] for key in added_sources)
if len(added_sources) != 5 or added_source_bytes != 48302780:
    raise ValueError(
        f'Unexpected added sources: count={len(added_sources)}, bytes={added_source_bytes}'
    )
print(json.dumps({
    'schema': 'nearing2022-partial-source-rehash-and-final-manifest-coverage-v5',
    'audit_bytes': len(audit_bytes),
    'audit_sha256': hashlib.sha256(audit_bytes).hexdigest(),
    'role_snapshot_bytes': role_path.stat().st_size,
    'role_snapshot_sha256': hashlib.sha256(role_path.read_bytes()).hexdigest(),
    'complete_coordinates': audit['complete_coordinates'],
    'comparison_rows': audit['comparison_rows'],
    'predecessor_coordinates_identical': len(old_coordinates),
    'added_coordinates': added_coordinates,
    'source_artifacts_verified': len(artifacts),
    'source_artifact_bytes_verified': verified_bytes,
    'unique_source_hashes': len(verified_hashes),
    'predecessor_source_records_identical': len(old_artifacts),
    'added_source_artifacts': len(added_sources),
    'added_source_artifact_bytes': added_source_bytes,
    'coordinate_result_and_reference_bindings_verified': len(coordinates) * 2,
    'registry_counts': closure['counts'],
    'final_manifest_preflight_complete': closure['complete'],
    'final_manifest_preflight_existing_artifact_count': len(enumerated),
    'final_manifest_preflight_missing_role_count': len(closure['missing']),
    'source_artifacts_covered': len(artifacts) - len(missing_coverage),
    'source_artifacts_missing_coverage': missing_coverage,
    'binding_type_counts': dict(sorted(binding_type_counts.items())),
    'mismatches': 0,
    'manifest_written': False,
    'registered_matrix_modified': False,
    'frozen_acceptance_modified': False,
}, indent=2, sort_keys=True))
PY

echo "=== REPLACEMENT AND HELD-MANIFEST STATES ==="
sacct -n -X -j 202510,202511,202293 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Reason -P
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "manifest_written=false"
echo "registered_matrix_modified=false"
echo "frozen_acceptance_modified=false"
