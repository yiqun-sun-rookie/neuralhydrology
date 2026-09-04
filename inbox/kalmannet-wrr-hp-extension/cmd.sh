#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
EXP="$ROOT/repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
echo "=== TIME ==="; date -Is
echo "=== JOBS ==="
squeue -j 220434,220454 -h -o '%i|%T|%M|%R' 2>&1 | sort || echo "none queued/running"
echo "=== FAULTS ==="
sacct -j 220434,220454 -X -n -P --format=JobID,State,ExitCode,NodeList 2>/dev/null | grep -E '\|(TIMEOUT|FAILED|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo none
echo "=== NEW CELLS (18-22) ==="
for i in 18 19 20 21 22; do
  d=$(ls -d "$EXP"/runs/formal_seed*_gpu/idx00${i}_* 2>/dev/null | head -1)
  if [ -z "$d" ]; then echo "idx$i: not started"; continue; fi
  if [ -f "$d/cell_metrics.json" ]; then
    python3 - "$d/cell_metrics.json" <<'PY' 2>/dev/null || echo "idx$i done (unreadable)"
import json,sys
c=json.load(open(sys.argv[1])); v=c["validation_scoring"]; e=c.get("epoch_log_summary",{}) or {}; b=c["combo"]
print(f'idx{b["index"]:<3}{b["role"]:<28}hs={b["hidden_size"]:<3}seed={b["seed"]} DONE M={v["pooled_mean_leads_1_12_corrected_def"]} best_ep={v["best_epoch_zero_based"]} roll={e.get("grad_explosion_rollbacks_total")} stop_ep={e.get("stop_epoch_zero_based")}')
PY
  else
    f="$d/results/epoch_log.jsonl"
    if [ -f "$f" ]; then
      python3 - "$f" "$i" <<'PY' 2>/dev/null || echo "idx$i ep=$(wc -l < "$f")"
import json,sys
r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; last=r[-1]
best=max((x for x in r if x.get("improved")), key=lambda x:x["epoch_zero_based"], default=None)
print(f'idx{sys.argv[2]:<3}RUNNING  ep={len(r):>3} lr_now={last["lr_used_this_epoch"]:<11g} nse={last["val_screening_nse"]:.4f} best_ep={best["epoch_zero_based"] if best else None} no_improve={last["no_improve_epochs"]} roll={sum(x.get("grad_explosion_rollbacks",0) for x in r)}')
PY
    else echo "idx$i: allocated, no epochs yet"; fi
  fi
done
echo "(done)"
