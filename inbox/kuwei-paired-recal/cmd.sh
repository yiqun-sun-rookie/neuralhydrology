#!/bin/bash
# Build a dedicated env whose versions match the machine where determinism was verified.
# Login node: this is network/IO only (pip download+install), no computation.
set -o pipefail

ROOT=~/kuwei_paired
VENV=$ROOT/venv
mkdir -p $ROOT

echo "=== A. base python from nh_final ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || true
conda activate nh_final 2>/dev/null || echo "(activate failed)"
which python; python -V

echo "=== B. create venv (idempotent) ==="
if [ -x "$VENV/bin/python" ]; then
  echo "venv already present"
else
  python -m venv $VENV 2>&1 | tail -3 || true
fi
source $VENV/bin/activate || { echo "FATAL venv activate failed"; exit 1; }
python -V

echo "=== C. pin the versions the local determinism gate was verified on ==="
python -m pip install --quiet --upgrade pip 2>&1 | tail -2 || true
python -m pip install --quiet \
  "numpy==1.26.4" "scipy==1.17.0" "pandas==2.3.3" "numba==0.61.2" "pyyaml" \
  2>&1 | tail -15 || echo "(pip install reported an issue)"

echo "=== D. verify ==="
python - <<'PY' 2>&1 || true
import sys
mods = {}
for name in ("numpy","scipy","pandas","numba","yaml"):
    try:
        m = __import__(name)
        mods[name] = getattr(m, "__version__", "n/a")
    except Exception as e:
        mods[name] = f"IMPORT FAILED: {e}"
print("python", sys.version.split()[0])
for k, v in mods.items():
    print(f"{k:8s} {v}")
target = {"numpy":"1.26.4","scipy":"1.17.0","pandas":"2.3.3","numba":"0.61.2"}
bad = {k: (mods.get(k), v) for k, v in target.items() if mods.get(k) != v}
print("MATCH_LOCAL:", "YES" if not bad else f"NO -> {bad}")
PY

echo "=== E. numba can actually compile on this node ==="
python - <<'PY' 2>&1 || true
try:
    import numpy as np, numba, time
    @numba.njit(cache=False, fastmath=True)
    def f(x):
        s = 0.0
        for i in range(x.size):
            s += x[i] * 1.0000001
        return s
    a = np.arange(1000, dtype=np.float64)
    t0 = time.time(); v1 = f(a); t1 = time.time()
    v2 = f(a)
    print(f"numba compile+run OK, value={v1!r}, bitwise-repeat={v1==v2}, compile_sec={t1-t0:.1f}")
except Exception as e:
    print("numba smoke FAILED:", e)
PY

echo "=== F. cpu model of this login node (compare later with the compute node) ==="
grep -m1 'model name' /proc/cpuinfo || true

echo "=== G. workspace ==="
df -h $ROOT 2>/dev/null | tail -1 || true
ls -la $ROOT | head -10 || true
echo "=== DONE ==="
