#!/bin/bash
set -o pipefail
OUT="/data1/home/sunyiq/zhenjiang_six_source_four_target_ukf_qr_learning_value_20260903"
printf '=== SNAPSHOT_TIME ===\n'; date -Is
printf '=== JOB_219223 ===\n'
squeue -j 219223 -o '%i|%j|%T|%P|%N|%M|%R' 2>&1 || true
sacct -j 219223 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList -P -n 2>&1 || true
printf '=== MY_OTHER_JOBS_UNTOUCHED ===\n'
squeue -u "$USER" -h -o '%i|%j|%T|%P|%N' 2>&1 | grep -v 219223 || true
printf '=== RESULT_DIRS ===\n'
for s in 17 29 43; do
  d="${OUT}/runs/qr_learning_value/s${s}/attempt_001"
  if [ -d "$d" ]; then
    printf 'DIR|%s\n' "$d"
    find "$d" -maxdepth 1 -type f -printf 'FILE|%f|bytes=%s\n' 2>/dev/null | sort || true
  else
    printf 'ABSENT|%s\n' "$d"
  fi
done
printf '=== LOGS ===\n'
for f in "${OUT}"/logs/*.out "${OUT}"/logs/*.err; do
  [ -f "$f" ] || continue
  printf 'LOG|%s|bytes=%s\n' "$(basename "$f")" "$(stat -c '%s' "$f")"
  tail -n 25 "$f" 2>/dev/null || true
done
printf '=== SUMMARY_IF_DONE ===\n'
for s in 17 29 43; do
  j="${OUT}/runs/qr_learning_value/s${s}/attempt_001/qr_learning_value.json"
  [ -f "$j" ] && { printf 'SEED_%s=' "$s"; cat "$j"; printf '\n'; }
done
printf '=== SNAPSHOT_END ===\n'; date -Is
exit 0
