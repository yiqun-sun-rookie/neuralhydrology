#!/bin/bash
# ID29 probe 2: can the HPC fetch the extended forcings itself, and what do the GPU nodes look like?
# Read-only / no sbatch.

echo "=== A: outbound reachability ==="
for u in https://www.hydroshare.org https://github.com https://pypi.org; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$u" 2>/dev/null)
  echo "  $u -> ${code:-TIMEOUT}"
done

echo "=== B: hydroshare bag endpoint (headers only, no download) ==="
curl -sIL --max-time 30 "https://www.hydroshare.org/hsapi/resource/17c896843cf940339c3c3496d0c1c077/" 2>&1 \
  | grep -iE "^HTTP|^location|^content-length" | head -6

echo "=== C: gpu node detail (hgpu4 / hgpu8) ==="
for n in ngu101 ngu201; do
  scontrol show node $n 2>/dev/null | grep -oE "NodeName=[^ ]+|Gres=[^ ]+|CPUTot=[0-9]+|RealMemory=[0-9]+|State=[^ ]+" | tr '\n' ' '
  echo ""
done

echo "=== D: queue pressure ==="
squeue -h -o "%.10P %.8T" 2>/dev/null | sort | uniq -c | head -10
echo "my jobs:"; squeue -u "$USER" -h 2>/dev/null | wc -l

echo "=== E: nh_final package check ==="
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY' 2>&1 | tail -20
import importlib
for m in ['torch','numpy','pandas','xarray','ruamel.yaml','tqdm','scipy','numba','matplotlib','netCDF4','sklearn']:
    try:
        mod = importlib.import_module(m)
        print(f'  OK   {m:14s} {getattr(mod,"__version__","?")}')
    except Exception as e:
        print(f'  MISS {m:14s} {type(e).__name__}')
PY

echo "=== F: camels data sanity (read-only) ==="
D=/data1/home/sunyiq/neuralhydrology_backup_20260304/data/camels_us
ls $D
echo "basins in maurer: $(ls $D/basin_mean_forcing/maurer/*/*.txt 2>/dev/null | wc -l)"
echo "basins in daymet: $(ls $D/basin_mean_forcing/daymet/*/*.txt 2>/dev/null | wc -l)"
echo "basins in nldas:  $(ls $D/basin_mean_forcing/nldas/*/*.txt 2>/dev/null | wc -l)"
echo "streamflow files: $(ls $D/usgs_streamflow/*/*.txt 2>/dev/null | wc -l)"
head -4 $D/basin_mean_forcing/maurer/01/01013500_lump_maurer_forcing_leap.txt 2>/dev/null | tail -1
