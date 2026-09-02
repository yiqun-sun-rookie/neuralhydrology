#!/bin/bash
# id29-transferable-noise seq=2: deploy the payload to the landing dir and submit two CPU jobs.
# Login node does only: extract, checksum, symlink, sbatch. No compute here.
set -o pipefail
ROOT=/data1/home/sunyiq/id29_transferable_noise_20260902
PAY=$HOME/hpc_mailbox/payload/id29-transferable-noise/id29_transferable_noise_20260902.tar.gz
DATA=/data1/home/sunyiq/neuralhydrology/data/camels_us

echo "=== PAYLOAD ==="
ls -la "$PAY" 2>&1 || { echo "PAYLOAD_MISSING"; exit 1; }
sha256sum "$PAY" 2>&1 || true

echo "=== DEPLOY ==="
if [ -e "$ROOT" ]; then echo "LANDING_EXISTS_REFUSING_TO_OVERWRITE"; exit 1; fi
mkdir -p "$ROOT" || exit 1
tar -xzf "$PAY" -C "$ROOT" --strip-components=1 || { echo "EXTRACT_FAILED"; exit 1; }
cd "$ROOT" || exit 1
mkdir -p logs data
[ -d "$DATA/basin_mean_forcing/maurer" ] || { echo "DATA_SOURCE_MISSING $DATA"; exit 1; }
ln -s "$DATA" data/camels_us || { echo "SYMLINK_FAILED"; exit 1; }
sed -i 's/\r$//' src/camels_switch_confirmation/hpc/*.slurm 2>/dev/null || true

echo "=== MANIFEST CHECK ==="
if sha256sum -c MANIFEST.sha256 --quiet > logs/manifest_check.txt 2>&1; then
  echo "MANIFEST_OK ($(wc -l < MANIFEST.sha256) files)"
else
  echo "MANIFEST_MISMATCH"; head -5 logs/manifest_check.txt; exit 1
fi

echo "=== LAYOUT ==="
ls src/camels_switch_confirmation/hpc/ 2>&1
ls -la data/ 2>&1 | tail -2
ls data/camels_us/basin_mean_forcing/maurer 2>&1 | head -3
ls src/camels_switch_confirmation/protocols/ 2>&1

echo "=== SUBMIT denorm ==="
out=$(sbatch "$ROOT/src/camels_switch_confirmation/hpc/id29_denorm_control.slurm" 2>&1); echo "$out"
J1=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$J1" ] || { echo "SUBMIT_FAILED_DENORM"; exit 1; }

echo "=== SUBMIT extra4 ==="
out=$(sbatch "$ROOT/src/camels_switch_confirmation/hpc/id29_391_extra_cells.slurm" 2>&1); echo "$out"
J2=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$J2" ] || { echo "SUBMIT_FAILED_EXTRA"; exit 1; }

echo "JOBS denorm=$J1 extra4=$J2"
echo "denorm=$J1 extra4=$J2" > "$ROOT/logs/jobids.txt"

echo "=== QUEUE (own jobs) ==="
squeue -u "$USER" -o "%.9i %.12P %.22j %.3t %.10M %.5C %.14R" 2>&1 | head -20 || true
echo "=== DONE ==="
