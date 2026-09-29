#!/bin/bash
# precip-selfrule-v05 seq=1 (2026-09-29): read-only preflight for selfrule_time_v05.
# No compute, no sbatch, no writes outside the mailbox receipt.
set -o pipefail
ROOT=/data1/home/sunyiq/precip_input_da_2026_09
NEWROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_20260929
REPO=$HOME/neuralhydrology

date "+wallclock %F %T %z"
hostname

echo "=== A. CURRENT USER JOBS ==="
squeue -u sunyiq -o "%.18i %.28j %.10P %.2t %.10M %.6D %R"

echo "=== B. GPU NODE STATE ==="
sinfo -p hgpu2p,hgpu4,hgpu8 -N -O nodelist,partition,statecompact,gres:18,gresused:30,cpusstate

echo "=== C. REQUIRED PATHS ==="
for p in "$ROOT" "$REPO" "$REPO/data/camels_us" "$REPO/data/camels_us/basin_mean_forcing/maurer" "$REPO/data/camels_us/usgs_streamflow"; do
  if [ -e "$p" ]; then
    echo "PRESENT $p"
  else
    echo "MISSING $p"
  fi
done
if [ -e "$NEWROOT" ]; then
  echo "NEWROOT_ALREADY_EXISTS $NEWROOT"
else
  echo "NEWROOT_FREE $NEWROOT"
fi

echo "=== D. C4 LANDING FILES ==="
find "$ROOT" -maxdepth 6 -type f \( -name model_epoch030.pt -o -name config.yml -o -name train_data_scaler.yml \) -print 2>/dev/null

echo "=== E. CORE SOURCE HASHES ==="
for rel in neuralhydrology/modelzoo/cudalstm.py neuralhydrology/modelzoo/inputlayer.py neuralhydrology/modelzoo/__init__.py neuralhydrology/modelzoo/head.py neuralhydrology/utils/config.py neuralhydrology/datautils/utils.py neuralhydrology/datasetzoo/camelsus.py; do
  f="$REPO/$rel"
  if [ -f "$f" ]; then
    sha256sum "$f"
  else
    echo "MISSING $f"
  fi
done

echo "=== F. ENVIRONMENT ==="
if command -v conda >/dev/null 2>&1; then
  conda run -n nh_final python -c 'import sys, torch, numpy, pandas, yaml; print(sys.version.split()[0], torch.__version__, torch.cuda.is_available(), numpy.__version__, pandas.__version__)'
else
  echo "CONDA_NOT_ON_PATH"
fi

echo "=== DONE READ-ONLY PREFLIGHT ==="