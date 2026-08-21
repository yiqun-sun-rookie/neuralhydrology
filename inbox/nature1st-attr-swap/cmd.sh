#!/bin/bash
# nature1st-attr-swap seq=65 -- SUBMIT armG (user authorised this training round).
# armG = the set China can actually supply, 17 attributes, raw scale.
# Context: armF (global 13 + area/dam-storage/nearest-dam/permeability) reached 0.6436,
# paired -0.0046 [-0.0138,+0.0029] vs the US-12 control = parity. armG asks whether
# China-supplyable substitutes for three of those four hold that parity.
# Pre-registered, paired vs armC (0.6466): good enough = paired >= -0.010 AND share
# dropping >0.10 <= 20%; rejected = paired < -0.030 OR that share > 35%.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
cd "$RUN" || { echo "RUN DIR MISSING"; exit 1; }

echo "=== A. GUARD: refuse to double-submit ==="
EXIST=$(squeue -u $USER -h -o '%j' 2>/dev/null | grep -c 'q_armG' || true)
echo "armG jobs already in queue: $EXIST"
if [ "$EXIST" != "0" ]; then echo "ALREADY SUBMITTED -- refusing"; exit 0; fi
if [ -d models/q_lstm_armG_hpc_s42 ]; then echo 'OUTPUT DIR EXISTS -- refusing'; exit 0; fi
mkdir -p logs/attr_swap

echo "=== B. PREFLIGHT: the two attribute files ==="
sha256sum data/interim/stage_static_feature_stats_armG.json \
          data/processed/station_meta/trainable_mountain_stations_armG.csv 2>&1

echo "=== C. SUBMIT ==="
out=$(sbatch scripts/hpc_train_q_armG_china_supplyable.sbatch 2>&1); echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
if [ -z "$JID" ]; then echo "SUBMIT_FAILED -- no job id in output"; exit 1; fi
echo "SUBMITTED jobid=$JID"

echo "=== D. QUEUE ==="
sleep 20
squeue -j $JID -o '%.10i %.28j %.10T %.8M %.20R' 2>&1

echo "=== E. armH META DISCREPANCY -- exact per-column fingerprints ==="
# armG matched the workstation byte-for-byte after newline normalisation; armH's meta
# did not, while its stats file DID. numpy differs (1.26.4 here vs 2.3.3 there), so the
# suspicion is last-ulp log1p. Hex floats are exact -- no rounding hides a real gap.
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python - <<'PY' 2>&1
import pandas as pd, numpy as np
d = pd.read_csv('data/processed/station_meta/trainable_mountain_stations_armH.csv')
print('numpy', np.__version__, 'rows', len(d))
for c in d.columns:
    if c == 'station_id':
        continue
    v = d[c].to_numpy(dtype=np.float64)
    print(f'{c:<34} sum={float(v.sum()).hex()}  max={float(v.max()).hex()}')
PY
echo "=== END seq=65 ==="
