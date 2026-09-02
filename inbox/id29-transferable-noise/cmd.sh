#!/bin/bash
# id29-transferable-noise seq=6: bounded wait (<= 9 min) for 218649/218650 to leave the queue, then emit result files.
set -o pipefail
J1=218649; J2=218650
echo "=== WAIT (max 9 min) ==="
for i in $(seq 1 54); do
  LEFT=$(squeue -u "$USER" -h -o "%i" -j $J1,$J2 2>/dev/null | wc -l)
  if [ $((i % 6)) -eq 0 ]; then echo "t=$((i*10))s left=$LEFT $(squeue -u "$USER" -h -o "%i:%t:%M" -j $J1,$J2 2>/dev/null | tr "\n" " ")"; fi
  [ "$LEFT" -eq 0 ] && break
  sleep 10
done
set -o pipefail
ROOT=/data1/home/sunyiq/id29_transferable_noise_20260902
R23=results/23_camels_switch_confirmation
J1=218649
J2=218650
cd "$ROOT" || { echo "ROOT_MISSING"; exit 1; }

echo "=== SACCT ==="
sacct -j $J1,$J2 -X --format=JobID%10,JobName%14,NodeList%9,State%12,ExitCode%8,Elapsed%10,AllocCPUS%6,MaxRSS%10 2>&1 || true

emit() {  # emit <relpath>
  if [ -f "$1" ]; then
    echo "=== FILE $1 ==="; cat "$1"; echo; echo "=== END FILE ==="
  else
    echo "=== MISSING $1 ==="
  fi
}

echo "=== FILES denorm ==="
emit "$R23/noise_axis_denormalized_transfer_control_20260902_hpc/p0_report.json"
emit "$R23/noise_axis_denormalized_transfer_control_20260902_hpc/summary.json"
emit "$R23/noise_axis_denormalized_transfer_control_20260902_hpc/receivers_per_basin.csv"
emit "$R23/noise_axis_denormalized_transfer_control_20260902_hpc/absolute_matrix_nse_holdout.csv"
echo "receiver json count: $(ls "$R23/noise_axis_denormalized_transfer_control_20260902_hpc/receivers/" 2>/dev/null | wc -l)"

echo "=== FILES extra4 ==="
emit "$R23/noise_axis_391_global_card_confirmation_20260901_local/extra_cells_summary.json"
emit "$R23/noise_axis_391_global_card_confirmation_20260901_local/extra_cells_per_basin.csv"
echo "extra json count: $(ls "$R23/noise_axis_391_global_card_confirmation_20260901_local/extra_cells/" 2>/dev/null | wc -l)"

echo "=== LOG TAILS ==="
for f in logs/id29-denorm_${J1}.out logs/id29-extra4_${J2}.out; do
  [ -f "$f" ] && { echo "--- $f ---"; tail -n 40 "$f"; }
done
for f in logs/id29-denorm_${J1}.err logs/id29-extra4_${J2}.err; do
  [ -f "$f" ] && { s=$(wc -c < "$f"); echo "--- $f ($s bytes) ---"; [ "$s" -gt 0 ] && tail -n 20 "$f"; }
done
echo "=== SHA256 of emitted files ==="
sha256sum "$R23"/noise_axis_denormalized_transfer_control_20260902_hpc/*.json "$R23"/noise_axis_denormalized_transfer_control_20260902_hpc/*.csv "$R23"/noise_axis_391_global_card_confirmation_20260901_local/extra_cells_*.json "$R23"/noise_axis_391_global_card_confirmation_20260901_local/extra_cells_*.csv 2>&1 || true
echo "=== DONE ==="
