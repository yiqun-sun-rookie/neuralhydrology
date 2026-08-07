#!/bin/bash
# id26-v09-strict seq=10 : watch training job 201718 for up to 100 min (worker dies at 120).
# Read-only. Reports progress, then final accounting if it finishes in this window.
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
REPO=$ROOT/neuralhydrology
D=$REPO/results/26_historical_band_experts/formal_v09
RUN=$D/strict_nesting/R09-NEST-S100
JID=$(cat "$ROOT/train_jobid.txt" 2>/dev/null || echo 201718)

echo "=== WATCHING JOB $JID (max 100 min this round) ==="
SEEN=""
DONE=0
for i in $(seq 1 600); do
  ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
  CUR=$(ls "$RUN" 2>/dev/null | sort | tr '\n' ' ')
  if [ "$CUR" != "$SEEN" ]; then
    echo "[t=$((i*10))s] run_dir: ${CUR:-<empty>}"
    SEEN="$CUR"
  fi
  if [ -z "$ST" ]; then echo "[t=$((i*10))s] job left the queue"; DONE=1; break; fi
  [ $((i % 30)) -eq 0 ] && echo "[t=$((i*10))s] state=$ST  run_dir=${SEEN:-<empty>}"
  sleep 10
done

echo "=== ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%10,JobName%10,NodeList%9,State%12,ExitCode%8,Elapsed%12 2>&1

echo "=== RUN DIR ==="
ls -la "$RUN" 2>&1 | head -15

echo "=== STDOUT (tail 40) ==="
tail -40 "$ROOT/logs/train_${JID}.out" 2>&1

echo "=== STDERR (tail 25) ==="
tail -25 "$ROOT/logs/train_${JID}.err" 2>&1

if [ "$DONE" = "1" ] && [ -f "$RUN/manifest.json" ]; then
  echo "=== MANIFEST VERDICT ==="
  "$HOME/miniconda3/envs/nh_final/bin/python" - <<'PY' 2>&1 | tail -20
import json, pathlib
p = pathlib.Path.home()/"v09_strict/neuralhydrology/results/26_historical_band_experts/formal_v09/strict_nesting/R09-NEST-S100/manifest.json"
m = json.loads(p.read_text(encoding="utf-8"))
for k in ("status","formal_execution","seed","epochs","batch_size","training_samples",
          "optimizer_steps_per_epoch","optimizer_steps_total","checkpoint_epochs",
          "formal_evaluation_observation_reads"):
    print(f"{k:34s} {m.get(k)}")
PY
fi

echo "=== STAGE STATE ==="
for p in "$D/authorizations/A09-NEST-01.authorization.json" "$D/authorizations/A09-NEST-01.consumption.json"; do
  [ -e "$p" ] && echo "present $(basename "$p")" || echo "absent  $(basename "$p")"
done
echo "=== END ==="
