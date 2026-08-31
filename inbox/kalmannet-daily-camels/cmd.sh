#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_ROOT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
SEQUENCE_FILE="${CHANNEL_ROOT}/seq"
RESULT_FILE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_100.txt"
PREVIOUS_RESULT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_99.txt"
DIAGNOSTIC_SCRIPT="${CHANNEL_ROOT}/seq100_a39_job217038_terminal_diagnostic.sh"

[[ -f "${SEQUENCE_FILE}" && ! -L "${SEQUENCE_FILE}" ]] || exit 80
[[ "$(tr -d '[:space:]' < "${SEQUENCE_FILE}")" == "100" ]] || exit 81
[[ ! -e "${RESULT_FILE}" && ! -L "${RESULT_FILE}" ]] || exit 82
[[ -f "${PREVIOUS_RESULT}" && ! -L "${PREVIOUS_RESULT}" ]] || exit 83
[[ "$(stat -c '%s' "${PREVIOUS_RESULT}")" == "526" ]] || exit 84
[[ "$(sha256sum "${PREVIOUS_RESULT}" | awk '{print $1}')" == "3709adbece5ab8f893daa935dace02a555b989700d86408e766407a76657c675" ]] || exit 85
grep -Fq '217038|daily-knet-a39-s98|sunyiq|hgpu8|FAILED|72:0|00:01:42|2026-08-31T18:44:47|2026-08-31T18:46:29|ngu202' "${PREVIOUS_RESULT}" || exit 86
grep -Fq 'SEQ99_A39_STATUS_QUERY_COMPLETE job_id=217038 squeue_exit=1 sacct_exit=0' "${PREVIOUS_RESULT}" || exit 86
[[ -f "${DIAGNOSTIC_SCRIPT}" && ! -L "${DIAGNOSTIC_SCRIPT}" ]] || exit 87
[[ "$(stat -c '%s' "${DIAGNOSTIC_SCRIPT}")" == "5060" ]] || exit 88
[[ "$(sha256sum "${DIAGNOSTIC_SCRIPT}" | awk '{print $1}')" == "640dc0556ce88d6f10f21f6e1e009244b4980115d36da5e0668fdcbf40897a04" ]] || exit 89
echo "SEQ100_A39_TERMINAL_DIAGNOSTIC_DISPATCH_VERIFIED job_id=217038"
exec bash "${DIAGNOSTIC_SCRIPT}"
