#!/bin/bash
# seq=57 deploy K1 (Liu-style causal conv embedding on T2) + 7 seed replicas; submit 3 packed jobs.
# Also report ID34 stage-1 progress (job 225539).
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
PAYLOAD=~/hpc_mailbox/payload/id33-transformer-recipe-repair/id33_k1_v01.tar.gz
echo "=== STAMP ==="; date -Iseconds
echo "=== A. IN-FLIGHT GATE (id33 arm jobs only) ==="
INFLIGHT=$(squeue -u "$USER" -h -t RUNNING,CONFIGURING -o "%j" 2>/dev/null | grep -c '^id33_' || true)
echo "id33_in_flight_count=${INFLIGHT}"
[ "${INFLIGHT}" = "0" ] || { echo "REFUSING TO DEPLOY"; exit 1; }
echo "=== B. ID34 STAGE-1 STATUS ==="
sacct -j 225539 -X --format=JobID%10,JobName%14,State%12,ExitCode%8,Elapsed%10,NodeList%8 2>&1 || true
tail -n 5 "$ROOT"/logs/34_path_signature_runoff/stage1-225539.out 2>/dev/null || echo "  (no log yet)"
echo "=== C. EXTRACT ==="
cd "$ROOT" || exit 1
tar -xzf "$PAYLOAD" -C "$ROOT"
sha256sum neuralhydrology/utils/config.py neuralhydrology/modelzoo/recipe_fixed_transformer.py \
          src/transformer_recipe_repair/registry/experiments.csv src/transformer_recipe_repair/scripts/audit_configs.py
echo "k1 configs: $(ls src/transformer_recipe_repair/configs/k1*.yml | wc -l)"
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
echo "=== D. AUDIT ==="
python -m src.transformer_recipe_repair.scripts.audit_configs 2>&1 | tail -3
echo "=== E. UNIT TESTS FOR THE NEW MODULE (cpu, seconds) ==="
python -m pytest test/test_recipe_fixed_transformer.py -q -k conv_embedding 2>&1 | tail -2
echo "=== F. SUBMIT 3 PACKED JOBS ==="
JOBS=""
submit () {
  local OUT J
  OUT=$(sbatch --export=ALL,ARMS="$1" --job-name="id33_k1_$2" src/transformer_recipe_repair/hpc/submit_packed_arms.slurm 2>&1)
  J=$(echo "$OUT" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
  [ -n "$J" ] || { echo "SUBMIT_FAILED $1: $OUT"; return 1; }
  echo "  $2 ($1) -> $J"; JOBS="$JOBS $J"
}
submit "K1 K1_s200 K1_s300" "a" || exit 1
submit "K1_s400 K1_s500 K1_s600" "b" || exit 1
submit "K1_s700 K1_s800" "c" || exit 1
echo "k1_jobs=$JOBS"
sleep 15; squeue -u "$USER" -o "%.10i %.14j %.3t %.8M %.8N %R" 2>&1 | grep -E 'JOBID|id33_k1|id34' || true
