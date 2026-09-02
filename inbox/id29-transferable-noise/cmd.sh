#!/bin/bash
# id29-transferable-noise seq=3: job status with a bounded wait (<= 8 min), then sacct + log tails.
# No compute on the login node.
set -o pipefail
ROOT=/data1/home/sunyiq/id29_transferable_noise_20260902
J1=218643
J2=218644

echo "=== WAIT (max 8 min) ==="
for i in $(seq 1 48); do
  LEFT=$(squeue -u "$USER" -h -o "%i" -j $J1,$J2 2>/dev/null | wc -l)
  if [ $((i % 6)) -eq 0 ]; then
    echo "t=$((i*10))s left=$LEFT $(squeue -u "$USER" -h -o '%i:%t:%M:%R' -j $J1,$J2 2>/dev/null | tr '\n' ' ')"
  fi
  [ "$LEFT" -eq 0 ] && break
  sleep 10
done

echo "=== SACCT ==="
sacct -j $J1,$J2 -X --format=JobID%10,JobName%14,Partition%8,NodeList%9,State%12,ExitCode%8,Elapsed%10,AllocCPUS%6 2>&1 || true

echo "=== LOG TAILS ==="
for f in "$ROOT"/logs/*.out; do
  [ -f "$f" ] || continue
  echo "--- $f ---"; tail -n 30 "$f" 2>&1 || true
done
for f in "$ROOT"/logs/*.err; do
  [ -f "$f" ] || continue
  s=$(wc -c < "$f"); echo "--- $f ($s bytes) ---"
  [ "$s" -gt 0 ] && tail -n 15 "$f" 2>&1 || true
done
echo "=== DONE ==="
