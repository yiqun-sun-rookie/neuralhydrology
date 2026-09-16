#!/bin/bash
# kalmannet-daily-perbasin sequence=136: READ-ONLY cluster snapshot before contract A (aligned rematch) build.
# No sbatch, no scancel, no file creation on the cluster. Login node does only scheduler queries and ls/df.
set -o pipefail
echo "channel=kalmannet-daily-perbasin sequence=136 purpose=read-only-cluster-snapshot-contract-a"
echo "SNAPSHOT_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ) HOST=$(hostname) USER=$USER"
OLD_ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908
NEW_ROOT_A=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
NEW_ROOT_B=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_v3_aligned_rematch_20260916
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
echo "=== ACCOUNT_QUEUE (all jobs of this account, any session) ==="
timeout 25s squeue -u "$USER" -h -o '%i|%T|%P|%R|%S|%C|%b|%M|%l|%j|%V' 2>&1
echo "ACCOUNT_QUEUE_EXIT=$?"
echo "ACCOUNT_QUEUE_COUNT_RUNNING=$(timeout 25s squeue -u "$USER" -h -t RUNNING 2>/dev/null | wc -l) PENDING=$(timeout 25s squeue -u "$USER" -h -t PENDING 2>/dev/null | wc -l)"
echo "=== PARTITION_LOAD ==="
timeout 25s sinfo -o '%.10P %.6a %.12l %.6D %.6t %.32N' 2>&1
echo "PARTITION_LOAD_EXIT=$?"
echo "=== PARTITION_NODES_hgpu4_hcpu48 ==="
timeout 25s sinfo -p hgpu4,hcpu48 -N -o '%12N %10P %10T %5c %12G %8O %30E' 2>&1
echo "=== DOWN_NODES ==="
timeout 25s sinfo -R -o '%20E %10T %20N' 2>&1
echo "=== PARTITION_CONFIG ==="
timeout 25s scontrol show partition hgpu4 2>&1
timeout 25s scontrol show partition hcpu48 2>&1
echo "=== ASSOCIATION_LIMITS ==="
timeout 25s sacctmgr -n -P show assoc user="$USER" format=Cluster,Account,Partition,MaxJobs,MaxSubmit,MaxTRESPerJob,GrpTRES,GrpJobs,QOS,Fairshare 2>&1
echo "ASSOCIATION_LIMITS_EXIT=$?"
echo "=== FAIRSHARE ==="
timeout 25s sshare -U -P 2>&1
echo "FAIRSHARE_EXIT=$?"
echo "=== RECENT_JOBS_SINCE_2026-09-12 (count by state) ==="
timeout 40s sacct -X -n -P -u "$USER" -S 2026-09-12 --format=State 2>/dev/null | cut -d'|' -f1 | sort | uniq -c
echo "=== RECENT_JOBS_SINCE_2026-09-12 (active or recent, jobname|partition|state|elapsed|submit|start|end) ==="
timeout 40s sacct -X -n -P -u "$USER" -S 2026-09-12 --format=JobIDRaw,JobName%40,Partition,State,ExitCode,ElapsedRaw,AllocTRES%40,NodeList,Submit,Start,End 2>&1 | grep -v -E '\|COMPLETED\|0:0\|' 
echo "RECENT_JOBS_EXIT=$?"
echo "=== KDPP_TRAIN_JOBS_GPU_SECONDS (kdpp-* since 2026-09-08) ==="
timeout 40s sacct -X -n -P -u "$USER" -S 2026-09-08 --name=kdpp-dev-train-08190500-seq91 --format=JobIDRaw,State,ElapsedRaw 2>&1 | head -n 3
timeout 40s sacct -X -n -P -u "$USER" -S 2026-09-08 --format=JobIDRaw,JobName%40,State,ElapsedRaw 2>/dev/null | awk -F'|' '$2 ~ /^kdpp-/ {n++; s+=$4} END {printf "kdpp_jobs=%d kdpp_elapsed_sum_seconds=%d\n", n, s}'
echo "=== REMOTE_ROOTS ==="
for d in "$OLD_ROOT" "$NEW_ROOT_A" "$NEW_ROOT_B"; do
  if [ -e "$d" ]; then echo "EXISTS $d"; else echo "ABSENT $d"; fi
done
if [ -d "$OLD_ROOT" ]; then
  echo "OLD_ROOT_TOP: $(ls "$OLD_ROOT" 2>/dev/null | tr '\n' ' ')"
  echo "OLD_ROOT_RUNS_COUNT=$(ls "$OLD_ROOT/runs" 2>/dev/null | wc -l) OLD_ROOT_RUNTIME_COUNT=$(ls "$OLD_ROOT/runtime" 2>/dev/null | wc -l)"
  echo "OLD_ROOT_RESOURCE_POLICY_SHA=$(sha256sum "$OLD_ROOT"/deployment_A40_verifier_repair_20260911_SEQ97/workspace/hpc/daily_camels_knet_21_development/resource_policy.json 2>/dev/null | cut -c1-16)"
fi
echo "HOME_TOP: $(ls /data1/home/sunyiq 2>/dev/null | tr '\n' ' ')"
echo "=== DISK ==="
timeout 25s df -h /data1/home/sunyiq 2>&1
timeout 60s du -sh "$OLD_ROOT" 2>&1
echo "=== INTERPRETER ==="
[ -x "$PY" ] && echo "PY_OK $PY" || echo "PY_MISSING $PY"
timeout 25s "$PY" -I -B -c 'import sys; print("python", sys.version.split()[0])' 2>&1
echo "=== RUNNER ==="
pgrep -af hpc_runner_active 2>&1 | head -n 3
echo "=== LOGIN_NODE_OS ==="
head -n 2 /etc/os-release 2>&1; git --version 2>&1; bash --version 2>&1 | head -n 1
echo "READ_ONLY_SNAPSHOT_COMPLETE submissions=0 cancellations=0 modifications=0"
