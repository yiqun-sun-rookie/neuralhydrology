#!/bin/bash
# READ-ONLY: why did the precip-swap gate fail on hgpu4 after 3 seconds with exit code 4 (my env guard)?
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap_daily_2026_09
echo "=== A. GATE STDOUT ==="
f=$(ls -t "$R"/logs/slurm_pswap_gate_*.out 2>/dev/null | head -1) || true
[ -n "$f" ] && { echo "--- $(basename $f) ---"; cat "$f"; }
echo "=== B. GATE STDERR ==="
e=$(ls -t "$R"/logs/slurm_pswap_gate_*.err 2>/dev/null | head -1) || true
[ -n "$e" ] && { echo "--- $(basename $e) ---"; head -40 "$e"; }
echo "=== C. WHAT OS / GLIBC / DRIVER DO THE PARTITIONS RUN? ==="
echo "  (login node for reference)"
cat /etc/redhat-release 2>/dev/null; ldd --version 2>/dev/null | head -1
echo "=== D. NODE FEATURES ==="
sinfo -p hgpu4 -N -o "%.9N %.8t %.14C %.8G %.30f" 2>&1
sinfo -p hgpu8 -N -o "%.9N %.8t %.14C %.8G %.30f" 2>&1
sinfo -p hgpu2p -N -o "%.9N %.8t %.14C %.8G %.30f" 2>&1 | head -10
echo "=== E. PAST SUCCESSFUL JOBS: WHICH NODES ==="
sacct -u "$USER" -X -S 2026-09-05 --format=JobID%9,JobName%22,State%11,NodeList%9,Partition%8 2>&1 \
  | grep -E "COMPLETED" | tail -12
echo "=== DONE ==="
