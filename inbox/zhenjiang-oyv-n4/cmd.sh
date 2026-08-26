#!/bin/bash
# Identify the hgpu8 cards. Logs go to my own landing zone, not into the mailbox
# working tree: the runner syncs that tree and transient files there are wiped.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
mkdir -p "$ROOT/probe"

cat > "$ROOT/probe/hgpu8_probe.slurm" <<'SLURMEOF'
#!/usr/bin/env bash
#SBATCH -J hgpu8probe
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 00:05:00
#SBATCH -o /data1/home/sunyiq/zhenjiang_oyv_v1/probe/probe_%j.out
#SBATCH -e /data1/home/sunyiq/zhenjiang_oyv_v1/probe/probe_%j.err
set -eo pipefail
echo "NODE=$(hostname)"
echo "OS=$(uname -r)"
cat /etc/os-release 2>/dev/null | head -1
echo "GLIBC=$(ldd --version 2>/dev/null | head -1)"
echo "--- nvidia-smi ---"
nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONPATH="/data1/home/sunyiq/zhenjiang_oyv_v1/pysite:${PYTHONPATH:-}"
python - <<'PYEOF'
import platform, torch, numpy, pandas, scipy, psutil
print("python  =", platform.python_version())
print("platform=", platform.platform())
print("torch   =", torch.__version__, "cuda", torch.version.cuda, "cudnn", torch.backends.cudnn.version())
print("numpy   =", numpy.__version__, "pandas", pandas.__version__, "scipy", scipy.__version__, "psutil", psutil.__version__)
print("cuda_ok =", torch.cuda.is_available())
if torch.cuda.is_available():
    print("gpu_name=", torch.cuda.get_device_name(0))
    print("gpu_cap =", list(torch.cuda.get_device_capability(0)))
    print("gpu_mem =", torch.cuda.get_device_properties(0).total_memory)
try:
    import threadpoolctl, json
    rows = threadpoolctl.threadpool_info()
    print("threadpool_rows =", len(rows))
    for r in rows:
        print("   ", r.get("user_api"), r.get("internal_api"), r.get("version"), "num_threads=", r.get("num_threads"))
except Exception as e:
    print("threadpoolctl unavailable:", e)
PYEOF
echo "PROBE_DONE"
SLURMEOF
sed -i 's/\r$//' "$ROOT/probe/hgpu8_probe.slurm"

echo "=== SUBMIT ==="
IDS=""
for spec in "hgpu8 ngu201" "hgpu8 ngu203" "hgpu2p ngu001"; do
  set -- $spec
  out=$(sbatch --parsable -p "$1" --nodelist="$2" --job-name="pr_$2" -t 00:05:00 "$ROOT/probe/hgpu8_probe.slurm" 2>&1)
  jid=$(echo "$out" | grep -oE '^[0-9]+' || true)
  if [ -n "$jid" ]; then echo "  $1/$2 -> $jid"; IDS="$IDS $jid"; else echo "  $1/$2 -> FAILED: $out"; fi
done
[ -n "$IDS" ] || { echo "NONE_SUBMITTED"; exit 1; }

echo "=== WAIT (max 3 min) ==="
for i in $(seq 1 18); do
  LEFT=0
  for j in $IDS; do
    st=$(sacct -j "$j" -X -n -o State 2>/dev/null | head -1 | awk '{print $1}')
    case "$st" in RUNNING|PENDING|"") LEFT=$((LEFT+1));; esac
  done
  [ "$LEFT" -eq 0 ] && { echo "  settled t=$((i*10))s"; break; }
  sleep 10
done

echo "=== RESULTS ==="
for j in $IDS; do
  echo "  ============ job $j ============"
  sacct -j "$j" -X --format=JobID%9,JobName%10,NodeList%9,State%11,ExitCode%7,Elapsed%9 2>&1 | tail -1
  if [ -f "$ROOT/probe/probe_${j}.out" ]; then sed -n '1,35p' "$ROOT/probe/probe_${j}.out" | sed 's/^/    /'; else echo "    (no stdout)"; fi
  if [ -s "$ROOT/probe/probe_${j}.err" ]; then echo "    -- err --"; tail -6 "$ROOT/probe/probe_${j}.err" | sed 's/^/      /'; fi
done
echo "=== DONE ==="
