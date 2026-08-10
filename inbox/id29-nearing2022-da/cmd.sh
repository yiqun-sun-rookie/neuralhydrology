#!/bin/bash
# ID29 seq=109: deploy the missing frozen headline binding, preserve attempt 202374, and resubmit preclosure.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD="$HOME/hpc_mailbox/inbox/id29-nearing2022-da/payload.tar.gz"
PAYLOAD_SHA=59287a2b7a4bb2933a68d4c95fe665e1e0c4430351eb629d91e9183b0d938661
RELATIVE=src/29_nearing2022_da_ar/reference/headline_artifact_recovery_binding.json
FILE_SHA=b0381957e7fcb23fc7ce0b946bc6cc46f1e3d74e31dce3c5a2f20c33dcba61cb
TARGET="$ROOT/$RELATIVE"
STAGE="$ROOT/closure_20260810/deployment/seq109"
PROVENANCE="$ROOT/closure_20260810/provenance"
PAYLOAD_COPY="$PROVENANCE/headline_binding_seq109_payload.tar.gz"
DEPLOYMENT_RECEIPT="$PROVENANCE/headline_binding_seq109_receipt.json"
FAILED_RECEIPT="$PROVENANCE/preclosure_failed_attempt_202374_receipt.json"
JOB_RECEIPT="$PROVENANCE/preclosure_validation_seq109_job.txt"
VALIDATION="$ROOT/src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm"
OUT_202374="$ROOT/closure_20260810/logs/N22-preclosure-check_202374.out"
ERR_202374="$ROOT/closure_20260810/logs/N22-preclosure-check_202374.err"
PRESERVED_OUT="$PROVENANCE/preclosure_attempt_202374.out"
PRESERVED_ERR="$PROVENANCE/preclosure_attempt_202374.err"

echo "=== PRE-INSTALL SAFETY BOUNDARY ==="
test -f "$PAYLOAD"
echo "$PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
mapfile -t MEMBERS < <(tar -tzf "$PAYLOAD")
test "${#MEMBERS[@]}" -eq 1
test "${MEMBERS[0]}" = "$RELATIVE"
test ! -e "$TARGET"
test ! -e "$STAGE"
test ! -e "$PAYLOAD_COPY"
test ! -e "$DEPLOYMENT_RECEIPT"
test ! -e "$FAILED_RECEIPT"
test ! -e "$JOB_RECEIPT"
test ! -e "$PRESERVED_OUT"
test ! -e "$PRESERVED_ERR"
test "$(sacct -n -P -j 202374 --format=JobIDRaw,State | awk -F'|' '$1 == "202374" {print $2; exit}')" = "FAILED"
grep -Fq "headline_artifact_recovery_binding.json" "$ERR_202374"
test -z "$(squeue -h -n N22-preclosure-check -o '%i')"
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"

echo "=== STAGE AND ATOMICALLY INSTALL BINDING ==="
mkdir -p "$STAGE"
tar -xzf "$PAYLOAD" -C "$STAGE"
STAGED="$STAGE/$RELATIVE"
test -f "$STAGED"
echo "$FILE_SHA  $STAGED" | sha256sum -c -
install -m 0644 "$PAYLOAD" "$PAYLOAD_COPY"
echo "$PAYLOAD_SHA  $PAYLOAD_COPY" | sha256sum -c -
mkdir -p "$(dirname "$TARGET")"
TEMPORARY="$TARGET.seq109.tmp"
test ! -e "$TEMPORARY"
install -m 0644 "$STAGED" "$TEMPORARY"
echo "$FILE_SHA  $TEMPORARY" | sha256sum -c -
mv "$TEMPORARY" "$TARGET"
echo "$FILE_SHA  $TARGET" | sha256sum -c -
python -m json.tool "$TARGET" >/dev/null

echo "=== PRESERVE ATTEMPT 202374 ==="
install -m 0644 "$OUT_202374" "$PRESERVED_OUT"
install -m 0644 "$ERR_202374" "$PRESERVED_ERR"
test "$(sha256sum "$OUT_202374" | awk '{print $1}')" = "$(sha256sum "$PRESERVED_OUT" | awk '{print $1}')"
test "$(sha256sum "$ERR_202374" | awk '{print $1}')" = "$(sha256sum "$PRESERVED_ERR" | awk '{print $1}')"

python - "$TARGET" "$PAYLOAD_COPY" "$DEPLOYMENT_RECEIPT" "$PRESERVED_OUT" "$PRESERVED_ERR" "$FAILED_RECEIPT" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

target, payload_copy, deployment_receipt, out, err, failed_receipt = map(Path, sys.argv[1:])

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

deployment = {
    'schema': 'nearing2022-headline-binding-deployment-v1',
    'mailbox_seq': 109,
    'created_utc': datetime.now(timezone.utc).isoformat(),
    'target': str(target),
    'target_bytes': target.stat().st_size,
    'target_sha256': digest(target),
    'payload_copy': str(payload_copy),
    'payload_bytes': payload_copy.stat().st_size,
    'payload_sha256': digest(payload_copy),
}
temporary = deployment_receipt.with_suffix(deployment_receipt.suffix + '.tmp')
assert not deployment_receipt.exists() and not temporary.exists()
temporary.write_text(json.dumps(deployment, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
temporary.replace(deployment_receipt)
print(json.dumps(deployment, sort_keys=True))

records = subprocess.run(
    ['sacct', '-n', '-P', '-j', '202374', '--format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList'],
    check=True,
    capture_output=True,
    text=True,
).stdout.splitlines()
record = next(line.split('|') for line in records if line.split('|', 1)[0].strip() == '202374')
fields = ('job_id', 'job_name', 'state', 'exit_code', 'elapsed', 'start', 'end', 'node_list')
slurm = dict(zip(fields, record, strict=True))
assert slurm['state'] == 'FAILED'
failed = {
    'schema': 'nearing2022-preclosure-failed-attempt-receipt-v1',
    'created_utc': datetime.now(timezone.utc).isoformat(),
    'slurm': slurm,
    'stdout': str(out),
    'stdout_bytes': out.stat().st_size,
    'stdout_sha256': digest(out),
    'stderr': str(err),
    'stderr_bytes': err.stat().st_size,
    'stderr_sha256': digest(err),
    'root_cause': 'missing_headline_artifact_recovery_binding',
}
temporary = failed_receipt.with_suffix(failed_receipt.suffix + '.tmp')
assert not failed_receipt.exists() and not temporary.exists()
temporary.write_text(json.dumps(failed, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
temporary.replace(failed_receipt)
print(json.dumps(failed, sort_keys=True))
PY

echo "=== SUBMIT PRECLOSURE VALIDATION ==="
VALIDATION_JOB_ID=$(sbatch --parsable "$VALIDATION" | cut -d';' -f1)
test -n "$VALIDATION_JOB_ID"
printf '%s\n' "$VALIDATION_JOB_ID" > "$JOB_RECEIPT"
echo "validation_job_id=$VALIDATION_JOB_ID"
scontrol show job -o "$VALIDATION_JOB_ID"

echo "=== POST-INSTALL SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
sha256sum "$TARGET" "$PAYLOAD_COPY" "$DEPLOYMENT_RECEIPT" "$PRESERVED_OUT" "$PRESERVED_ERR" "$FAILED_RECEIPT" "$JOB_RECEIPT"
