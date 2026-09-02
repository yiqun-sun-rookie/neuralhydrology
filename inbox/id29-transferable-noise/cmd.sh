#!/bin/bash
# id29-transferable-noise seq=10: status of the two training-length jobs. No wait loop, no compute.
set -o pipefail
ROOT=/data1/home/sunyiq/id29_transferable_noise_20260902
cd "$ROOT" || { echo "ROOT_MISSING"; exit 1; }
echo "=== SACCT ==="
sacct -j 218675,218676 -X --format=JobID%10,JobName%16,NodeList%9,State%12,ExitCode%8,Elapsed%10,AllocCPUS%6 2>&1 || true
echo "=== PROGRESS COUNTS ==="
D=results/23_camels_switch_confirmation/noise_axis_training_length_20260902_hpc
for L in L2 L3; do
  echo "$L learn: $(ls "$D/$L/learn" 2>/dev/null | grep -c json) / 46   borrow: $(ls "$D/$L/borrow" 2>/dev/null | grep -c json) / 46"
done
[ -f "$D/frozen_basin_list.csv" ] && echo "frozen list rows: $(( $(wc -l < "$D/frozen_basin_list.csv") - 1 ))"
echo "=== LOG TAILS ==="
for f in logs/id29-trlen-L2_218675.out logs/id29-trlen-L3_218676.out; do
  [ -f "$f" ] && { echo "--- $f ---"; tail -n 8 "$f"; }
done
for f in logs/id29-trlen-L2_218675.err logs/id29-trlen-L3_218676.err; do
  [ -f "$f" ] && { s=$(wc -c < "$f"); echo "--- $f ($s bytes) ---"; [ "$s" -gt 0 ] && tail -n 12 "$f"; }
done
echo "=== DONE ==="
