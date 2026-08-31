#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_ROOT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
SEQUENCE_FILE="${CHANNEL_ROOT}/seq"
PREVIOUS_RESULT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_92.txt"
DIAGNOSTIC_SCRIPT="${CHANNEL_ROOT}/seq93_a39_job216847_terminal_diagnostic.sh"

[[ -f "${SEQUENCE_FILE}" && ! -L "${SEQUENCE_FILE}" ]] || exit 80
[[ "$(tr -d '[:space:]' < "${SEQUENCE_FILE}")" == "93" ]] || exit 81
[[ -f "${PREVIOUS_RESULT}" && ! -L "${PREVIOUS_RESULT}" ]] || exit 82
[[ "$(sha256sum "${PREVIOUS_RESULT}" | awk '{print $1}')" == "f15f30f8587be56c69c0f76fb7f6b77f5c9b2a9963d6d6a5fd46fbb4d71b5c4e" ]] || exit 83
[[ -f "${DIAGNOSTIC_SCRIPT}" && ! -L "${DIAGNOSTIC_SCRIPT}" ]] || exit 84
echo "SEQ93_A39_TERMINAL_DIAGNOSTIC_DISPATCH_VERIFIED job_id=216847"
exec bash "${DIAGNOSTIC_SCRIPT}"
