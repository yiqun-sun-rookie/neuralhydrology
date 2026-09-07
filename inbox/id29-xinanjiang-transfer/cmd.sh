#!/bin/bash
set -eo pipefail
printf 'SECOND_MODEL_DEPENDENCY_PROBE\n'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import sys
import importlib.metadata as m
print(sys.executable)
for name in ['numpy','pandas','numba','cma','pytest','pluggy','packaging','iniconfig','pygments']:
    try:
        print(name, m.version(name))
    except m.PackageNotFoundError:
        print(name, 'MISSING')
PY
printf 'PROBE_COMPLETE\n'
