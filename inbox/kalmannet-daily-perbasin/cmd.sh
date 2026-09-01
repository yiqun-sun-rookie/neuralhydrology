#!/usr/bin/env bash
set -euo pipefail

REMOTE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901"
EXECUTION_ID="DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_A800_TRAIN3_SEQ13"
JOB_ID="217415"
JOB_NAME="kdpp-04105700-s13"
STATUS_DIRECTORY="${REMOTE_ROOT}/status"
RUN_DIRECTORY="${REMOTE_ROOT}/runs/${EXECUTION_ID}"
SUBMISSION_RECEIPT="${STATUS_DIRECTORY}/${EXECUTION_ID}.submission_receipt.txt"
EXPECTED_SUBMISSION_RECEIPT_SHA256="8d3c249cec64c5e4c9230ea995fbb528dc5658c59247e77b1dbf10401dfa6a2d"

echo '=== READ-ONLY 04105700 FRAMEWORK-FREE PROGRESS QUERY ==='
date --iso-8601=seconds
hostname
echo 'channel=kalmannet-daily-perbasin sequence=14 purpose=read-only-first-pilot-runtime-gate-and-training-progress'
echo 'signals_sent=0 submissions_created=0 files_modified=0'

if [[ ! -f "${SUBMISSION_RECEIPT}" ]] || \
   [[ "$(sha256sum "${SUBMISSION_RECEIPT}" | awk '{print $1}')" != "${EXPECTED_SUBMISSION_RECEIPT_SHA256}" ]]; then
  echo '04105700 submission receipt is absent or changed' >&2
  exit 120
fi

echo '=== SQUEUE ==='
squeue -j "${JOB_ID}" -o '%i|%j|%P|%T|%R|%M|%S|%N' || true
echo '=== SACCT ==='
sacct -j "${JOB_ID}" -X \
  --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList,AllocTRES \
  -n -P || true
echo '=== EXACT JOB COUNTS ==='
squeue -h -u sunyiq -o '%i|%j|%T|%N' | \
  awk -F'|' -v name="${JOB_NAME}" '$2 == name {count++} END {print "active_exact_name=" count+0}'
sacct -u sunyiq -S 2026-09-01T00:00:00 -X --format=JobIDRaw,JobName,State -n -P | \
  awk -F'|' -v name="${JOB_NAME}" '$2 == name {count++} END {print "historical_exact_name=" count+0}'

for member in \
  "${STATUS_DIRECTORY}/${EXECUTION_ID}.slurm-${JOB_ID}.out" \
  "${STATUS_DIRECTORY}/${EXECUTION_ID}.slurm-${JOB_ID}.err" \
  "${STATUS_DIRECTORY}/${EXECUTION_ID}.entry.json" \
  "${STATUS_DIRECTORY}/${EXECUTION_ID}.audit.json" \
  "${STATUS_DIRECTORY}/${EXECUTION_ID}.cgroup.txt"
do
  echo "=== STATUS MEMBER: ${member} ==="
  if [[ -f "${member}" ]]; then
    stat -c 'bytes=%s modified=%y' "${member}"
    sha256sum "${member}"
    tail -n 100 "${member}"
  else
    echo 'MISSING'
  fi
done

GPU_LOG="${STATUS_DIRECTORY}/${EXECUTION_ID}.gpu.csv"
echo '=== GPU RESOURCE LOG ==='
if [[ -f "${GPU_LOG}" ]]; then
  stat -c 'bytes=%s modified=%y' "${GPU_LOG}"
  awk -F',' 'BEGIN {max=-1; rows=0} {value=$5+0; if (value>max) max=value; rows++} END {print "rows=" rows " peak_memory_used_mib=" max}' "${GPU_LOG}"
  tail -n 5 "${GPU_LOG}"
else
  echo 'MISSING'
fi

echo '=== RUN DIRECTORY PROGRESS ==='
if [[ -d "${RUN_DIRECTORY}" ]]; then
  du -sh "${RUN_DIRECTORY}"
  printf 'checkpoint_files='; find "${RUN_DIRECTORY}/checkpoints" -maxdepth 1 -type f 2>/dev/null | wc -l
  printf 'prediction_files='; find "${RUN_DIRECTORY}/predictions" -maxdepth 1 -type f 2>/dev/null | wc -l
  find "${RUN_DIRECTORY}" -maxdepth 2 -type f -printf '%P|%s|%TY-%Tm-%TdT%TH:%TM:%TS\n' | sort | tail -n 20
  if [[ -f "${RUN_DIRECTORY}/epoch_history.json" ]]; then
    python - "${RUN_DIRECTORY}/epoch_history.json" <<'PY'
import json
from pathlib import Path
import sys

history = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
best = min(history, key=lambda row: row["checkpoint_objective_728"])
last = history[-1]
print(
    json.dumps(
        {
            "history_rows": len(history),
            "last_completed_epoch": last["epoch"],
            "last_checkpoint_objective_728": last["checkpoint_objective_728"],
            "best_epoch_so_far": best["epoch"],
            "best_checkpoint_objective_728_so_far": best["checkpoint_objective_728"],
            "optimizer_steps": last["optimizer_steps"],
            "training_forecast_error_events": last["training_forecast_error_events"],
        },
        sort_keys=True,
    )
)
PY
  fi
  for final_member in result_summary.json completion.marker.json; do
    if [[ -f "${RUN_DIRECTORY}/${final_member}" ]]; then
      echo "=== FINAL MEMBER: ${final_member} ==="
      sha256sum "${RUN_DIRECTORY}/${final_member}"
      cat "${RUN_DIRECTORY}/${final_member}"
    fi
  done
  if [[ -f "${RUN_DIRECTORY}/manifest.sha256.json" ]]; then
    echo '=== FINAL MANIFEST HASH ==='
    sha256sum "${RUN_DIRECTORY}/manifest.sha256.json"
  fi
else
  echo 'MISSING'
fi

echo '=== QUERY COMPLETE: READ ONLY, NO SUBMISSION OR SIGNAL ==='
