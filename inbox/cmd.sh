#!/bin/bash
# seq=11  robust fingerprints (immune to md5sum binary marker) + inspect the 4 suspect maurer files.
export LC_ALL=C
R=~/neuralhydrology
cd $R || { echo "REPO_MISSING"; exit 0; }

echo "=== ROBUST FINGERPRINTS ==="
for d in data/camels_us/basin_mean_forcing/maurer data/camels_us/usgs_streamflow data/camels_us/camels_attributes_v2.0; do
  hashonly=$(find "$d" -type f | sort | xargs md5sum 2>/dev/null | awk '{print $1}' | md5sum | cut -c1-32)
  paths=$(find "$d" -type f | sort | md5sum | cut -c1-32)
  echo "$d  hashes_md5=$hashonly  paths_md5=$paths"
done

echo "=== THE 4 SUSPECT FILES ON HPC ==="
for p in 03/02108000 09/05120500 11/07067000 15/09492400; do
  f="data/camels_us/basin_mean_forcing/maurer/${p}_lump_maurer_forcing_leap.txt"
  if [ -f "$f" ]; then
    echo "--- $p  size=$(stat -c%s $f)  md5=$(md5sum $f | cut -c1-32)"
    sed -n '4p' "$f" | cut -c1-100
  else
    echo "--- $p MISSING"
  fi
done

echo "=== A KNOWN-GOOD FILE FOR CONTRAST ==="
f=data/camels_us/basin_mean_forcing/maurer/01/01022500_lump_maurer_forcing_leap.txt
echo "01022500 size=$(stat -c%s $f) md5=$(md5sum $f | cut -c1-32)"
sed -n '4p' "$f" | cut -c1-100
