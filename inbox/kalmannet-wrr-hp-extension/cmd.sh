#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
EXP="$ROOT/repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
echo "=== TIME ==="; date -Is
echo "=== JOBS ==="
squeue -j 218659,219190 -h -o '%i|%T|%M|%R' 2>&1 | sort || echo "all finished"
echo "=== ACCOUNTING (terminal states only) ==="
sacct -j 218659,219190 -X -n -P --format=JobID,State,ExitCode,Elapsed,End 2>/dev/null | grep -vE '\|(RUNNING|PENDING)\|' | sort || true
echo "=== FAULTS ==="
sacct -j 218659,219190 -X -n -P --format=JobID,State,ExitCode,NodeList 2>/dev/null | grep -E '\|(TIMEOUT|FAILED|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo none
echo "=== ALL CELL METRICS ==="
for f in "$EXP"/runs/formal_seed*_gpu/idx*/cell_metrics.json; do
  [ -f "$f" ] || continue
  python3 - "$f" <<'PY' 2>/dev/null || echo "(unreadable) $f"
import json,sys
c=json.load(open(sys.argv[1])); v=c.get("validation_scoring",{}); e=c.get("epoch_log_summary",{}) or {}; b=c["combo"]
print(f'{b["index"]:>2} {b["role"]:<24} lr={b["lr"]:<6g} hs={b["hidden_size"]:<3} nl={b["num_layers"]} mult={b["in_out_mult"]:<3} seed={b["seed"]} '
      f'M={v.get("pooled_mean_leads_1_12_corrected_def")} best_ep={v.get("best_epoch_zero_based")} lr@best={e.get("lr_at_best_epoch")} '
      f'roll={e.get("grad_explosion_rollbacks_total")} stop_ep={e.get("stop_epoch_zero_based")}')
PY
done
echo "=== STILL-RUNNING PROGRESS ==="
for f in "$EXP"/runs/formal_seed*_gpu/idx*/results/epoch_log.jsonl; do
  d=$(dirname "$(dirname "$f")"); [ -f "$d/cell_metrics.json" ] && continue
  cell=$(echo "$f" | sed 's#.*/idx#idx#; s#/results/.*##')
  python3 - "$f" "$cell" <<'PY' 2>/dev/null || echo "$cell ep=$(wc -l < "$f")"
import json,sys
r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
last=r[-1]; roll=sum(x.get("grad_explosion_rollbacks",0) for x in r)
best=max((x for x in r if x.get("improved")), key=lambda x:x["epoch_zero_based"], default=None)
print(f'{sys.argv[2]:<32} ep={len(r):>3} lr_now={last["lr_used_this_epoch"]:<11g} nse={last["val_screening_nse"]:.4f} best_ep={best["epoch_zero_based"] if best else None} no_improve={last["no_improve_epochs"]} roll={roll}')
PY
done
echo "(done)"
