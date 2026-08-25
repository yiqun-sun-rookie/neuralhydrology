#!/bin/bash
# nature1st-attr-swap seq=91 -- READ-ONLY roll call. What, if anything, is running?
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
echo "=== A. MY QUEUE RIGHT NOW ==="
date "+wallclock %F %T %z"
squeue -u $USER -o '%.10i %.26j %.9T %.11M %.20R' 2>&1 | head -25
echo "-- total lines above (1 = header only = nothing queued) --"
squeue -u $USER -h 2>&1 | wc -l

echo "=== B. ANY ATTRIBUTE-SWAP ARM ANYWHERE? ==="
squeue -u $USER -h -o '%i %j %T' 2>&1 | grep -Ei 'arm|attr|q_ctrl|q_treat' || echo '  none'

echo "=== C. THE EIGHT ARMS -- WHAT EXISTS ON DISK ==="
cd "$RUN" || exit 1
for d in q_lstm_control_hpc_s42 q_lstm_hydroatlas_hpc_s42 q_lstm_usminus4_hpc_s42 \
         q_lstm_globalplus4_hpc_s42 q_lstm_armE_hpc_s42 q_lstm_armF_hpc_s42 \
         q_lstm_armG_hpc_s42 q_lstm_armH_hpc_s42 q_lstm_armG_hpc_s43 q_lstm_armG_hpc_s44 ; do
  if [ -f models/$d/best_metrics.json ]; then
    m=$(python -c "import json,sys;print(f'{json.load(open(sys.argv[1]))[\"median_nse\"]:.4f}')" models/$d/best_metrics.json 2>/dev/null)
    printf '  %-30s DONE  median=%s
' "$d" "$m"
  elif [ -d models/$d ]; then printf '  %-30s DIR EXISTS but no best_metrics
' "$d"
  else printf '  %-30s absent
' "$d"; fi
done

echo "=== D. RECENT JOBS (last 3 days) ==="
sacct -S $(date -d '3 days ago' +%F) -u $USER -X --format=JobID%10,JobName%26,State%12,Elapsed%11,End%17 2>&1 | grep -Ei 'arm|attr|q_ctrl|q_treat|JobID|^---' || echo '  no attribute-swap jobs in window'

echo "=== E. ATTRIBUTE FILES READY TO SUBMIT ==="
for f in stage_static_feature_stats_armH.json stage_static_feature_stats_armG.json ; do
  [ -f data/interim/$f ] && printf '  %-46s present
' "$f" || printf '  %-46s ABSENT
' "$f"
done
ls -1 scripts/hpc_train_q_arm*.sbatch 2>&1 | head -6
echo "=== END seq=91 ==="
