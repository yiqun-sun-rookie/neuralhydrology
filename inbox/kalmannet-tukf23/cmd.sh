#!/bin/bash
set -o pipefail
echo "=== PARTITIONS (all, real occupancy) ==="
sinfo -o "%.12P %.6a %.10l %.6D %.8t %.30N" 2>&1 | head -40
echo "=== DOWN REASONS ==="
sinfo -R 2>&1 | head -20
echo "=== CPU NODE OS SAMPLE (scontrol, read-only) ==="
for n in icn201 icn230 icn260 icn270 icn275 icn281; do
  scontrol show node $n 2>/dev/null | grep -E "NodeName|OS=|CPUAlloc|State|Partitions" | tr '\n' ' ' ; echo ""
done
echo "=== CPU IDLE COUNTS ==="
sinfo -p hcpu48 -t idle -o "%D idle of hcpu48" 2>&1 | tail -1
sinfo -p hcpu48y -t idle -o "%D idle of hcpu48y" 2>&1 | tail -1
echo "=== NEW PARTITIONS FROM UPGRADED MANUAL (hcpu64/hcpu128/hcore40) ==="
sinfo -p hcpu64 2>&1 | head -3
sinfo -p hcpu128 2>&1 | head -3
sinfo -p hcore40 2>&1 | head -3
echo "=== PRIOR KALMANNET DEPLOY DIRS ==="
ls -d /data1/home/sunyiq/kalmannet_tukf* 2>&1 | head -10
du -sh /data1/home/sunyiq/kalmannet_tukf19_20260823_retry4 2>/dev/null || true
echo "=== CAMELS DATA ON HPC ==="
ls ~/neuralhydrology/data/camels_us/ 2>&1 | head -12
ls ~/neuralhydrology/data/camels_us/basin_mean_forcing/ 2>&1 | head -6
ls ~/neuralhydrology/data/camels_us/usgs_streamflow/ 2>&1 | head -4
echo "=== PRIOR V5 CSV ==="
ls -la ~/neuralhydrology/results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_BEST/summary/ 2>&1 | head -8
echo "=== NH_FINAL VERSIONS ==="
source /data1/home/$USER/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final 2>&1 && python -c "import torch,numpy,pandas;print('torch',torch.__version__,'numpy',numpy.__version__,'pandas',pandas.__version__)" 2>&1
echo "=== DISK ==="
df -h /data1 2>&1 | tail -1
echo "=== MY RUNNING JOBS ==="
squeue -u $USER -h 2>&1 | head -10 || true
