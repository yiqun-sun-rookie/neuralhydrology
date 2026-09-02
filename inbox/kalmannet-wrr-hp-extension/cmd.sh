#!/bin/bash
set -o pipefail
echo "=== TIME_AND_HOST ==="; date -Is; hostname
echo "=== RUNNER ==="; pgrep -af hpc_runner_active || true
echo "=== GPU_PARTITIONS ==="
sinfo -h -o '%P|%a|%l|%D|%t|%N|%G' | grep -E '^hgpu(2p|2|4|8)' || true
sinfo -o "%.10P %.6a %.6D %.6t %.30N" || true
echo "=== OWN_JOBS_NOW ==="
squeue -u "$USER" -o '%i|%j|%T|%P|%M|%l|%R' || true
echo "=== OWN_JOBS_LAST_3_DAYS ==="
sacct -X -n -P -u "$USER" -S "$(date -d '3 days ago' +%Y-%m-%d)" --format=JobID,JobName,Partition,State,ExitCode,Elapsed,End,NodeList 2>&1 | tail -n 60 || true
echo "=== LIMITS ==="
scontrol show config 2>/dev/null | grep -iE 'MaxArraySize|MaxJobCount' || true
sacctmgr -n -P show assoc where user="$USER" format=Account,Partition,QOS,MaxJobs,MaxSubmit,GrpTRES,MaxTRESPerJob 2>&1 | head -10 || true
sacctmgr -n -P show qos format=Name,MaxJobsPU,MaxSubmitPU,MaxTRESPU,GrpTRES 2>&1 | head -20 || true
echo "=== ROOTS ==="
for d in /data1/home/sunyiq/kalmannet_wrr_lr_boundary_20260901 /data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902 /data1/home/sunyiq/kalmannet /data1/home/sunyiq/knet_project; do
  if [ -e "$d" ]; then echo "EXISTS=$d"; du -sh "$d" 2>/dev/null | head -1 || true; else echo "MISSING=$d"; fi
done
echo "=== OLD_ROOT_TREE ==="
ls -la /data1/home/sunyiq/kalmannet_wrr_lr_boundary_20260901 2>&1 | head -20 || true
ls /data1/home/sunyiq/kalmannet_wrr_lr_boundary_20260901/repo 2>&1 | head -40 || true
echo "=== OLD_ROOT_SOURCE_HASHES ==="
( cd /data1/home/sunyiq/kalmannet_wrr_lr_boundary_20260901/repo 2>/dev/null && sha256sum knet/pipelines/train_clean_based_on_11.py knet/pipelines/pipeline_clean_based_on_11.py knet/dl/nn_kalman_clamp_5.py knet/modules/pipeline/core_fun.py knet/modules/pipeline/walrus_batch_speedup.py knet/modules/utils/metrics.py knet/modules/utils/metricsV2.py knet/utils/model_initialization_use_script_mdl_1.py hydrologic/params.py experiments/optimize_hyper_parameters/grid_search_knet.py experiments/optimize_hyper_parameters/train_and_eval.py 2>&1 ) || true
echo "=== DATA ==="
sha256sum /data1/home/sunyiq/knet_project/data/processed/high_flow_aug/train_win800_19990101_01-20070527_03.pt /data1/home/sunyiq/knet_project/data/processed/high_flow_aug/val_win800_20070527_04-20090314_13.pt 2>&1 || true
echo "=== DISK ==="
df -h /data1/home/sunyiq 2>&1 | tail -2 || true
lfs quota -u "$USER" /data1 2>&1 | head -5 || true
echo "=== CONDA ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null || true
conda env list 2>&1 | grep -E 'knet_clean|nh_final' || true
