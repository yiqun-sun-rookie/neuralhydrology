#!/bin/bash
# seq=13 : diagnose why conda activate nh_final failed (read-only)

echo "=== A CONDA LOCATION ==="
which conda 2>&1
ls -d /data1/home/${USER}/miniconda3 2>&1
echo "--- envs ---"
/data1/home/${USER}/miniconda3/bin/conda env list 2>&1 | head -12

echo "=== B ACTIVATE WITH FULL OUTPUT ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
echo "source_rc=$?"
conda activate nh_final
echo "activate_rc=$?"
echo "CONDA_PREFIX=$CONDA_PREFIX"
echo "which python: $(which python)"
python --version 2>&1

echo "=== C PACKAGES IN nh_final (direct path) ==="
NHP=/data1/home/${USER}/miniconda3/envs/nh_final
ls -d $NHP 2>&1
$NHP/bin/python --version 2>&1
$NHP/bin/python -c "
for m in ['torch','pandas','numpy','pyarrow','tqdm','scipy','sklearn']:
    try:
        mod=__import__(m); print('  OK  ',m,getattr(mod,'__version__','?'))
    except Exception as e: print('  MISS',m,type(e).__name__)
" 2>&1 | head -12

echo "=== D OTHER ENVS QUICK CHECK ==="
for e in nh_clean neuralhydrology knet_clean; do
  P=/data1/home/${USER}/miniconda3/envs/$e/bin/python
  if [ -x "$P" ]; then
    echo "--- $e: $($P --version 2>&1)"
    $P -c "
import importlib
got=[]
for m in ['torch','pandas','numpy','pyarrow']:
    try:
        mod=importlib.import_module(m); got.append(m+'='+getattr(mod,'__version__','?'))
    except Exception: got.append(m+'=MISS')
print('   ', ' '.join(got))
" 2>&1 | head -3
  fi
done
