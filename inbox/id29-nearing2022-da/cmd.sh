#!/bin/bash
# ID29 seq=115: verify preclosure job 202388 and preserve immutable success evidence.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOB=202388
OUT="$ROOT/closure_20260810/logs/N22-preclosure-check_${JOB}.out"
ERR="$ROOT/closure_20260810/logs/N22-preclosure-check_${JOB}.err"
PROVENANCE="$ROOT/closure_20260810/provenance"
PRESERVED_OUT="$PROVENANCE/preclosure_validation_${JOB}.out"
PRESERVED_ERR="$PROVENANCE/preclosure_validation_${JOB}.err"
RECEIPT="$PROVENANCE/preclosure_validation_${JOB}_receipt.json"
JOB_RECEIPT="$PROVENANCE/preclosure_validation_seq114_job.txt"
DEPLOYMENT_RECEIPT="$PROVENANCE/dynamic_progress_contract_seq114_receipt.json"
VALIDATION="$ROOT/src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm"
CHECKER="$ROOT/src/29_nearing2022_da_ar/scripts/run_server_preclosure_check.py"
VERIFIER="$ROOT/src/29_nearing2022_da_ar/scripts/verify_registered_closure.py"
LOCAL_RECEIPT="$ROOT/src/29_nearing2022_da_ar/reference/local_contract_validation.json"
LOCAL_JUNIT="$ROOT/src/29_nearing2022_da_ar/reference/local_contract_validation_junit.xml"
CONTRACT_TEST="$ROOT/test/test_nearing2022_reproduction_contract.py"
ARCHIVED_RECEIPT="$ROOT/src/29_nearing2022_da_ar/reference/local_contract_validation_pre_dynamic_progress_20260810.json"
ARCHIVED_JUNIT="$ROOT/src/29_nearing2022_da_ar/reference/local_contract_validation_junit_pre_dynamic_progress_20260810.xml"
HEADLINE_BINDING="$ROOT/src/29_nearing2022_da_ar/reference/headline_artifact_recovery_binding.json"

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
  grep -q '"bound_file_count": 15' "$OUT"
  grep -q '"unique_file_count": 97' "$OUT"
  grep -q '"file_count": 20' "$OUT"
  grep -q '"dataset_sha256": "a3cb1f81e6b2f25e2b919c0d5b315e46fe82f8ed9c9d8a4bd56671da5500a35f"' "$OUT"
  grep -q '"complete_history_verified_in_empty_repository": true' "$OUT"
  grep -q 'finished=' "$OUT"
  echo 'dc8c5a18b77d321b1a4ae6aba24315b16cb5a59e4fa2c3a6c99ae8de4ba2d6ed  '"$CONTRACT_TEST" | sha256sum -c -
  echo '25f0ad9ba2e9cf51c1bac3de15ef307a6a56f64adce35a9b70043abf6fd2a553  '"$LOCAL_JUNIT" | sha256sum -c -
  echo 'dd7819377de090baf9e7210216e8d62ac1fd12fa46d2eb8a59fa74c6a4372b67  '"$LOCAL_RECEIPT" | sha256sum -c -
  echo '3224f75cb2a8c28d80b94055fe143278b07e52c667386ff8241eedae7679db01  '"$ARCHIVED_JUNIT" | sha256sum -c -
  echo '62c11fb1cdd1aa1545cc073c178049e704369b36ac7152b9f8d31f9ee9ae7a7e  '"$ARCHIVED_RECEIPT" | sha256sum -c -
  test ! -e "$PRESERVED_OUT"
  test ! -e "$PRESERVED_ERR"
  test ! -e "$RECEIPT"
  install -m 0644 "$OUT" "$PRESERVED_OUT"
  install -m 0644 "$ERR" "$PRESERVED_ERR"
  test "$(sha256sum "$OUT" | awk '{print $1}')" = "$(sha256sum "$PRESERVED_OUT" | awk '{print $1}')"
  test "$(sha256sum "$ERR" | awk '{print $1}')" = "$(sha256sum "$PRESERVED_ERR" | awk '{print $1}')"
  python - "$JOB" "$OUT" "$ERR" "$PRESERVED_OUT" "$PRESERVED_ERR" "$RECEIPT" \
    "$JOB_RECEIPT" "$DEPLOYMENT_RECEIPT" "$VALIDATION" "$CHECKER" "$VERIFIER" "$LOCAL_RECEIPT" \
    "$LOCAL_JUNIT" "$CONTRACT_TEST" "$ARCHIVED_RECEIPT" "$ARCHIVED_JUNIT" "$HEADLINE_BINDING" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

job = sys.argv[1]
(out, err, preserved_out, preserved_err, receipt, job_receipt, deployment_receipt, validation,
 checker, verifier, local_receipt, local_junit, contract_test, archived_receipt, archived_junit,
 headline_binding) = (Path(value) for value in sys.argv[2:])

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

records = subprocess.run(
    ['sacct', '-n', '-P', '-j', job, '--format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList'],
    check=True,
    capture_output=True,
    text=True,
).stdout.splitlines()
record = next(line.split('|') for line in records if line.split('|', 1)[0].strip() == job)
fields = ('job_id', 'job_name', 'state', 'exit_code', 'elapsed', 'start', 'end', 'node_list')
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
    'deployment_receipt_sha256': digest(deployment_receipt),
    'validation_slurm_sha256': digest(validation),
    'server_checker_sha256': digest(checker),
    'closure_verifier_sha256': digest(verifier),
    'local_validation_receipt_sha256': digest(local_receipt),
    'local_validation_junit_sha256': digest(local_junit),
    'contract_test_sha256': digest(contract_test),
    'archived_validation_receipt_sha256': digest(archived_receipt),
    'archived_validation_junit_sha256': digest(archived_junit),
    'headline_artifact_binding_sha256': digest(headline_binding),
}
assert payload['stdout_sha256'] == digest(preserved_out)
assert payload['stderr_sha256'] == digest(preserved_err)
assert payload['local_validation_receipt_sha256'] == 'dd7819377de090baf9e7210216e8d62ac1fd12fa46d2eb8a59fa74c6a4372b67'
assert payload['local_validation_junit_sha256'] == '25f0ad9ba2e9cf51c1bac3de15ef307a6a56f64adce35a9b70043abf6fd2a553'
assert payload['contract_test_sha256'] == 'dc8c5a18b77d321b1a4ae6aba24315b16cb5a59e4fa2c3a6c99ae8de4ba2d6ed'
temporary = receipt.with_suffix(receipt.suffix + '.tmp')
assert not receipt.exists() and not temporary.exists()
temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
temporary.replace(receipt)
print(json.dumps(payload, sort_keys=True))
PY
  sha256sum "$OUT" "$ERR" "$PRESERVED_OUT" "$PRESERVED_ERR" "$RECEIPT" "$JOB_RECEIPT" \
    "$DEPLOYMENT_RECEIPT" "$VALIDATION" "$CHECKER" "$VERIFIER" "$LOCAL_RECEIPT" "$LOCAL_JUNIT" \
    "$CONTRACT_TEST" "$ARCHIVED_RECEIPT" "$ARCHIVED_JUNIT" "$HEADLINE_BINDING"
elif [ "$STATE" = "RUNNING" ] || [ "$STATE" = "PENDING" ]; then
  echo "validation_pending=1"
else
  echo "=== FAILED STDOUT ==="
  test -f "$OUT" && cat "$OUT"
  echo "=== FAILED STDERR ==="
  test -f "$ERR" && cat "$ERR"
  test -f "$OUT" && test -f "$ERR" && sha256sum "$OUT" "$ERR" "$JOB_RECEIPT"
fi

echo "=== ACTIVE MAIN FAILURE STATES ==="
JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315
FAILURES=$(sacct -n -P -j "$JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$FAILURES"
test -z "$FAILURES"

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"

if [ "$STATE" != "COMPLETED" ] && [ "$STATE" != "RUNNING" ] && [ "$STATE" != "PENDING" ]; then
  exit 4
fi
