#!/bin/bash
# id23-r-pert seq=1 : read-only reconnaissance, no compute, no job submission
echo "=== WHO/WHERE ==="
whoami; hostname; date -Is; pwd

echo "=== HOME TOP LEVEL ==="
ls -1 ~/ | head -40

echo "=== TARGET DIR (prereg 6.2: ~/id23_r_perturbation) ==="
ls -la ~/id23_r_perturbation 2>&1 | head -5

echo "=== CONDA ENVS ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda env list 2>&1 | head -20

echo "=== PY DEPS IN nh_final ==="
conda activate nh_final 2>/dev/null && python -c "import sys,numpy,pandas;print('python',sys.version.split()[0]);print('numpy',numpy.__version__);print('pandas',pandas.__version__)" 2>&1
python -c "import cma;print('cma',cma.__version__)" 2>&1 | head -3
python -c "import psutil;print('psutil',psutil.__version__)" 2>&1 | head -3

echo "=== CPU QUEUE STATE ==="
sinfo -p hcpu48 -o "%12P %6D %8T %6c %10m" 2>&1 | head -10
echo "--- my jobs ---"
squeue -u $USER -o "%.10i %.12j %.9P %.8T %.10M" 2>&1 | head -20

echo "=== EXISTING neuralhydrology CLONE (read-only peek, git untouched) ==="
ls -d ~/neuralhydrology 2>&1
ls -1 ~/neuralhydrology/src 2>/dev/null | head -30
echo "--- camels_switch_confirmation present? ---"
ls -1 ~/neuralhydrology/src/camels_switch_confirmation 2>&1 | head -8
echo "--- stage3 frozen products present? ---"
ls -d ~/neuralhydrology/results/23_camels_switch_confirmation/online_noise_real_obs_stage3_01_20260818_local 2>&1
ls -d ~/neuralhydrology/results/23_camels_switch_confirmation/noise_axis_step2_learned_q_20260827_local 2>&1
echo "--- camels data present? ---"
ls -d ~/neuralhydrology/data/camels_us 2>&1 | head -3
du -sh ~/neuralhydrology/data/camels_us 2>/dev/null | head -2

echo "=== DISK ==="
df -h /data1/home/$USER 2>&1 | head -3
