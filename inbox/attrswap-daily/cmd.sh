#!/bin/bash
# seq=79 READ-ONLY first-check after HANDOFF_20260913: (a) no job of this campaign in queue,
# (b) accounting of the 33 stage-2 jobs 225205-225237 still all COMPLETED,
# (c) the four landing dirs still exist with expected counts. Nothing is written or modified.
# No backslash literals anywhere in this file.
set -o pipefail
date "+wallclock %F %T %z"
R2=/data1/home/sunyiq/precip_swap2_daily_2026_09
RA=/data1/home/sunyiq/attr_swap_daily_2026_09
RF=/data1/home/sunyiq/forcing_swap_daily_2026_09
RP=/data1/home/sunyiq/precip_swap_daily_2026_09
SH="$R2/data_shadow/camels_us"

echo "=== A. QUEUE: this campaign (header must be visible; expect header only) ==="
squeue -u "$USER" -o '%.10i %.34j %.9T %.10M %.9P %R' 2>&1 | grep -Ei 'pswap|ref_daymet|attrswap|fswap|JOBID'
echo "  squeue rc=${PIPESTATUS[0]}"
echo "  whole-account queue count (all channels, context only): $(squeue -u "$USER" -h 2>/dev/null | wc -l)"

echo "=== B. ACCOUNTING of registered stage-2 jobs (expect 33 COMPLETED, 0 other) ==="
if [ -f "$R2/logs/jobs.txt" ]; then
  ids=$(awk '{print $2}' "$R2/logs/jobs.txt" | paste -sd, -)
  echo "  registered ids: $(awk '{print $2}' "$R2/logs/jobs.txt" | wc -l) (first $(awk 'NR==1{print $2}' "$R2/logs/jobs.txt") last $(awk 'END{print $2}' "$R2/logs/jobs.txt"))"
  st=$(sacct -X -n -j "$ids" --format=State 2>&1)
  echo "  sacct rc=$?"
  echo "  completed: $(echo "$st" | grep -c COMPLETED)  running: $(echo "$st" | grep -c RUNNING)  pending: $(echo "$st" | grep -c PENDING)  failed/cancelled/timeout: $(echo "$st" | grep -cE 'FAILED|CANCEL|TIMEOUT|NODE_FAIL')"
else
  echo "  MISSING $R2/logs/jobs.txt"
fi

echo "=== C. FOUR LANDING DIRS (expect all 4 present) ==="
for d in "$R2" "$RA" "$RF" "$RP"; do
  if [ -d "$d" ]; then echo "  OK  $(stat -c '%y' "$d" | cut -c1-19)  $d"; else echo "  MISSING $d"; fi
done

echo "=== D. precip_swap2 counts (expect runs=26 runs_smoke=9 metrics=26 gate=7 build=6) ==="
echo "  runs=$(ls "$R2/runs" 2>/dev/null | wc -l) runs_smoke=$(ls "$R2/runs_smoke" 2>/dev/null | wc -l) metrics=$(ls "$R2"/runs/*/test/model_epoch030/test_metrics.csv 2>/dev/null | wc -l) gate=$(ls "$R2"/logs/gate_*.txt 2>/dev/null | wc -l) build=$(ls "$R2"/logs/build_*.json 2>/dev/null | wc -l)"
echo "  files under runs/ newer than 2026-09-13 16:06 (expect 0): $(find "$R2/runs" -type f -newermt '2026-09-13 16:06' 2>/dev/null | wc -l)"
echo "  daymet shadow link: $(readlink "$SH/basin_mean_forcing/daymet" 2>/dev/null || echo 'not a symlink or absent')"
echo "  dangling links under shadow (expect none): $(find -L "$SH" -type l 2>/dev/null | head -3 | wc -l)"

echo "=== E. sealed roots (expect precip_swap runs=9 with 3 INCOMPLETE_ABORTED_*) ==="
echo "  precip_swap runs=$(ls "$RP/runs" 2>/dev/null | wc -l) aborted=$(ls -d "$RP"/runs/INCOMPLETE_ABORTED_* 2>/dev/null | wc -l)"
echo "  attr_swap runs=$(ls "$RA/runs" 2>/dev/null | wc -l)  forcing_swap runs=$(ls "$RF/runs" 2>/dev/null | wc -l)"
echo "  files newer than 2026-09-13 18:20 in the three sealed roots (expect 0): $(find "$RA" "$RF" "$RP" -type f -newermt '2026-09-13 18:20' 2>/dev/null | wc -l)"

echo "=== F. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
