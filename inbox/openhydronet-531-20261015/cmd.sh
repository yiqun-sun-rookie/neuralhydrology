#!/bin/bash
set -o pipefail
# read-only: timing facts from the smoke job log
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
F="$ROOT/logs/ohn_smoke-243024.out"
grep -aE "Device|device|cuda|NVIDIA|A800|torch " "$F" | head -5 | cut -c1-200
echo "--- epoch lines"
grep -aE "Epoch [0-9]+ average|Epoch [0-9]+ .*validation|number_of_basins|Setting up|Loading basin|samples|n_samples|len\(" "$F" | cut -c1-260 | head -12
echo "--- training progress bars (last chunks)"
tr '\r' '\n' < "$F" | grep -aE "^# Epoch" | tail -4 | cut -c1-200
echo "--- run dir size / checkpoints"
ls -d "$ROOT"/runs/smoke_* | head -3
du -sh "$ROOT"/runs/smoke_* | head -2
ls "$ROOT"/runs/smoke_*/ | head -20
echo "--- how many train samples / batches"
grep -aE "batch|Batch|iterations|updates" "$F" | head -6 | cut -c1-200
exit 0
