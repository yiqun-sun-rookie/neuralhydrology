#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
EXP="$ROOT/repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
echo "=== TIME ==="; date -Is
echo "=== MY JOBS ==="; squeue -j 220434,220454,220535 -h -o '%i|%T|%M|%R' 2>&1 | sort || echo "none queued/running"
echo "=== FAULTS ==="; sacct -j 220434,220454,220535 -X -n -P --format=JobID,State,ExitCode,NodeList 2>/dev/null | grep -E '\|(TIMEOUT|FAILED|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo none
echo "=== SIZE LADDER (all cells at lr 0.01, mult 10) ==="
for f in "$EXP"/runs/formal_seed*_gpu/idx*/cell_metrics.json; do
  [ -f "$f" ] || continue
  python3 - "$f" <<'PY' 2>/dev/null || true
import json,sys
c=json.load(open(sys.argv[1])); b=c["combo"]; v=c["validation_scoring"]; e=c.get("epoch_log_summary",{}) or {}
if b["lr"]==0.01 and b["in_out_mult"]==10 and b["num_layers"]==1:
    print(f'hs={b["hidden_size"]:<3} seed={b["seed"]} M={v["pooled_mean_leads_1_12_corrected_def"]:.6f} best_ep={v["best_epoch_zero_based"]:<3} stop_ep={e.get("stop_epoch_zero_based")} roll={e.get("grad_explosion_rollbacks_total")}')
PY
done
echo "=== STILL RUNNING (18-25) ==="
for i in 18 19 20 21 22 23 24 25; do
  d=$(ls -d "$EXP"/runs/formal_seed*_gpu/idx00${i}_* 2>/dev/null | head -1)
  [ -z "$d" ] && { echo "idx$i: not started"; continue; }
  [ -f "$d/cell_metrics.json" ] && continue
  f="$d/results/epoch_log.jsonl"
  if [ -f "$f" ]; then
    python3 - "$f" "$i" <<'PY' 2>/dev/null || echo "idx$i ep=$(wc -l < "$f")"
import json,sys
r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; last=r[-1]
best=max((x for x in r if x.get("improved")), key=lambda x:x["epoch_zero_based"], default=None)
print(f'idx{sys.argv[2]:<3} RUNNING ep={len(r):>3} nse={last["val_screening_nse"]:.4f} best_ep={best["epoch_zero_based"] if best else None} no_improve={last["no_improve_epochs"]} roll={sum(x.get("grad_explosion_rollbacks",0) for x in r)}')
PY
  else echo "idx$i: allocated, no epochs yet"; fi
done
echo "(done)"
