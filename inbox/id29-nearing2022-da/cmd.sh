#!/bin/bash
# ID29 seq=114: atomically deploy the dynamic-progress contract evidence and submit preclosure validation.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD="$HOME/hpc_mailbox/inbox/id29-nearing2022-da/payload.tar.gz"
PAYLOAD_SHA=a029b3b9468e7b5bc9d652eb8e38b41897f904cb1c57c25500df4496982a5478
PROVENANCE="$ROOT/closure_20260810/provenance"
STAGE="$ROOT/closure_20260810/deployment/seq114"
PAYLOAD_COPY="$PROVENANCE/dynamic_progress_contract_seq114_payload.tar.gz"
BACKUP="$PROVENANCE/pre_dynamic_progress_contract_seq114"
DEPLOYMENT_RECEIPT="$PROVENANCE/dynamic_progress_contract_seq114_receipt.json"
JOB_RECEIPT="$PROVENANCE/preclosure_validation_seq114_job.txt"
VALIDATION="$ROOT/src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm"

REL_TEST=test/test_nearing2022_reproduction_contract.py
REL_JUNIT=src/29_nearing2022_da_ar/reference/local_contract_validation_junit.xml
REL_RECEIPT=src/29_nearing2022_da_ar/reference/local_contract_validation.json
REL_ARCHIVE_JUNIT=src/29_nearing2022_da_ar/reference/local_contract_validation_junit_pre_dynamic_progress_20260810.xml
REL_ARCHIVE_RECEIPT=src/29_nearing2022_da_ar/reference/local_contract_validation_pre_dynamic_progress_20260810.json

TEST_TARGET="$ROOT/$REL_TEST"
JUNIT_TARGET="$ROOT/$REL_JUNIT"
RECEIPT_TARGET="$ROOT/$REL_RECEIPT"
ARCHIVE_JUNIT_TARGET="$ROOT/$REL_ARCHIVE_JUNIT"
ARCHIVE_RECEIPT_TARGET="$ROOT/$REL_ARCHIVE_RECEIPT"

check_file() {
  local path=$1
  local bytes=$2
  local sha=$3
  test -f "$path"
  test "$(stat -c '%s' "$path")" -eq "$bytes"
  echo "$sha  $path" | sha256sum -c -
}

echo "=== PRE-INSTALL SAFETY BOUNDARY ==="
test -f "$PAYLOAD"
check_file "$PAYLOAD" 19053 "$PAYLOAD_SHA"
mapfile -t MEMBERS < <(tar -tzf "$PAYLOAD")
test "${#MEMBERS[@]}" -eq 5
test "${MEMBERS[0]}" = "$REL_TEST"
test "${MEMBERS[1]}" = "$REL_JUNIT"
test "${MEMBERS[2]}" = "$REL_RECEIPT"
test "${MEMBERS[3]}" = "$REL_ARCHIVE_JUNIT"
test "${MEMBERS[4]}" = "$REL_ARCHIVE_RECEIPT"
check_file "$TEST_TARGET" 68737 8896fe1f7437789ac14087d8b67cc68e11b4bff6d806e24bcd0cd263530b1b4a
check_file "$JUNIT_TARGET" 9288 3224f75cb2a8c28d80b94055fe143278b07e52c667386ff8241eedae7679db01
check_file "$RECEIPT_TARGET" 3517 62c11fb1cdd1aa1545cc073c178049e704369b36ac7152b9f8d31f9ee9ae7a7e
test ! -e "$ARCHIVE_JUNIT_TARGET"
test ! -e "$ARCHIVE_RECEIPT_TARGET"
test ! -e "$STAGE"
test ! -e "$PAYLOAD_COPY"
test ! -e "$BACKUP"
test ! -e "$DEPLOYMENT_RECEIPT"
test ! -e "$JOB_RECEIPT"
test "$(sacct -n -P -j 202376 --format=JobIDRaw,State | awk -F'|' '$1 == "202376" {print $2; exit}')" = "COMPLETED"
test -z "$(squeue -h -n N22-preclosure-check -o '%i')"
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"

echo "=== STAGE AND VERIFY ALL FIVE MEMBERS ==="
mkdir -p "$STAGE"
tar -xzf "$PAYLOAD" -C "$STAGE"
check_file "$STAGE/$REL_TEST" 69070 dc8c5a18b77d321b1a4ae6aba24315b16cb5a59e4fa2c3a6c99ae8de4ba2d6ed
check_file "$STAGE/$REL_JUNIT" 9288 25f0ad9ba2e9cf51c1bac3de15ef307a6a56f64adce35a9b70043abf6fd2a553
check_file "$STAGE/$REL_RECEIPT" 3517 dd7819377de090baf9e7210216e8d62ac1fd12fa46d2eb8a59fa74c6a4372b67
check_file "$STAGE/$REL_ARCHIVE_JUNIT" 9288 3224f75cb2a8c28d80b94055fe143278b07e52c667386ff8241eedae7679db01
check_file "$STAGE/$REL_ARCHIVE_RECEIPT" 3517 62c11fb1cdd1aa1545cc073c178049e704369b36ac7152b9f8d31f9ee9ae7a7e
cmp -s "$JUNIT_TARGET" "$STAGE/$REL_ARCHIVE_JUNIT"
cmp -s "$RECEIPT_TARGET" "$STAGE/$REL_ARCHIVE_RECEIPT"

echo "=== PRESERVE PREVIOUS CANONICAL BYTES ==="
mkdir -p "$BACKUP"
install -m 0644 "$TEST_TARGET" "$BACKUP/test_nearing2022_reproduction_contract.py"
install -m 0644 "$JUNIT_TARGET" "$BACKUP/local_contract_validation_junit.xml"
install -m 0644 "$RECEIPT_TARGET" "$BACKUP/local_contract_validation.json"
check_file "$BACKUP/test_nearing2022_reproduction_contract.py" 68737 8896fe1f7437789ac14087d8b67cc68e11b4bff6d806e24bcd0cd263530b1b4a
check_file "$BACKUP/local_contract_validation_junit.xml" 9288 3224f75cb2a8c28d80b94055fe143278b07e52c667386ff8241eedae7679db01
check_file "$BACKUP/local_contract_validation.json" 3517 62c11fb1cdd1aa1545cc073c178049e704369b36ac7152b9f8d31f9ee9ae7a7e
install -m 0644 "$PAYLOAD" "$PAYLOAD_COPY"
check_file "$PAYLOAD_COPY" 19053 "$PAYLOAD_SHA"

echo "=== PREPARE AND ATOMICALLY PUBLISH NEW BYTES ==="
TEST_TMP="$TEST_TARGET.seq114.tmp"
JUNIT_TMP="$JUNIT_TARGET.seq114.tmp"
RECEIPT_TMP="$RECEIPT_TARGET.seq114.tmp"
ARCHIVE_JUNIT_TMP="$ARCHIVE_JUNIT_TARGET.seq114.tmp"
ARCHIVE_RECEIPT_TMP="$ARCHIVE_RECEIPT_TARGET.seq114.tmp"
for temporary in "$TEST_TMP" "$JUNIT_TMP" "$RECEIPT_TMP" "$ARCHIVE_JUNIT_TMP" "$ARCHIVE_RECEIPT_TMP"; do
  test ! -e "$temporary"
done
install -m 0644 "$STAGE/$REL_TEST" "$TEST_TMP"
install -m 0644 "$STAGE/$REL_JUNIT" "$JUNIT_TMP"
install -m 0644 "$STAGE/$REL_RECEIPT" "$RECEIPT_TMP"
install -m 0644 "$STAGE/$REL_ARCHIVE_JUNIT" "$ARCHIVE_JUNIT_TMP"
install -m 0644 "$STAGE/$REL_ARCHIVE_RECEIPT" "$ARCHIVE_RECEIPT_TMP"
check_file "$TEST_TMP" 69070 dc8c5a18b77d321b1a4ae6aba24315b16cb5a59e4fa2c3a6c99ae8de4ba2d6ed
check_file "$JUNIT_TMP" 9288 25f0ad9ba2e9cf51c1bac3de15ef307a6a56f64adce35a9b70043abf6fd2a553
check_file "$RECEIPT_TMP" 3517 dd7819377de090baf9e7210216e8d62ac1fd12fa46d2eb8a59fa74c6a4372b67
check_file "$ARCHIVE_JUNIT_TMP" 9288 3224f75cb2a8c28d80b94055fe143278b07e52c667386ff8241eedae7679db01
check_file "$ARCHIVE_RECEIPT_TMP" 3517 62c11fb1cdd1aa1545cc073c178049e704369b36ac7152b9f8d31f9ee9ae7a7e
mv "$ARCHIVE_JUNIT_TMP" "$ARCHIVE_JUNIT_TARGET"
mv "$ARCHIVE_RECEIPT_TMP" "$ARCHIVE_RECEIPT_TARGET"
mv "$TEST_TMP" "$TEST_TARGET"
mv "$JUNIT_TMP" "$JUNIT_TARGET"
mv "$RECEIPT_TMP" "$RECEIPT_TARGET"

check_file "$TEST_TARGET" 69070 dc8c5a18b77d321b1a4ae6aba24315b16cb5a59e4fa2c3a6c99ae8de4ba2d6ed
check_file "$JUNIT_TARGET" 9288 25f0ad9ba2e9cf51c1bac3de15ef307a6a56f64adce35a9b70043abf6fd2a553
check_file "$RECEIPT_TARGET" 3517 dd7819377de090baf9e7210216e8d62ac1fd12fa46d2eb8a59fa74c6a4372b67
check_file "$ARCHIVE_JUNIT_TARGET" 9288 3224f75cb2a8c28d80b94055fe143278b07e52c667386ff8241eedae7679db01
check_file "$ARCHIVE_RECEIPT_TARGET" 3517 62c11fb1cdd1aa1545cc073c178049e704369b36ac7152b9f8d31f9ee9ae7a7e
python -m json.tool "$RECEIPT_TARGET" >/dev/null
python -m json.tool "$ARCHIVE_RECEIPT_TARGET" >/dev/null

echo "=== VERIFY RECEIPT CONTENT AND WRITE DEPLOYMENT RECEIPT ==="
python - "$ROOT" "$PAYLOAD_COPY" "$BACKUP" "$DEPLOYMENT_RECEIPT" \
  "$REL_TEST" "$REL_JUNIT" "$REL_RECEIPT" "$REL_ARCHIVE_JUNIT" "$REL_ARCHIVE_RECEIPT" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

root, payload_copy, backup, deployment_receipt = map(Path, sys.argv[1:5])
relative_paths = sys.argv[5:]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

receipt_path = root / relative_paths[2]
receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
assert receipt['result'] == {'tests': 64, 'failures': 0, 'errors': 0, 'skipped': 0}
assert receipt['junit_sha256'] == '25f0ad9ba2e9cf51c1bac3de15ef307a6a56f64adce35a9b70043abf6fd2a553'
test_entry = next(item for item in receipt['files'] if item['path'] == relative_paths[0])
assert test_entry == {
    'path': relative_paths[0],
    'bytes': 69070,
    'sha256': 'dc8c5a18b77d321b1a4ae6aba24315b16cb5a59e4fa2c3a6c99ae8de4ba2d6ed',
}

def record(path):
    return {'path': str(path), 'bytes': path.stat().st_size, 'sha256': digest(path)}

payload = {
    'schema': 'nearing2022-dynamic-progress-contract-deployment-v1',
    'mailbox_seq': 114,
    'created_utc': datetime.now(timezone.utc).isoformat(),
    'payload': record(payload_copy),
    'previous_canonical_files': [record(path) for path in sorted(backup.iterdir())],
    'deployed_files': [record(root / relative) for relative in relative_paths],
    'result': 'five exact members deployed; previous canonical bytes preserved; local receipt content verified',
}
temporary = deployment_receipt.with_suffix(deployment_receipt.suffix + '.tmp')
assert not deployment_receipt.exists() and not temporary.exists()
temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
temporary.replace(deployment_receipt)
print(json.dumps(payload, sort_keys=True))
PY

echo "=== SUBMIT UPDATED PRECLOSURE VALIDATION ==="
VALIDATION_JOB_ID=$(sbatch --parsable --nodelist=ngu003 "$VALIDATION" | cut -d';' -f1)
test -n "$VALIDATION_JOB_ID"
printf '%s\n' "$VALIDATION_JOB_ID" > "$JOB_RECEIPT"
echo "validation_job_id=$VALIDATION_JOB_ID"
scontrol show job -o "$VALIDATION_JOB_ID"

echo "=== POST-INSTALL SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
sha256sum "$PAYLOAD_COPY" "$DEPLOYMENT_RECEIPT" "$JOB_RECEIPT" "$VALIDATION" \
  "$TEST_TARGET" "$JUNIT_TARGET" "$RECEIPT_TARGET" "$ARCHIVE_JUNIT_TARGET" "$ARCHIVE_RECEIPT_TARGET"
