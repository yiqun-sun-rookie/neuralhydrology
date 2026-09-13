#!/bin/bash
# TUKF09-455: read-only summary of the nine neural units' training-side validation records.
# Reads only model_selection.json and validation_history.npz. Opens no evaluation array.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909
R="$ROOT/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
echo "TIME=$(date -Is)"
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo CONDA_FAILED; exit 12; }
python -X utf8 - "$R" <<'PYEOF'
import json, sys
import numpy as np
from pathlib import Path
root = Path(sys.argv[1])
units = sorted(p for p in (root / "neural").iterdir() if p.name.startswith("lead_"))
print(f"units={len(units)}")
for u in units:
    sel = json.loads((u / "model_selection.json").read_text())
    h = np.load(u / "validation_history.npz", allow_pickle=False)
    med = h["validation_median_nse"]
    byb = h["validation_nse_by_basin"]
    e = int(sel["selected_epoch"])
    at = byb[e - 1]
    q = np.percentile(at, [10, 25, 50, 75, 90])
    print(f"\n[{u.name}] selected_epoch={e}/30  median_nse_at_selection={sel['validation_median_nse']:.4f}"
          f"  rule={sel['selection_rule']}")
    print("  per-epoch median NSE (epochs 1..30):")
    print("  " + " ".join(f"{v:.3f}" for v in med[:15]))
    print("  " + " ".join(f"{v:.3f}" for v in med[15:]))
    print(f"  at selected epoch across 455 basins: p10={q[0]:.3f} p25={q[1]:.3f} p50={q[2]:.3f} p75={q[3]:.3f} p90={q[4]:.3f}"
          f"  min={at.min():.3f} max={at.max():.3f}")
    print(f"  basins with NSE>0.5: {(at>0.5).sum()}/455   >0.7: {(at>0.7).sum()}/455   <0: {(at<0).sum()}/455"
          f"   non-finite: {(~np.isfinite(at)).sum()}")
    print(f"  epoch-1 median={med[0]:.3f}  best={med.max():.3f}@{int(np.argmax(med))+1}  last(30)={med[-1]:.3f}")
PYEOF

echo "EVALUATION_SURFACE=$(ls -d "$R"/evaluation* 2>/dev/null | wc -l)"
echo TUKF09_455_V2R14_VALIDATION_SUMMARY_READ_ONLY_DONE
