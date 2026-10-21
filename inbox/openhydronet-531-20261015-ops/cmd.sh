#!/bin/bash
set -o pipefail
# Read-only health check of the shared OpenHydroNet install (runs on the HPC login node through the ops mailbox channel).
# FAIL = the install is missing / changed / cannot be imported. WARN = something drifted but the install still imports.
SH=/data1/home/sunyiq/openhydronet_shared
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
BASE="$ROOT/results/shared_baseline.txt"
fail=0
date --iso-8601=seconds

if [ ! -d "$SH" ]; then echo "HEALTH_FAIL: SHARED_DIR_MISSING"; exit 0; fi
for f in env.sh run_template.slurm VERSION README.md pysite flood-forecasting; do
  [ -e "$SH/$f" ] || { echo "HEALTH_FAIL: MISSING:$f"; fail=1; }
done

# file count + total bytes of the install (bytecode caches excluded) against the baseline taken at the first check
fp=$(find "$SH" -type f -not -name '*.pyc' -printf '%s\n' 2>/dev/null | awk '{n++; s+=$1} END {print n, s}')
if [ ! -f "$BASE" ]; then
  echo "$fp" > "$BASE"; echo "BASELINE_CREATED: $fp"
elif [ "$fp" != "$(cat "$BASE")" ]; then
  echo "HEALTH_FAIL: FINGERPRINT_CHANGED now=[$fp] baseline=[$(cat "$BASE")]"; fail=1
fi
w=$(find "$SH" -perm -u+w -not -type l 2>/dev/null | head -3 | wc -l)
[ "$w" = "0" ] || echo "HEALTH_WARN: install is not read-only any more ($w writable entries seen)"

# the decisive test: a fresh shell sources env.sh and imports the package
cat > "$ROOT/results/health_import.py" <<'PY'
import itertools, sys
import numpy, pandas, torch, xarray
print("VERS", sys.version.split()[0], torch.__version__, numpy.__version__, pandas.__version__, xarray.__version__)
import googlehydrology, zarr
from googlehydrology.modelzoo import mean_embedding_forecast_lstm
print("IMPORT_OK", "batched=%s" % hasattr(itertools, "batched"), "zarr=" + zarr.__version__, googlehydrology.__file__)
PY
out=$(bash -c "source $SH/env.sh >/dev/null 2>&1 && cd /tmp && python $ROOT/results/health_import.py" 2>&1)
echo "$out" | grep -E '^(VERS|IMPORT_OK)|Error|Traceback' | head -6 | cut -c1-200
echo "$out" | grep -q '^IMPORT_OK' || { echo "HEALTH_FAIL: IMPORT_FAILED"; fail=1; }
echo "$out" | grep -q '^VERS 3.11.13 2.4.0 2.3.3 2.3.2 2025.12.0$' || echo "HEALTH_WARN: shared conda env nh_final versions differ from the verified set (python torch numpy pandas xarray: 3.11.13 2.4.0 2.3.3 2.3.2 2025.12.0)"

sacct -X -n -P -j 245855 --format=JobID,State,ExitCode,Elapsed 2>/dev/null | sed 's/^/SMOKE_JOB /'

if [ $fail = 0 ]; then echo "HEALTH_PASS"; else echo "HEALTH_FAIL: see lines above"; fi
exit 0
