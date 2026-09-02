#!/bin/bash
# id29-transferable-noise seq=8: emit the six per-basin extra-cell JSONs whose m10_c0 arm failed (tiny files). No compute.
set -o pipefail
ROOT=/data1/home/sunyiq/id29_transferable_noise_20260902
D=results/23_camels_switch_confirmation/noise_axis_391_global_card_confirmation_20260901_local/extra_cells
cd "$ROOT" || { echo "ROOT_MISSING"; exit 1; }
emit() { if [ -f "$1" ]; then echo "=== FILE $1 ==="; cat "$1"; echo; echo "=== END FILE ==="; else echo "=== MISSING $1 ==="; fi; }
for b in 02297155 05489000 06889200 06910800 08066200 08164600; do emit "$D/$b.json"; done
echo "json count: $(ls "$D" | wc -l)"
echo "failed-arm count across all JSONs: $(grep -l '"status": "failed"' "$D"/*.json 2>/dev/null | wc -l)"
echo "=== DONE ==="
