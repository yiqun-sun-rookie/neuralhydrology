#!/bin/bash
set -o pipefail

JOB_ID=217799
ROOT=/data1/home/sunyiq/kalmannet_wrr_lr_boundary_20260901
EXPERIMENT="$ROOT/repo/experiments/optimize_hyper_parameters/validation_lr_boundary_20260831"
FORMAL_LOG="$EXPERIMENT/logs/WRR-HLRB-HPCBRIDGE-20260901-C0_formal.stdout.log"
SMOKE_LOG="$EXPERIMENT/logs/WRR-HLRB-HPCBRIDGE-20260901-C0_smoke_seeded_standard.stdout.log"
RUN_DIR="$EXPERIMENT/runs/formal_gpu/idx0000_lr0p01_hs32_nl1_mult10"

echo "=== TIME_AND_HOST ==="
date -Is
hostname

echo "=== QUEUE ==="
squeue -j "$JOB_ID" -o '%i|%j|%T|%P|%M|%R' || true

echo "=== ACCOUNTING ==="
sacct -X -j "$JOB_ID" -n -P --format=JobID,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList,Reason || true

echo "=== JOB_DETAIL ==="
scontrol show job -o "$JOB_ID" 2>&1 || true

echo "=== SLURM_LOGS ==="
for file in "$ROOT/logs/slurm-$JOB_ID.out" "$ROOT/logs/slurm-$JOB_ID.err"; do
  if [ -f "$file" ]; then
    stat -c '%n|bytes=%s|mtime=%y' "$file"
    tail -n 80 "$file"
  else
    echo "MISSING=$file"
  fi
done

echo "=== INTERNAL_LOGS ==="
for file in "$SMOKE_LOG" "$FORMAL_LOG"; do
  if [ -f "$file" ]; then
    stat -c '%n|bytes=%s|mtime=%y' "$file"
    tail -n 80 "$file"
  else
    echo "MISSING=$file"
  fi
done

echo "=== RUNTIME_AND_REGISTRY ==="
for file in "$EXPERIMENT/hpc_runtime.json" "$EXPERIMENT/registry.csv"; do
  if [ -f "$file" ]; then
    stat -c '%n|bytes=%s|mtime=%y' "$file"
    cat "$file"
  else
    echo "MISSING=$file"
  fi
done

echo "=== FORMAL_ARTIFACTS ==="
for file in "$RUN_DIR/metrics.json" "$EXPERIMENT/bridge_summary.json"; do
  if [ -f "$file" ]; then
    stat -c '%n|bytes=%s|mtime=%y' "$file"
    cat "$file"
  else
    echo "MISSING=$file"
  fi
done

echo "=== CHECKPOINTS ==="
if [ -d "$RUN_DIR/results/checkpoints" ]; then
  find "$RUN_DIR/results/checkpoints" -maxdepth 1 -type f -printf '%f|bytes=%s|mtime=%TY-%Tm-%TdT%TH:%TM:%TS%Tz\n' | sort
else
  echo "MISSING=$RUN_DIR/results/checkpoints"
fi
