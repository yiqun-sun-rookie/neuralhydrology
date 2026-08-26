#!/bin/bash
# Four-target ladder: settle the smoke test, then launch the formal array if it passed.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
MAILBOX=/data1/home/sunyiq/hpc_mailbox
JID=212898

echo "=== A. HOST ==="
hostname; date -u +%Y-%m-%dT%H:%M:%SZ

echo "=== B. WAIT FOR SMOKE JOB ${JID} (max 25 min) ==="
STATE=""
for i in $(seq 1 150); do
  STATE=$(sacct -j "$JID" -X -n -o State 2>/dev/null | head -1 | awk '{print $1}')
  case "$STATE" in
    RUNNING|PENDING|"") [ $((i % 6)) -eq 0 ] && echo "  t=$((i*10))s state=${STATE:-unknown}"; sleep 10;;
    *) echo "  settled at t=$((i*10))s state=$STATE"; break;;
  esac
done

echo "=== C. SMOKE RESULT ==="
sacct -j "$JID" -X --format=JobID%12,JobName%12,NodeList%10,State%12,ExitCode%8,Elapsed%10 2>&1 || true
echo "--- stdout tail ---"
tail -25 "$ROOT/logs/n4_smoke_${JID}.out" 2>/dev/null || echo "  (none)"
echo "--- stderr tail ---"
tail -10 "$ROOT/logs/n4_smoke_${JID}.err" 2>/dev/null || echo "  (none)"

echo "=== D. SMOKE ARTEFACTS ==="
SMOKE_DIR=$(ls -d "$ROOT/n4_smoke"/*/ 2>/dev/null | head -1)
OK=0
if [ -n "$SMOKE_DIR" ]; then
  echo "  task dir: $(basename "$SMOKE_DIR")"
  N=0
  for f in best_state.pt training_history.csv test_predictions.npz run_identity.json completion_manifest.json; do
    if [ -f "${SMOKE_DIR}${f}" ]; then echo "    ok      $f  ($(stat -c%s "${SMOKE_DIR}${f}") B)"; N=$((N+1)); else echo "    MISSING $f"; fi
  done
  [ "$N" -eq 5 ] && OK=1
  echo "  --- run identity extract ---"
  python - "${SMOKE_DIR}run_identity.json" <<'PYEOF' 2>&1 | sed 's/^/    /'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for k in ("task_id", "target", "condition", "kept_stations", "test_year", "seed"):
    print(k, "=", d.get(k))
rt = d.get("runtime_environment", {})
for k in ("node_name", "graphics_processor_name", "torch_version", "numpy_version"):
    print(k, "=", rt.get(k))
print("training_sample_count =", d.get("training_sample_count"))
print("test_sample_count =", d.get("test_sample_count"))
print("fold_isolation_findings =", d.get("fold_isolation", {}).get("finding_count"))
PYEOF
else
  echo "  no task directory produced"
fi

STATE_OK=0
case "$STATE" in COMPLETED) STATE_OK=1;; esac
echo "  state_ok=$STATE_OK artefacts_ok=$OK"

if [ "$STATE_OK" -ne 1 ] || [ "$OK" -ne 1 ]; then
  echo "=== SMOKE FAILED - NOT SUBMITTING THE ARRAY ==="
  exit 1
fi

echo "=== E. CLEAR THE THROWAWAY SMOKE ROOT ==="
rm -rf "$ROOT/n4_smoke"
[ -e "$ROOT/n4_smoke" ] && { echo "  could not remove"; exit 1; } || echo "  removed"
[ -e "$ROOT/n4_tasks" ] && { echo "  n4_tasks already exists -> stop"; exit 1; } || echo "  n4_tasks absent -> ok"

echo "=== F. SUBMIT THE FORMAL ARRAY (1440 tasks) ==="
cd "$ROOT/repo" || exit 1
sed -i 's/\r$//' scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm
out=$(sbatch scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm 2>&1); echo "$out"
AID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$AID" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "  array job id = $AID"

echo "=== G. QUEUE SNAPSHOT ==="
sleep 20
squeue -u "$USER" -h -o "%.14i %.12j %.9T" 2>/dev/null | head -12 || true
echo "  my queued/running entries: $(squeue -u "$USER" -h -o '%i' 2>/dev/null | wc -l)"
echo "ARRAY_JOB_ID=$AID"

echo "=== H. DONE ==="
