#!/bin/bash
# ID29 seq=100: read-only audit every file bound by the local 64-test receipt after job 202369 found one source mismatch.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
RECEIPT="$ROOT/src/29_nearing2022_da_ar/reference/local_contract_validation.json"

echo "=== VALIDATION FAILURE BOUNDARY ==="
test "$(sacct -n -P -j 202369 --format=JobIDRaw,State | awk -F'|' '$1 == "202369" {print $2; exit}')" = "FAILED"
test -f "$RECEIPT"

echo "=== ALL LOCAL-TEST BINDING HASHES ==="
python - "$ROOT" "$RECEIPT" <<'PY'
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys

root = Path(sys.argv[1]).resolve()
receipt_path = Path(sys.argv[2]).resolve()
receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
assert receipt['schema'] == 'nearing2022-local-pytest-receipt-v1'


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


rows = []
for item in receipt['files']:
    relative = item['path']
    pure = PurePosixPath(relative)
    assert pure.as_posix() == relative and not pure.is_absolute()
    assert all(part not in {'', '.', '..'} for part in pure.parts)
    path = (root / Path(*pure.parts)).resolve()
    path.relative_to(root)
    exists = path.is_file()
    observed_bytes = path.stat().st_size if exists else None
    observed_sha256 = digest(path) if exists else None
    rows.append({
        'path': relative,
        'exists': exists,
        'expected_bytes': item['bytes'],
        'observed_bytes': observed_bytes,
        'expected_sha256': item['sha256'],
        'observed_sha256': observed_sha256,
        'match': exists and observed_bytes == item['bytes'] and observed_sha256 == item['sha256'],
    })
payload = {
    'schema': 'nearing2022-server-local-test-binding-audit-v1',
    'receipt_sha256': digest(receipt_path),
    'file_count': len(rows),
    'match_count': sum(row['match'] for row in rows),
    'mismatch_count': sum(not row['match'] for row in rows),
    'files': rows,
}
print(json.dumps(payload, indent=2, sort_keys=True))
PY

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
