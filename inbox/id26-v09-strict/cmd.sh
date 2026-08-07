#!/bin/bash
# id26-v09-strict seq=14 : GPU verification of the S3 resource preflight.
# seq=13 died on a CUDA-init bug in the preflight itself (now fixed at c9bcfb4e).
# job. The CPU suite already passes locally; nh_final is left alone (a02 / id05 use it).
# Synthetic data only. No formal input opened, no formal report written, no training.
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
CODE=$ROOT/codetest/neuralhydrology
export PATH=$ROOT/gitenv/bin:$PATH

echo "=== A CODE CHECKOUT ==="
cd "$CODE" && git fetch -q origin "+codex/historical-band-experts-pilot:refs/remotes/origin/codex/historical-band-experts-pilot" \
  && git checkout -q refs/remotes/origin/codex/historical-band-experts-pilot
echo "codetest HEAD = $(git rev-parse HEAD)"

cat > "$ROOT/jobs/preflight.slurm" <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J v09pre
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 02:00:00
#SBATCH -o /data1/home/sunyiq/v09_strict/logs/preflight_%j.out
#SBATCH -e /data1/home/sunyiq/v09_strict/logs/preflight_%j.err

set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
export PATH=/data1/home/sunyiq/v09_strict/gitenv/bin:$PATH
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export CUBLAS_WORKSPACE_CONFIG=:4096:8

cd /data1/home/sunyiq/v09_strict/codetest/neuralhydrology
export PYTHONPATH=$(pwd):$PYTHONPATH

echo "node=$(hostname)"
nvidia-smi --query-gpu=index,name,memory.free --format=csv,noheader
python -c "import torch;print('torch',torch.__version__,'cudnn',torch.backends.cudnn.version())"

echo "=== REAL GPU PREFLIGHT: 4 workloads x 2 fresh subprocesses, batch 256, window 3562 ==="
python -u - <<'PY'
import json, sys, traceback
sys.path.insert(0, "src/26_historical_band_experts")
from resource_preflight_formal_v09 import FORMAL_PROFILE_V09, run_preflight_workloads_v09
print("profile:", json.dumps(FORMAL_PROFILE_V09, sort_keys=True))
try:
    summaries = run_preflight_workloads_v09(device="cuda:0")
except Exception:
    traceback.print_exc()
    print("ALL_WORKLOADS_IDENTICAL: False")
    raise SystemExit(2)
for s in summaries:
    a = s["peak_allocated_bytes"]; r = s["peak_reserved_bytes"]
    print(f"{s['workload']:32s} identical={s['arrays_identical']} "
          f"params={[m['trainable_parameters'] for m in s['models']]} "
          f"peak_alloc={a/2**20:.0f}MiB peak_reserved={r/2**20:.0f}MiB "
          f"pids={[x['process_id'] for x in s['runs']]}")
print("determinism:", json.dumps(summaries[0]["determinism"], sort_keys=True))
print("ALL_WORKLOADS_IDENTICAL:", all(s["arrays_identical"] for s in summaries))
PY
echo "done=$(date -Iseconds)"
SLURM
sed -i 's/\r$//' "$ROOT/jobs/preflight.slurm"

echo "=== B SUBMIT AND WAIT (cap 60 min) ==="
cd "$ROOT/jobs"
JID=$(sbatch --parsable preflight.slurm 2>&1)
echo "jobid=$JID"
for i in $(seq 1 360); do
  ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
  [ -z "$ST" ] && { echo "finished at t=$((i*10))s"; break; }
  [ $((i % 12)) -eq 0 ] && echo "  t=$((i*10))s state=$ST"
  sleep 10
done

echo "=== C ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%10,JobName%10,NodeList%9,State%12,ExitCode%8,Elapsed%12 2>&1
echo "=== D STDOUT ==="
cat "$ROOT/logs/preflight_${JID}.out" 2>&1 | tail -40
echo "=== E STDERR (tail 25) ==="
tail -25 "$ROOT/logs/preflight_${JID}.err" 2>&1

echo "=== F NOTHING FORMAL TOUCHED ==="
D=$ROOT/neuralhydrology/results/26_historical_band_experts/formal_v09
echo "strict HEAD still: $(cd $ROOT/neuralhydrology && git rev-parse HEAD)"
echo "strict run dir files: $(ls "$D/strict_nesting/R09-NEST-S100" 2>/dev/null | wc -l)"
[ -e "$D/training_resource_preflight.external_audit.json" ] && echo "FORMAL REPORT PRESENT (unexpected)" || echo "no formal report written (expected)"
echo "=== END ==="
