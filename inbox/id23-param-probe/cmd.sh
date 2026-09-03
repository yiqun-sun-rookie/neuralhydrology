#!/bin/bash
# Redeploy bundle b (adds hydroagent.experiment_logger) and re-run the import gate.
set -o pipefail
ROOT=/data1/home/sunyiq/id23_param_probe
PAY=~/hpc_mailbox/inbox/id23-param-probe/payload

echo "=== GUARD: only redeploy while no results exist ==="
if [ -n "$(ls -A $ROOT/out 2>/dev/null)" ]; then echo "REFUSE: $ROOT/out is not empty"; ls -la "$ROOT/out"; exit 1; fi

cd "$PAY" || exit 1
sha256sum -c par_probe_bundle_20260903b.tar.gz.sha256 || exit 1

echo "=== REDEPLOY ==="
tar xzf "$PAY/par_probe_bundle_20260903b.tar.gz" -C "$ROOT"
sed -i 's/\r$//' "$ROOT"/par_probe.slurm "$ROOT"/src/*/*.py "$ROOT"/src/*/*/*.py 2>/dev/null
ls "$ROOT/src/hydroagent/"

echo "=== IMPORT + INPUT CHECK ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final
cd "$ROOT"
PYTHONPATH="$ROOT/src" python - <<'PY' 2>&1 | head -25
import hashlib, sys
from pathlib import Path
ROOT = Path("/data1/home/sunyiq/id23_param_probe")
sys.path.insert(0, str(ROOT / "src"))
from camels_switch_confirmation.scripts import run_parameter_axis_probe as r
print("import OK; fc_bounds =", r.FC_BOUNDS)
h = hashlib.sha256((ROOT / r.CENTER_TABLE).read_bytes()).hexdigest()
print("center table sha256 matches:", h == r.CENTER_TABLE_SHA256)
print("design90 basins:", len(r.load_basin_list(ROOT, "design90")))
print("admitted52 basins:", len(r.load_basin_list(ROOT, "admitted52")))
centers = r.load_center_table(ROOT)
gate = r.verify_center_protocol(r.load_basin_list(ROOT, "design90"), centers, ROOT / "data/camels_us", n_check=3)
print("center-protocol gate max|diff| =", round(gate["max_abs_diff"], 6), "over", gate["n_checked"], "basins")
PY
echo "=== READY (still not submitted) ==="
