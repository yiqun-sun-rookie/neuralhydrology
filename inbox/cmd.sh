#!/bin/bash
# seq=9  read-only survey: can the adversarial 531 re-run start on HPC as-is?
R=~/neuralhydrology

echo "=== A. REPO STATE ==="
cd $R 2>/dev/null || { echo "REPO_MISSING"; exit 0; }
echo "branch: $(git rev-parse --abbrev-ref HEAD 2>&1)"
echo "commit: $(git log --oneline -1 2>&1)"
echo "dirty files: $(git status --porcelain 2>/dev/null | wc -l)"

echo "=== B. CAMELS DATA PRESENT? ==="
for d in data/camels_us/basin_mean_forcing/maurer data/camels_us/usgs_streamflow data/camels_us/camels_attributes_v2.0; do
  if [ -d "$R/$d" ]; then
    echo "OK   $d  size=$(du -sh $R/$d 2>/dev/null | cut -f1)  files=$(find $R/$d -type f 2>/dev/null | wc -l)"
  else
    echo "MISS $d"
  fi
done
echo "maurer subdirs: $(ls $R/data/camels_us/basin_mean_forcing/maurer 2>/dev/null | tr '\n' ' ')"

echo "=== C. TARGET MODEL PRESENT? ==="
M=$R/results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30
for f in config.yml model_epoch030.pt test/model_epoch030/test_results.p; do
  if [ -f "$M/$f" ]; then echo "OK   $f  $(du -h $M/$f | cut -f1)"; else echo "MISS $f"; fi
done
echo "--- config key lines ---"
grep -E "^data_dir|^dataset|^forcings" $M/config.yml 2>&1 | head -5

echo "=== D. ADVERSARIAL CODE PRESENT? ==="
ls $R/src/adversarial/scripts/run_exp*.py 2>&1 | head -10
echo "basin list lines: $(wc -l < $R/src/adversarial/data/531_basins.txt 2>&1)"
echo "existing adversarial results:"
ls $R/results/05_adversarial_robustness/ 2>&1 | head -5

echo "=== E. CONDA ENVS ==="
ls -d /data1/home/$USER/miniconda3/envs/* 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' '
echo ""

echo "=== F. GPU PARTITION NOW ==="
sinfo -p hgpu2p -o "%12P %10a %8D %20N %10T" 2>&1 | head -8
echo "--- my jobs ---"
squeue -u $USER 2>&1 | head -5

echo "=== G. DISK ==="
df -h /data1 2>&1 | tail -1
