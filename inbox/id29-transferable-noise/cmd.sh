#!/bin/bash
# id29-transferable-noise seq=9: update the landing dir with payload v2 (src/docs only; results and
# pysite untouched), then submit the two training-length jobs. No compute on the login node.
set -o pipefail
ROOT=/data1/home/sunyiq/id29_transferable_noise_20260902
PAY=$HOME/hpc_mailbox/payload/id29-transferable-noise/id29_transferable_noise_20260902_v2.tar.gz
STAGE=$HOME/.id29_stage_v2

echo "=== PAYLOAD ==="
ls -la "$PAY" 2>&1 || { echo "PAYLOAD_MISSING"; exit 1; }
sha256sum "$PAY" 2>&1 || true

echo "=== EXTRACT TO STAGE ==="
rm -rf "$STAGE"; mkdir -p "$STAGE" || exit 1
tar -xzf "$PAY" -C "$STAGE" --strip-components=1 || { echo "EXTRACT_FAILED"; exit 1; }
cd "$STAGE" || exit 1
if sha256sum -c MANIFEST.sha256 --quiet > /dev/null 2>&1; then echo "STAGE_MANIFEST_OK ($(wc -l < MANIFEST.sha256) files)"; else echo "STAGE_MANIFEST_MISMATCH"; exit 1; fi

echo "=== UPDATE LANDING (src + docs only) ==="
[ -d "$ROOT" ] || { echo "LANDING_MISSING"; exit 1; }
cp -r "$STAGE/src/." "$ROOT/src/" || exit 1
cp -r "$STAGE/docs/." "$ROOT/docs/" || exit 1
cp -f "$STAGE/MANIFEST.sha256" "$ROOT/MANIFEST.sha256"
cd "$ROOT" || exit 1
sed -i 's/\r$//' src/camels_switch_confirmation/hpc/*.slurm 2>/dev/null || true
echo "untouched dirs:"; ls -d results pysite data 2>&1
echo "hpc scripts:"; ls src/camels_switch_confirmation/hpc/ 2>&1

echo "=== IMPORT CHECK ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
PYTHONPATH="$ROOT/src:$ROOT/pysite" CAMELS_SWITCH_RESULTS="$ROOT/results/23_camels_switch_confirmation" python -c "import camels_switch_confirmation.noise_axis_training_length as t; print('import OK; lengths', t.LENGTHS); print('windows', {k:t.window(v) for k,v in t.LENGTHS.items()})" || { echo "IMPORT_CHAIN_FAILED"; exit 1; }

echo "=== SUBMIT L2 ==="
out=$(sbatch "$ROOT/src/camels_switch_confirmation/hpc/id29_training_length_L2.slurm" 2>&1); echo "$out"
J1=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$J1" ] || { echo "SUBMIT_FAILED_L2"; exit 1; }

echo "=== SUBMIT L3 ==="
out=$(sbatch "$ROOT/src/camels_switch_confirmation/hpc/id29_training_length_L3.slurm" 2>&1); echo "$out"
J2=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$J2" ] || { echo "SUBMIT_FAILED_L3"; exit 1; }

echo "JOBS trlen_L2=$J1 trlen_L3=$J2"
echo "trlen_L2=$J1 trlen_L3=$J2" >> "$ROOT/logs/jobids.txt"
rm -rf "$STAGE"

echo "=== QUEUE (own jobs) ==="
squeue -u "$USER" -o "%.9i %.10P %.18j %.3t %.10M %.5C %.12R" 2>&1 | head -20 || true
echo "=== DONE ==="
