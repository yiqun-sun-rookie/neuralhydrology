#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf28_20260902
JOB=218693

echo "=== WAIT FOR ANCHOR $JOB (max 25 min) ==="
for i in $(seq 1 50); do
  S=$(sacct -j $JOB -X -n -P --format=State 2>/dev/null | head -1)
  case "$S" in
    COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL) break ;;
  esac
  sleep 30
done
echo "anchor state: ${S:-unknown}"
sacct -j $JOB -X -n -P --format=State,ExitCode,Elapsed 2>/dev/null | head -1

echo "=== ANCHOR GATE ==="
python - <<'PY'
import json, pathlib
p = pathlib.Path('/data1/home/sunyiq/kalmannet_tukf28_20260902/results/anchor_gate_verdict.json')
if not p.exists():
    print('VERDICT_MISSING'); raise SystemExit(1)
v = json.loads(p.read_text())
print('pass=%s %d/%d  missing=%d  tol=%g'
      % (v['pass'], v['passed_count'], v['required'], len(v['missing']), v['tolerance']))
print('max_anchor_delta=%.3e' % max(v['anchor_deltas'].values()))
raise SystemExit(0 if v['pass'] else 1)
PY
if [ $? -ne 0 ]; then echo "ANCHOR_GATE_FAILED"; exit 1; fi

echo "=== NODE HEADROOM BEFORE TRAIN ==="
sinfo -p hcpu48y -o "%t %C" -h | head -6

echo "=== SBATCH TRAIN ARRAY 54 (2 cpus/task) ==="
cd $ROOT || exit 1
sbatch $ROOT/slurm/tukf28_train.slurm || exit 1
echo SEQ3_OK
