#!/bin/bash
# id26-v09-strict seq=1 : read-only survey before any v09 migration decision.
# Nothing here computes, writes, or submits. Purely inventory.

echo "=== IDENTITY ==="
hostname; whoami; date '+%Y-%m-%d %H:%M:%S %z'

echo "=== DISK ==="
df -h /data1 2>&1 | tail -2
echo "-- home usage (top level, may be slow; capped) --"
du -sh "$HOME" 2>/dev/null

echo "=== HOME TOP LEVEL (do not disturb existing work) ==="
ls -la "$HOME" 2>&1 | head -30

echo "=== RUNNING / QUEUED JOBS (must not disturb) ==="
squeue -u "$USER" -o "%.10i %.14j %.9P %.8T %.10M %.6D %R" 2>&1 | head -20

echo "=== RECENT JOBS (last 3 days) ==="
sacct -S "$(date -d '3 days ago' +%Y-%m-%d)" -X --format=JobID%10,JobName%18,State%12,Elapsed%10,NodeList%9 2>&1 | head -20

echo "=== PARTITIONS ==="
sinfo -s 2>&1 | head -12

echo "=== NEURALHYDROLOGY REPO STATE ==="
if [ -d "$HOME/neuralhydrology" ]; then
  cd "$HOME/neuralhydrology" || exit 0
  echo "HEAD=$(git rev-parse HEAD 2>&1)"
  echo "branch=$(git rev-parse --abbrev-ref HEAD 2>&1)"
  echo "dirty_files=$(git status --porcelain --untracked-files=all 2>/dev/null | wc -l)"
  echo "remote=$(git config --get remote.origin.url 2>&1)"
  echo "-- does the v09 branch exist remotely? --"
  git ls-remote --heads origin codex/historical-band-experts-pilot 2>&1 | head -3
else
  echo "MISSING: $HOME/neuralhydrology"
fi

echo "=== IS THE V09 CODE PRESENT? ==="
ls "$HOME/neuralhydrology/src/26_historical_band_experts/" 2>&1 | head -5

echo "=== RAW CAMELS DATA (needed only if inputs were ever rebuilt here) ==="
for d in basin_mean_forcing/maurer usgs_streamflow camels_attributes_v2.0; do
  p="$HOME/neuralhydrology/data/camels_us/$d"
  if [ -e "$p" ]; then echo "OK   $d  $(du -sh "$p" 2>/dev/null | cut -f1)"; else echo "MISS $d"; fi
done

echo "=== LEGACY 8-SEED CHECKPOINTS (bridge needs these) ==="
L="$HOME/neuralhydrology/results/18_lstm_fair_531"
if [ -d "$L" ]; then
  echo "dir exists"
  ls "$L" 2>/dev/null | head -10
  echo "checkpoint count: $(find "$L" -name 'model_epoch030.pt' 2>/dev/null | wc -l)"
  echo "config count:     $(find "$L" -name 'config.yml' 2>/dev/null | wc -l)"
else
  echo "MISSING $L"
fi

echo "=== ANY EXISTING V09 FORMAL DIR? (must not clobber) ==="
ls -la "$HOME/neuralhydrology/results/26_historical_band_experts" 2>&1 | head -10

echo "=== CONDA ENV nh_final ==="
source "$HOME/miniconda3/etc/profile.d/conda.sh" 2>/dev/null && conda activate nh_final 2>/dev/null && \
  python -c "import sys,torch,numpy;print('python',sys.version.split()[0]);print('torch',torch.__version__);print('cuda',torch.version.cuda);print('numpy',numpy.__version__)" 2>&1 | head -6

echo "=== END ==="
