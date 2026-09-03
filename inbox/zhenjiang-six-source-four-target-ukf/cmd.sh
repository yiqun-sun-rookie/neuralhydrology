#!/bin/bash
set -o pipefail

printf '=== SNAPSHOT_TIME ===\n'
date -Is

printf '=== MY_RUNNING_AND_QUEUED_JOBS ===\n'
squeue -u "$USER" -o '%i|%j|%T|%P|%N|%M|%l|%R' 2>&1 || true
printf 'job_line_count=%s\n' "$(squeue -u "$USER" -h -o '%i' 2>/dev/null | wc -l)"

printf '=== RECENT_TERMINAL_STATES_7D ===\n'
sacct -X -n -P -S "$(date -d '7 days ago' +%Y-%m-%d)" \
  --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null \
  | grep -E '\|(TIMEOUT|FAILED|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' | tail -15 || echo '  none'

printf '=== HOME_TOP_LEVEL_DIRS ===\n'
find /data1/home/sunyiq -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort || true

printf '=== ZHENJIANG_SIX_SOURCE_ROOTS ===\n'
for d in /data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_*; do
  [ -e "$d" ] || continue
  printf 'ROOT|%s|dirs=%s\n' "$d" "$(find "$d" -maxdepth 1 -mindepth 1 -type d -printf '%f,' 2>/dev/null)"
done

printf '=== V1_INPUTS_TO_REUSE_READONLY ===\n'
V1=/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2
for p in "$V1/inputs/pre2024-four-target-v1" "$V1/runs/base" "$V1/runs/observation_head" "$V1/runs/filter"; do
  if [ -d "$p" ]; then
    printf 'DIR|%s|entries=%s|bytes=%s\n' "$p" \
      "$(find "$p" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)" \
      "$(du -sb "$p" 2>/dev/null | awk '{print $1}')"
  else
    printf 'ABSENT|%s\n' "$p"
  fi
done
printf 'input_manifest=%s\n' "$(sha256sum "$V1/inputs/pre2024-four-target-v1/four_target_input_manifest.json" 2>/dev/null | awk '{print $1}')"

printf '=== DISK ===\n'
df -h /data1 2>&1 | tail -2 || true

printf '=== PARTITIONS ===\n'
sinfo -o '%.10P %.6a %.6D %.6t %.28N' 2>&1 | head -12 || true

printf '=== CONDA_ENV ===\n'
ls -d /data1/home/sunyiq/miniconda3/envs/* 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ' || true
printf '\n=== SNAPSHOT_END ===\n'
date -Is
exit 0
