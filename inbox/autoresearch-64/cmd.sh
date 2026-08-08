#!/bin/bash
# Which versions actually have wheels for this glibc? Query only, install into an isolated dir.
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh && conda activate nh_final
ROOT=~/autoresearch64
TGT=$ROOT/.pylibs_probe
rm -rf "$TGT"

echo "=== A. platform tags this pip accepts ==="
python -c "import sysconfig,platform;print(sysconfig.get_platform(), platform.python_version())"
python -m pip debug --verbose 2>/dev/null | grep -E "manylinux_2_1[0-9]|manylinux2014" | head -5

echo "=== B. the DECLARED set, binary only ==="
python -m pip install --only-binary=:all: --target "$TGT/declared" \
  "numpy==1.26.4" "pandas==2.3.3" "pyarrow==22.0.0" 2>&1 | tail -6

echo "=== C. if that failed, an older CONSISTENT set ==="
if [ ! -d "$TGT/declared/numpy" ]; then
  python -m pip install --only-binary=:all: --target "$TGT/fallback" \
    "numpy==1.26.4" "pandas==2.2.3" "pyarrow==17.0.0" 2>&1 | tail -6
fi

echo "=== D. what landed where ==="
for d in "$TGT/declared" "$TGT/fallback"; do
  [ -d "$d" ] && { echo "--- $d ---"; ls "$d" | grep -E "^(numpy|pandas|pyarrow)" | head -8; }
done

echo "=== E. does numpy 1.26 avoid the ctypes.dlopen that the sandbox blocks? ==="
for d in "$TGT/declared" "$TGT/fallback"; do
  [ -d "$d/numpy" ] || continue
  echo "--- testing $d ---"
  PYTHONPATH="$d" python - <<'PY'
import ctypes, sys
calls = []
original = ctypes.CDLL
class Traced(original):
    def __init__(self, name, *a, **k):
        calls.append(name); super().__init__(name, *a, **k)
ctypes.CDLL = Traced
import numpy, pandas, pyarrow
print("versions:", numpy.__version__, pandas.__version__, pyarrow.__version__)
print("ctypes.CDLL calls during import:", calls if calls else "NONE")
PY
done
