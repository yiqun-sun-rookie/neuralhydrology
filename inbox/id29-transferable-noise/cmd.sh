#!/bin/bash
# id29-transferable-noise seq=4: install the one missing pure-python package (cma) into a private
# pysite dir (nh_final untouched), patch PYTHONPATH in the two SLURM scripts, resubmit both jobs.
# Login node does: pip --target, import check, sed, sbatch. No compute.
set -o pipefail
ROOT=/data1/home/sunyiq/id29_transferable_noise_20260902
cd "$ROOT" || { echo "ROOT_MISSING"; exit 1; }
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }

echo "=== ENV BEFORE ==="
python -c "import sys; print('python', sys.version.split()[0], sys.executable)"
python -c "import numba; print('numba present', numba.__version__)" 2>/dev/null || echo "numba ABSENT (pure-python fallback will be used)"
python -c "import cma; print('cma present', cma.__version__)" 2>/dev/null || echo "cma ABSENT"

echo "=== PIP INSTALL cma -> pysite ==="
mkdir -p pysite
python -m pip install --no-input --no-deps --only-binary=:all: --timeout 120 --target "$ROOT/pysite" "cma==4.4.4" 2>&1 | tail -3
if ! PYTHONPATH="$ROOT/pysite" python -c "import cma; print('cma via pysite', cma.__version__)"; then
  echo "retry once"
  python -m pip install --no-input --no-deps --only-binary=:all: --timeout 180 --target "$ROOT/pysite" "cma==4.4.4" 2>&1 | tail -3
  PYTHONPATH="$ROOT/pysite" python -c "import cma; print('cma via pysite', cma.__version__)" || { echo "CMA_INSTALL_FAILED"; exit 1; }
fi

echo "=== IMPORT CHAIN CHECK (login node, import only) ==="
PYTHONPATH="$ROOT/src:$ROOT/pysite" CAMELS_SWITCH_RESULTS="$ROOT/results/23_camels_switch_confirmation" python -c "import camels_switch_confirmation.noise_axis_denormalized_transfer as a; import camels_switch_confirmation.noise_axis_391_confirmation as b; print('import chain OK')" || { echo "IMPORT_CHAIN_FAILED"; exit 1; }

echo "=== PATCH SLURM PYTHONPATH ==="
for f in src/camels_switch_confirmation/hpc/id29_denorm_control.slurm src/camels_switch_confirmation/hpc/id29_391_extra_cells.slurm; do
  sed -i 's#^export PYTHONPATH="\$ROOT/src:\${PYTHONPATH:-}"$#export PYTHONPATH="$ROOT/src:$ROOT/pysite:${PYTHONPATH:-}"#' "$f"
  grep -n '^export PYTHONPATH' "$f"
  sha256sum "$f"
done

echo "=== SUBMIT denorm ==="
out=$(sbatch "$ROOT/src/camels_switch_confirmation/hpc/id29_denorm_control.slurm" 2>&1); echo "$out"
J1=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$J1" ] || { echo "SUBMIT_FAILED_DENORM"; exit 1; }

echo "=== SUBMIT extra4 ==="
out=$(sbatch "$ROOT/src/camels_switch_confirmation/hpc/id29_391_extra_cells.slurm" 2>&1); echo "$out"
J2=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$J2" ] || { echo "SUBMIT_FAILED_EXTRA"; exit 1; }

echo "JOBS denorm=$J1 extra4=$J2"
echo "denorm=$J1 extra4=$J2 (resubmit after cma install into pysite; 218643/218644 failed at import)" >> "$ROOT/logs/jobids.txt"

echo "=== QUEUE (own jobs) ==="
squeue -u "$USER" -o "%.9i %.12P %.22j %.3t %.10M %.5C %.14R" 2>&1 | head -20 || true
echo "=== DONE ==="
