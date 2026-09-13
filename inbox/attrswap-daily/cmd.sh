#!/bin/bash
# READ-ONLY Stage-2 status probe (2026-09-13): queue with reasons, accounting, partition state, priority diagnosis.
# No backslash literals anywhere in this file.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap2_daily_2026_09
echo "=== A. our queue (all states) ==="
squeue -u "$USER" -o '%.10i %.34j %.9T %.10M %.9P %.12S %R' 2>&1 | head -45
echo "  squeue rc=${PIPESTATUS[0]}"
echo "=== B. accounting of the 33 registered jobs ==="
ids=$(awk '{print $2}' $R/logs/jobs.txt | paste -sd, -)
sacct -X -j "$ids" --format=JobID%9,JobName%30,State%12,Submit%20,Start%20,Elapsed%10,ExitCode%8,NodeList%10 2>&1 | head -40
echo "  sacct rc=${PIPESTATUS[0]}"
echo "  states: $(sacct -X -n -j "$ids" --format=State 2>/dev/null | awk '{print $1}' | sort | uniq -c | tr -s ' ' | paste -sd, -)"
echo "=== C. partitions and nodes ==="
sinfo -p hgpu4,hgpu8 -o '%P %.6D %.10T %.20G %.30N %.8c %.10m' 2>&1
sinfo -p hgpu4 -N -o '%N %.10T %.20G %.30E' 2>&1 | head -8
echo "=== D. who is running on hgpu4 right now ==="
squeue -p hgpu4 -o '%.10i %.9u %.9T %.10M %.6D %.12b %R' 2>&1 | head -20
echo "=== E. priority diagnosis for the reference gate ==="
sprio -j 225205 2>&1 | head -3
scontrol show job 225205 2>&1 | grep -E 'JobState|Reason|Priority|SubmitTime|EligibleTime|StartTime|Partition|QOS|TRES' | head -10
sshare -u "$USER" 2>&1 | head -5
echo "=== F. gate markers / runs ==="
ls $R/logs/gate_*.txt 2>/dev/null | sed 's/^/  /' || echo "  (none)"
echo "  runs: $(ls $R/runs 2>/dev/null | wc -l)  evaluated: $(ls $R/runs/*/test/model_epoch030/test_metrics.csv 2>/dev/null | wc -l)"
ls -t $R/logs/slurm_*.out 2>/dev/null | head -3 | sed 's/^/  /'
echo "=== G. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
