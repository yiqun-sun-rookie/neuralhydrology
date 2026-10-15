#!/bin/bash
set -o pipefail
# READ-ONLY probe + create own landing dir (seq 1). Touches nothing outside ROOT.
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds; hostname
mkdir -p "$ROOT/logs" "$ROOT/pysite" "$ROOT/data" "$ROOT/src" "$ROOT/runs" "$ROOT/configs" && echo "ROOT_READY $ROOT"
df -h /data1 | tail -1
echo "=== nh_final (read-only) ==="
source ~/miniconda3/etc/profile.d/conda.sh; conda activate nh_final || { echo CONDA_FAILED; exit 1; }
python -V
python - <<'PY'
import importlib
mods = ["torch", "numpy", "pandas", "scipy", "xarray", "zarr", "numcodecs", "dask", "cachey", "toolz", "cloudpickle", "fsspec", "heapdict",
        "donfig", "packaging", "pydantic", "pydantic_core", "annotated_types", "typing_inspection", "ruamel.yaml", "yaml", "more_itertools",
        "tqdm", "tensorboard", "absl", "matplotlib", "pyarrow", "psutil", "dateutil", "pytz", "typing_extensions", "partd", "locket", "sympy", "filelock", "jinja2", "networkx"]
for m in mods:
    try:
        x = importlib.import_module(m)
        print("OK     ", m, getattr(x, "__version__", ""))
    except Exception as e:
        print("MISSING", m, type(e).__name__)
import torch
print("torch cuda build", torch.version.cuda)
PY
echo "=== network (30s+ timeouts) ==="
curl -sS -m 45 -o /dev/null -w "gcs-bucket http=%{http_code} t=%{time_total}s\n" "https://storage.googleapis.com/storage/v1/b/caravan-multimet/o?maxResults=1" 2>&1 | tail -1
curl -sS -m 60 -o /dev/null -w "usgs-nwis http=%{http_code} t=%{time_total}s\n" "https://waterservices.usgs.gov/nwis/dv/?format=json&sites=01022500&parameterCd=00060&statCd=00003&startDT=2025-01-01&endDT=2025-01-31" 2>&1 | tail -1
curl -sS -m 60 -o /dev/null -w "pypi http=%{http_code} t=%{time_total}s\n" "https://pypi.org/simple/zarr/" 2>&1 | tail -1
timeout 90 git ls-remote https://github.com/google-research/flood-forecasting.git HEAD 2>&1 | head -2
echo "=== GPU partitions (free cards) ==="
for P in hgpu8 hgpu4 hgpu2p hgpu2; do echo "-- $P"; sinfo -p $P -N -h -O nodelist:10,statecompact:8,gres:10,gresused:22,cpusstate:16 2>&1 | head -12; done
echo "=== my queue ==="
squeue -u sunyiq -h -o '%.12i %.18j %.9T %.10M %R' | head -20
exit 0
