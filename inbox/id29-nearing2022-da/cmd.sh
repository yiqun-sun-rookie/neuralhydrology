#!/bin/bash
# seq=396 重建断链评价数组: 取消永不满足的 202226, 以同一脚本+同一批次文件免依赖重提
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
date --iso-8601=seconds
echo "=== 1. IDEMPOTENCE GUARD ==="
N=$(squeue -u sunyiq -h -o '%j' 2>/dev/null | grep -c 'N22-evalfix' || true)
echo "existing N22-evalfix jobs: $N"
if [ "$N" != "0" ]; then echo "ABORT: rebuild already queued"; exit 0; fi
echo "=== 2. CANCEL DEAD 202226 ONLY ==="
scancel 202226 2>&1 || true
sleep 3
squeue -j 202226 -h 2>/dev/null || echo "202226 gone"
echo "=== 3. SUBMIT FRESH EVAL ARRAY (same script, same batch, no dependency) ==="
sbatch --job-name=N22-evalfix --array=0-119%4 --exclude=ngu002,ngu101 \
  --export=ALL,REGISTRY_REL=src/29_nearing2022_da_ar/registry/evaluation_registry.csv,BATCH_FILE_REL=src/29_nearing2022_da_ar/registry/time_split_pending_source_evaluation_batch.txt,REGISTRY_KIND=evaluation \
  src/29_nearing2022_da_ar/hpc/run_registered_evaluation_array.slurm
echo "=== 4. QUEUE AFTER SUBMIT ==="
squeue -u sunyiq -h -o '%.12i %.16j %.10T %.11M %R' 2>/dev/null | grep -E 'N22' || true
