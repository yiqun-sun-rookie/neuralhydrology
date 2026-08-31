#!/bin/bash
# Submit exactly one independent five-minute A800 allocation-semantics probe.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_a800_exclusive_semantics_probe_v1_20260831_01a055e6
MAILBOX_ROOT="$(pwd -P)"
SRC="${MAILBOX_ROOT}/payload/kalmannet-tukf09-455/a800-exclusive-semantics-probe-v1/probe.slurm"
PENDING="${ROOT}.pending.mailbox.$$"
JOB_NAME=t455a8sem01
PROBE_SHA=fd34fa08da8d74781ef952f21907ba62018475702b299611db414cd4a3ddaed6

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== PRE-SUBMISSION GATES ==="
[[ -f "${SRC}" && ! -L "${SRC}" ]] || fail "probe payload missing, linked, or irregular"
[[ "$(stat -c '%h' "${SRC}")" -eq 1 ]] || fail "probe payload hard-link count is not one"
[[ "$(sha256sum "${SRC}" | awk '{print $1}')" = "${PROBE_SHA}" ]] || fail "probe payload hash mismatch"
[[ ! -e "${ROOT}" && ! -L "${ROOT}" ]] || fail "unique probe root already exists; refusing overwrite or resubmit"
[[ ! -e "${PENDING}" && ! -L "${PENDING}" ]] || fail "pending path already exists"
squeue_output=$(squeue -u "${USER}" -h -o '%i|%j' 2>&1)
squeue_rc=$?
[[ "${squeue_rc}" -eq 0 ]] || fail "cannot prove absence of a same-name job: ${squeue_output}"
existing=$(printf '%s\n' "${squeue_output}" | awk -F'|' -v name="${JOB_NAME}" '$2==name {print $0}')
[[ -z "${existing}" ]] || fail "same-name job already exists: ${existing}"

umask 077
mkdir "${PENDING}" || fail "cannot create pending root"
mkdir "${PENDING}/logs" "${PENDING}/status" || fail "cannot create probe subdirectories"
cp --no-clobber "${SRC}" "${PENDING}/probe.slurm" || fail "cannot install probe without overwrite"
chmod 0555 "${PENDING}/probe.slurm" || fail "cannot freeze probe script mode"
[[ -f "${PENDING}/probe.slurm" && ! -L "${PENDING}/probe.slurm" ]] || fail "installed probe is linked or irregular"
[[ "$(stat -c '%h' "${PENDING}/probe.slurm")" -eq 1 ]] || fail "installed probe hard-link count is not one"
[[ "$(sha256sum "${PENDING}/probe.slurm" | awk '{print $1}')" = "${PROBE_SHA}" ]] || fail "installed probe hash mismatch"
printf '%s  %s\n' "${PROBE_SHA}" "${ROOT}/probe.slurm" > "${PENDING}/status/probe_slurm.sha256" || fail "cannot write probe hash evidence"
mv --no-clobber --no-target-directory "${PENDING}" "${ROOT}" || fail "cannot publish unique probe root"
[[ -d "${ROOT}" && ! -L "${ROOT}" && ! -e "${PENDING}" ]] || fail "probe root publication failed closed"
PROBE="${ROOT}/probe.slurm"

echo "=== EXACTLY ONE SUBMISSION ==="
submit_output=$(sbatch "${PROBE}" 2>&1)
submit_rc=$?
printf '%s\n' "${submit_output}"
job_ids=$(printf '%s\n' "${submit_output}" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
job_id_count=$(printf '%s\n' "${job_ids}" | awk 'NF{count++} END{print count+0}')
[[ "${submit_rc}" -eq 0 && "${job_id_count}" -eq 1 ]] || fail "submission not proven exactly once (wrapper_rc=${submit_rc}, parsed_count=${job_id_count})"
job_id=$(printf '%s\n' "${job_ids}" | awk 'NF{print; exit}')
case "${job_id}" in
  ''|*[!0-9]*) fail "invalid parsed job id" ;;
esac
submission_pending="${ROOT}/status/submitted_job_id.txt.pending.$$"
( set -o noclobber; printf '%s\n' "${job_id}" > "${submission_pending}" ) || fail "cannot write submission evidence"
ln "${submission_pending}" "${ROOT}/status/submitted_job_id.txt" || fail "submission evidence target appeared concurrently"
rm -f "${submission_pending}"

echo "=== IMMEDIATE STATE (NO WAIT) ==="
echo "PROBE_ROOT=${ROOT}"
echo "JOB_ID=${job_id}"
squeue -j "${job_id}" -o '%.18i %.20j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true
echo "TUKF09_455_A800_EXCLUSIVE_SEMANTICS_PROBE_SUBMITTED_ONCE"
