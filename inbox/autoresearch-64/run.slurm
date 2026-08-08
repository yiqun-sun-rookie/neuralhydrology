#!/usr/bin/env bash
#SBATCH -J a64-candidate
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH -t 04:00:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.err

set -o pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
# A real environment, not a PYTHONPATH injection: the dependency gate probes a clean
# interpreter on purpose, so the pinned versions have to actually be installed.
VENV=/data1/home/sunyiq/autoresearch64/.venv
[ -x "$VENV/bin/python" ] && { export PATH="$VENV/bin:$PATH"; hash -r; }
export MKL_THREADING_LAYER=GNU

ROOT=/data1/home/sunyiq/autoresearch64
cd "$ROOT" || exit 1
export PYTHONPATH="$ROOT/src"
export PATH="$ROOT/.pytools/bin:$PATH"

echo "=== 0. environment actually in use ==="
python -c "import numpy,pandas,pyarrow;print('numpy',numpy.__version__,'pandas',pandas.__version__,'pyarrow',pyarrow.__version__)"

echo "=== 1. full test suite on the cluster ==="
python -m pytest src/unified_autoresearch/tests -q 2>&1 | tail -12

echo "=== 2. run HBV-lite on the 64 basins, cluster dependency set ==="
python src/unified_autoresearch/scripts/run_single_candidate.py \
  --candidate hbv_lite \
  --dependencies cluster \
  --package-root runs/unified_autoresearch/development_packages_real_64_hpc \
  --output-root runs/unified_autoresearch/hbv_lite_64_hpc_v4 \
  --monitor-sample-interval-seconds 1.0 \
  --monitor-reason "first real candidate on the cluster; per-basin calibration needs supervision" 2>&1 | tail -15

echo "=== 3. scores, split by the pre-registered eligibility record ==="
python - <<'PY'
import json, pathlib, statistics, sys
sys.path.insert(0, "src")
from unified_autoresearch.evaluation.basin_eligibility import partition_summary_cells
r = json.loads(pathlib.Path("runs/unified_autoresearch/hbv_lite_64_hpc_v4/CANDIDATE_SUMMARY.json").read_text())
e = json.loads(pathlib.Path("runs/unified_autoresearch/BASIN_ELIGIBILITY_64_HPC.json").read_text())
p = partition_summary_cells(cells=r["cells"], eligibility=e)
for label, group in (("ALL 64", r["cells"]), ("standard", p["standard"]), ("unstable", p["unstable"])):
    m = [c["mean_nse"] for c in group]
    print("%-9s n=%2d median %.6f  min %.4f  max %.4f  #>0 %d" % (
        label, len(m), statistics.median(m), min(m), max(m), sum(1 for v in m if v > 0)))
print("declared dependencies:", json.loads(pathlib.Path("runs/unified_autoresearch/hbv_lite_64_hpc_v4/candidate/candidate-descriptor.json").read_text())["dependencies"])
print("markers:", {k: v for k, v in r.items() if k.endswith(("_run", "_claimed", "_scored"))})
PY

echo "=== 4. supervisor: peak and denied access, recounted from raw logs ==="
python - <<'PY'
import json, pathlib
root = pathlib.Path("runs/unified_autoresearch/hbv_lite_64_hpc_v4/runs")
peak = 0.0; samples = 0; denied = 0
for p in sorted(root.rglob("resource-monitor.jsonl")):
    rows = [json.loads(l) for l in p.read_text().splitlines() if l.strip()]
    samples += len(rows)
    peak = max([peak] + [r["process_memory_gb"] for r in rows if isinstance(r.get("process_memory_gb"), (int, float))])
for p in sorted(root.rglob("access.jsonl")):
    denied += sum(1 for l in p.read_text().splitlines() if l.strip() and json.loads(l).get("decision") == "deny")
print(f"samples={samples} process_peak_gb={peak:.4f} denied_access={denied}")
PY
