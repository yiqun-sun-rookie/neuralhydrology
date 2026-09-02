#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
EXP="$ROOT/repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
echo "=== TIME ==="; date -Is
echo "=== EPOCH_PROGRESS ==="
for f in "$EXP"/runs/formal_seed*_gpu/idx*/results/epoch_log.jsonl; do
  [ -f "$f" ] || continue
  cell=$(echo "$f" | sed 's#.*/idx#idx#; s#/results/.*##')
  echo "$cell epochs=$(wc -l < "$f") last=$(tail -n 1 "$f" | cut -c1-260)"
done
echo "=== SLURM_OUT_TAILS ==="
for f in "$ROOT"/logs/slurm-*.out; do
  [ -f "$f" ] || continue
  echo "--- $(basename "$f") $(stat -c %s "$f")B"
  grep -aE 'EpochSummary|EarlyStop|FATAL|Traceback|Error|CONDA_FAILED|SHA256_MISMATCH|Launcher\] M\(' "$f" | tail -n 2 || true
done
echo "=== NONEMPTY_ERR ==="
for f in "$ROOT"/logs/slurm-*.err; do
  [ -f "$f" ] && [ -s "$f" ] && { echo "--- $(basename "$f")"; tail -n 4 "$f"; } || true
done
echo "(err scan done)"
