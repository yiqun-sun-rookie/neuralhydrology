#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
JOB_ID="216691"
EXPERIMENT_ID="DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_V1_20260831_A39"
EXECUTION_ID="DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL2_SEQ86"
RUN_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation2_20260831"
STATUS_ROOT="${RUN_ROOT}/status"
LOCK_ROOT="${STATUS_ROOT}/locks/${EXECUTION_ID}.submission.lock"
RUNTIME_LOCK="${STATUS_ROOT}/locks/${EXECUTION_ID}.evaluation.lock"

[[ "$(id -un)" == "${EXPECTED_USER}" ]] || { echo "fixed user differs" >&2; exit 40; }

printf 'SEQ88_A39_TERMINAL_DIAGNOSTIC experiment_id=%s execution_id=%s job_id=%s\n' \
  "${EXPERIMENT_ID}" "${EXECUTION_ID}" "${JOB_ID}"
set +e
sacct -n -X -j "${JOB_ID}" \
  --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,Start,End,NodeList -P
SACCT_EXIT=$?
set -e
[[ "${SACCT_EXIT}" == 0 ]] || { echo "Slurm accounting query failed" >&2; exit 41; }

for directory in \
  "${RUN_ROOT}" \
  "${RUN_ROOT}/source_A39_formal_evaluation_seq86" \
  "${RUN_ROOT}/logs" \
  "${STATUS_ROOT}" \
  "${RUN_ROOT}/evaluation" \
  "${RUN_ROOT}/verification" \
  "${LOCK_ROOT}" \
  "${RUNTIME_LOCK}"
do
  if [[ -d "${directory}" && ! -L "${directory}" ]]; then
    printf 'DIRECTORY_PRESENT path=%s\n' "${directory}"
  elif [[ -e "${directory}" || -L "${directory}" ]]; then
    printf 'UNSAFE_OR_NON_DIRECTORY path=%s\n' "${directory}"
  else
    printf 'DIRECTORY_ABSENT path=%s\n' "${directory}"
  fi
done

show_text_file() {
  local path="$1" label="$2"
  if [[ -f "${path}" && ! -L "${path}" ]]; then
    printf 'FILE_BEGIN label=%s path=%s size=%s sha256=%s\n' \
      "${label}" "${path}" "$(stat -c '%s' "${path}")" "$(sha256sum "${path}" | awk '{print $1}')"
    sed -n '1,1200p' "${path}"
    printf 'FILE_END label=%s\n' "${label}"
  elif [[ -e "${path}" || -L "${path}" ]]; then
    printf 'FILE_UNSAFE_OR_NON_REGULAR label=%s path=%s\n' "${label}" "${path}"
  else
    printf 'FILE_ABSENT label=%s path=%s\n' "${label}" "${path}"
  fi
}

show_text_file "${RUN_ROOT}/logs/evaluation-${JOB_ID}.out" "slurm_stdout"
show_text_file "${RUN_ROOT}/logs/evaluation-${JOB_ID}.err" "slurm_stderr"
show_text_file "${STATUS_ROOT}/submitted_job_id.txt" "submitted_job_id"
show_text_file "${STATUS_ROOT}/sbatch.stdout" "sbatch_stdout"
show_text_file "${STATUS_ROOT}/sbatch.stderr" "sbatch_stderr"
show_text_file "${STATUS_ROOT}/sbatch.exit" "sbatch_exit"
show_text_file "${LOCK_ROOT}/owner.json" "submission_owner"
show_text_file "${LOCK_ROOT}/bound.json" "submission_bound"
show_text_file "${RUNTIME_LOCK}/owner.json" "runtime_owner"
show_text_file "${STATUS_ROOT}/preflight-${EXECUTION_ID}-${JOB_ID}.json" "preflight_report"
show_text_file "${STATUS_ROOT}/resource-summary-${EXECUTION_ID}-${JOB_ID}.json" "resource_summary"
show_text_file "${STATUS_ROOT}/evaluation-exit-${EXECUTION_ID}-${JOB_ID}.txt" "evaluation_exit"
show_text_file "${STATUS_ROOT}/verification-exit-${EXECUTION_ID}-${JOB_ID}.txt" "verification_exit"
show_text_file "${RUN_ROOT}/evaluation/result_summary.json" "result_summary"
show_text_file "${RUN_ROOT}/evaluation/access_ledger.json" "access_ledger"
show_text_file "${RUN_ROOT}/verification/independent_verification.json" "independent_verification"

printf 'SEQ88_A39_TERMINAL_DIAGNOSTIC_COMPLETE job_id=%s\n' "${JOB_ID}"
