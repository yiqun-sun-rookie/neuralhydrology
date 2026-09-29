#!/bin/bash
# precip-selfrule-v05 seq=27: locate the active neuralhydrology package without importing frozen assimilation modules.
set -eo pipefail

ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_concurrency4_probe_20260929

date "+wallclock %F %T %z"
test ! -e "$ROOT" || { echo "PROBE_ROOT_ALREADY_EXISTS=$ROOT"; exit 1; }
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
python - <<'PY'
import hashlib
from pathlib import Path
import neuralhydrology
root = Path(neuralhydrology.__file__).resolve().parent
print("PACKAGE_ROOT", root)
for relative in ("evaluation/assimilation.py", "utils/assimilationconfig.py"):
    path = root / relative
    print(relative, "EXISTS", path.is_file())
    if path.is_file():
        print(relative, "SHA256", hashlib.sha256(path.read_bytes()).hexdigest())
PY
