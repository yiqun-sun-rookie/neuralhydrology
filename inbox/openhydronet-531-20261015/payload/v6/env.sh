# Shared OpenHydroNet (Google flood-forecasting, googlehydrology 1.13.0, commit 011265446e11) on the HHU HPC.
# Read-only install. Use:  source /data1/home/sunyiq/openhydronet_shared/env.sh   then   ohn train --config-file X.yml   /   ohn infer --run-dir DIR
# Runs on conda env nh_final (Python 3.11, torch 2.4.0); the missing packages live in ./pysite, itertools.batched is patched by pysite/sitecustomize.py.
# Put configs, data, run directories and logs in YOUR OWN directory, never in this one. Configs need `compile: False`.
OHN_SHARED=/data1/home/sunyiq/openhydronet_shared
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "ohn env.sh: conda activate nh_final failed"; return 1 2>/dev/null || exit 1; }
export PYTHONPATH="$OHN_SHARED/pysite:$OHN_SHARED/flood-forecasting${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONDONTWRITEBYTECODE=1
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
ohn() {
  python -u -c 'import sys; sys.argv[0] = "ohn"; from googlehydrology.run import _main; _main()' "$@"
}
