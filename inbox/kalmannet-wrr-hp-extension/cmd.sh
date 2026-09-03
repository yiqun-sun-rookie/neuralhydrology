#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
EXP="$ROOT/repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
echo "=== TIME ==="; date -Is
echo "=== DIVCHECK 219190 ==="
squeue -j 219190 -o '%i|%j|%T|%P|%M|%R|%S' 2>&1 || true
sacct -j 219190 -X -n -P --format=JobID,State,ExitCode,Elapsed,Start,NodeList 2>&1 || true
echo "=== DIVCHECK EPOCHS ==="
f="$EXP/runs/formal_seed43_gpu/idx0017_lr0p05_hs32_nl1_mult10/results/epoch_log.jsonl"
if [ -f "$f" ]; then wc -l < "$f"; tail -n 3 "$f" | cut -c1-240; else echo "not started yet"; fi
echo "=== MAIN ARRAY 218659 ==="
squeue -j 218659 -h -o '%i|%T|%M' 2>&1 | sort || echo "array finished"
echo "=== FINISHED CELLS COUNT ==="
ls -d "$EXP"/runs/formal_seed*_gpu/idx*/cell_metrics.json 2>/dev/null | wc -l
