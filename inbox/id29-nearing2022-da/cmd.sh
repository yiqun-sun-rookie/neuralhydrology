#!/bin/bash
# ID29 seq=106: verify pinned preclosure job 202373 and preserve immutable success evidence.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOB=202373
OUT="$ROOT/closure_20260810/logs/N22-preclosure-check_${JOB}.out"
ERR="$ROOT/closure_20260810/logs/N22-preclosure-check_${JOB}.err"
PROVENANCE="$ROOT/closure_20260810/provenance"
PRESERVED_OUT="$PROVENANCE/preclosure_validation_${JOB}.out"
PRESERVED_ERR="$PROVENANCE/preclosure_validation_${JOB}.err"
RECEIPT="$PROVENANCE/preclosure_validation_${JOB}_receipt.json"
JOB_RECEIPT="$PROVENANCE/preclosure_validation_seq105_job.txt"
VALIDATION="$ROOT/src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm"
CHECKER="$ROOT/src/29_nearing2022_da_ar/scripts/run_server_preclosure_check.py"
VERIFIER="$ROOT/src/29_nearing2022_da_ar/scripts/verify_registered_closure.py"
LOCAL_RECEIPT="$ROOT/src/29_nearing2022_da_ar/reference/local_contract_validation.json"

echo "=== VALIDATION STATE ==="
squeue -h -j "$JOB" -o '%i|%T|%r|%j' || true
sacct -n -P -j "$JOB" --format=JobID,JobName,State,ExitCode,Elapsed,Start,End,NodeList | sed '/^[[:space:]]*$/d'
STATE=$(sacct -n -P -j "$JOB" --format=JobIDRaw,State | awk -F'|' -v job="$JOB" '$1 == job {print $2; exit}')
echo "validation_state=$STATE"

if [ "$STATE" = "COMPLETED" ]; then
  test -f "$OUT"
  test -f "$ERR"
  echo "=== VALIDATION STDOUT ==="
  cat "$OUT"
  echo "=== VALIDATION STDERR ==="
  cat "$ERR"
  test ! -s "$ERR"
  grep -q '"ok": true' "$OUT"
  grep -q '"tests": 64' "$OUT"
  grep -q '"unique_file_count": 97' "$OUT"
  grep -q '"file_count": 20' "$OUT"
  grep -q '"dataset_sha256": "a3cb1f81e6b2f25e2b919c0d5b315e46fe82f8ed9c9d8a4bd56671da5500a35f"' "$OUT"
  grep -q '"complete_history_verified_in_empty_repository": true' "$OUT"
  grep -q 'finished=' "$OUT"
  test ! -e "$PRESERVED_OUT"
  test ! -e "$PRESERVED_ERR"
  test ! -e "$RECEIPT"
  install -m 0644 "$OUT" "$PRESERVED_OUT"
  install -m 0644 "$ERR" "$PRESERVED_ERR"
  test "$(sha256sum "$OUT" | awk '{print $1}')" = "$(sha256sum "$PRESERVED_OUT" | awk '{print $1}')"
  test "$(sha256sum "$ERR" | awk '{print $1}')" = "$(sha256sum "$PRESERVED_ERR" | awk '{print $1}')"
  python - "$JOB" "$OUT" "$ERR" "$PRESERVED_OUT" "$PRESERVED_ERR" "$RECEIPT" "$JOB_RECEIPT" "$VALIDATION" "$CHECKER" "$VERIFIER" "$LOCAL_RECEIPT" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

job = sys.argv[1]
paths = [Path(value) for value in sys.argv[2:]]
out, err, preserved_out, preserved_err, receipt, job_receipt, validation, checker, verifier, local_receipt = paths

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

sacct = subprocess.run(
    ['sacct', '-n', '-P', '-j', job, '--format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList'],
    check=True,
    capture_output=True,
    text=True,
).stdout.splitlines()
record = next(line.split('|') for line in sacct if line.split('|', 1)[0].strip() == job)
fields = ['job_id', 'job_name', 'state', 'exit_code', 'elapsed', 'start', 'end', 'node_list']
slurm = dict(zip(fields, record, strict=True))
assert slurm['state'] == 'COMPLETED'
assert slurm['exit_code'] == '0:0'
assert slurm['node_list'] == 'ngu003'
payload = {
    'schema': 'nearing2022-preclosure-validation-receipt-v1',
    'created_utc': datetime.now(timezone.utc).isoformat(),
    'slurm': slurm,
    'source_stdout': str(out),
    'source_stderr': str(err),
    'preserved_stdout': str(preserved_out),
    'preserved_stderr': str(preserved_err),
    'stdout_sha256': digest(out),
    'stderr_sha256': digest(err),
    'job_receipt_sha256': digest(job_receipt),
    'validation_slurm_sha256': digest(validation),
    'server_checker_sha256': digest(checker),
    'closure_verifier_sha256': digest(verifier),
    'local_validation_receipt_sha256': digest(local_receipt),
}
assert payload['stdout_sha256'] == digest(preserved_out)
assert payload['stderr_sha256'] == digest(preserved_err)
temporary = receipt.with_suffix(receipt.suffix + '.tmp')
assert not receipt.exists() and not temporary.exists()
temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
temporary.replace(receipt)
print(json.dumps(payload, sort_keys=True))
PY
  sha256sum "$OUT" "$ERR" "$PRESERVED_OUT" "$PRESERVED_ERR" "$RECEIPT" "$JOB_RECEIPT" "$VALIDATION" "$CHECKER" "$VERIFIER" "$LOCAL_RECEIPT"
elif [ "$STATE" = "RUNNING" ] || [ "$STATE" = "PENDING" ]; then
  echo "validation_pending=1"
else
  echo "=== FAILED STDOUT ==="
  test -f "$OUT" && cat "$OUT"
  echo "=== FAILED STDERR ==="
  test -f "$ERR" && cat "$ERR"
  test -f "$OUT" && test -f "$ERR" && sha256sum "$OUT" "$ERR" "$JOB_RECEIPT"
fi

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"

if [ "$STATE" != "COMPLETED" ] && [ "$STATE" != "RUNNING" ] && [ "$STATE" != "PENDING" ]; then
  exit 4
fi
