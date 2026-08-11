#!/bin/bash
# ID29 seq=193: read-only recovery of partial numerical audit job 202554.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
FINAL="$DIAGNOSTIC_ROOT/partial_numerical_audit_seq192_v1"
RECEIPT="$DIAGNOSTIC_ROOT/partial_numerical_audit_seq192_submission.json"
STAGING_PATTERN='partial_numerical_audit_seq192_v1.preparing-*'
STDOUT="$ROOT/closure_20260810/logs/N22-part-audit2_202554.out"
STDERR="$ROOT/closure_20260810/logs/N22-part-audit2_202554.err"

echo "=== FROZEN SUBMISSION RECEIPT ==="
date --iso-8601=seconds
test -f "$RECEIPT"
test ! -L "$RECEIPT"
test "$(sha256sum "$RECEIPT" | awk '{print $1}')" = 0ae9c1e53196b28f7a7817cc9dff4ebaf367801390829fef17d3f70bcc31eee9
sha256sum "$RECEIPT"

echo "=== SCHEDULER ==="
sacct -n -X -j 202554 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList%20 -P
squeue -h -j 202554 -o '%i|%j|%T|%M|%R' || true

echo "=== LOG SNAPSHOT ==="
for path in "$STDOUT" "$STDERR"; do
  if test -f "$path"; then
    stat -c '%n|%s' "$path"
    sha256sum "$path"
    echo "tail_begin|$path"
    tail -c 65536 "$path"
    echo
    echo "tail_end|$path"
  else
    echo "absent|$path"
  fi
done

echo "=== OUTPUT STATE ==="
echo "final_exists=$(test -e "$FINAL" && echo true || echo false)"
echo "staging_count=$(find "$DIAGNOSTIC_ROOT" -maxdepth 1 -name "$STAGING_PATTERN" | wc -l)"
if test -e "$FINAL"; then
  test -d "$FINAL"
  test ! -L "$FINAL"
  test "$(find "$FINAL" -type l -print -quit)" = ""
  test "$(find "$DIAGNOSTIC_ROOT" -maxdepth 1 -name "$STAGING_PATTERN" -print -quit)" = ""
  cmp "$FINAL/audit_1.json" "$FINAL/audit_2.json"
  cmp "$FINAL/audit_stdout_1.json" "$FINAL/audit_stdout_2.json"
  sha256sum "$FINAL"/*
  echo "execution_receipt_begin"
  cat "$FINAL/execution_receipt.json"
  echo "execution_receipt_end"
  echo "artifact_manifest_begin"
  cat "$FINAL/artifact_manifest.json"
  echo "artifact_manifest_end"
  echo "audit_stdout_begin"
  cat "$FINAL/audit_stdout_1.json"
  echo "audit_stdout_end"
  export FINAL
  python - <<'PY'
import base64
import hashlib
import json
import os
from pathlib import Path

final = Path(os.environ['FINAL'])
audit_path = final / 'audit_1.json'
payload = audit_path.read_bytes()
audit = json.loads(payload)
print(json.dumps({
    'audit_bytes': len(payload),
    'audit_sha256': hashlib.sha256(payload).hexdigest(),
    'complete_coordinates': audit['complete_coordinates'],
    'comparison_rows': audit['comparison_rows'],
    'individual_tolerance_failures': audit['individual_tolerance_failures'],
    'coordinates_with_failures': audit['coordinates_with_failures'],
    'registered_matrix_modified': audit['registered_matrix_modified'],
    'frozen_acceptance_modified': audit['frozen_acceptance_modified'],
}, sort_keys=True))
encoded = base64.b64encode(payload).decode('ascii')
print('AUDIT1_B64_BEGIN')
for start in range(0, len(encoded), 4096):
    print(encoded[start:start + 4096])
print('AUDIT1_B64_END')
PY
fi

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "registered_matrix_modified=false"
echo "frozen_acceptance_modified=false"
