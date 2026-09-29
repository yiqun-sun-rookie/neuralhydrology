#!/bin/bash
set -eo pipefail
sequence=5

echo "=== existing environment identities ==="
for python_path in \
  /data1/home/sunyiq/miniconda3/bin/python \
  /data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python \
  /data1/home/sunyiq/miniconda3/envs/neuralhydrology/bin/python \
  /data1/home/sunyiq/miniconda3/envs/nh_clean/bin/python \
  /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python \
  /data1/home/sunyiq/v09_strict/gitenv/bin/python; do
  if test ! -x "$python_path"; then
    echo "ABSENT $python_path"
    continue
  fi
  "$python_path" - "$python_path" <<'PY'
import json
import platform
import sys

result = {
    "requested_python": sys.argv[1],
    "executable": sys.executable,
    "python": platform.python_version(),
}
for name in ("numpy", "torch", "pandas", "psutil", "scipy", "matplotlib", "pytest"):
    try:
        module = __import__(name)
        result[name] = getattr(module, "__version__", "present_without_version")
        result[name + "_path"] = getattr(module, "__file__", None)
    except Exception as error:
        result[name] = None
        result[name + "_error"] = type(error).__name__ + ": " + str(error)
print(json.dumps(result, sort_keys=True))
PY
done

echo "=== Singularity cache ==="
singularity cache list 2>&1 || true

echo "=== failed runtime attempt remains preserved ==="
PROBE=/data1/home/sunyiq/regge_record_length_20260929_001/runtime_probe_001
stat -c '%A %U %G %s %y %n' "$PROBE" "$PROBE/logs/runtime-231216.out" "$PROBE/logs/runtime-231216.err"
