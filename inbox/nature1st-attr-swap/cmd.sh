#!/bin/bash
# nature1st-attr-swap seq=93 -- SUBMIT armI (user authorised this training round).
# armI = armF minus gageii_HydroMod_Dams_RAW_DIS_NEAREST_DAM, 16 attributes.
# Isolates what deleting distance-to-nearest-dam alone costs, since that is the only
# straight deletion separating armG (China-supplyable, 0.6299) from armF (0.6436).
# Pre-registered vs armF, paired: <= -0.015 it IS the main cause; >= -0.005 it is not.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
cd "$RUN" || { echo RUN_DIR_MISSING; exit 1; }

echo "=== A. GUARD ==="
EXIST=$(squeue -u $USER -h -o '%j' 2>/dev/null | grep -c 'q_armI' || true)
echo "armI jobs already queued: $EXIST"
if [ "$EXIST" != "0" ]; then echo "ALREADY SUBMITTED -- refusing"; exit 0; fi
if [ -d models/q_lstm_armI_hpc_s42 ]; then echo 'OUTPUT DIR EXISTS -- refusing'; exit 0; fi
mkdir -p logs/attr_swap
sha256sum data/interim/stage_static_feature_stats_armI.json 2>&1 | cut -c1-16,65-

echo "=== B. SUBMIT ==="
out=$(sbatch scripts/hpc_train_q_armI_no_neardam.sbatch 2>&1); echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
if [ -z "$JID" ]; then echo "SUBMIT_FAILED -- no job id"; exit 1; fi
echo "SUBMITTED jobid=$JID"

echo "=== C. QUEUE ==="
sleep 20
squeue -j $JID -o '%.10i %.24j %.10T %.8M %.22R' 2>&1
sinfo -p hgpu2p -o '%.10P %.6a %.6D %.6t %N' 2>&1 | head -6
echo "=== END seq=93 ==="
