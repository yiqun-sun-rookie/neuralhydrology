#!/bin/bash
# precip-selfrule-v05 seq=10: preserve completed work, cancel only pending tasks, and continue with a scheduler-safe wrapper.
set -eo pipefail
ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_20260929_r03
SOURCE="$ROOT/code/src/precip_input_assimilation/hpc/selfrule_time_v05_technical.slurm"
WRAPPER="$ROOT/technical_8/technical_retry_remaining.slurm"

date "+wallclock %F %T %z"
echo "=== BEFORE ==="
squeue -j 231259 -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true

retry_ids=()
for index in 2 3 4 5 6 7; do
  task="231259_${index}"
  state=$(squeue -h -j "$task" -o "%T" 2>/dev/null | head -1)
  if test "$state" = "PENDING"; then
    scancel "$task"
    retry_ids+=("$index")
    echo "CANCELLED_PENDING=$task"
  elif test -z "$state"; then
    echo "NOT_IN_QUEUE=$task"
  else
    echo "LEFT_UNCHANGED=$task state=$state"
  fi
done

awk '!/^scontrol -d show job /' "$SOURCE" > "$WRAPPER"
chmod 700 "$WRAPPER"
bash -n "$WRAPPER"

if test "${#retry_ids[@]}" -gt 0; then
  array_spec=$(IFS=,; echo "${retry_ids[*]}")
  submit=$(sbatch --dependency=afterany:231259_1 --array="${array_spec}%1" --job-name=psv05t3r "$WRAPPER")
  case "$submit" in
    "Submitted batch job "*) ;;
    *) echo "RETRY_SBATCH_FAILED $submit"; exit 1 ;;
  esac
  retry_job=${submit##* }
  printf 'retry_job=%s\narray_spec=%s\ndependency=afterany:231259_1\n' "$retry_job" "$array_spec" > \
    "$ROOT/technical_8/retry_submission.txt"
  echo "RETRY_JOB_ID=$retry_job"
  echo "RETRY_ARRAY_SPEC=$array_spec"
  squeue -j "$retry_job" -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true
else
  echo "NO_PENDING_TASKS_REQUIRED_RETRY"
fi

echo "=== AFTER ORIGINAL ARRAY ==="
squeue -j 231259 -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true