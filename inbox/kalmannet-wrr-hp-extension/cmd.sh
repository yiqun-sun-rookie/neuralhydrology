#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
EXP="$ROOT/repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
echo "=== TIME ==="; date -Is
echo "=== ARRAY_STATE ==="
squeue -j 218659 -h -o '%i|%T|%M|%R' 2>&1 | sort || true
echo "=== ACCOUNTING (finished tasks) ==="
sacct -j 218659 -X -n -P --format=JobID,State,ExitCode,Elapsed,End,NodeList 2>/dev/null | grep -vE '\|RUNNING\||\|PENDING\|' || echo "none finished yet"
echo "=== FAULTS ==="
sacct -j 218659 -X -n -P --format=JobID,State,ExitCode,NodeList 2>/dev/null | grep -E '\|(TIMEOUT|FAILED|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo none
echo "=== CELL_METRICS (finished cells) ==="
for f in "$EXP"/runs/formal_seed*_gpu/idx*/cell_metrics.json; do
  [ -f "$f" ] || continue
  python3 - "$f" <<'PY' 2>/dev/null || echo "(raw) $f"
import json,sys
c=json.load(open(sys.argv[1])); v=c.get("validation_scoring",{}); e=c.get("epoch_log_summary",{}) or {}
b=c["combo"]
print(f'{b["role"]:<24} lr={b["lr"]:<6g} hs={b["hidden_size"]:<3} nl={b["num_layers"]} mult={b["in_out_mult"]:<3} seed={b["seed"]} '
      f'M(1-12)={v.get("pooled_mean_leads_1_12_corrected_def")} best_ep={v.get("best_epoch_zero_based")} '
      f'lr@best={e.get("lr_at_best_epoch")} rollbacks={e.get("grad_explosion_rollbacks_total")} stop_ep={e.get("stop_epoch_zero_based")} secs={c.get("train_seconds")}')
PY
done
echo "=== EPOCH_PROGRESS (running cells) ==="
for f in "$EXP"/runs/formal_seed*_gpu/idx*/results/epoch_log.jsonl; do
  [ -f "$f" ] || continue
  cell=$(echo "$f" | sed 's#.*/idx#idx#; s#/results/.*##')
  python3 - "$f" "$cell" <<'PY' 2>/dev/null || echo "$cell epochs=$(wc -l < "$f")"
import json,sys
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
r=rows[-1]; roll=sum(x.get("grad_explosion_rollbacks",0) for x in rows)
best=max((x for x in rows if x.get("improved")), key=lambda x:x["epoch_zero_based"], default=None)
print(f'{sys.argv[2]:<32} ep={len(rows):>3} lr_now={r["lr_used_this_epoch"]:<9g} nse={r["val_screening_nse"]:.4f} '
      f'best_ep={best["epoch_zero_based"] if best else None} no_improve={r["no_improve_epochs"]} rollbacks={roll}')
PY
done
echo "=== NONEMPTY_ERR ==="
for f in "$ROOT"/logs/slurm-*.err; do
  [ -f "$f" ] && [ -s "$f" ] && { echo "--- $(basename "$f")"; tail -n 3 "$f"; } || true
done
echo "(scan done)"
