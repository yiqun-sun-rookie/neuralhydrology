#!/usr/bin/env bash
# ID33 seq=6 : deploy the calibration delta and submit C1/C2 to hgpu8 (idle A800 capacity).
# Does not touch the six treatment arms already running on hgpu2p.
set -o pipefail
ID33=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
PKG=~/hpc_mailbox/payload/id33-transformer-recipe-repair/id33_calib_v01.tar.gz
EXPECT=94c04ced99c0d3904ed92160b57798352427b303814b934002d1ee6dba17f3ae
echo "=== A. STAMP ==="; date -Is
test "$(sha256sum "$PKG" 2>/dev/null | cut -d' ' -f1)" = "$EXPECT" && echo PAYLOAD_OK || { echo PAYLOAD_MISMATCH; exit 1; }

echo "=== B. TREATMENT ARMS MUST BE UNDISTURBED ==="
squeue -u "$USER" -o "%.9i %.10j %.14P %.2t %.11M %.16R" 2>&1 | grep -E 'JOBID|id33' || true

echo "=== C. OVERLAY CALIBRATION DELTA ==="
cd "$ID33"
tar -xzf "$PKG" && echo extracted
sed -i 's/\r$//' src/transformer_recipe_repair/hpc/*.slurm
sha256sum src/transformer_recipe_repair/configs/c1.yml src/transformer_recipe_repair/configs/c2.yml           src/transformer_recipe_repair/hpc/submit_calibration_arm.slurm 2>&1 || true

echo "=== D. AUDIT ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
export MKL_THREADING_LAYER=GNU
python -m src.transformer_recipe_repair.scripts.audit_configs 2>&1 || { echo AUDIT_FAILED; exit 1; }

echo "=== E. hgpu8 STATE ==="
sinfo -p hgpu8 -o "%.8P %.6D %.8t %.20N" 2>&1 || true

echo "=== F. SUBMIT C1 AND C2 TO hgpu8 ==="
SUB=""
for ARM in C1 C2; do
  out=$(EXPERIMENT_ID="$ARM" sbatch --export=ALL,EXPERIMENT_ID="$ARM"         --job-name="id33_${ARM}" src/transformer_recipe_repair/hpc/submit_calibration_arm.slurm 2>&1)
  jid=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  if [ -n "$jid" ]; then echo "  $ARM -> $jid"; SUB="$SUB $ARM:$jid"; else echo "  $ARM -> SUBMIT_FAILED"; echo "$out" | head -4; fi
done
echo "SUBMITTED:$SUB"

echo "=== G. FULL QUEUE AFTER ==="
squeue -u "$USER" -o "%.9i %.10j %.14P %.2t %.11M %.16R" 2>&1 | grep -E 'JOBID|id33' || true
echo ID33_CALIB_SEQ6_COMPLETE
