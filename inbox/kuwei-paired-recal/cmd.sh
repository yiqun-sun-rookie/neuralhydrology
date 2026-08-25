#!/bin/bash
# Build a Linux run_config and sbatch ONE short-budget probe to a compute node.
# Login node does config generation + sbatch only. All computation is on icn via SLURM.
set -o pipefail

ROOT=~/kuwei_paired
FSL=$ROOT/fsl
LAOS=$ROOT/laos
RUN=$ROOT/run_probe
QUAL=$LAOS/basins/namou_kuwei/dl/highflow_2026_06_17/results/continuous_rainfall_qualification_20260824
mkdir -p $RUN/runtime_data/full $RUN/runtime_data/namou_kuwei_discharge_hourly $RUN/logs

echo "=== A. isolated runtime data dir (must contain NO timeseries.db) ==="
cp -f $FSL/basins/namou_kuwei/data/full/* $RUN/runtime_data/full/ 2>/dev/null && echo "matrix files copied"
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || true
conda activate nh_final 2>/dev/null || true
python - <<PY 2>&1 | tail -5
import pandas as pd
d = pd.read_csv("$LAOS/data/03_final/namou_kuwei/discharge_clean.csv", parse_dates=["time"])
d = d[(d["time"] >= "2017-06-01") & (d["time"] <= "2023-12-31 23:00")]
out = d[["time","q_obs"]].rename(columns={"q_obs":"discharge"})
out.to_csv("$RUN/runtime_data/namou_kuwei_discharge_hourly/obs_discharge_hourly.csv", index=False)
print("discharge rows:", len(out), "NaN:", int(out['discharge'].isna().sum()))
PY
echo "timeseries.db in runtime dir: $(find $RUN/runtime_data -name 'timeseries.db' | wc -l) (must be 0)"

echo "=== B. generate the Linux run_config ==="
python - <<PY 2>&1 | tail -12
import re, json
from pathlib import Path
src = Path("$FSL/basins/namou_kuwei/config/run_config.yml").read_text(encoding="utf-8")
s = src
s = re.sub(r"\n[ \t]*initial_params:[^\n]*\n", "\n", s)
s = re.sub(r"\n([ \t]*)workers:[^\n]*\n",  r"\n\1workers: 1\n",  s)
s = re.sub(r"\n([ \t]*)max_iter:[^\n]*\n", r"\n\1max_iter: 1\n", s)
s = re.sub(r"\n([ \t]*)pop_size:[^\n]*\n", r"\n\1pop_size: 60\n", s)
s = s.replace('end_date: "2022-12-31"', 'end_date: "2022-12-31 23:00:00"')
if "exclude_windows" not in s:
    s = s.replace("  exclude_years: []", '  exclude_windows: [["2022-09-01","2022-10-31"]]\n  exclude_years: []', 1)
s = re.sub(r"\nmeteo_file:[^\n]*\n", "\nmeteo_file: $QUAL/grid_hybrid_current.csv\n", s)
s = re.sub(r"\ndata_dir:[^\n]*\n",
           "\nobs_discharge_file: $RUN/runtime_data/namou_kuwei_discharge_hourly/obs_discharge_hourly.csv"
           "\ndata_dir: $RUN/runtime_data\n", s)
Path("$RUN/run_config_probe.yml").write_text(s, encoding="utf-8")
for k in ("initial_params","workers:","max_iter:","end_date:","exclude_windows","meteo_file:","data_dir:","obs_discharge_file:"):
    hits=[l.strip() for l in s.splitlines() if k in l]
    print(f"{k:20s} -> {hits if hits else 'ABSENT'}")
PY

echo "=== C. write the slurm job ==="
cat > $RUN/probe.slurm <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J kuwei-probe
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=2
#SBATCH -t 01:30:00
#SBATCH -o %x-%j.out
#SBATCH -e %x-%j.err
set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS=1
ROOT=$HOME/kuwei_paired
export PYTHONPATH=$ROOT/fsl:$PYTHONPATH
cd $ROOT/fsl
echo "[$(date)] node=$(hostname) cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2)"
python -c "import numpy,scipy,numba;print('numpy',numpy.__version__,'scipy',scipy.__version__,'numba',numba.__version__)"
time python -u scripts/core_optimization/namou_kuwei/run_calibration.py \
  --run-config $ROOT/run_probe/run_config_probe.yml \
  --output-root $ROOT/run_probe/out
echo "[$(date)] exit=$?"
SLURM
echo "slurm written"

echo "=== D. submit ==="
cd $RUN && sbatch probe.slurm 2>&1 | tee $RUN/last_jobid.txt || echo "sbatch FAILED"

echo "=== E. queue ==="
squeue -u ${USER} -n kuwei-probe -o "%.10i %.12j %.10P %.8T %.10M %R" 2>&1 | head -5 || true
echo "=== DONE ==="
