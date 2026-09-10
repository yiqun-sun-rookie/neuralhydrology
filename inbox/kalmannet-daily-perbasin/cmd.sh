#!/bin/bash
# channel=kalmannet-daily-perbasin sequence=94 purpose=read-only-gpu-allocation-and-test-only-start-estimates
set -u
set -o pipefail

printf '%s\n' 'GPU_NODE_ALLOC_TRES_BEGIN'
while IFS= read -r task_node; do
    timeout 10s scontrol show node "$task_node" -o
    printf 'NODE_QUERY_EXIT node=%s exit=%s\n' "$task_node" "$?"
done < <(sinfo -a -N -h -o '%N|%G' | awk -F'|' '$2 ~ /gpu/ {print $1}' | sort -u)
printf '%s\n' 'GPU_NODE_ALLOC_TRES_END'

printf '%s\n' 'GPU_PARTITIONS_BEGIN'
for task_partition in hgpu2p hgpu2 hgpu4 hgpu8; do
    timeout 10s scontrol show partition "$task_partition" -o
    printf 'PARTITION_QUERY_EXIT partition=%s exit=%s\n' "$task_partition" "$?"
done
printf '%s\n' 'GPU_PARTITIONS_END'

printf '%s\n' 'TEST_ONLY_START_ESTIMATES_BEGIN'
for task_partition in hgpu2p hgpu2 hgpu4 hgpu8 hgpu2p,hgpu2,hgpu4,hgpu8; do
    printf 'TEST_ONLY_BEGIN partition=%s\n' "$task_partition"
    timeout 20s sbatch --test-only --partition="$task_partition" --nodes=1 --ntasks=1 --cpus-per-task=4 --gres=gpu:1 --time=02:00:00 --no-requeue --job-name=kdpp-test-only --wrap='exit 0'
    printf 'TEST_ONLY_EXIT partition=%s exit=%s\n' "$task_partition" "$?"
done
printf '%s\n' 'TEST_ONLY_START_ESTIMATES_END'

printf '%s\n' 'TARGET_START_ESTIMATE_BEGIN'
timeout 20s squeue --start -j 224875 -o '%i|%j|%T|%P|%S|%Y|%R'
printf 'TARGET_START_ESTIMATE_EXIT=%s\n' "$?"
printf '%s\n' 'READ_ONLY_GPU_ALLOCATION_QUERY_COMPLETE submissions=0 cancellations=0 updates=0 test_only_calls=5'
