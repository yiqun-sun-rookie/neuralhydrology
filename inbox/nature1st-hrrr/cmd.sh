#!/bin/bash
# nature1st-hrrr seq=1 : READ-ONLY feasibility probe. No sbatch, no writes outside this file.
export LC_ALL=C

echo "=== A HRRR ARCHIVE REACHABLE (decisive question) ==="
# Long timeouts on purpose: this host's TLS handshake alone can take 11s.
URL="https://noaa-hrrr-bdp-pds.s3.amazonaws.com/?list-type=2&prefix=hrrr.20240101/conus/hrrr.t00z.wrfsfcf01&max-keys=4"
curl -s -o /tmp/hrrr_probe.xml -w "  http=%{http_code} tls=%{time_appconnect}s total=%{time_total}s bytes=%{size_download}\n" \
     --max-time 90 "$URL" 2>&1 || echo "  CURL_FAILED rc=$?"
echo "  --- keys returned ---"
grep -o "<Key>[^<]*</Key>" /tmp/hrrr_probe.xml 2>/dev/null | head -4 || echo "  (no keys parsed)"

echo "=== B BYTE-RANGE FETCH (the actual access pattern we need) ==="
OBJ="https://noaa-hrrr-bdp-pds.s3.amazonaws.com/hrrr.20240101/conus/hrrr.t00z.wrfsfcf01.grib2"
curl -s -r 0-1048575 -o /tmp/hrrr_range.bin -w "  http=%{http_code} total=%{time_total}s bytes=%{size_download} speed=%{speed_download}B/s\n" \
     --max-time 120 "$OBJ" 2>&1 || echo "  RANGE_FAILED rc=$?"
ls -la /tmp/hrrr_range.bin 2>/dev/null | awk '{print "  local:",$5,"bytes"}'
rm -f /tmp/hrrr_probe.xml /tmp/hrrr_range.bin

echo "=== C GRIB DECODE TOOLING IN nh_final ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null || echo "  CONDA_ACTIVATE_FAILED"
for m in torch numpy pandas xarray cfgrib eccodes pyarrow netCDF4 psutil; do
  python - "$m" <<'PY' 2>/dev/null || echo "  MISS $m"
import importlib, sys
m = sys.argv[1]
mod = importlib.import_module(m)
print(f"  OK   {m} {getattr(mod,'__version__','?')}")
PY
done
command -v wgrib2 >/dev/null && echo "  OK   wgrib2 $(wgrib2 -version 2>&1 | head -1)" || echo "  MISS wgrib2"

echo "=== D STORAGE HEADROOM ==="
df -h /data1 2>&1 | tail -1 | awk '{print "  /data1 size="$2" used="$3" avail="$4" ("$5")"}'
du -sh /data1/home/$USER 2>/dev/null | awk '{print "  home total: "$1}'

echo "=== E EXISTING nature_1st PACKAGE (read-only, not touching it) ==="
if [ -d /data1/home/$USER/nature_1st_a02 ]; then
  du -sh /data1/home/$USER/nature_1st_a02 2>/dev/null | awk '{print "  ~/nature_1st_a02 size: "$1}'
  ls /data1/home/$USER/nature_1st_a02 2>/dev/null | head -12 | sed 's/^/    /'
  echo "  --- data subdir sizes ---"
  du -sh /data1/home/$USER/nature_1st_a02/data/* 2>/dev/null | head -8 | sed 's/^/    /'
else
  echo "  absent"
fi

echo "=== F GPU AVAILABILITY RIGHT NOW ==="
sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -h -O "Partition:10,NodeList:26,StateLong:10,Nodes:5" 2>&1 | head -10 | sed 's/^/  /'
echo "  --- my jobs (must not be disturbed) ---"
squeue -u "$USER" -h -o "  %.9i %.16j %.9P %.8T %.10M" 2>&1 | head -20
