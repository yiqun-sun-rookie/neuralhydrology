#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_ROOT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
SEQUENCE_FILE="${CHANNEL_ROOT}/seq"
PREVIOUS_RESULT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_91.txt"
STATUS_SCRIPT="${CHANNEL_ROOT}/seq92_a39_job216847_status.sh"

[[ -f "${SEQUENCE_FILE}" && ! -L "${SEQUENCE_FILE}" ]] || exit 80
[[ "$(tr -d '[:space:]' < "${SEQUENCE_FILE}")" == "92" ]] || exit 81
[[ -f "${PREVIOUS_RESULT}" && ! -L "${PREVIOUS_RESULT}" ]] || exit 82
[[ "$(sha256sum "${PREVIOUS_RESULT}" | awk '{print $1}')" == "8a6790e87027a45160a21a9c3cc45a009702e88785da49dcaf6c624ffdd3fb38" ]] || exit 83
[[ -f "${STATUS_SCRIPT}" && ! -L "${STATUS_SCRIPT}" ]] || exit 84
echo "SEQ92_A39_STATUS_DISPATCH_VERIFIED job_id=216847"
exec bash "${STATUS_SCRIPT}"
