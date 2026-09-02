#!/usr/bin/env bash
set -euo pipefail

REMOTE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901"
EXECUTION_ID="DAILY_CAMELS_KNET_PER_BASIN_PILOT_08070200_A800_TRAIN1_SEQ18"
JOB_ID="217562"
STATUS_DIRECTORY="${REMOTE_ROOT}/status"
RUN_DIRECTORY="${REMOTE_ROOT}/runs/${EXECUTION_ID}"
SUBMISSION_RECEIPT="${STATUS_DIRECTORY}/${EXECUTION_ID}.submission_receipt.txt"
EXPECTED_SUBMISSION_RECEIPT_SHA256="3c1fa0c33ba42d4b48f0f721cf8fbc2b88b4cc2f1d79377df13d5ea5e5efa195"
EXPECTED_LAST_CHECKPOINT_SHA256="e4d53ec2e51c74378a4ec87b5bd3d46f271966170cf1ff351c4f9c19fd4172c8"

echo '=== READ-ONLY 08070200 EPOCH-58 FAILURE DIAGNOSTIC EVIDENCE ==='
date --iso-8601=seconds
hostname
echo 'channel=kalmannet-daily-perbasin sequence=29 purpose=read-only-eleven-state-nonfinite-gradient-diagnosis'
echo 'signals_sent=0 submissions_created=0 files_modified=0 optimizer_steps=0 formal_evaluation_access=0'

if [[ ! -f "${SUBMISSION_RECEIPT}" ]] || \
   [[ "$(sha256sum "${SUBMISSION_RECEIPT}" | awk '{print $1}')" != "${EXPECTED_SUBMISSION_RECEIPT_SHA256}" ]]; then
  echo '08070200 submission receipt is absent or changed' >&2
  exit 191
fi

echo '=== ACTIVE JOB COUNTS FOR ALL THREE PILOTS (expect 0) ==='
squeue -h -u sunyiq -o '%i|%j|%T|%N' | \
  awk -F'|' '$2 ~ /^kdpp-/ {count++} END {print "active_per_basin_pilot_jobs=" count+0}'
squeue -h -u sunyiq -o '%i|%j|%T|%N' | awk -F'|' '{print "  other_active: " $0}' | head -20
echo '=== SACCT FOR THE FAILED JOB ==='
sacct -j "${JOB_ID}" -X --format=JobIDRaw,JobName,State,ExitCode,Elapsed -n -P || true

echo '=== RUN DIRECTORY INTEGRITY ==='
if [[ ! -d "${RUN_DIRECTORY}" ]]; then echo 'RUN DIRECTORY MISSING' >&2; exit 192; fi
du -sh "${RUN_DIRECTORY}"
printf 'checkpoint_files='; find "${RUN_DIRECTORY}/checkpoints" -maxdepth 1 -type f | wc -l
printf 'prediction_files='; find "${RUN_DIRECTORY}/predictions" -maxdepth 1 -type f | wc -l

echo '=== EPOCH 57 CHECKPOINT IDENTITY AND DOWNLOAD SIZE ==='
LAST_CKPT="$(find "${RUN_DIRECTORY}/checkpoints" -maxdepth 1 -type f -name '*057*' | sort | tail -n 1)"
echo "path=${LAST_CKPT}"
if [[ -n "${LAST_CKPT}" && -f "${LAST_CKPT}" ]]; then
  stat -c 'bytes=%s modified=%y' "${LAST_CKPT}"
  ACTUAL="$(sha256sum "${LAST_CKPT}" | awk '{print $1}')"
  echo "sha256=${ACTUAL}"
  if [[ "${ACTUAL}" == "${EXPECTED_LAST_CHECKPOINT_SHA256}" ]]; then
    echo 'epoch_57_checkpoint_identity=MATCHES_REGISTERED_AUDIT'
  else
    echo 'epoch_57_checkpoint_identity=MISMATCH_DO_NOT_USE'
  fi
else
  echo 'epoch_57_checkpoint=MISSING'
fi
echo '--- checkpoint sizes (first 3 and last 3) ---'
find "${RUN_DIRECTORY}/checkpoints" -maxdepth 1 -type f -printf '%f|%s\n' | sort | head -3
find "${RUN_DIRECTORY}/checkpoints" -maxdepth 1 -type f -printf '%f|%s\n' | sort | tail -3

echo '=== EPOCH HISTORY: GRADIENT NORM TRAJECTORY (never retrieved before) ==='
HIST="${RUN_DIRECTORY}/epoch_history.json"
if [[ -f "${HIST}" ]]; then
  stat -c 'bytes=%s modified=%y' "${HIST}"
  sha256sum "${HIST}"
  python - "${HIST}" <<'PY'
import json, sys
from pathlib import Path
rows = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
keys = sorted({k for r in rows for k in r})
print("history_rows=%d" % len(rows))
print("available_keys=%s" % ",".join(keys))
print("epoch|gradient_norm_before_clip|training_objective|same_segment_post_step|checkpoint_objective_728|parameter_sha256_prefix")
for r in rows:
    g = r.get("gradient_norm_before_clip")
    p = r.get("parameter_sha256") or ""
    print("%d|%s|%s|%s|%s|%s" % (
        r.get("epoch", -1),
        "" if g is None else repr(g),
        repr(r.get("training_objective")),
        repr(r.get("same_segment_post_step_objective")),
        repr(r.get("checkpoint_objective_728")),
        p[:16],
    ))
vals = [(r["epoch"], r["gradient_norm_before_clip"]) for r in rows
        if r.get("gradient_norm_before_clip") is not None]
if vals:
    mx = max(vals, key=lambda t: t[1])
    print("gradient_norm_min=%r gradient_norm_max=%r at_epoch=%d" % (min(v for _, v in vals), mx[1], mx[0]))
    print("epochs_above_clip_threshold_10=%r" % [e for e, v in vals if v > 10.0])
PY
else
  echo 'EPOCH HISTORY MISSING'
fi

echo '=== QUERY COMPLETE: READ ONLY, NO SUBMISSION, NO SIGNAL, NO WRITE ==='
