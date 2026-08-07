#!/bin/bash
# a02 seq=6 : unpack the verified tarball and prepare the job environment.
# No sbatch here -- submitting jobs costs billed compute and needs the user's word.
export LC_ALL=C
set -o pipefail
HOME_DIR=/data1/home/$USER
PKG=$HOME_DIR/nature_1st_a02

echo "=== A UNPACK ==="
cd $HOME_DIR || exit 1
if [ -d "$PKG" ]; then
  echo "  package dir already exists -- refusing to overwrite"
  ls -d $PKG
else
  time tar xzf nature_1st_a02.tar.gz 2>&1 | tail -3
  echo "  unpacked"
fi

echo "=== B STRUCTURE ==="
for d in data/processed/timeseries data/interim data/processed/station_meta scripts src/models hpc reference; do
  n=$(ls -1 $PKG/$d 2>/dev/null | wc -l)
  printf "  %-32s %6s entries\n" "$d" "$n"
done

echo "=== C KEY FILES PRESENT ==="
for f in scripts/train_depth_v1.py src/stage_dataset_v2.py src/models/simple_lstm_v2.py \
         data/interim/stage_station_splits.json reference/A01R1_config.json \
         manifest_sha256.json hpc/a02_smoke.slurm hpc/verify_package.py \
         hpc/check_config_contract.py hpc/submit_all.sh; do
  [ -f "$PKG/$f" ] && echo "  OK   $f" || echo "  MISS $f"
done
echo "  slurm job scripts: $(ls -1 $PKG/hpc/a02_*.slurm 2>/dev/null | wc -l) (expect 13)"

echo "=== D FIX LINE ENDINGS + PERMISSIONS (iron rule 4) ==="
sed -i 's/\r$//' $PKG/hpc/*.slurm $PKG/hpc/*.sh $PKG/hpc/*.py $PKG/scripts/*.py $PKG/src/*.py $PKG/src/models/*.py 2>/dev/null
chmod +x $PKG/hpc/*.sh 2>/dev/null
file $PKG/hpc/a02_smoke.slurm 2>&1 | sed 's/^/  /'
mkdir -p $PKG/logs $PKG/runs
echo "  logs/ and runs/ ready"

echo "=== E IMPORT SMOKE (login node, lightweight) ==="
cd $PKG
PYTHONPATH=$PKG /data1/home/$USER/miniconda3/envs/nh_final/bin/python -c "
import sys
from src.stage_dataset_v2 import StageDatasetConfigV2
from src.models.simple_lstm_v2 import FlowAuxRegressorV2
cfg = StageDatasetConfigV2()
print('  imports OK')
print('  window',cfg.window,'stride',cfg.stride,'align',cfg.discharge_alignment)
import pandas as pd
d = pd.read_parquet('data/processed/timeseries/01011000_hourly.parquet')
print('  sample station rows',len(d),'cols',list(d.columns))
" 2>&1 | tail -8

echo "=== F CLI CONTRACT ==="
/data1/home/$USER/miniconda3/envs/nh_final/bin/python $PKG/scripts/train_depth_v1.py --help 2>&1 | grep -E "discharge_alignment|--seed|--output_dir|--device|require_empty" | head -6

echo "=== G DISK ==="
du -sh $PKG 2>&1
df -h /data1 2>&1 | tail -1
