#!/bin/bash
# Deploy the parameter-axis open-loop probe into its own landing dir. No sbatch yet.
set -o pipefail
ROOT=/data1/home/sunyiq/id23_param_probe
SRC=~/hpc_mailbox/inbox/id23-param-probe/payload/par_probe_bundle_20260903.tar.gz

echo "=== GUARD: refuse to clobber an existing landing dir ==="
if [ -e "$ROOT" ]; then echo "REFUSE: $ROOT already exists"; ls -la "$ROOT" | head; exit 1; fi

echo "=== VERIFY BUNDLE ==="
cd ~/hpc_mailbox/inbox/id23-param-probe/payload || exit 1
sha256sum -c par_probe_bundle_20260903.tar.gz.sha256 || exit 1

echo "=== DEPLOY ==="
mkdir -p "$ROOT/logs" "$ROOT/out" "$ROOT/data"
tar xzf "$SRC" -C "$ROOT"
ln -s /data1/home/sunyiq/neuralhydrology/data/camels_us "$ROOT/data/camels_us"
sed -i 's/\r$//' "$ROOT"/par_probe.slurm "$ROOT"/src/*/*.py "$ROOT"/src/*/*/*.py 2>/dev/null
find "$ROOT" -type f | sed "s|$ROOT/||" | sort
echo "symlink: $(readlink -f $ROOT/data/camels_us)"

echo "=== IMPORT + INPUT HASH CHECK (login node, no computation) ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final
cd "$ROOT"
PYTHONPATH="$ROOT/src" python - <<'PY' 2>&1 | head -20
import hashlib, sys
sys.path.insert(0, "/data1/home/sunyiq/id23_param_probe/src")
from camels_switch_confirmation.scripts import run_parameter_axis_probe as r
print("import OK; fc_bounds =", r.FC_BOUNDS)
h = hashlib.sha256(open("/data1/home/sunyiq/id23_param_probe/" + str(r.CENTER_TABLE), "rb").read()).hexdigest()
print("center table sha256 matches:", h == r.CENTER_TABLE_SHA256)
print("design90:", len(r.load_basin_list(__import__("pathlib").Path("/data1/home/sunyiq/id23_param_probe"), "design90")))
print("admitted52:", len(r.load_basin_list(__import__("pathlib").Path("/data1/home/sunyiq/id23_param_probe"), "admitted52")))
PY
echo "=== READY (not submitted) ==="
