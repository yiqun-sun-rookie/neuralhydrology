#!/bin/bash
# READ-ONLY Stage-2 status probe: queue, accounting of the 33 submitted jobs, gate markers, finished arms.
# No backslash literals anywhere in this file.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap2_daily_2026_09
echo "=== A. queue (ours) ==="
squeue -u "$USER" -o '%.10i %.34j %.9T %.10M %.9P %R' 2>&1 | grep -Ei 'pswap2|ref_daymet|JOBID'
echo "  squeue rc=${PIPESTATUS[0]}"
echo "=== B. accounting of registered jobs ==="
ids=$(awk '{print $2}' $R/logs/jobs.txt | paste -sd, -)
sacct -X -j "$ids" --format=JobID%9,JobName%34,State%12,Elapsed%10,ExitCode%8,NodeList%10 2>&1 | grep -vE '^ *[0-9]+ .* (PENDING) ' | head -60
echo "  sacct rc=${PIPESTATUS[0]}"
echo "  pending: $(sacct -X -n -j "$ids" --format=State 2>/dev/null | grep -c PENDING)  running: $(sacct -X -n -j "$ids" --format=State 2>/dev/null | grep -c RUNNING)  completed: $(sacct -X -n -j "$ids" --format=State 2>/dev/null | grep -c COMPLETED)  failed/cancelled/timeout: $(sacct -X -n -j "$ids" --format=State 2>/dev/null | grep -cE 'FAILED|CANCEL|TIMEOUT|NODE_FAIL')"
echo "=== C. gate markers ==="
ls -la $R/logs/gate_*.txt 2>/dev/null | sed 's/^/  /' || echo "  (none yet)"
echo "=== D. build reports (V4 max NaN, lag stats) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null; conda activate nh_final 2>/dev/null
for f in $R/logs/build_*.json; do [ -f "$f" ] && echo "  $(basename $f): $(python -c "import json,sys; d=json.load(open(sys.argv[1])); print('fails', len(d.get('failures',[])), 'nan_max', d.get('nan_days_max'), 'lag_within1', round(d.get('lag_within1_share',0),3), 'ratio', round(d.get('ratio_over_daymet',{}).get('median',0),3))" $f 2>/dev/null)"; done
echo "=== E. finished arms (test_metrics.csv present) ==="
n=$(ls $R/runs/*/test/model_epoch030/test_metrics.csv 2>/dev/null | wc -l); echo "  $n arm(s) evaluated"
ls $R/runs 2>/dev/null | sed 's/^/  /'
echo "=== F. recent failures in slurm logs ==="
grep -lE 'Traceback|Error|FAIL' $R/logs/slurm_*.err $R/logs/slurm_*.out 2>/dev/null | head -10 | sed 's/^/  /' || true
echo "=== G. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
