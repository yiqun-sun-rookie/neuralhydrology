#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
EXPECTED_JOB_ID="212886"
EXPECTED_JOB_NAME="daily-knet-a34r3"
EXPERIMENT_ID="DAILY_CAMELS_NATIVE_KALMANNET_FULL_STATE_MASKED_NSE_SMOKE_V1_20260825_A34"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_NATIVE_KALMANNET_FULL_STATE_A34_INFRA_RETRY3_SEQ28"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_full_state_a34_retry3_20260826"
SOURCE_DIRECTORY="${RUN_BASE}/source_A34_infra_retry3_seq28"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_DIRECTORY="${RUN_BASE}/logs"
OUTBOX_DIRECTORY="/data1/home/sunyiq/hpc_mailbox/outbox/kalmannet-daily-camels"
EVIDENCE_ARCHIVE="${OUTBOX_DIRECTORY}/DAILY_CAMELS_NATIVE_KALMANNET_FULL_STATE_A34_INFRA_RETRY3_SEQ28_evidence.tar.gz"
TEMPORARY_ARCHIVE=""

sha256_file() { sha256sum "$1" | awk '{print $1}'; }

cleanup() {
  if [[ -n "$TEMPORARY_ARCHIVE" ]]; then
    case "$TEMPORARY_ARCHIVE" in
      /data1/home/sunyiq/hpc_mailbox/outbox/kalmannet-daily-camels/.seq29-a34-job212886-evidence.*.tar.gz)
        rm -f -- "$TEMPORARY_ARCHIVE"
        ;;
      *)
        echo "refusing unsafe temporary archive cleanup path" >&2
        return 91
        ;;
    esac
  fi
}
trap cleanup EXIT INT TERM

if [[ "${USER-}" != "$EXPECTED_USER" || "$(id -un)" != "$EXPECTED_USER" ]]; then
  echo "fixed-user check failed" >&2
  exit 50
fi
[[ -d "$RUN_BASE" && ! -L "$RUN_BASE" ]] || {
  echo "A34 retry3 run root absent or symbolic" >&2
  exit 51
}
[[ -d "$STATUS_DIRECTORY" && ! -L "$STATUS_DIRECTORY" ]] || {
  echo "A34 retry3 status directory absent or symbolic" >&2
  exit 52
}
[[ -f "${STATUS_DIRECTORY}/training_job_id.txt" && ! -L "${STATUS_DIRECTORY}/training_job_id.txt" ]] || {
  echo "A34 retry3 training job identity absent or symbolic" >&2
  exit 53
}
ACTUAL_JOB_ID="$(tr -d '[:space:]' < "${STATUS_DIRECTORY}/training_job_id.txt")"
[[ "$ACTUAL_JOB_ID" = "$EXPECTED_JOB_ID" ]] || {
  echo "A34 retry3 training job identity differs" >&2
  exit 54
}
[[ -f "${SOURCE_DIRECTORY}/bundle_manifest.json" && ! -L "${SOURCE_DIRECTORY}/bundle_manifest.json" ]] || {
  echo "A34 retry3 bundle manifest absent or symbolic" >&2
  exit 55
}
grep -Fq "\"experiment_id\":\"${EXPERIMENT_ID}\"" "${SOURCE_DIRECTORY}/bundle_manifest.json" || {
  echo "A34 retry3 scientific experiment identity differs" >&2
  exit 56
}
grep -Fq "$EXECUTION_ATTEMPT_ID" \
  "${SOURCE_DIRECTORY}/hpc/daily_camels_native_kalmannet_full_state_masked_nse/submit_smoke_gpu.slurm" || {
  echo "A34 retry3 execution attempt identity differs" >&2
  exit 57
}

printf 'SEQ29_A34_JOB212886_IDENTITY experiment_id=%s execution_attempt_id=%s job_id=%s run_base=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$EXPECTED_JOB_ID" "$RUN_BASE"

set +e
SACCT_OUTPUT="$(sacct -j "$EXPECTED_JOB_ID" --units=K --parsable2 \
  --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,ReqMem,AllocTRES,MaxRSS,MaxVMSize 2>&1)"
SACCT_EXIT="$?"
SQUEUE_OUTPUT="$(squeue -j "$EXPECTED_JOB_ID" -o '%i|%j|%T|%M|%R' 2>&1)"
SQUEUE_EXIT="$?"
set -e

echo "SEQ29_LIVE_SACCT_BEGIN"
printf '%s\n' "$SACCT_OUTPUT"
echo "SEQ29_LIVE_SACCT_END exit_code=${SACCT_EXIT}"
echo "SEQ29_LIVE_SQUEUE_BEGIN"
printf '%s\n' "$SQUEUE_OUTPUT"
echo "SEQ29_LIVE_SQUEUE_END exit_code=${SQUEUE_EXIT}"
[[ "$SACCT_EXIT" -eq 0 ]] || {
  echo "A34 job accounting query failed" >&2
  exit 58
}

ROOT_ACCOUNTING_LINE="$(printf '%s\n' "$SACCT_OUTPUT" | awk -F'|' -v job="$EXPECTED_JOB_ID" '$1 == job {print; exit}')"
[[ -n "$ROOT_ACCOUNTING_LINE" ]] || {
  echo "A34 root accounting row absent" >&2
  exit 59
}
IFS='|' read -r ACCOUNTED_JOB_ID ACCOUNTED_JOB_NAME ACCOUNTED_PARTITION ACCOUNTED_CPUS TERMINAL_STATE ACCOUNTED_EXIT_CODE ACCOUNTED_ELAPSED ACCOUNTED_REQMEM ACCOUNTED_TRES ACCOUNTED_MAXRSS ACCOUNTED_MAXVMSIZE <<< "$ROOT_ACCOUNTING_LINE"
TERMINAL_STATE="$(printf '%s' "$TERMINAL_STATE" | sed 's/[+ ].*$//')"
[[ "$ACCOUNTED_JOB_ID" = "$EXPECTED_JOB_ID" && "$ACCOUNTED_JOB_NAME" = "$EXPECTED_JOB_NAME" ]] || {
  echo "A34 Slurm accounting identity differs" >&2
  exit 60
}

case "$TERMINAL_STATE" in
  COMPLETED|FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)
    ;;
  *)
    printf 'SEQ29_A34_JOB212886_NON_TERMINAL_STATUS_ONLY state=%s sacct_exit=%s squeue_exit=%s\n' \
      "${TERMINAL_STATE:-UNKNOWN}" "$SACCT_EXIT" "$SQUEUE_EXIT"
    exit 75
    ;;
esac

if find "$RUN_BASE" -type l -print -quit | grep -q .; then
  echo "A34 retry3 run evidence contains a symbolic link" >&2
  exit 61
fi
mkdir -p "$OUTBOX_DIRECTORY"
if [[ -e "$EVIDENCE_ARCHIVE" || -L "$EVIDENCE_ARCHIVE" ]]; then
  [[ -f "$EVIDENCE_ARCHIVE" && ! -L "$EVIDENCE_ARCHIVE" ]] || {
    echo "existing A34 retry3 evidence path is not a regular file" >&2
    exit 62
  }
  gzip -t "$EVIDENCE_ARCHIVE" || {
    echo "existing A34 retry3 evidence archive is invalid" >&2
    exit 63
  }
else
  TEMPORARY_ARCHIVE="$(mktemp "${OUTBOX_DIRECTORY}/.seq29-a34-job212886-evidence.XXXXXX.tar.gz")"
  tar -czf "$TEMPORARY_ARCHIVE" -C "$(dirname "$RUN_BASE")" "$(basename "$RUN_BASE")"
  [[ -s "$TEMPORARY_ARCHIVE" ]] && gzip -t "$TEMPORARY_ARCHIVE" || {
    echo "new A34 retry3 evidence archive is invalid" >&2
    exit 64
  }
  [[ ! -e "$EVIDENCE_ARCHIVE" && ! -L "$EVIDENCE_ARCHIVE" ]] || {
    echo "A34 retry3 evidence path appeared during collection" >&2
    exit 65
  }
  ln -- "$TEMPORARY_ARCHIVE" "$EVIDENCE_ARCHIVE"
  rm -- "$TEMPORARY_ARCHIVE"
  TEMPORARY_ARCHIVE=""
fi

printf 'SEQ29_A34_JOB212886_EVIDENCE archive=%s sha256=%s size=%s terminal_state=%s job_exit_code=%s elapsed=%s\n' \
  "$EVIDENCE_ARCHIVE" "$(sha256_file "$EVIDENCE_ARCHIVE")" "$(stat -c '%s' "$EVIDENCE_ARCHIVE")" \
  "$TERMINAL_STATE" "$ACCOUNTED_EXIT_CODE" "$ACCOUNTED_ELAPSED"

emit_text_file() {
  local path="$1" label size
  [[ -f "$path" && ! -L "$path" ]] || return 0
  size="$(stat -c '%s' "$path")"
  [[ "$size" -le 1048576 ]] || {
    printf 'SEQ29_SKIP_OVERSIZE path=%s size=%s\n' "$path" "$size"
    return 0
  }
  if [[ "$size" -gt 0 ]] && ! grep -Iq . "$path"; then
    printf 'SEQ29_SKIP_BINARY path=%s size=%s\n' "$path" "$size"
    return 0
  fi
  label="${path#"$RUN_BASE"/}"
  printf '\nSEQ29_FILE_BEGIN\t%s\t%s\n' "$label" "$size"
  sed -n '1,5000p' "$path"
  printf '\nSEQ29_FILE_END\t%s\n' "$label"
}

emit_text_file "${STATUS_DIRECTORY}/workflow-status-${EXPECTED_JOB_ID}.json"
emit_text_file "${STATUS_DIRECTORY}/independent-verification-${EXPECTED_JOB_ID}.json"
emit_text_file "${STATUS_DIRECTORY}/job-evidence-manifest-${EXPECTED_JOB_ID}.json"
emit_text_file "${STATUS_DIRECTORY}/preflight-${EXPECTED_JOB_ID}.json"
emit_text_file "${STATUS_DIRECTORY}/entry-preflight-${EXPECTED_JOB_ID}.json"
emit_text_file "${STATUS_DIRECTORY}/runtime-selfcheck-${EXPECTED_JOB_ID}.log"
emit_text_file "${STATUS_DIRECTORY}/cgroup-resources-${EXPECTED_JOB_ID}.txt"
emit_text_file "${LOG_DIRECTORY}/smoke-${EXPECTED_JOB_ID}.out"
emit_text_file "${LOG_DIRECTORY}/smoke-${EXPECTED_JOB_ID}.err"
emit_text_file "${RUN_DIRECTORY}/result_summary.json"
emit_text_file "${RUN_DIRECTORY}/manifest.sha256.json"
emit_text_file "${RUN_DIRECTORY}/completion.marker.json"

GPU_RESOURCE_LOG="${STATUS_DIRECTORY}/gpu-resources-${EXPECTED_JOB_ID}.csv"
if [[ -f "$GPU_RESOURCE_LOG" && ! -L "$GPU_RESOURCE_LOG" ]]; then
  printf 'SEQ29_GPU_RESOURCE_LOG path=%s size=%s sha256=%s samples=%s\n' \
    "$GPU_RESOURCE_LOG" "$(stat -c '%s' "$GPU_RESOURCE_LOG")" "$(sha256_file "$GPU_RESOURCE_LOG")" \
    "$(awk 'END {print (NR > 0 ? NR - 1 : 0)}' "$GPU_RESOURCE_LOG")"
fi

printf 'SEQ29_A34_JOB212886_TERMINAL_EVIDENCE_COLLECTED state=%s job_exit_code=%s\n' \
  "$TERMINAL_STATE" "$ACCOUNTED_EXIT_CODE"
