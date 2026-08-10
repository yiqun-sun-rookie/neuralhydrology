#!/bin/bash
# ID29 seq=101: preserve and align the sole mismatching tested Slurm source, then submit the third preclosure validation attempt.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD="$HOME/hpc_mailbox/inbox/id29-nearing2022-da/payload.tar.gz"
PAYLOAD_SHA=1f01b23421d39755478916c33f58bd13952deb39e3c4ac9a5e1aab0ab6911d1f
RELATIVE=src/29_nearing2022_da_ar/hpc/run_registered_numerical_gate.slurm
TARGET="$ROOT/$RELATIVE"
OLD_SHA=9c5bfa339b3ed8be3b389cf10f8555a74b278dbf27aa247f7e77abc7b753f254
NEW_SHA=1513634e48a76be1ccffe1f7ef6a36955e6594b05bda39ed0957c41d72ed58ac
STAGE="$ROOT/closure_20260810/deployment/seq101"
BACKUP="$ROOT/closure_20260810/provenance/run_registered_numerical_gate_pre_seq101_9c5bfa33.slurm"
RECEIPT="$ROOT/closure_20260810/provenance/numerical_gate_slurm_source_seq101_receipt.json"
JOB_RECEIPT="$ROOT/closure_20260810/provenance/preclosure_validation_seq101_job.txt"
VALIDATION="$ROOT/src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm"

echo "=== PRE-INSTALL SAFETY BOUNDARY ==="
test -f "$PAYLOAD"
echo "$PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
mapfile -t MEMBERS < <(tar -tzf "$PAYLOAD")
test "${#MEMBERS[@]}" -eq 1
test "${MEMBERS[0]}" = "$RELATIVE"
test "$(sha256sum "$TARGET" | awk '{print $1}')" = "$OLD_SHA"
test "$(sacct -n -P -j 202369 --format=JobIDRaw,State | awk -F'|' '$1 == "202369" {print $2; exit}')" = "FAILED"
test -z "$(squeue -h -n N22-preclosure-check -o '%i')"
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"

echo "=== PRESERVE, DIFF, AND INSTALL ==="
test ! -e "$STAGE"
mkdir -p "$STAGE"
tar -xzf "$PAYLOAD" -C "$STAGE"
STAGED="$STAGE/$RELATIVE"
echo "$NEW_SHA  $STAGED" | sha256sum -c -
diff -u "$TARGET" "$STAGED" || true
test ! -e "$BACKUP"
install -m 0644 "$TARGET" "$BACKUP"
echo "$OLD_SHA  $BACKUP" | sha256sum -c -
TEMPORARY="$TARGET.seq101.tmp"
test ! -e "$TEMPORARY"
install -m 0644 "$STAGED" "$TEMPORARY"
echo "$NEW_SHA  $TEMPORARY" | sha256sum -c -
mv "$TEMPORARY" "$TARGET"
echo "$NEW_SHA  $TARGET" | sha256sum -c -
bash -n "$TARGET"

python - "$TARGET" "$BACKUP" "$RECEIPT" "$OLD_SHA" "$NEW_SHA" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

target, backup, receipt = map(Path, sys.argv[1:4])
old_sha, new_sha = sys.argv[4:6]
payload = {
    'schema': 'nearing2022-numerical-gate-slurm-source-update-v1',
    'mailbox_seq': 101,
    'installed_at': datetime.now(timezone.utc).isoformat(),
    'target': str(target),
    'previous_source_backup': str(backup),
    'previous_sha256': hashlib.sha256(backup.read_bytes()).hexdigest(),
    'installed_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
    'queued_job_id': '202315',
    'queued_job_state_during_update': 'PENDING Dependency',
    'queued_job_spool_changed': False,
    'numerical_evaluator_changed': False,
}
assert payload['previous_sha256'] == old_sha
assert payload['installed_sha256'] == new_sha
receipt.parent.mkdir(parents=True, exist_ok=True)
temporary = receipt.with_suffix(receipt.suffix + '.tmp')
assert not receipt.exists() and not temporary.exists()
temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
temporary.replace(receipt)
print(json.dumps(payload, sort_keys=True))
PY

echo "=== SUBMIT THIRD CPU VALIDATION ATTEMPT ==="
test ! -e "$JOB_RECEIPT"
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
sha256sum "$PAYLOAD" "$TARGET" "$BACKUP" "$RECEIPT" "$JOB_RECEIPT"
