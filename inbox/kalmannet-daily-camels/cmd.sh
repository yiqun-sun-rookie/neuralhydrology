#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL="kalmannet-daily-camels"
SCRIPT="${ROOT}/inbox/${CHANNEL}/seq86_a39_submit_formal_evaluation_retry2.sh"
EXPECTED_SHA256="95b15b25742a70db6f9f28ac51c95f728638aac59f53aa7255691122c11b514a"
EXPECTED_SIZE="15776"

[[ "$(<"${ROOT}/inbox/${CHANNEL}/seq")" == "86" ]] || {
  echo "sequence is not 86" >&2
  exit 80
}
[[ -f "${SCRIPT}" && ! -L "${SCRIPT}" ]] || {
  echo "sequence-86 controller is absent or unsafe" >&2
  exit 81
}
[[ "$(stat -c '%s' "${SCRIPT}")" == "${EXPECTED_SIZE}" ]] || {
  echo "sequence-86 controller size differs" >&2
  exit 82
}
[[ "$(sha256sum "${SCRIPT}" | awk '{print $1}')" == "${EXPECTED_SHA256}" ]] || {
  echo "sequence-86 controller SHA-256 differs" >&2
  exit 83
}
[[ ! -e "${ROOT}/outbox/${CHANNEL}/result_86.txt" && ! -L "${ROOT}/outbox/${CHANNEL}/result_86.txt" ]] || {
  echo "result 86 already exists" >&2
  exit 84
}
printf 'SEQ86_A39_DISPATCH_VERIFIED controller_sha256=%s controller_size=%s\n' \
  "${EXPECTED_SHA256}" "${EXPECTED_SIZE}"
exec bash "${SCRIPT}"
