#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
EXP="$ROOT/repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
RD="$EXP/runs/formal_seed42_gpu/idx0005_lr0p05_hs32_nl1_mult10"
echo "=== FAILED_CELL_ERROR ==="
sed -n '/\[Fail\] idx=5/,/^$/p' "$ROOT/logs/slurm-218659_5.out" | head -40 || true
echo "--- error.txt ---"
cat "$RD/error.txt" 2>&1 | tail -25 || true
echo "--- FAILED tag ---"
cat "$RD/FAILED" 2>&1 || true
echo "=== EPOCH_TRAIL (all epochs of the failed cell) ==="
cat "$RD/results/epoch_log.jsonl" 2>/dev/null | python3 -c "
import json,sys
for l in sys.stdin:
    r=json.loads(l)
    print(f'ep={r[\"epoch_zero_based\"]:>3} lr={r[\"lr_used_this_epoch\"]:<11g} train={r[\"train_bp_loss\"]:.6g} val={r[\"val_bp_loss\"]:.6g} nse={r[\"val_screening_nse\"]:.4f} rollbacks={r[\"grad_explosion_rollbacks\"]:>4} nan={r[\"nan_inf_skips\"]:>3} improved={r[\"improved\"]}')
" 2>&1 | tail -15 || true
echo "=== ROLLBACK/NAN LINES IN LOG ==="
grep -acE 'Grad explosion|NaN/Inf loss|Exceeded max NaN' "$ROOT/logs/slurm-218659_5.out" || true
grep -aE 'Exceeded max NaN|RuntimeError|Traceback' "$ROOT/logs/slurm-218659_5.out" | head -5 || true
echo "=== ARRAY_NOW ==="
squeue -j 218659 -h -o '%i|%T|%M' 2>&1 | sort || echo "all done"
