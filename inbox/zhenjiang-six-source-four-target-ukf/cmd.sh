#!/usr/bin/env bash
set -eo pipefail
REMOTE_ROOT="/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001"
date --iso-8601=seconds
hostname
if [ ! -d "${REMOTE_ROOT}" ] || [ -L "${REMOTE_ROOT}" ]; then
  echo 'registered_new_root_absent_or_not_ordinary'
  exit 0
fi
RECEIPT="${REMOTE_ROOT}/evidence/submission/attempt_001/submission_receipt.json"
if [ -f "${RECEIPT}" ] && [ ! -L "${RECEIPT}" ]; then
  echo '=== SUBMISSION RECEIPT ==='
  cat "${RECEIPT}"
  JOB_ID="$(sed -n 's/.*"job_id": "\([0-9][0-9]*\)".*/\1/p' "${RECEIPT}")"
  [[ "${JOB_ID}" =~ ^[0-9]+$ ]] || exit 1
  echo '=== CURRENT JOB STATE ==='
  squeue -j "${JOB_ID}" -h -o '%i|%j|%T|%P|%M|%R|%Z' || true
  sacct -j "${JOB_ID}" --format=JobID,State,ExitCode,Elapsed,NodeList -P || true
  for extension in out err; do
    LOG="${REMOTE_ROOT}/logs/stage-a-${JOB_ID}.${extension}"
    if [ -f "${LOG}" ] && [ ! -L "${LOG}" ]; then
      printf '\n=== LOG %s ===\n' "${extension}"
      tail -n 100 -- "${LOG}"
    fi
  done
else
  echo 'submission_receipt_absent'
fi
echo '=== ATTEMPT EVIDENCE NAMES ONLY ==='
find "${REMOTE_ROOT}/evidence/stage_a_attempts" "${REMOTE_ROOT}/evidence/stage_a_failures" "${REMOTE_ROOT}/runs/stage_a" -maxdepth 3 -type f -printf '%P|%s bytes\n' | head -n 55 || true
echo 'read_only_status=true data_files_opened=false sbatch_calls=0'
if [ -f "${REMOTE_ROOT}/evidence/stage_a_formal_data_usage.sqlite3" ]; then
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export PYTHONDONTWRITEBYTECODE=1
python -B - "${REMOTE_ROOT}/evidence/stage_a_formal_data_usage.sqlite3" <<'PY'
import json
from pathlib import Path
import sqlite3
import sys
path = Path(sys.argv[1])
if path.is_symlink() or not path.is_file():
    raise SystemExit('ordinary ledger is absent')
connection = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)
connection.execute('PRAGMA query_only=ON')
document = {
    'events_by_type': connection.execute('SELECT event_type,COUNT(*),SUM(bytes_read) FROM usage_events GROUP BY event_type ORDER BY event_type').fetchall(),
    'partitions': connection.execute('SELECT DISTINCT time_partition FROM usage_events ORDER BY time_partition').fetchall(),
    'baselines': connection.execute('SELECT authorization_id,previous_access_count_confirmed,maximum_read_count FROM authorization_baselines').fetchall(),
    'completed_distinct_paths': connection.execute("SELECT COUNT(DISTINCT path) FROM usage_events WHERE event_type='COMPLETED'").fetchone()[0],
    'raw_formal_data_opened': False,
}
connection.close()
print(json.dumps(document, sort_keys=True))
PY
fi
