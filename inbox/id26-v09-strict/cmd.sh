#!/bin/bash
# id26-v09-strict seq=21 : short status query, no waiting loop.
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
CODE=$ROOT/codetest/neuralhydrology
PY=$HOME/miniconda3/envs/nh_final/bin/python
JID=$(cat "$ROOT/suite_jobid.txt" 2>/dev/null || echo 201861)
echo "=== JOB ==="
sacct -j "$JID" -X --format=JobID%10,State%12,ExitCode%8,Elapsed%12 2>&1 | head -4
echo "=== DIRS ==="
find "$CODE/results/26_historical_band_experts/formal_v09" -maxdepth 2 -name 'seed_*' 2>/dev/null | sed 's|.*formal_v09/||' | sort
echo "=== LOG TAIL ==="
tail -20 "$ROOT/logs/suite_${JID}.out" 2>&1
tail -10 "$ROOT/logs/suite_${JID}.err" 2>&1
echo "=== ARMS ==="
cd "$CODE"
$PY - <<'PY' 2>&1 | tail -20
import json, pathlib
base = pathlib.Path.cwd()/"results/26_historical_band_experts/formal_v09"
for family in ("classic", "capacity", "continuous"):
    m = base/family/"seed_100"/"manifest.json"
    if not m.is_file():
        print(f"{family:11s}: not finished"); continue
    d = json.loads(m.read_text(encoding="utf-8"))
    print(f"{family:11s}: {d['status']} params={d['trainable_parameters']} steps={d['optimizer_steps_total']} "
          f"wake={d.get('history_encoder_first_nonzero_gradient_step')} "
          f"loss {d['epoch_trace'][0]['mean_training_loss']:.5f} -> {d['epoch_trace'][-1]['mean_training_loss']:.5f}")
    if d.get("history_health_trace"):
        h = d["history_health_trace"][0]
        print(f"             step1 gate_abs_max={h['gate_absolute_maximum']} enc_grad={h['history_encoder_gradient_norm']} "
              f"gate_grad={h['gate_gradient_norm']:.6g}")
PY
echo "=== END ==="
