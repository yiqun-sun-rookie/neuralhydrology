#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_ROOT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
SEQUENCE_FILE="${CHANNEL_ROOT}/seq"
RESULT_FILE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_97.txt"
PREVIOUS_RESULT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_96.txt"
DIAGNOSTIC_SCRIPT="${CHANNEL_ROOT}/seq97_a39_job216974_terminal_diagnostic.sh"

[[ -f "${SEQUENCE_FILE}" && ! -L "${SEQUENCE_FILE}" ]] || exit 80
[[ "$(tr -d '[:space:]' < "${SEQUENCE_FILE}")" == "97" ]] || exit 81
[[ ! -e "${RESULT_FILE}" && ! -L "${RESULT_FILE}" ]] || exit 82
[[ -f "${PREVIOUS_RESULT}" && ! -L "${PREVIOUS_RESULT}" ]] || exit 83
[[ "$(stat -c '%s' "${PREVIOUS_RESULT}")" == "525" ]] || exit 84
[[ "$(sha256sum "${PREVIOUS_RESULT}" | awk '{print $1}')" == "1a3c0e598d4368e01e1cecdf2f5ab7781e4ce16802a372650eca72b3e514d1a0" ]] || exit 85
grep -Fq '216974|daily-knet-a39-s94|sunyiq|hgpu8|FAILED|2:0|00:00:26|' "${PREVIOUS_RESULT}" || exit 86
grep -Fq 'SEQ96_A39_STATUS_QUERY_COMPLETE job_id=216974 squeue_exit=1 sacct_exit=0' "${PREVIOUS_RESULT}" || exit 86
[[ -f "${DIAGNOSTIC_SCRIPT}" && ! -L "${DIAGNOSTIC_SCRIPT}" ]] || exit 87
[[ "$(stat -c '%s' "${DIAGNOSTIC_SCRIPT}")" == "4520" ]] || exit 88
[[ "$(sha256sum "${DIAGNOSTIC_SCRIPT}" | awk '{print $1}')" == "0a7f62478c9f2ec22fa86390135d23962f85b38dc000ec0c39a380eeb267d753" ]] || exit 89
echo "SEQ97_A39_TERMINAL_DIAGNOSTIC_DISPATCH_VERIFIED job_id=216974"
exec bash "${DIAGNOSTIC_SCRIPT}"
