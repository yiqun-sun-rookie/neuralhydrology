#!/bin/bash
echo "=== 我这条线还有作业在跑吗 ==="
squeue -u "$USER" -o "%.10i %.16j %.10P %.9T %.10M" 2>&1 | head -10
echo "=== 今天所有作业的收尾状态 ==="
sacct -S 2026-08-08 -X --format=JobID%10,JobName%16,State%12,Elapsed%10 2>&1 | tail -12
echo "=== 我的工作区有没有残留的锁或半成品 ==="
ls -d ~/autoresearch64/runs/unified_autoresearch/*/ 2>/dev/null
echo "--- 是否有未完成的 CANDIDATE_SUMMARY ---"
for d in ~/autoresearch64/runs/unified_autoresearch/hbv_lite_64_hpc_v*/; do
  [ -d "$d" ] && echo "$(basename $d): $([ -f "$d/CANDIDATE_SUMMARY.json" ] && echo COMPLETE || echo INCOMPLETE)"
done
