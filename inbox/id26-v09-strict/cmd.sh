#!/bin/bash
# id26-v09-strict seq=16 : watch the seed-100 three-arm suite (job in suite_jobid.txt).
# Read-only. Caps at 100 min because the mailbox worker is killed at 120.
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
CODE=$ROOT/codetest/neuralhydrology
PY=$HOME/miniconda3/envs/nh_final/bin/python
JID=$(cat "$ROOT/suite_jobid.txt" 2>/dev/null || echo 201861)

echo "=== WATCHING SUITE $JID (cap 100 min) ==="
SEEN=""
for i in $(seq 1 600); do
  ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
  CUR=$(find "$CODE/results/26_historical_band_experts/formal_v09" -maxdepth 2 -name 'seed_*' -printf '%f@%h\n' 2>/dev/null | sed 's|.*/||' | sort | tr '\n' ' ')
  if [ "$CUR" != "$SEEN" ]; then echo "[t=$((i*10))s] dirs: ${CUR:-<none>}"; SEEN="$CUR"; fi
  [ -z "$ST" ] && { echo "[t=$((i*10))s] job left the queue"; break; }
  [ $((i % 30)) -eq 0 ] && echo "[t=$((i*10))s] state=$ST"
  sleep 10
done

echo "=== ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%10,JobName%10,NodeList%9,State%12,ExitCode%8,Elapsed%12 2>&1

echo "=== SUITE STDOUT (tail 45) ==="
tail -45 "$ROOT/logs/suite_${JID}.out" 2>&1
echo "=== SUITE STDERR (tail 25) ==="
tail -25 "$ROOT/logs/suite_${JID}.err" 2>&1

echo "=== PROGRESS ==="
cd "$CODE"
$PY - <<'PY' 2>&1 | tail -40
import json, pathlib, sys
sys.path.insert(0, "src/26_historical_band_experts")
from run_formal_training_v09 import scan_progress_v09
from train_formal_v09 import load_run_order_v09
root = pathlib.Path.cwd()
specs = load_run_order_v09("src/26_historical_band_experts/configs/formal_v09_run_order.json")
try:
    p = scan_progress_v09(root, specs)
    print("completed:", p["completed"])
    print("dirty    :", p["dirty"])
    print("pending  :", len(p["pending"]))
except Exception as exc:
    print("scan error:", exc)

base = root/"results/26_historical_band_experts/formal_v09"
for family, seed in (("classic", 100), ("capacity", 100), ("continuous", 100)):
    m = base/family/f"seed_{seed}"/"manifest.json"
    if not m.is_file():
        print(f"{family:11s} seed{seed}: not finished")
        continue
    d = json.loads(m.read_text(encoding="utf-8"))
    print(f"{family:11s} seed{seed}: status={d['status']} params={d['trainable_parameters']} "
          f"steps={d['optimizer_steps_total']} wake={d.get('history_encoder_first_nonzero_gradient_step')} "
          f"loss_ep1={d['epoch_trace'][0]['mean_training_loss']:.5f} "
          f"loss_ep30={d['epoch_trace'][-1]['mean_training_loss']:.5f}")
    if d.get("history_health_trace"):
        h = d["history_health_trace"][0]
        print(f"             step1 gate_abs_max={h['gate_absolute_maximum']} "
              f"enc_grad={h['history_encoder_gradient_norm']} gate_grad={h['gate_gradient_norm']:.6g}")
PY
echo "=== END ==="
