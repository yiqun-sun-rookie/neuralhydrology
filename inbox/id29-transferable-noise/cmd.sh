#!/bin/bash
# id29-transferable-noise seq=15: retrieve the training-length P0 receipt (p0_report.json) byte-exactly.
# Read-only on the cluster: find + sha256sum + base64. No compute, no sbatch, nothing written to the landing dir.
set -o pipefail
ROOT=/data1/home/sunyiq/id29_transferable_noise_20260902
D=$ROOT/results/23_camels_switch_confirmation/noise_axis_training_length_20260902_hpc
cd "$ROOT" || { echo "ROOT_MISSING"; exit 1; }

echo "=== LOCATE ==="
find "$D" -maxdepth 3 -name 'p0_report*.json' -printf '%p\t%s bytes\t%TY-%Tm-%Td %TH:%TM\n' 2>&1

echo "=== DIR LISTING (top level) ==="
ls -la "$D" 2>&1 | head -30

echo "=== SHA256 ==="
find "$D" -maxdepth 3 -name 'p0_report*.json' -exec sha256sum {} \; 2>&1

for f in $(find "$D" -maxdepth 3 -name 'p0_report*.json' 2>/dev/null | sort); do
  echo "=== B64 $f ==="
  base64 -w0 "$f"; echo
  echo "=== END B64 ==="
done

echo "=== CROSS-CHECK: denorm p0 (already retrieved locally) ==="
sha256sum "$ROOT/results/23_camels_switch_confirmation/noise_axis_denormalized_transfer_control_20260902_hpc/p0_report.json" 2>&1
