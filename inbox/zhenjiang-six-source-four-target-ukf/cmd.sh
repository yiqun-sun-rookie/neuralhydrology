#!/usr/bin/env bash
set -eo pipefail
ROOT='/data1/home/sunyiq/zhenjiang_5s5t_stage_b_20260907_001'
JOB='223517'
QUERY_CONDA_SH="/data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh"
[ -f "$QUERY_CONDA_SH" ] || { printf '[FATAL] query conda activation script absent: %s\n' "$QUERY_CONDA_SH" >&2; exit 1; }
source "$QUERY_CONDA_SH"
conda activate nh_final
python -B - "$ROOT/evidence/submission/attempt_001/submission_receipt.json" "$JOB" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); expected=sys.argv[2]
if not p.is_file(): raise SystemExit('fixed-root submission receipt absent')
d=json.loads(p.read_bytes())
if d.get('status')!='submitted' or d.get('job_id')!=expected or d.get('sbatch_call_count')!=1:
    raise SystemExit('job identifier is not bound to the fixed-root receipt')
PY
printf '%s\n' '=== SUBMISSION ==='
find "$ROOT/evidence/submission" -type f -maxdepth 3 -print -exec sed -n '1,80p' {} \; 2>/dev/null || true
squeue -j "$JOB" -h -o '%i|%j|%T|%P|%M|%R|%Z' || true
sacct -j "$JOB" -X --format=JobID,JobName,State,ExitCode,Elapsed,NodeList || true
printf '%s\n' '=== PROGRESS ==='
for seed in 17 29 43; do
  dir="$ROOT/runs/stage_b/seed_$seed"
  if [ ! -d "$dir" ]; then printf 'seed_%s=not-created\n' "$seed"; continue; fi
  for p in "$dir/first_optimizer_update.json" "$dir/completion.json" "$dir/failure.json"; do [ ! -f "$p" ] || { echo "--- $p"; sed -n '1,200p' "$p"; }; done
  find "$dir" -maxdepth 1 -type f -name 'epoch_*.json' -printf '%f\n' 2>/dev/null | sort | tail -n 3 | while read name; do p="$dir/$name"; echo "--- $p"; tail -n 25 "$p"; done
done
for p in "$ROOT/evidence/stage_b_job_attempt/attempt_001/failure.txt" "$ROOT/evidence/stage_b_job_attempt/attempt_001/completion.json" "$ROOT/logs/stage-b-$JOB.out" "$ROOT/logs/stage-b-$JOB.err"; do [ ! -f "$p" ] || { echo "--- $p"; tail -n 80 "$p"; }; done
printf '%s\n' '=== READ-ONLY USAGE LEDGER ==='
python -B - "$ROOT/evidence/stage_b_formal_data_usage.sqlite3" <<'PY'
import pathlib, sqlite3, sys
p = pathlib.Path(sys.argv[1])
if not p.is_file(): print('ledger_absent'); raise SystemExit(0)
db = sqlite3.connect('file:' + str(p) + '?mode=ro', uri=True)
for name, in db.execute("select name from sqlite_master where type='table' order by name"):
    print(name, db.execute('select count(*) from "' + name.replace('"','""') + '"').fetchone()[0])
print('events_by_type', db.execute('SELECT event_type,COUNT(*),SUM(bytes_read) FROM usage_events GROUP BY event_type ORDER BY event_type').fetchall())
print('partitions', db.execute('SELECT DISTINCT time_partition FROM usage_events ORDER BY time_partition').fetchall())
db.close()
PY
