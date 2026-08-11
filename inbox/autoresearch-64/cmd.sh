#!/bin/bash
set -o pipefail

ROOT=/data1/home/sunyiq/autoresearch64
PYTHON="$ROOT/.venv/bin/python"
RUNS="$ROOT/runs/unified_autoresearch"
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/inbox/autoresearch-64/payload/automatic_rehearsal_source_65b31c82.tar.gz
PAYLOAD_SHA256=9a16c06ca3bf57126d0c538a4ae4ff43619cd5d3b752f9f791ad0281503cbcc2
ATTEMPT="$RUNS/automatic_rehearsal_8x3_20260811_seq57"
SOURCE8="$RUNS/hbv_lite_8_hpc_smoke_20260810_seq36/source_8"
PACKAGE8="$RUNS/hbv_lite_8_hpc_smoke_20260810_seq36/packages_8"
SLURM=/data1/home/sunyiq/hpc_mailbox/inbox/autoresearch-64/automatic_rehearsal_seq57.slurm

echo "=== READ-ONLY PREFLIGHT ==="
test -x "$PYTHON" || { echo "HOLD missing_python=$PYTHON"; exit 10; }
test -f "$PAYLOAD" || { echo "HOLD missing_payload=$PAYLOAD"; exit 10; }
ACTUAL_PAYLOAD_SHA256=$(sha256sum "$PAYLOAD" | awk '{print $1}')
test "$ACTUAL_PAYLOAD_SHA256" = "$PAYLOAD_SHA256" || {
  echo "HOLD payload_hash expected=$PAYLOAD_SHA256 actual=$ACTUAL_PAYLOAD_SHA256"
  exit 10
}
test -f "$SOURCE8/SOURCE_MANIFEST.json" || { echo "HOLD missing_source_manifest"; exit 10; }
test -f "$PACKAGE8/PACKAGE_MANIFEST.json" || { echo "HOLD missing_package_manifest"; exit 10; }
test "$(sha256sum "$PACKAGE8/PACKAGE_MANIFEST.json" | awk '{print $1}')" = \
  "f877e7932d33dc2db35f25026b425dd69755dda1338649020db40a1f4d5b38ea" || {
  echo "HOLD package_manifest_hash_mismatch"
  exit 10
}
test ! -e "$ATTEMPT" || { echo "HOLD output_already_exists=$ATTEMPT"; exit 10; }
"$PYTHON" - "$SOURCE8/SOURCE_MANIFEST.json" "$PACKAGE8/PACKAGE_MANIFEST.json" <<'PY'
import json
import sys
from pathlib import Path

source = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
package = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert source["date_bounds"] == ["1999-10-01", "2008-09-30"]
assert source["sealed_final_evaluation_present"] is False
assert len(package["basins"]) == 8 and len(set(package["basins"])) == 8
assert package["protocols"] == ["forward", "reverse"]
print("preflight=pass basins=8 protocols=2 sealed_final_evaluation_present=false")
PY

echo "=== SUBMIT THREE-CANDIDATE REHEARSAL ==="
JID=$(sbatch --parsable "$SLURM" 2>&1)
case "$JID" in
  ''|*[!0-9]*) echo "HOLD sbatch_failed=$JID"; exit 11 ;;
esac
echo "jobid=$JID"

echo "=== WAIT FOR EXACT JOB ==="
for i in $(seq 1 270); do
  STATE=$(squeue -j "$JID" -h -o '%T' 2>/dev/null | head -1)
  [ -z "$STATE" ] && break
  [ $((i % 6)) -eq 0 ] && echo "t=$((i * 10))s state=$STATE"
  sleep 10
done

echo "=== JOB ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%12,JobName%20,NodeList%9,State%14,ExitCode%8,Elapsed%10
FINAL_STATE=$(sacct -j "$JID" -X -n -o State | head -1 | xargs)
FINAL_EXIT=$(sacct -j "$JID" -X -n -o ExitCode | head -1 | xargs)
echo "final_state=$FINAL_STATE final_exit=$FINAL_EXIT"

echo "=== EXACT JOB LOGS ==="
tail -80 "/data1/home/sunyiq/hpc_mailbox/outbox/slurm_${JID}.out" 2>/dev/null || true
tail -80 "/data1/home/sunyiq/hpc_mailbox/outbox/slurm_${JID}.err" 2>/dev/null || true
echo "=== STABLE ATTEMPT OUTPUT ==="
tail -160 "$ATTEMPT/evidence/JOB_STDOUT.txt" 2>/dev/null || true
echo "=== STABLE ATTEMPT ERROR ==="
tail -120 "$ATTEMPT/evidence/JOB_STDERR.txt" 2>/dev/null || true

if [ "$FINAL_STATE" != "COMPLETED" ] || [ "$FINAL_EXIT" != "0:0" ]; then
  echo "HOLD job_failed_or_unfinished jobid=$JID state=$FINAL_STATE exit=$FINAL_EXIT"
  exit 12
fi

echo "=== EVIDENCE STATUS ==="
for path in \
  "$ATTEMPT/evidence/FULL_GATE.json" \
  "$ATTEMPT/evidence/PACKAGE_GATE.json" \
  "$ATTEMPT/rehearsal/PROPOSAL_REGISTRY.json" \
  "$ATTEMPT/rehearsal/REHEARSAL_SUMMARY.json" \
  "$ATTEMPT/evidence/REHEARSAL_EVIDENCE.json" \
  "$ATTEMPT/evidence/MANIFEST.sha256"; do
  test -f "$path" || { echo "HOLD missing=$path"; exit 13; }
  stat -c '%n|bytes=%s|mtime=%y' "$path"
done
(cd "$ATTEMPT" && sha256sum -c evidence/MANIFEST.sha256 >/dev/null)
echo "manifest_check=ok entries=$(wc -l < "$ATTEMPT/evidence/MANIFEST.sha256")"
"$PYTHON" - "$ATTEMPT/evidence/REHEARSAL_EVIDENCE.json" <<'PY'
import json
import sys
from pathlib import Path

value = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(json.dumps({
    "experiment_id": value["experiment_id"],
    "job_id": value["job_id"],
    "full_test_gate": value["full_test_gate"],
    "candidate_count": value["candidate_count"],
    "runtime_count": value["runtime_count"],
    "process_exit_codes": [row["process_exit_code"] for row in value["runtimes"]],
    "normalized_exit_codes": [row["normalized_exit_code"] for row in value["runtimes"]],
    "required_outputs_complete": [row["required_outputs_complete"] for row in value["runtimes"]],
    "independently_counted_denials": value["independently_counted_denials"],
    "independently_recomputed_median_mean_nse": value["independently_recomputed_median_mean_nse"],
    "recommended_candidate_id": value["recommended_candidate_id"],
}, sort_keys=True))
PY
echo "GO jobid=$JID"
