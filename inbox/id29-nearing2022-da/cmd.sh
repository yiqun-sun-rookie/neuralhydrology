#!/bin/bash
# ID29 seq=174: independently rehash every source artifact bound by the seq=171 partial numerical audit.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
AUDIT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq171.json"

test -f "$AUDIT"
test "$(sha256sum "$AUDIT" | awk '{print $1}')" = \
  672a679fe8a32fa30e7d4001fe0cb6e73a889d988171295745c60217aa5a64a1

python - "$ROOT" "$AUDIT" <<'PY'
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys

root = Path(sys.argv[1]).resolve()
audit_path = Path(sys.argv[2]).resolve()
audit_bytes = audit_path.read_bytes()
audit = json.loads(audit_bytes)

if audit['schema'] != 'nearing2022-partial-numerical-audit-v2':
    raise ValueError(audit['schema'])
if audit['complete_coordinates'] != 12 or audit['comparison_rows'] != 84:
    raise ValueError('Unexpected partial-audit dimensions')
if audit['registered_matrix_modified'] or audit['frozen_acceptance_modified']:
    raise ValueError('Frozen boundary was not preserved')

artifacts = audit['source_artifacts']
if len(artifacts) != 66:
    raise ValueError(f'Expected 66 source artifacts, found {len(artifacts)}')

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
    if len(payload) != expected['bytes']:
        raise ValueError(f'Byte mismatch: {relative}')
    if actual_hash != expected['sha256']:
        raise ValueError(f'Hash mismatch: {relative}')
    verified_bytes += len(payload)
    verified_hashes.add(actual_hash)

for coordinate in audit['coordinates']:
    for path_key, hash_key in (
        ('result_path', 'result_sha256'),
        ('reference_path', 'reference_sha256'),
    ):
        relative = coordinate[path_key]
        if relative not in artifacts:
            raise ValueError(f"{coordinate['eval_id']} missing {path_key} from source manifest")
        if artifacts[relative]['sha256'] != coordinate[hash_key]:
            raise ValueError(f"{coordinate['eval_id']} {path_key} hash disagreement")

if verified_bytes != 631590173:
    raise ValueError(f'Unexpected verified byte total: {verified_bytes}')
if len(verified_hashes) != 56:
    raise ValueError(f'Unexpected unique hash count: {len(verified_hashes)}')

print(json.dumps({
    'audit_bytes': len(audit_bytes),
    'audit_sha256': hashlib.sha256(audit_bytes).hexdigest(),
    'complete_coordinates': audit['complete_coordinates'],
    'comparison_rows': audit['comparison_rows'],
    'source_artifacts_verified': len(artifacts),
    'source_artifact_bytes_verified': verified_bytes,
    'unique_source_hashes': len(verified_hashes),
    'coordinate_result_and_reference_bindings_verified': len(audit['coordinates']) * 2,
    'mismatches': 0,
    'registered_matrix_modified': False,
}, sort_keys=True))
PY

test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "registered_matrix_modified=false"
