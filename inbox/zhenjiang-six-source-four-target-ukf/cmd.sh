#!/bin/bash
set -o pipefail
OUT="/data1/home/sunyiq/zhenjiang_six_source_four_target_ukf_qr_learning_value_20260903"
printf '=== SNAPSHOT_TIME ===\n'; date -Is
printf '=== JOB_219223 ===\n'
sacct -j 219223 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList -P -n 2>&1 | grep -v '\.batch\|\.extern' || true
printf '=== RESULT_FILES ===\n'
for s in 17 29 43; do
  d="${OUT}/runs/qr_learning_value/s${s}/attempt_001"
  if [ -d "$d" ]; then
    find "$d" -maxdepth 1 -type f -printf 'FILE|s'"${s}"'|%f|bytes=%s\n' 2>/dev/null | sort || true
  else
    printf 'ABSENT|s%s\n' "$s"
  fi
done
printf '=== RESULTS ===\n'
for s in 17 29 43; do
  j="${OUT}/runs/qr_learning_value/s${s}/attempt_001/qr_learning_value.json"
  if [ -f "$j" ]; then printf 'SEED_%s_JSON=' "$s"; cat "$j"; printf '\n'; else printf 'SEED_%s_JSON=absent\n' "$s"; fi
done
printf '=== BLOCK_CSV_HEAD ===\n'
for s in 17 29 43; do
  c="${OUT}/runs/qr_learning_value/s${s}/attempt_001/selection_block_sums.csv"
  [ -f "$c" ] && { printf 'CSV|s%s|lines=%s\n' "$s" "$(wc -l < "$c")"; head -3 "$c"; } || true
done
printf '=== ERR_TAILS ===\n'
for f in "${OUT}"/logs/*.err; do
  [ -f "$f" ] || continue
  printf 'ERR|%s|bytes=%s\n' "$(basename "$f")" "$(stat -c '%s' "$f")"
  [ -s "$f" ] && tail -n 20 "$f" || true
done
printf '=== OUT_TAILS ===\n'
for f in "${OUT}"/logs/*.out; do
  [ -f "$f" ] || continue
  printf 'OUT|%s|bytes=%s\n' "$(basename "$f")" "$(stat -c '%s' "$f")"
  tail -n 14 "$f" 2>/dev/null || true
done
printf '=== FROZEN_ROOT_UNCHANGED ===\n'
V1=/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2
for spec in \
  "704366cb22eef1d3acb58f4f0524a6e50d49ffa442afcf0fca498fbd21154cb8|${V1}/run/docs/records/ZHENJIANG_SIX_SOURCE_FOUR_TARGET_D32_GRU_DIFFERENTIABLE_UKF_V1_REGISTRY.json" \
  "badf3ee5f8cf3f0d9c5e5771b11385a45a6f22d6355fc43357bc44f2bd364c9e|${V1}/evidence/development_2023/evaluation/attempt_001.partial/development_access_started.json" \
  "f64e5ffcc47061d97f66e28e15ec45f7412b1d8a59455771180c4ef47eab9281|${V1}/run/scripts/analysis/zhenjiang_six_source_four_target_d32_gru_ukf_development_evaluation_v1.py"
do
  e="${spec%%|*}"; p="${spec#*|}"
  o="$(sha256sum "${p}" 2>/dev/null | awk '{print $1}')"
  printf 'IDENTITY|match=%s|path=%s\n' "$([ "${o}" = "${e}" ] && echo true || echo false)" "$(basename "${p}")"
done
find "${V1}/run/scripts" -name '__pycache__' -newermt '2026-09-03' -print 2>/dev/null | head -3 || true
printf 'pycache_check=done\n'
printf '=== SNAPSHOT_END ===\n'; date -Is
exit 0
