#!/bin/bash
# seq=37 rescore v02: the frequency entry is {'xr': Dataset, ...}, not the Dataset itself.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
PAYLOAD=~/hpc_mailbox/payload/id33-transformer-recipe-repair/id33_rescore_v02.tar.gz
echo "=== STAMP ==="; date -Iseconds
UNSAFE=$(squeue -u "$USER" -h -t RUNNING,CONFIGURING -o "%j" 2>/dev/null | grep '^id33_' | grep -vE '^id33_repro_(det|ctl)$' | wc -l)
echo "unsafe_id33_in_flight=${UNSAFE}"
[ "${UNSAFE}" = "0" ] || { echo "REFUSING"; exit 1; }
cd "$ROOT" || exit 1
tar -xzf "$PAYLOAD" -C "$ROOT"
sha256sum src/transformer_recipe_repair/scripts/rescore_common_window.py
OUT=$(sbatch src/transformer_recipe_repair/hpc/submit_rescore.slurm 2>&1); echo "$OUT"
J=$(echo "$OUT" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$J" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "rescore_job=$J"
echo "=== WAIT (max 6 min) ==="
for i in $(seq 1 36); do
  ST=$(sacct -j "$J" -X -n --format=State 2>/dev/null | head -1 | tr -d ' ')
  case "$ST" in RUNNING|PENDING|"") sleep 10;; *) echo "state=$ST after ${i}0s"; break;; esac
done
sacct -j "$J" -X --format=JobID%10,State%12,ExitCode%8,Elapsed%10 2>&1 || true
echo "=== OUTPUT ==="
cat "$ROOT/logs/33_transformer_recipe_repair/rescore-${J}.out" 2>&1 | tail -45 || true
echo "-- stderr --"
tail -n 12 "$ROOT/logs/33_transformer_recipe_repair/rescore-${J}.err" 2>&1 || true
