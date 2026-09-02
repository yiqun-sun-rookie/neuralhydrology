#!/bin/bash
# ID23 parameter-axis multicandidate value probe -- read-only reconnaissance.
# No sbatch, no writes outside ~/id23_param_probe (which is only probed, not created).
echo "=== WHOAMI / HOST ==="
whoami; hostname; date

echo "=== RUNNING JOBS (do not disturb) ==="
squeue -u "$USER" -o "%.10i %.18j %.10P %.8T %.11M %.6D %R" 2>&1 | head -40
echo "job_count=$(squeue -u "$USER" -h -o '%i' 2>/dev/null | wc -l)"

echo "=== MY LANDING DIR (must be absent or empty) ==="
ls -ld ~/id23_param_probe 2>&1 | head -3
ls -la ~/id23_param_probe 2>&1 | head -10

echo "=== SISTER LINE DIRS (must NOT touch) ==="
ls -ld /data1/home/sunyiq/id29_transferable_noise_20260902 2>&1 | head -2

echo "=== CONDA ENV / NUMPY ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>&1 | head -2
python -c "import sys,numpy; print('python', sys.version.split()[0]); print('numpy', numpy.__version__)" 2>&1 | head -5

echo "=== CAMELS-US DATA ==="
ls -d ~/neuralhydrology/data/camels_us 2>&1 | head -2
ls ~/neuralhydrology/data/camels_us 2>&1 | head -10

echo "=== DISK ==="
df -h /data1 2>&1 | tail -2
echo "quota:"; du -sh ~/ 2>/dev/null | tail -1

echo "=== PARTITIONS ==="
sinfo -o "%.12P %.6a %.10l %.6D %.6t %N" 2>&1 | head -12
