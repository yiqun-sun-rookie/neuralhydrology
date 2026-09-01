#!/bin/bash
set -o pipefail

ROOT="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2"
IDS="217803,217804,217805,217806,217807,217808,217809,217810"

printf '=== SNAPSHOT_TIME ===\n'
date -Is
printf '=== SQUEUE ===\n'
squeue -j "${IDS}" -o '%i|%j|%T|%P|%N|%M|%l|%R' || true
printf '=== SACCT ===\n'
sacct -j "${IDS}" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList -P -n || true

printf '=== REGISTERED_OUTPUTS ===\n'
for seed in 17 29 43; do
  for relative in \
    "runs/base_smoke/s${seed}/attempt_001" \
    "runs/base/s${seed}/attempt_001" \
    "runs/observation_head_smoke/s${seed}/attempt_001" \
    "runs/observation_head/s${seed}/attempt_001" \
    "runs/filter_real_batch_smoke/s${seed}/attempt_001" \
    "runs/filter/s${seed}/attempt_001"
  do
    path="${ROOT}/${relative}"
    if [ -d "${path}" ]; then
      printf 'PUBLISHED|%s\n' "${path}"
      [ -f "${path}/completion_manifest.json" ] && sha256sum "${path}/completion_manifest.json"
    elif [ -d "${path}.partial" ]; then
      printf 'PARTIAL|%s\n' "${path}.partial"
    fi
  done
done
for relative in \
  "runs/development_evaluation_smoke/attempt_001" \
  "evidence/development_2023/evaluation/attempt_001" \
  "evidence/development_2023/independent_audit/attempt_001"
do
  path="${ROOT}/${relative}"
  if [ -d "${path}" ]; then
    printf 'PUBLISHED|%s\n' "${path}"
    [ -f "${path}/completion_manifest.json" ] && sha256sum "${path}/completion_manifest.json"
  elif [ -d "${path}.partial" ]; then
    printf 'PARTIAL|%s\n' "${path}.partial"
  fi
done

printf '=== PREFLIGHT_LOGS ===\n'
for file in \
  "${ROOT}"/logs/upstream-217803_*.out \
  "${ROOT}"/logs/upstream-217803_*.err \
  "${ROOT}"/logs/development-2023-217804.out \
  "${ROOT}"/logs/development-2023-217804.err \
  "${ROOT}"/logs/upstream-217805_*.out \
  "${ROOT}"/logs/upstream-217805_*.err
do
  [ -f "${file}" ] || continue
  printf '%s\n' "--- ${file}"
  tail -n 120 "${file}"
done

printf '=== SAFETY_SENTINELS ===\n'
[ -d "/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r1.staging" ] && echo 'R1_STAGING_PRESERVED=true' || echo 'R1_STAGING_PRESERVED=false'
[ -e "${ROOT}/evidence/development_2023/evaluation/attempt_001" ] && echo 'DEVELOPMENT_2023_PUBLISHED=true' || echo 'DEVELOPMENT_2023_PUBLISHED=false'
echo 'HELDOUT_2024_TARGET_ACCESS_AUTHORIZED=false'
exit 0
