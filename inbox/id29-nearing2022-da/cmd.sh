#!/bin/bash
# ID29 seq=71: install direct-evaluation execution metadata and verify repaired dependency state.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/id29-nearing2022-da/closure_v7.tar.gz
EXPECTED_PAYLOAD_SHA=354238801963aec7626052a26a77df166b09b28f9dc7b5a07a9122f56b092fd8
REGISTRY="$ROOT/src/29_nearing2022_da_ar/registry/evaluation_registry.csv"

echo "=== INSTALL ==="
echo "$EXPECTED_PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
test "$(tar -tzf "$PAYLOAD" | wc -l)" -eq 1
tar -xzf "$PAYLOAD" -C "$ROOT"
echo "37b312dbd362399a9771f2233d1e1139ea25d5339d1bbc7a806fa75be30b9215  $REGISTRY" | sha256sum -c -

echo "=== REGISTRY BINDING ==="
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python - <<'PY'
from pathlib import Path
import pandas as pd

path = Path('/data1/home/sunyiq/nearing2022_da/src/29_nearing2022_da_ar/registry/evaluation_registry.csv')
registry = pd.read_csv(path, keep_default_na=False, dtype=str)
direct = registry.loc[registry['family'].isin({'basin_simulation', 'basin_autoregression'})]
expected = [f'202238_{index}' for index in range(20)]
actual = direct['slurm_job_id'].tolist()
if len(direct) != 20 or actual != expected or set(direct['status']) != {'submitted'}:
    raise SystemExit(f'Invalid direct evaluation execution binding: rows={len(direct)} jobs={actual}')
print('direct_rows=20')
print('direct_jobs=202238_0..202238_19')
PY

echo "=== JOB AND DEPENDENCY ==="
squeue -j 202238,202229 -o '%.18i %.24j %.2t %.10M %.6D %R'
scontrol show job -o 202229 | sed -n 's/.*Dependency=\([^ ]*\).*/aggregation_dependency=\1/p'
sacct -n -P -j 202238 --format=JobID,State,ExitCode | awk -F'|' 'NF >= 3 && $1 !~ /\./ {print}' | sort
