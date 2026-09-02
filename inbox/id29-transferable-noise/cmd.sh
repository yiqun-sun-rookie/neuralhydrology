#!/bin/bash
# id29-transferable-noise seq=7: bounded wait (<= 6 min) for 218650, then emit the extra-cells result files.
set -o pipefail
ROOT=/data1/home/sunyiq/id29_transferable_noise_20260902
R23=results/23_camels_switch_confirmation
J2=218650
cd "$ROOT" || { echo "ROOT_MISSING"; exit 1; }
echo "=== WAIT (max 6 min) ==="
for i in $(seq 1 36); do
  LEFT=$(squeue -u "$USER" -h -o "%i" -j $J2 2>/dev/null | wc -l)
  if [ $((i % 6)) -eq 0 ]; then echo "t=$((i*10))s left=$LEFT $(squeue -u "$USER" -h -o "%i:%t:%M" -j $J2 2>/dev/null | tr "\n" " ")"; fi
  [ "$LEFT" -eq 0 ] && break
  sleep 10
done
echo "=== SACCT ==="
sacct -j $J2 -X --format=JobID%10,JobName%14,NodeList%9,State%12,ExitCode%8,Elapsed%10,AllocCPUS%6,MaxRSS%10 2>&1 || true
emit() { if [ -f "$1" ]; then echo "=== FILE $1 ==="; cat "$1"; echo; echo "=== END FILE ==="; else echo "=== MISSING $1 ==="; fi; }
echo "=== FILES extra4 ==="
emit "$R23/noise_axis_391_global_card_confirmation_20260901_local/extra_cells_summary.json"
emit "$R23/noise_axis_391_global_card_confirmation_20260901_local/extra_cells_per_basin.csv"
echo "extra json count: $(ls "$R23/noise_axis_391_global_card_confirmation_20260901_local/extra_cells/" 2>/dev/null | wc -l)"
echo "=== LOG TAIL ==="
tail -n 12 "logs/id29-extra4_${J2}.out" 2>&1 || true
s=$(wc -c < "logs/id29-extra4_${J2}.err" 2>/dev/null || echo 0); echo "err bytes: $s"; [ "$s" -gt 0 ] && tail -n 20 "logs/id29-extra4_${J2}.err"
echo "=== SHA256 ==="
sha256sum "$R23"/noise_axis_391_global_card_confirmation_20260901_local/extra_cells_summary.json "$R23"/noise_axis_391_global_card_confirmation_20260901_local/extra_cells_per_basin.csv 2>&1 || true
echo "=== DONE ==="
