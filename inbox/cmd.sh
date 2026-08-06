#!/bin/bash
# seq=10  data-identity check: fingerprint the CAMELS inputs so local and HPC can be compared.
export LC_ALL=C
R=~/neuralhydrology
cd $R || { echo "REPO_MISSING"; exit 0; }

echo "=== DATA MANIFEST FINGERPRINTS ==="
for d in data/camels_us/basin_mean_forcing/maurer data/camels_us/usgs_streamflow data/camels_us/camels_attributes_v2.0; do
  n=$(find "$d" -type f | wc -l)
  b=$(find "$d" -type f -printf '%s\n' | awk '{s+=$1} END{print s}')
  h=$(find "$d" -type f | sort | xargs md5sum 2>/dev/null | md5sum | cut -c1-32)
  echo "$d  files=$n  bytes=$b  manifest_md5=$h"
done

echo "=== SAMPLE FILE HEAD (line-ending probe) ==="
f=$(find data/camels_us/basin_mean_forcing/maurer -name "01022500*" -type f | head -1)
echo "file: $f"
head -4 "$f" | cat -A | cut -c1-90

echo "=== FREE SPACE FOR NEW WORKDIR ==="
df -h /data1 | tail -1
ls -d ~/adv531 2>/dev/null && echo "adv531 EXISTS" || echo "adv531 absent (good)"

echo "=== STUCK JOBS ==="
squeue -u $USER -o "%.10i %.10P %.14j %.3t %.10M %R" 2>&1 | head -6
