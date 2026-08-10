#!/bin/bash
# ID29 seq=88: install the safety-only immutable-output evaluator revision before pending gate job 202315 can start; keep candidate manifest 202293 held.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
PAYLOAD="$HOME/hpc_mailbox/inbox/id29-nearing2022-da/payload.tar.gz"
EVALUATOR="$IDEA/scripts/evaluate_full_reproduction.py"
PROVENANCE="$IDEA/reference/numerical_gate_source_update.json"
BACKUP="$ROOT/closure_20260810/provenance/evaluate_full_reproduction_pre_immutability_patch_f6548d2c.py"
RECEIPT="$ROOT/closure_20260810/provenance/numerical_gate_source_update_receipt.json"
GATE_OUTPUT="$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
GATE_DETAILS="$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
PAYLOAD_SHA=ac999e267e1fc20257ea3f4d7467a7653d35c20ba8b5b0722b4d4e7104c86acd
OLD_SHA=f6548d2c1935093266ddbfcced8f66b5a540a02ce4e52216001526a34d6b4082
NEW_SHA=820ce3cb543270edd439afcd5b26d21de8867c2560d5be4addc86be80c098276
PROVENANCE_SHA=31737312ed6dd35097670ddf20b34af09cf255894ec104600a021e271b3e423e

echo "=== PRE-INSTALL SAFETY BOUNDARY ==="
test -f "$PAYLOAD"
echo "$PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
mapfile -t PAYLOAD_MEMBERS < <(tar -tzf "$PAYLOAD")
test "${#PAYLOAD_MEMBERS[@]}" -eq 2
test "${PAYLOAD_MEMBERS[0]}" = "src/29_nearing2022_da_ar/scripts/evaluate_full_reproduction.py"
test "${PAYLOAD_MEMBERS[1]}" = "src/29_nearing2022_da_ar/reference/numerical_gate_source_update.json"
GATE_STATE=$(squeue -h -j 202315 -o '%i|%T|%r|%j')
echo "gate_state_before=$GATE_STATE"
test "$GATE_STATE" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$GATE_OUTPUT"
test ! -e "$GATE_DETAILS"
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"

echo "=== PRESERVE AND INSTALL ==="
mkdir -p "$(dirname "$BACKUP")"
CURRENT_SHA=$(sha256sum "$EVALUATOR" | awk '{print $1}')
case "$CURRENT_SHA" in
  "$OLD_SHA")
    if [ -e "$BACKUP" ]; then
      echo "$OLD_SHA  $BACKUP" | sha256sum -c -
    else
      install -m 0644 "$EVALUATOR" "$BACKUP"
      echo "$OLD_SHA  $BACKUP" | sha256sum -c -
    fi
    tar -xzf "$PAYLOAD" -C "$ROOT"
    ;;
  "$NEW_SHA")
    echo "$OLD_SHA  $BACKUP" | sha256sum -c -
    echo "install_status=ALREADY_INSTALLED"
    ;;
  *)
    echo "Unexpected evaluator SHA-256 before install: $CURRENT_SHA" >&2
    exit 3
    ;;
esac

echo "$NEW_SHA  $EVALUATOR" | sha256sum -c -
echo "$PROVENANCE_SHA  $PROVENANCE" | sha256sum -c -
python -m py_compile "$EVALUATOR"
python - "$PROVENANCE" "$BACKUP" "$RECEIPT" "$OLD_SHA" "$NEW_SHA" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

provenance_path, backup_path, receipt_path = map(Path, sys.argv[1:4])
old_sha, new_sha = sys.argv[4:6]
provenance = json.loads(provenance_path.read_text(encoding='utf-8'))
assert provenance['schema'] == 'nearing2022-numerical-gate-source-update-v1'
assert provenance['slurm_job_id'] == '202315'
assert provenance['numerical_logic_changed'] is False
assert provenance['submitted_evaluator_sha256'] == old_sha
assert provenance['replacement_evaluator_sha256'] == new_sha
payload = {
    'schema': 'nearing2022-numerical-gate-source-update-receipt-v1',
    'mailbox_seq': 88,
    'slurm_job_id': '202315',
    'installed_at': datetime.now(timezone.utc).isoformat(),
    'old_evaluator_backup': str(backup_path),
    'old_evaluator_sha256': hashlib.sha256(backup_path.read_bytes()).hexdigest(),
    'installed_evaluator_sha256': new_sha,
    'numerical_logic_changed': False,
}
receipt_path.parent.mkdir(parents=True, exist_ok=True)
if receipt_path.exists():
    existing = json.loads(receipt_path.read_text(encoding='utf-8'))
    for key in payload.keys() - {'installed_at'}:
        assert existing[key] == payload[key]
else:
    temporary = receipt_path.with_suffix(receipt_path.suffix + '.tmp')
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    temporary.replace(receipt_path)
print(json.dumps(json.loads(receipt_path.read_text(encoding='utf-8')), sort_keys=True))
PY

echo "=== POST-INSTALL SAFETY BOUNDARY ==="
GATE_STATE=$(squeue -h -j 202315 -o '%i|%T|%r|%j')
echo "gate_state_after=$GATE_STATE"
test "$GATE_STATE" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$GATE_OUTPUT"
test ! -e "$GATE_DETAILS"
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
sha256sum "$EVALUATOR" "$PROVENANCE" "$BACKUP" "$RECEIPT"
