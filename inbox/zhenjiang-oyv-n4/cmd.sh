#!/bin/bash
# Four-target ladder: short status check. Submits the formal array only if the
# smoke test has already completed cleanly. Deliberately does not wait in a long
# loop: a worker that waits can be killed by a runner restart, and the truncated
# result then blocks the sequence number from being retried.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
JID=212898

echo "=== A. HOST ==="
hostname; date -u +%Y-%m-%dT%H:%M:%SZ

echo "=== B. SMOKE JOB ${JID} ==="
sacct -j "$JID" -X --format=JobID%12,JobName%12,NodeList%10,State%12,ExitCode%8,Elapsed%10 2>&1 | head -4 || true
STATE=$(sacct -j "$JID" -X -n -o State 2>/dev/null | head -1 | awk '{print $1}')
echo "  state=${STATE:-unknown}"
if [ "$STATE" = "PENDING" ]; then
  echo "  reason: $(squeue -j "$JID" -h -o '%r' 2>/dev/null)"
  echo "  est start: $(squeue -j "$JID" -h --start -o '%S' 2>/dev/null)"
fi

echo "=== C. PARTITION LOAD ==="
sinfo -p hgpu2p -o "%.10P %.6a %.26N %.10T" 2>&1 | head -8 || true
echo "  my entries in queue: $(squeue -u "$USER" -h -o '%i' 2>/dev/null | wc -l)"
echo "  total queue length : $(squeue -h -o '%i' 2>/dev/null | wc -l)"

if [ "$STATE" != "COMPLETED" ]; then
  echo "=== SMOKE NOT COMPLETE YET - NOTHING SUBMITTED ==="
  echo "STATUS=WAITING"
  exit 0
fi

echo "=== D. SMOKE LOG ==="
tail -20 "$ROOT/logs/n4_smoke_${JID}.out" 2>/dev/null || echo "  (none)"

echo "=== E. SMOKE ARTEFACTS ==="
SMOKE_DIR=$(ls -d "$ROOT/n4_smoke"/*/ 2>/dev/null | head -1)
OK=0
if [ -n "$SMOKE_DIR" ]; then
  echo "  task dir: $(basename "$SMOKE_DIR")"
  N=0
  for f in best_state.pt training_history.csv test_predictions.npz run_identity.json completion_manifest.json; do
    if [ -f "${SMOKE_DIR}${f}" ]; then echo "    ok      $f  ($(stat -c%s "${SMOKE_DIR}${f}") B)"; N=$((N+1)); else echo "    MISSING $f"; fi
  done
  [ "$N" -eq 5 ] && OK=1
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
if [ "$OK" -ne 1 ]; then
  echo "=== ARTEFACTS INCOMPLETE - NOTHING SUBMITTED ==="
  echo "STATUS=SMOKE_FAILED"
  exit 1
fi

echo "=== F. CLEAR THROWAWAY ROOT AND SUBMIT THE ARRAY ==="
rm -rf "$ROOT/n4_smoke"
[ -e "$ROOT/n4_smoke" ] && { echo "  could not remove"; exit 1; } || echo "  n4_smoke removed"
[ -e "$ROOT/n4_tasks" ] && { echo "  n4_tasks already exists -> stop"; exit 1; } || echo "  n4_tasks absent -> ok"

cd "$ROOT/repo" || exit 1
sed -i 's/\r$//' scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm
out=$(sbatch scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm 2>&1); echo "$out"
AID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$AID" ] || { echo "SUBMIT_FAILED"; echo "STATUS=SUBMIT_FAILED"; exit 1; }
echo "  array job id = $AID"
sleep 15
squeue -u "$USER" -h -o "%.16i %.12j %.9T" 2>/dev/null | head -8 || true
echo "ARRAY_JOB_ID=$AID"
echo "STATUS=ARRAY_SUBMITTED"

echo "=== G. DONE ==="
