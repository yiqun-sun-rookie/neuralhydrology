#!/bin/bash
set -o pipefail
cd ~/id17_film_gate || exit 1
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final >/dev/null 2>&1
echo "=== SENSITIVITY: same verdict computed at EPOCH 20 instead of 30 ==="
sed 's/^EPOCH = 30$/EPOCH = 20/' src/static_falsification/hpc/analyze_gate_matrix.py > /tmp/agm20.py
python /tmp/agm20.py 2>&1 | tail -32
echo ""
echo "=== EPOCH 20 -> 30 DEGRADATION PER ARM (test median NSE) ==="
python - <<'PY'
import glob, re, numpy as np, pandas as pd
from pathlib import Path
def med(model, fold, seed, ep):
    d = sorted(Path('runs').glob(f"gate_{model}_fold{fold}_seed{seed}_*"))
    if not d: return None
    f = glob.glob(str(d[-1]/'test'/f'model_epoch{ep:03d}'/'*_metrics.csv'))
    return float(np.nanmedian(pd.read_csv(f[0])['NSE'])) if f else None
rows=[]
for m in ('ea','film'):
    drops=[]
    for fo in range(5):
        for se in (0,1):
            a,b = med(m,fo,se,20), med(m,fo,se,30)
            if a and b: drops.append(b-a)
    print(f"{m:5s}: ep30-ep20 per cell = {['%+.4f'%d for d in drops]}")
    print(f"       mean {np.mean(drops):+.4f}   worst {min(drops):+.4f}   cells that got worse: {sum(1 for d in drops if d<0)}/10")
    e30=[med(m,fo,se,30) for fo in range(5) for se in (0,1)]
    e20=[med(m,fo,se,20) for fo in range(5) for se in (0,1)]
    print(f"       ep20 spread: min {min(e20):.4f} max {max(e20):.4f} sd {np.std(e20):.4f}")
    print(f"       ep30 spread: min {min(e30):.4f} max {max(e30):.4f} sd {np.std(e30):.4f}")
PY
