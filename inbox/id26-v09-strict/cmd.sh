#!/bin/bash
# id26-v09-strict seq=12 : verify the S3 resource preflight on real GPUs.
# Uses a SEPARATE code checkout (~/v09_strict/codetest) so the sealed strict-nesting
# evidence in ~/v09_strict/neuralhydrology keeps its recorded HEAD f9418320 untouched.
# Synthetic data only. No formal input opened, no formal report written, no training.
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
CODE=$ROOT/codetest/neuralhydrology
GITENV=$ROOT/gitenv
BRANCH="codex/historical-band-experts-pilot"
WANT=abdeb4bd1043198d4a8e4f4b8d4e8aedacf6e0b1
export PATH=$GITENV/bin:$PATH

echo "=== A SEALED STRICT EVIDENCE MUST STAY AT ITS RECORDED COMMIT ==="
cd "$ROOT/neuralhydrology" && echo "strict checkout HEAD = $(git rev-parse HEAD) (must stay f9418320...)"

echo "=== B CODE CHECKOUT ==="
mkdir -p "$ROOT/codetest"
if [ -d "$CODE/.git" ]; then
  cd "$CODE" && git fetch -q origin "+${BRANCH}:refs/remotes/origin/${BRANCH}" && \
    git checkout -q "refs/remotes/origin/${BRANCH}"
else
  git clone -q --depth 1 --branch "$BRANCH" --single-branch \
    git@github.com:yiqun-sun-rookie/neuralhydrology.git "$CODE" 2>&1 | tail -3
fi
cd "$CODE" || { echo "CHECKOUT FAILED"; exit 1; }
echo "codetest HEAD = $(git rev-parse HEAD)"
echo "expected      = $WANT"
[ "$(git rev-parse HEAD)" = "$WANT" ] && echo "MATCH" || echo "MISMATCH"

echo "=== C WRITE GPU PREFLIGHT JOB ==="
mkdir -p "$ROOT/jobs" "$ROOT/logs"
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

echo "=== CPU TEST SUITE FOR S1-S3 ==="
python -m pytest src/26_historical_band_experts/tests/test_formal_v09_run_order.py \
                 src/26_historical_band_experts/tests/test_train_formal_v09.py \
                 src/26_historical_band_experts/tests/test_resource_preflight_formal_v09.py \
                 -p no:cacheprovider -q 2>&1 | tail -6

echo "=== REAL GPU PREFLIGHT: 4 workloads x 2 fresh subprocesses, batch 256 ==="
python -u - <<'PY'
import json, sys
sys.path.insert(0, "src/26_historical_band_experts")
from resource_preflight_formal_v09 import FORMAL_PROFILE_V09, run_preflight_workloads_v09
summaries = run_preflight_workloads_v09(device="cuda:0")
print("profile:", json.dumps(FORMAL_PROFILE_V09))
for s in summaries:
    peak_a = s["peak_allocated_bytes"]
    peak_r = s["peak_reserved_bytes"]
    print(f"{s['workload']:32s} identical={s['arrays_identical']} "
          f"params={[m['trainable_parameters'] for m in s['models']]} "
          f"peak_alloc={peak_a/2**20:.0f}MiB peak_reserved={peak_r/2**20:.0f}MiB")
    print(f"    determinism={json.dumps(s['determinism'], sort_keys=True)}")
    print(f"    pids={[r['process_id'] for r in s['runs']]}")
print("ALL_WORKLOADS_IDENTICAL:", all(s["arrays_identical"] for s in summaries))
PY
echo "done=$(date -Iseconds)"
SLURM
sed -i 's/\r$//' "$ROOT/jobs/preflight.slurm"

echo "=== D SUBMIT AND WAIT (cap 60 min) ==="
cd "$ROOT/jobs"
JID=$(sbatch --parsable preflight.slurm 2>&1)
echo "jobid=$JID"
for i in $(seq 1 360); do
  ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
  [ -z "$ST" ] && { echo "finished at t=$((i*10))s"; break; }
  [ $((i % 12)) -eq 0 ] && echo "  t=$((i*10))s state=$ST"
  sleep 10
done

echo "=== E ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%10,JobName%10,NodeList%9,State%12,ExitCode%8,Elapsed%12 2>&1
echo "=== F STDOUT ==="
cat "$ROOT/logs/preflight_${JID}.out" 2>&1 | tail -50
echo "=== G STDERR (tail 20) ==="
tail -20 "$ROOT/logs/preflight_${JID}.err" 2>&1

echo "=== H CONFIRM NOTHING FORMAL WAS TOUCHED ==="
D=$ROOT/neuralhydrology/results/26_historical_band_experts/formal_v09
echo "strict HEAD still: $(cd $ROOT/neuralhydrology && git rev-parse HEAD)"
ls "$D"/training_resource_preflight.external_audit.json 2>&1 | head -2
echo "strict run dir intact: $(ls "$D/strict_nesting/R09-NEST-S100" 2>/dev/null | wc -l) files"
echo "=== END ==="
