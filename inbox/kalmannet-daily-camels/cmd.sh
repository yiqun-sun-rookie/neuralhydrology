#!/usr/bin/env bash
set -eo pipefail

MAILBOX_ROOT="/data1/home/${USER}/hpc_mailbox"
PAYLOAD_ROOT="${MAILBOX_ROOT}/payload/kalmannet-daily-camels"
ARCHIVE_NAME="DAILY_CAMELS_NATIVE_KALMANNET_SMOKE_V1_20260824_A01.tar.gz"
EXPECTED_ARCHIVE_SHA256="84da898ef1776692e75aa228ba92ef58c2abed05bea5881bbdda84559b927106"
BASE="/data1/home/sunyiq/kalmannet_daily_camels_20260824"
RUN_DIRECTORY="${BASE}/DAILY_CAMELS_NATIVE_KALMANNET_SMOKE_V1_20260824_A01"
SOURCE_DIRECTORY="${BASE}/source"
SOURCE_TEMPORARY="${BASE}/.source_probe_seq1_$$"
TRANSPORT_DIRECTORY="${BASE}/_transport"
STATUS_DIRECTORY="${BASE}/status"
LOG_DIRECTORY="${BASE}/logs"

echo '=== DAILY CAMELS KALMANNET PROBE PRECONDITIONS ==='
test ! -e "$BASE" || { echo "independent target already exists: $BASE" >&2; exit 60; }
test -f "${PAYLOAD_ROOT}/${ARCHIVE_NAME}"
ACTUAL_ARCHIVE_SHA256=$(sha256sum "${PAYLOAD_ROOT}/${ARCHIVE_NAME}" | awk '{print $1}')
test "$ACTUAL_ARCHIVE_SHA256" = "$EXPECTED_ARCHIVE_SHA256" || exit 61
printf 'archive_sha256=%s\n' "$ACTUAL_ARCHIVE_SHA256"

mkdir -p "$TRANSPORT_DIRECTORY" "$STATUS_DIRECTORY" "$LOG_DIRECTORY"
cp "${PAYLOAD_ROOT}/${ARCHIVE_NAME}" "${TRANSPORT_DIRECTORY}/${ARCHIVE_NAME}"
cp "${PAYLOAD_ROOT}/bundle_manifest.sha256.json" \
  "${TRANSPORT_DIRECTORY}/bundle_manifest.sha256.json"
test "$(sha256sum "${TRANSPORT_DIRECTORY}/${ARCHIVE_NAME}" | awk '{print $1}')" = \
  "$EXPECTED_ARCHIVE_SHA256"

mkdir "$SOURCE_TEMPORARY"
tar -xzf "${TRANSPORT_DIRECTORY}/${ARCHIVE_NAME}" -C "$SOURCE_TEMPORARY"
export PYTHONDONTWRITEBYTECODE=1
python -u "${SOURCE_TEMPORARY}/hpc/daily_camels_native_kalmannet/preflight.py" \
  --bundle-root "$SOURCE_TEMPORARY" \
  --offline-bundle-check > "${STATUS_DIRECTORY}/offline_bundle_check_before_probe.json"
mv "$SOURCE_TEMPORARY" "$SOURCE_DIRECTORY"
test ! -e "$RUN_DIRECTORY"

echo '=== SUBMIT GPU-ONLY READ-ONLY PROBE ==='
cd "$SOURCE_DIRECTORY"
SUBMISSION_OUTPUT=$(sbatch --parsable \
  hpc/daily_camels_native_kalmannet/submit_probe_gpu.slurm 2>&1)
printf '%s\n' "$SUBMISSION_OUTPUT" | tee "${STATUS_DIRECTORY}/probe_submission_raw.txt"
JOB_ID=$(printf '%s' "$SUBMISSION_OUTPUT" | awk -F';' 'NR==1 {print $1}')
case "$JOB_ID" in
  ''|*[!0-9]*) echo "invalid probe job id: $JOB_ID" >&2; exit 62 ;;
esac
printf '%s\n' "$JOB_ID" > "${STATUS_DIRECTORY}/probe_job_id.txt"

for ATTEMPT in $(seq 1 240); do
  LIVE_STATE=$(squeue -h -j "$JOB_ID" -o '%T' 2>/dev/null | head -1 | tr -d '[:space:]')
  if [[ -z "$LIVE_STATE" ]]; then
    break
  fi
  if (( ATTEMPT % 6 == 1 )); then
    printf 'probe_wait attempt=%s state=%s\n' "$ATTEMPT" "$LIVE_STATE"
  fi
  sleep 10
done

echo '=== PROBE ACCOUNTING ==='
sacct -X --jobs "$JOB_ID" \
  --format=JobID,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End
MAIN=$(sacct -X --noheader --parsable2 --jobs "$JOB_ID" \
  --format=JobID,State,ExitCode 2>/dev/null | \
  awk -F'|' -v id="$JOB_ID" '$1 == id {print; exit}')
STATE=$(printf '%s' "$MAIN" | awk -F'|' '{print $2}' | sed 's/+.*$//')
EXIT_CODE=$(printf '%s' "$MAIN" | awk -F'|' '{print $3}')

echo '=== PROBE REPORT ==='
test -s "${STATUS_DIRECTORY}/probe-${JOB_ID}.json" || exit 63
cat "${STATUS_DIRECTORY}/probe-${JOB_ID}.json"
echo '=== PROBE LOGS ==='
cat "${LOG_DIRECTORY}/probe-${JOB_ID}.out" 2>/dev/null || true
cat "${LOG_DIRECTORY}/probe-${JOB_ID}.err" 2>/dev/null || true

python -u hpc/daily_camels_native_kalmannet/preflight.py \
  --bundle-root "$SOURCE_DIRECTORY" \
  --offline-bundle-check > "${STATUS_DIRECTORY}/offline_bundle_check_after_probe.json"
test ! -e "$RUN_DIRECTORY" || exit 64
test "$STATE" = "COMPLETED" || {
  echo "probe did not complete: state=${STATE:-UNKNOWN} exit=${EXIT_CODE:-UNKNOWN}" >&2
  exit 65
}
test "$EXIT_CODE" = "0:0" || exit 66
echo "DAILY_CAMELS_KALMANNET_PROBE_PASS job_id=$JOB_ID run_directory_absent=true"
