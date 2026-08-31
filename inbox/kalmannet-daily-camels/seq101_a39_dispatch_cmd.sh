#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_ROOT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
SEQUENCE_FILE="${CHANNEL_ROOT}/seq"
RESULT_FILE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_101.txt"
PREVIOUS_RESULT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_100.txt"
COLLECTOR="${CHANNEL_ROOT}/seq101_a39_job217038_terminal_collect.sh"
DISPATCH_SNAPSHOT="${CHANNEL_ROOT}/seq101_a39_dispatch_cmd.sh"
ARCHIVE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A39_JOB217038_TERMINAL_EVIDENCE_SEQ101.tar.gz"

[[ -f "${SEQUENCE_FILE}" && ! -L "${SEQUENCE_FILE}" ]] || exit 80
[[ "$(tr -d '[:space:]' < "${SEQUENCE_FILE}")" == "101" ]] || exit 81
[[ ! -e "${RESULT_FILE}" && ! -L "${RESULT_FILE}" ]] || exit 82
[[ ! -e "${ARCHIVE}" && ! -L "${ARCHIVE}" ]] || exit 82
[[ -f "${PREVIOUS_RESULT}" && ! -L "${PREVIOUS_RESULT}" ]] || exit 83
[[ "$(stat -c '%s' "${PREVIOUS_RESULT}")" == "58391" ]] || exit 84
[[ "$(sha256sum "${PREVIOUS_RESULT}" | awk '{print $1}')" == "7f2f58ef81e9dd91836f1a962b3c7333a5bd3e48e0fef00596069b72b4ac179c" ]] || exit 85
grep -Fq 'A39_FORMAL_EVALUATION_COMPLETE capability=PASS comparison=NO_DISCERNIBLE_ADVANTAGE scale_up=GO convergence=UNKNOWN_NOT_ESTABLISHED_BY_SINGLE_CHECKPOINT_FORMAL_EVALUATION' "${PREVIOUS_RESULT}" || exit 86
grep -Fq 'INDEPENDENT_VERIFICATION_PASS capability=PASS comparison=NO_DISCERNIBLE_ADVANTAGE scale_up=GO' "${PREVIOUS_RESULT}" || exit 86
grep -Fq 'RuntimeError: successful A39 entry lacks complete A800 resource coverage' "${PREVIOUS_RESULT}" || exit 86
grep -Fq 'SEQ100_A39_TERMINAL_DIAGNOSTIC_COMPLETE job_id=217038' "${PREVIOUS_RESULT}" || exit 86
grep -Fxq '### channel=kalmannet-daily-camels seq=100' "${PREVIOUS_RESULT}" || exit 86
grep -Fxq '### exit_code=0' "${PREVIOUS_RESULT}" || exit 86
[[ -f "${COLLECTOR}" && ! -L "${COLLECTOR}" ]] || exit 87
[[ "$(stat -c '%s' "${COLLECTOR}")" == "41763" ]] || exit 88
[[ "$(sha256sum "${COLLECTOR}" | awk '{print $1}')" == "61cb223617ba0bf038b6d2571719248b4464fa4988264627241876d28d5b262e" ]] || exit 89
[[ -f "${DISPATCH_SNAPSHOT}" && ! -L "${DISPATCH_SNAPSHOT}" ]] || exit 90
[[ -f "$0" && ! -L "$0" ]] || exit 90
cmp -s -- "$0" "${DISPATCH_SNAPSHOT}" || exit 90
echo "SEQ101_A39_RECOLLECT_DISPATCH_VERIFIED job_id=217038"
exec bash "${COLLECTOR}"
