#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
EXP="$ROOT/repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
JOB_ID=218659
echo "=== TIME_AND_HOST ==="; date -Is; hostname
echo "=== QUEUE (job $JOB_ID) ==="
squeue -j "$JOB_ID" -o '%i|%j|%T|%P|%M|%l|%R' 2>&1 || true
echo "=== ACCOUNTING ==="
sacct -j "$JOB_ID" -X -n -P --format=JobID,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList 2>&1 || true
echo "=== FAULTS (never truncated) ==="
sacct -j "$JOB_ID" -X -n -P --format=JobID,State,ExitCode,NodeList,Elapsed 2>/dev/null | grep -E '\|(TIMEOUT|FAILED|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo none
echo "=== REGISTRY ==="
cat "$EXP/registry.csv" 2>&1 || true
echo "=== CELL_METRICS ==="
for f in "$EXP"/runs/formal_seed*_gpu/idx*/cell_metrics.json; do
  [ -f "$f" ] || continue
  echo "--- $f"
  python3 - "$f" <<'PY' 2>/dev/null || cat "$f" | head -40
import json, sys
c = json.load(open(sys.argv[1]))
vs = c.get("validation_scoring", {}); el = c.get("epoch_log_summary", {})
print(json.dumps({"run_id": c["run_id"], "combo": c["combo"], "train_seconds": c.get("train_seconds"),
  "M_leads_1_12": vs.get("pooled_mean_leads_1_12_corrected_def"), "M_slots_0_11": vs.get("pooled_mean_slots_0_11_current_def"),
  "best_epoch": vs.get("best_epoch_zero_based"), "lr_at_best": el.get("lr_at_best_epoch"), "rollbacks": el.get("grad_explosion_rollbacks_total"),
  "stop_epoch": el.get("stop_epoch_zero_based")}))
PY
done
echo "=== EPOCH_PROGRESS (last line of each epoch_log) ==="
for f in "$EXP"/runs/formal_seed*_gpu/idx*/results/epoch_log.jsonl; do
  [ -f "$f" ] || continue
  echo "--- $f"; tail -n 1 "$f"
done
echo "=== SLURM_LOG_TAILS ==="
for f in "$ROOT"/logs/slurm-*.out; do
  [ -f "$f" ] || continue
  echo "--- $f ($(stat -c %s "$f") bytes)"; grep -E 'EpochSummary|EarlyStop|Done|Fail|FATAL|Traceback|Error|SHA256|Launcher\] cell' "$f" | tail -n 4 || true
done
for f in "$ROOT"/logs/slurm-*.err; do
  [ -f "$f" ] && [ -s "$f" ] && { echo "--- $f"; tail -n 5 "$f"; } || true
done
