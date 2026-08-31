#!/usr/bin/env bash
set -Eeuo pipefail

JOB_ID="216551"
RUN_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation1_20260831"
EXECUTION_ID="DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL1_SEQ83"
SUBMISSION_LOCK="${RUN_ROOT}/status/locks/${EXECUTION_ID}.submission.lock"
RUNTIME_LOCK="${RUN_ROOT}/status/locks/${EXECUTION_ID}.evaluation.lock"

show_safe_text() {
  local path="$1" label="$2"
  if [[ -f "$path" && ! -L "$path" ]]; then
    printf 'SEQ85_FILE_BEGIN label=%s path=%s size=%s sha256=%s\n' \
      "$label" "$path" "$(stat -c '%s' "$path")" "$(sha256sum "$path" | awk '{print $1}')"
    head -c 200000 "$path"
    printf '\nSEQ85_FILE_END label=%s\n' "$label"
  else
    printf 'SEQ85_FILE_ABSENT label=%s path=%s\n' "$label" "$path"
  fi
}

sacct -X -j "$JOB_ID" -n -P \
  --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,Start,End,NodeList,AllocTRES,ReqTRES,MaxRSS,MaxVMSize
show_safe_text "${RUN_ROOT}/logs/evaluation-${JOB_ID}.out" "slurm_stdout"
show_safe_text "${RUN_ROOT}/logs/evaluation-${JOB_ID}.err" "slurm_stderr"
show_safe_text "${RUN_ROOT}/status/sbatch.stdout" "sbatch_stdout"
show_safe_text "${RUN_ROOT}/status/sbatch.stderr" "sbatch_stderr"
show_safe_text "${RUN_ROOT}/status/sbatch.exit" "sbatch_exit"
show_safe_text "${RUN_ROOT}/status/submitted_job_id.txt" "submitted_job_id"
show_safe_text "${SUBMISSION_LOCK}/owner.json" "submission_owner"
show_safe_text "${SUBMISSION_LOCK}/bound.json" "submission_bound"

printf 'SEQ85_PATH_STATE evaluation_exists=%s verification_exists=%s runtime_lock_exists=%s submission_lock_exists=%s\n' \
  "$(if [[ -e "${RUN_ROOT}/evaluation" || -L "${RUN_ROOT}/evaluation" ]]; then printf true; else printf false; fi)" \
  "$(if [[ -e "${RUN_ROOT}/verification" || -L "${RUN_ROOT}/verification" ]]; then printf true; else printf false; fi)" \
  "$(if [[ -e "$RUNTIME_LOCK" || -L "$RUNTIME_LOCK" ]]; then printf true; else printf false; fi)" \
  "$(if [[ -e "$SUBMISSION_LOCK" || -L "$SUBMISSION_LOCK" ]]; then printf true; else printf false; fi)"
printf 'SEQ85_A39_TERMINAL_DIAGNOSTIC_COMPLETE job_id=%s\n' "$JOB_ID"
