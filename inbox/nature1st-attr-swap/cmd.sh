#!/bin/bash
# nature1st-attr-swap seq=14 -- install the stream-network ablation (arms C and D)
# and verify the payload arrived intact. NO sbatch anywhere in this round.
set -o pipefail
CH=nature1st-attr-swap
IN=$HOME/hpc_mailbox/inbox/$CH
RUN=/data1/home/sunyiq/nature_1st

echo "=== A. INSTALL scripts ==="
for f in chain_prepare_network_ablation_static.py \
         chain_train_q_us_minus_network.py \
         chain_train_q_hydroatlas_plus_network.py \
         chain_eval_q_us_minus_network.py \
         chain_eval_q_hydroatlas_plus_network.py \
         hpc_train_q_us_minus_network.sbatch \
         hpc_train_q_hydroatlas_plus_network.sbatch; do
    cp -v "$IN/$f" "$RUN/scripts/" 2>&1
done
sed -i 's/\r$//' "$RUN"/scripts/chain_*_network.py "$RUN"/scripts/hpc_train_q_*_network.sbatch 2>&1

echo "=== B. INSTALL attribute files ==="
cp -v "$IN/stage_static_feature_stats_us_minus_network.json" "$RUN/data/interim/" 2>&1
cp -v "$IN/stage_static_feature_stats_hydroatlas_plus_network.json" "$RUN/data/interim/" 2>&1
cp -v "$IN/trainable_mountain_stations_hydroatlas_plus_network.csv" \
      "$RUN/data/processed/station_meta/" 2>&1
sed -i 's/\r$//' "$RUN"/data/interim/stage_static_feature_stats_*_network.json \
                 "$RUN"/data/processed/station_meta/trainable_mountain_stations_hydroatlas_plus_network.csv 2>&1

echo "=== C. CONTENT FINGERPRINTS (must match the local values) ==="
echo "expected: statsC=8c2d69fe08fe4efc n=8 | statsD=81372304d67d2669 n=17 | metaD=0b0fb44e4b8a2711 shape=(2908, 18)"
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate "${CONDA_ENV:-nh_final}" 2>&1 | head -2
python - <<'PY' 2>&1
import hashlib, json, pandas as pd
from pathlib import Path
R = Path("/data1/home/sunyiq/nature_1st")
def jh(p):
    d = json.loads(Path(p).read_text())
    return hashlib.sha256(json.dumps(d, sort_keys=True).encode()).hexdigest()[:16], len(d), list(d)
def ch(p):
    df = pd.read_csv(p)
    return hashlib.sha256(df.to_csv(index=False, lineterminator="\n").encode()).hexdigest()[:16], df.shape
h, n, keys = jh(R / "data/interim/stage_static_feature_stats_us_minus_network.json")
print(f"statsC {h} n={n}")
print(f"  keys {keys}")
h, n, keys = jh(R / "data/interim/stage_static_feature_stats_hydroatlas_plus_network.json")
print(f"statsD {h} n={n}")
print(f"  keys {keys}")
h, shape = ch(R / "data/processed/station_meta/trainable_mountain_stations_hydroatlas_plus_network.csv")
print(f"metaD  {h} shape={shape}")
PY

echo "=== D. SBATCH SCRIPTS SANITY (want 1 and 1 for each grep) ==="
grep -c 'exclude=ngu002' "$RUN"/scripts/hpc_train_q_us_minus_network.sbatch \
                         "$RUN"/scripts/hpc_train_q_hydroatlas_plus_network.sbatch 2>&1 || true
grep -c 'no usable GPU' "$RUN"/scripts/hpc_train_q_us_minus_network.sbatch \
                        "$RUN"/scripts/hpc_train_q_hydroatlas_plus_network.sbatch 2>&1 || true
echo "-- epochs / output_dir lines --"
grep -nE 'epochs|output_dir' "$RUN"/scripts/hpc_train_q_us_minus_network.sbatch \
                             "$RUN"/scripts/hpc_train_q_hydroatlas_plus_network.sbatch 2>&1 || true

echo "=== E. OUTPUT DIRS MUST NOT EXIST YET (the trainer refuses a non-empty dir) ==="
for d in q_lstm_usminus4_hpc_s42 q_lstm_globalplus4_hpc_s42; do
    if [ -e "$RUN/models/$d" ]; then echo "PRESENT  $d  <-- must be moved before submitting"; \
    else echo "absent   $d  (good)"; fi
done

echo "=== F. CLUSTER STATE ==="
squeue -u "$USER" 2>&1 | head -10
sacct -j 206175,206176 -X --format=JobID%10,JobName%22,State%12,ExitCode%8,Elapsed%10,NodeList%9 2>&1 | head -5

echo "=== END seq=14 (nothing submitted) ==="
