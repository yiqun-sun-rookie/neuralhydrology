#!/bin/bash
# seq=395 重排前只读确认: 202226 的依赖方、202230 终态、202228 全数组状态、服务器侧脚本与批次文件指纹
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== A. PENDING JOBS AND THEIR DEPENDENCY FIELDS ==="
squeue -u sunyiq -h -o '%.10i %.16j %.10T | dep=%E' 2>/dev/null || true
echo "=== B. 202230 agg-hyper FINAL STATE ==="
sacct -j 202230 -X -n -P --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null || true
echo "=== C. 202228 hyper array state summary ==="
sacct -j 202228 -X -n -P --format=State 2>/dev/null | sort | uniq -c || true
echo "=== D. SERVER-SIDE FINGERPRINTS (eval script / batch / registry) ==="
sha256sum "$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_evaluation_array.slurm" "$ROOT/src/29_nearing2022_da_ar/registry/time_split_pending_source_evaluation_batch.txt" "$ROOT/src/29_nearing2022_da_ar/registry/evaluation_registry.csv" 2>/dev/null || true
wc -l < "$ROOT/src/29_nearing2022_da_ar/registry/time_split_pending_source_evaluation_batch.txt" 2>/dev/null || true
echo "=== E. 202226 timelimit and state ==="
sacct -j 202226 -X -n -P --format=JobID,JobName,State,Timelimit 2>/dev/null | head -3 || true
echo "=== F. existing rebuild jobs (idempotence pre-check) ==="
squeue -u sunyiq -h -o '%j' 2>/dev/null | grep -c 'N22-evalfix' || true
