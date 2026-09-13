#!/bin/bash
# seq=56 ID34 stage 1: deploy signature diagnostic, evaluate C4 on its training period, run the
# residual test. Lives in the ID33 landing zone because it reads ID33's C4 run; writes only under
# results/34_* and logs/34_* plus an additive train/ folder inside C4's run directory.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
PAYLOAD=~/hpc_mailbox/payload/id33-transformer-recipe-repair/id34_stage1_v01.tar.gz
echo "=== STAMP ==="; date -Iseconds
echo "=== A. IN-FLIGHT ==="
squeue -u "$USER" -h -t RUNNING,CONFIGURING,PENDING -o "%i %j %T" 2>/dev/null | grep -E 'id3[34]' || echo "  none"
echo "=== B. EXTRACT ==="
ls -la "$PAYLOAD" 2>&1 || { echo "PAYLOAD MISSING"; exit 1; }
cd "$ROOT" || exit 1
tar -xzf "$PAYLOAD" -C "$ROOT"
sed -i 's/\r$//' src/path_signature_runoff/hpc/submit_stage1.slurm
sha256sum src/path_signature_runoff/scripts/signature_features.py \
          src/path_signature_runoff/scripts/stage1_residual_diagnostic.py \
          src/path_signature_runoff/hpc/submit_stage1.slurm
echo "=== C. LOCATE C4 RUN ==="
C4=$(ls -d results/33_transformer_recipe_repair/C4/*_2026_0909_* 2>/dev/null | tail -1)
echo "C4_RUN=$C4"
[ -f "$C4/config.yml" ] || { echo "C4 run dir not found"; exit 1; }
ls "$C4/train_data/" 2>&1 | head -3
echo "=== D. SUBMIT ==="
mkdir -p logs/34_path_signature_runoff results/34_path_signature_runoff/_reports
OUT=$(sbatch --export=ALL,C4_RUN="$C4" src/path_signature_runoff/hpc/submit_stage1.slurm 2>&1); echo "$OUT"
J=$(echo "$OUT" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$J" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "stage1_job=$J"
sleep 15; squeue -j "$J" -o "%.10i %.14j %.3t %.8M %.8N %R" 2>&1 || true
