#!/bin/bash
echo "=== A. are our 64 basins all in the HPC archive? ==="
cd ~/neuralhydrology/data/camels_us || exit 1
MISS=0
for b in 10259000 04045500 12175500 02300700 08190500 02038850 11230500 06847900 11143000 14301000 04122500 09306242 05458000 02450250 06289000 08109700 08267500 14216500 11151300 12375900 11528700 06879650 02472000 06614800 04213075 12073500 04296000 13313000 06350000 01491000 03281500 08194200 04057510 13240000 04063700 11476600 01466500 07060710 08158810 10244950 14020000 14138800 12010000 04115265 08066300 04185000 06409000 02231000 09378170 07142300 02077200 02102908 01451800 09512280 06906800 03455500 13161500 04027000 09494000 09430600 12167000 11381500 12377150 08189500; do
  F=$(find basin_mean_forcing/maurer -name "${b}_*_forcing_leap.txt" 2>/dev/null | wc -l)
  Q=$(find usgs_streamflow -name "${b}_streamflow_qc.txt" 2>/dev/null | wc -l)
  [ "$F" -eq 1 ] && [ "$Q" -eq 1 ] || { echo "MISSING $b forcing=$F flow=$Q"; MISS=$((MISS+1)); }
done
echo "missing_basins=$MISS / 64"
echo "=== B. conda envs available ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null && conda env list 2>&1 | head -10
echo "=== C. are the pinned versions installable? (query only, no install) ==="
conda activate nh_final 2>/dev/null
timeout 60 pip index versions numpy 2>&1 | head -3
timeout 60 pip index versions pyarrow 2>&1 | head -3
echo "=== D. git on login node ==="
git --version 2>&1
echo "=== E. does ~/autoresearch64 already exist? (must not clobber) ==="
ls -d ~/autoresearch64 2>&1 | head -2
echo "=== F. other people's live jobs (do not disturb) ==="
squeue -u "$USER" -o "%.10i %.14j %.10P %.8T %.10M" 2>&1 | head -10
echo "=== G. cpu partition idle ==="
sinfo -p hcpu48 -o "%.10P %.6D %.14F" 2>&1 | head -3
