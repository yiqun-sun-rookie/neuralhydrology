#!/bin/bash
# seq=59 ID34 stage-1 v02: fix the (T,1) shape bug; C4 train_results.p already exists so the job skips evaluation.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
tar -xzf ~/hpc_mailbox/payload/id33-transformer-recipe-repair/id34_stage1_v02.tar.gz -C "$ROOT"
sha256sum src/path_signature_runoff/scripts/stage1_residual_diagnostic.py
C4=$(ls -d results/33_transformer_recipe_repair/C4/*_2026_0909_* | tail -1)
ls -la "$C4/train/model_epoch030/train_results.p" 2>&1
OUT=$(sbatch --export=ALL,C4_RUN="$C4" src/path_signature_runoff/hpc/submit_stage1.slurm 2>&1); echo "$OUT"
J=$(echo "$OUT" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true); [ -n "$J" ] || exit 1
echo "stage1_job=$J"
echo "=== WAIT (max 25 min) ==="
for i in $(seq 1 150); do
  ST=$(sacct -j "$J" -X -n --format=State 2>/dev/null | head -1 | tr -d ' ')
  case "$ST" in RUNNING|PENDING|"") sleep 10;; *) echo "state=$ST after ${i}0s"; break;; esac
done
sacct -j "$J" -X --format=JobID%10,State%12,ExitCode%8,Elapsed%10 2>&1
echo "=== REPORT ==="
R=results/34_path_signature_runoff/_reports/stage1_residual_diagnostic.json
[ -f "$R" ] && cat "$R" || { echo "NO REPORT"; grep -vE 'Evaluation:' logs/34_path_signature_runoff/stage1-$J.out | tail -25; tail -n 15 logs/34_path_signature_runoff/stage1-$J.err; }
