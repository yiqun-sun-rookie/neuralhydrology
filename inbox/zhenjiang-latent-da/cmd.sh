#!/bin/bash
set -eo pipefail

JOB_ID=215189
ROOT="/data1/home/sunyiq/zhenjiang_latent_da_20260827"
RUN_REL="run/results/runtime/zhenjiang_latent_gru_kalmannet_hpc_smoke_v1/ZLDA-SMOKE-01"
RUN_DIR="${ROOT}/${RUN_REL}"
MAILBOX_OUT="${HOME}/hpc_mailbox/outbox/zhenjiang-latent-da"
ARCHIVE_NAME="ZLDA-SMOKE-01_job215189_small_evidence.tar.gz"

test -f "${RUN_DIR}/completion_manifest.json"
test -f "${RUN_DIR}/run_identity.json"

echo "COLLECT_START $(date -Is)"
echo "SACCT"
sacct -j "${JOB_ID}" -P \
  --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList,AllocTRES,ReqTRES,MaxRSS,MaxVMSize

for relative_path in \
  completion_manifest.json \
  run_identity.json \
  config_snapshot.json \
  registry_snapshot.json \
  fold_astronomical_tide/completion_manifest.json \
  fold_astronomical_tide/fold_tide_metadata.json \
  stage_one/training_history.csv \
  stage_two/training_history.csv
do
  echo "FILE_BEGIN ${relative_path}"
  cat "${RUN_DIR}/${relative_path}"
  echo
  echo "FILE_END ${relative_path}"
done

echo "ARTIFACT_SHA256"
find "${RUN_DIR}" -type f -print0 | sort -z | xargs -0 sha256sum

echo "SLURM_STDOUT"
cat "${ROOT}/logs/zlda-smoke01-${JOB_ID}.out"
echo "SLURM_STDERR"
cat "${ROOT}/logs/zlda-smoke01-${JOB_ID}.err"

TMP_DIR="$(mktemp -d "${HOME}/zlda_evidence_XXXXXX")"
tar -czf "${TMP_DIR}/${ARCHIVE_NAME}" -C "${ROOT}" \
  "logs/zlda-smoke01-${JOB_ID}.out" \
  "logs/zlda-smoke01-${JOB_ID}.err" \
  "${RUN_REL}/completion_manifest.json" \
  "${RUN_REL}/run_identity.json" \
  "${RUN_REL}/config_snapshot.json" \
  "${RUN_REL}/registry_snapshot.json" \
  "${RUN_REL}/fold_astronomical_tide/completion_manifest.json" \
  "${RUN_REL}/fold_astronomical_tide/fold_tide_metadata.json" \
  "${RUN_REL}/stage_one/training_history.csv" \
  "${RUN_REL}/stage_two/training_history.csv"
mkdir -p "${MAILBOX_OUT}"
cp -f "${TMP_DIR}/${ARCHIVE_NAME}" "${MAILBOX_OUT}/${ARCHIVE_NAME}"
echo "EVIDENCE_ARCHIVE $(sha256sum "${MAILBOX_OUT}/${ARCHIVE_NAME}") bytes=$(stat -c '%s' "${MAILBOX_OUT}/${ARCHIVE_NAME}")"
echo "COLLECT_END $(date -Is)"
