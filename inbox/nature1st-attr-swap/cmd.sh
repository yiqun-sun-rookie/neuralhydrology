#!/bin/bash
# nature1st-attr-swap seq=103 -- let armJ (215195) also use partition hgpu2.
# MEASURED, not assumed: ngu009 (hgpu2) reports NVIDIA GeForce RTX 3090 / 24576 MiB /
# driver 535.104.05 -- identical to ngu010 (hgpu2p), where earlier arms ran. ngu101
# (hgpu4) reports NVIDIA A40 / 46068 MiB, a DIFFERENT card, so hgpu4 and hgpu8 stay out:
# the effects being judged are 0.005-0.030 wide and must not absorb a hardware change.
# This is scontrol update on a PENDING job -- no cancel, no resubmit, priority/age kept,
# job id and log paths unchanged. No new machine time is consumed by the change itself.
set -o pipefail
date "+wallclock %F %T %z"

echo "=== A. BEFORE ==="
squeue -j 215195 -o '%.10i %.22j %.9T %.12P %.20S %.20R' 2>&1
scontrol show job 215195 2>&1 | grep -E 'Partition=|ExcNodeList|JobState|Reason' | head -4 || true

echo "=== B. WIDEN PARTITION LIST ==="
scontrol update JobId=215195 Partition=hgpu2p,hgpu2 2>&1 && echo '  update accepted' || echo '  UPDATE REFUSED'

echo "=== C. AFTER (wait 30s for the scheduler to re-evaluate) ==="
sleep 30
squeue -j 215195 -o '%.10i %.22j %.9T %.12P %.10M %.9N %.24R %.20S' 2>&1
scontrol show job 215195 2>&1 | grep -E 'Partition=|JobState|Reason|StartTime|NodeList' | head -5 || true

echo "=== D. IF STILL PENDING, WAIT A BIT MORE ==="
for i in $(seq 1 12); do
  ST=$(squeue -j 215195 -h -o '%T' 2>/dev/null)
  [ "$ST" = 'RUNNING' ] && { echo "  started at t=$((i*10))s"; break; }
  [ -z "$ST" ] && { echo '  no longer in queue'; break; }
  [ $((i % 3)) -eq 0 ] && echo "  t=$((i*10))s state=$ST"
  sleep 10
done
squeue -j 215195 -o '%.10i %.9T %.12P %.10M %.9N %.24R' 2>&1

echo "=== E. GUARD CHECK IF IT STARTED ==="
f=$(ls /data1/home/sunyiq/nature_1st/logs/attr_swap/armJ_china_min15-215195.out 2>/dev/null | head -1)
if [ -n "$f" ]; then echo "  log: $f ($(stat -c%s "$f") bytes)"; grep -E "\[guard\]|PyTorch|Epoch" "$f" 2>/dev/null | head -5 || true; else echo "  (no log yet)"; fi
echo "=== END seq=103 ==="
