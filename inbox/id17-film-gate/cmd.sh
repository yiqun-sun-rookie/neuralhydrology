#!/bin/bash
set -o pipefail
cd ~/id17_film_gate || exit 1
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final >/dev/null 2>&1
echo "=== VERDICT RECOMPUTED AT EPOCH 20 (same script, same rules, only the epoch differs) ==="
mkdir -p src/static_falsification/hpc/_tmp
sed -e 's/^EPOCH = 30$/EPOCH = 20/' -e 's/parents\[3\]/parents[4]/' \
    src/static_falsification/hpc/analyze_gate_matrix.py > src/static_falsification/hpc/_tmp/agm20.py
python src/static_falsification/hpc/_tmp/agm20.py 2>&1 | tail -30
rm -rf src/static_falsification/hpc/_tmp
