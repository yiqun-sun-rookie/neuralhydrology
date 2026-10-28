#!/bin/bash
# OHN latent-UKF pilot seq86 (read-only on all existing data): the pilot runs on AutoDL (user priority 2026-10-28).
# 1) package the tune_v0 run used by P1b (config, scaler, epoch-50 weights) + P1b g04/noda result zarrs, split into
#    5 MB chunks under the NEW temp dir $NEW/ukf_xfer_20261028; print chunk 0 as base64 (chunks 1.. in later seqs);
# 2) digest of the 100 tune-basin ID18 data, to check the AutoDL rebuild. No jobs, nothing else written.
set -o pipefail
NEW=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021
OLD=/data1/home/sunyiq/openhydronet_531_20261015
X=$NEW/ukf_xfer_20261028
date --iso-8601=seconds
RUN=$(ls "$NEW/copies/p1b/noda" | head -1)
G04=$(ls -d "$NEW"/copies/p1b/g04_* | head -1)
echo "RUN=$RUN G04=$(basename "$G04")"
ls -la "$OLD/runs/$RUN" | grep -v -E 'model_epoch0[0-4]|optimizer_state' | head -30

if [ ! -f "$X/MANIFEST.txt" ]; then
  [ -e "$X" ] && { echo "XFER_DIR_INCOMPLETE"; ls -la "$X"; exit 1; }
  mkdir -p "$X/pack/run" "$X/pack/p1b"
  tar -C "$OLD/runs/$RUN" --exclude=./test --exclude=./validation --exclude=./train \
      --exclude='./model_epoch00*' --exclude='./model_epoch01*' --exclude='./model_epoch02*' \
      --exclude='./model_epoch03*' --exclude='./model_epoch04*' --exclude='./optimizer_state*' -cf - . \
    | tar -C "$X/pack/run" -xf -
  [ -f "$X/pack/run/model_epoch050.pt" ] || { echo "MISSING_WEIGHTS"; exit 1; }
  mkdir -p "$X/pack/p1b/g04" "$X/pack/p1b/noda"
  cp -a "$G04/$RUN/test/model_epoch050/test_results_data_assimilation.zarr" "$X/pack/p1b/g04/"
  cp -a "$NEW/copies/p1b/noda/$RUN/test/model_epoch050/test_results.zarr" "$X/pack/p1b/noda/"
  cp "$NEW/results/p1b/p1b_grid_scores.csv" "$X/pack/p1b/" 2>/dev/null || true
  echo "$RUN" > "$X/pack/RUN_NAME"
  (cd "$X/pack" && find . -type f | sort | xargs sha256sum) > "$X/pack_files.sha256"
  tar -C "$X/pack" -czf "$X/xfer.tar.gz" .
  split -b 5000000 -d -a 2 "$X/xfer.tar.gz" "$X/chunk_"
  (cd "$X" && sha256sum xfer.tar.gz chunk_* > MANIFEST.txt)
fi
echo "=== PACK ==="
du -sh "$X/pack/run" "$X/pack/p1b"
cat "$X/MANIFEST.txt"
ls -l "$X"/chunk_* | awk '{print $5, $9}'
echo "=== P1B GRID ==="
cat "$X/pack/p1b/p1b_grid_scores.csv" 2>/dev/null

echo "=== DIGEST ==="
source ~/miniconda3/etc/profile.d/conda.sh && conda activate nh_final
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
sha256sum "$NEW/configs/tune_basins_100.txt"

echo "=== CHUNK_00_BASE64_BEGIN ==="
base64 -w 0 "$X/chunk_00"; echo
echo "=== CHUNK_00_BASE64_END ==="
echo "SEQ86_DONE"
