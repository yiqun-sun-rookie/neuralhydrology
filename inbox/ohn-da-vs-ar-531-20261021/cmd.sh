#!/bin/bash
# OHN latent-UKF pilot seq87 (read-only): chunk 01 of the transfer package + the 100 tune-basin data digest
# (seq86's digest lacked the pysite PYTHONPATH that provides zarr). Nothing written.
set -o pipefail
NEW=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021
OLD=/data1/home/sunyiq/openhydronet_531_20261015
X=$NEW/ukf_xfer_20261028
date --iso-8601=seconds
echo "=== DIGEST ==="
source ~/miniconda3/etc/profile.d/conda.sh && conda activate nh_final
export PYTHONPATH="$OLD/pysite"
python - "$OLD/data/id18_maurer" "$NEW/configs/tune_basins_100.txt" <<'PY'
import hashlib, sys
import numpy as np, xarray as xr
root, basins = sys.argv[1], open(sys.argv[2]).read().split()
def h(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes()).hexdigest()[:16]
q = xr.open_zarr(f'{root}/streamflow.zarr', consolidated=False)['streamflow'].sel(basin=basins)
d = q['date'].values
print('streamflow', q.dtype, q.shape, str(d[0])[:10], str(d[-1])[:10], h(q.values), round(float(np.nansum(q.values)), 3))
a = xr.open_zarr(f'{root}/attributes.zarr', consolidated=False).sel(basin=basins)
names = sorted(a.data_vars)
print('attributes', len(names), h(np.stack([a[v].values.astype('float32') for v in names])))
m = xr.open_zarr(f'{root}/dynamics/MAURER/timeseries.zarr', consolidated=False).sel(basin=basins)
for v in sorted(m.data_vars):
    x = m[v].values
    print('maurer', v, x.dtype, x.shape, h(x), round(float(np.nansum(x)), 3))
PY
echo "=== CHUNK_01_BASE64_BEGIN ==="
base64 -w 0 "$X/chunk_01"; echo
echo "=== CHUNK_01_BASE64_END ==="
echo "SEQ87_DONE"
