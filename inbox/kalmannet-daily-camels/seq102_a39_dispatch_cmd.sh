#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL_ROOT="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels"
SEQUENCE_FILE="${CHANNEL_ROOT}/seq"
RESULT_FILE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_102.txt"
PREVIOUS_RESULT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_101.txt"
FAILED_ARCHIVE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A39_JOB217038_TERMINAL_EVIDENCE_SEQ101.tar.gz"
COLLECTOR="${CHANNEL_ROOT}/seq102_a39_job217038_terminal_collect.sh"
DISPATCH_SNAPSHOT="${CHANNEL_ROOT}/seq102_a39_dispatch_cmd.sh"
ARCHIVE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A39_JOB217038_TERMINAL_EVIDENCE_SEQ102.tar.gz"

[[ -f "${SEQUENCE_FILE}" && ! -L "${SEQUENCE_FILE}" ]] || exit 80
[[ "$(tr -d '[:space:]' < "${SEQUENCE_FILE}")" == "102" ]] || exit 81
[[ ! -e "${RESULT_FILE}" && ! -L "${RESULT_FILE}" ]] || exit 82
[[ ! -e "${ARCHIVE}" && ! -L "${ARCHIVE}" ]] || exit 82
[[ ! -e "${FAILED_ARCHIVE}" && ! -L "${FAILED_ARCHIVE}" ]] || exit 82
[[ -f "${PREVIOUS_RESULT}" && ! -L "${PREVIOUS_RESULT}" ]] || exit 83
[[ "$(stat -c '%s' "${PREVIOUS_RESULT}")" == "4272" ]] || exit 84
[[ "$(sha256sum "${PREVIOUS_RESULT}" | awk '{print $1}')" == "6a588f234306681d76cd9da8195acbf19ad6de4d83974bb88ebf8dd982bfd2d5" ]] || exit 85
grep -Fq 'SEQ101_A39_INDEPENDENT_TERMINAL_VALIDATION capability=PASS comparison=NO_DISCERNIBLE_ADVANTAGE scale_up=GO convergence=UNKNOWN_NOT_ESTABLISHED_BY_SINGLE_CHECKPOINT_FORMAL_EVALUATION' "${PREVIOUS_RESULT}" || exit 86
grep -Fxq "tar: unrecognized option '--sort=name'" "${PREVIOUS_RESULT}" || exit 86
grep -Fxq '### channel=kalmannet-daily-camels seq=101' "${PREVIOUS_RESULT}" || exit 86
grep -Fxq '### exit_code=1' "${PREVIOUS_RESULT}" || exit 86
[[ -f "${COLLECTOR}" && ! -L "${COLLECTOR}" ]] || exit 87
[[ "$(stat -c '%s' "${COLLECTOR}")" == "42933" ]] || exit 88
[[ "$(sha256sum "${COLLECTOR}" | awk '{print $1}')" == "e91055c7e08e63c5aa270387548caf9209dd75c54f147ca81330aaf2f93e1926" ]] || exit 89
[[ -f "${DISPATCH_SNAPSHOT}" && ! -L "${DISPATCH_SNAPSHOT}" ]] || exit 90
[[ -f "$0" && ! -L "$0" ]] || exit 90
cmp -s -- "$0" "${DISPATCH_SNAPSHOT}" || exit 90
echo "SEQ102_A39_RECOLLECT_DISPATCH_VERIFIED job_id=217038"
exec bash "${COLLECTOR}"
