#!/bin/bash
# Transformer absolute MAE on the hidden_target arm, for a like-for-like level
# comparison against the ridge baseline. Read-only.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export PYTHONPATH="$ROOT/pysite:${PYTHONPATH:-}"
python - <<'PYEOF' 2>&1 | sed 's/^/  /'
import pandas as pd
p = "/data1/home/sunyiq/zhenjiang_oyv_v1/n4_impact/n4_task_errors.csv"
d = pd.read_csv(p)
h = d[d.condition == "hidden_target"]
# seed median within fold, then fold median -- the REPORTING aggregation
fold = h.groupby(["target","horizon_hours","test_year"]).mean_absolute_error_m.median().reset_index()
out = fold.groupby(["target","horizon_hours"]).mean_absolute_error_m.median().unstack()
print("TRANSFORMER hidden_target MAE (m), new family:")
print(out[[1,3,6,12,24]].round(4).to_string())
PYEOF
echo "=== OLD FAMILY (zhenjiang/jiangyin) ==="
python - <<'PYEOF' 2>&1 | sed 's/^/  /'
import os, numpy as np, pandas as pd, sys
sys.path.insert(0,"/data1/home/sunyiq/zhenjiang_oyv_v1/repo/scripts/analysis")
sys.path.insert(0,"/data1/home/sunyiq/zhenjiang_oyv_v1/repo/scripts/modeling")
os.chdir("/data1/home/sunyiq/zhenjiang_oyv_v1/repo")
import zhenjiang_oyv_v1_contract as v1
root = "/data1/home/sunyiq/zhenjiang_oyv_v1/tasks"
rows = []
for t in v1.enumerate_tasks():
    if t["condition"] != "hidden_target": continue
    f = os.path.join(root, str(t["task_id"]), "test_predictions.npz")
    if not os.path.isfile(f): continue
    with np.load(f) as z:
        e = np.abs(z["prediction_m"].astype("float64") - z["target_m"].astype("float64"))
    for hh in (1,3,6,12,24):
        rows.append({"target":t["target"],"horizon_hours":hh,"test_year":t["test_year"],
                     "seed":t["seed"],"mae":float(np.mean(e[:,hh-1]))})
d = pd.DataFrame(rows)
if d.empty:
    print("no hidden_target tasks found under", root)
else:
    fold = d.groupby(["target","horizon_hours","test_year"]).mae.median().reset_index()
    print(fold.groupby(["target","horizon_hours"]).mae.median().unstack()[[1,3,6,12,24]].round(4).to_string())
PYEOF
echo "=== DONE ==="
