#!/usr/bin/env bash
set -eo pipefail
REMOTE_ROOT="/data1/home/sunyiq/zhenjiang_five_source_five_target_single_analysis_ukf_oracle_datong_20260904_r1"
date --iso-8601=seconds
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
cat "${REMOTE_ROOT}/evidence/stage_a_failures/first_stage_failure/failure.json"
printf '\nread_only_evidence_query=true sbatch_calls=0\n'
