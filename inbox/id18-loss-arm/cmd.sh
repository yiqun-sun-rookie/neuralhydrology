#!/bin/bash
# ID18 seq=5: deploy and validate E04 in a new isolated directory. No sbatch.
set -eo pipefail

TARGET=/data1/home/sunyiq/id18_e04_20260809
STAGING=/data1/home/sunyiq/id18_e04_20260809.deploying_seq5
BASE=/data1/home/sunyiq/neuralhydrology
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/inbox/id18-loss-arm/payload_e04_20260809_v2.tar.gz
EXPECTED=509de349ce6bcb3479bb5872b1a0063fc3b6df472bc9a6b860f86cc3a8cd19bb
ORIGINAL_PYTHONPATH="${PYTHONPATH:-}"

echo "=== PRECONDITIONS ==="
date -Is
test ! -e "$TARGET" || { echo "REFUSE_EXISTING_TARGET=$TARGET"; exit 3; }
test ! -e "$STAGING" || { echo "REFUSE_EXISTING_STAGING=$STAGING"; exit 3; }
test -f "$PAYLOAD"
ACTUAL=$(sha256sum "$PAYLOAD" | awk '{print $1}')
echo "payload_sha256=$ACTUAL"
test "$ACTUAL" = "$EXPECTED"

echo "=== EXTRACT_NEW_TARGET ==="
mkdir "$STAGING"
tar -xzf "$PAYLOAD" -C "$STAGING"
mkdir -p "$STAGING/logs"
find "$STAGING/src/loss_mechanism_531/hpc" -type f -name 'e04_*.slurm' -exec sed -i 's/\r$//' {} +
find "$STAGING/src/loss_mechanism_531/hpc" -type f -name 'e04_*.slurm' -exec bash -n {} \;

echo "=== ISOLATED_IMPORTS ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONPATH="$STAGING:$BASE:$ORIGINAL_PYTHONPATH"
cd "$STAGING"
python - <<'PY'
import json
import pathlib

import cma
import numpy
import pandas
import torch
import xarray

root = pathlib.Path('/data1/home/sunyiq/id18_e04_20260809.deploying_seq5').resolve()
loaded = pathlib.Path(cma.__file__).resolve()
assert root in loaded.parents, loaded
assert cma.__version__ == '4.4.4'
print(json.dumps({
    'cma_version': cma.__version__,
    'cma_file': str(loaded),
    'numpy_version': numpy.__version__,
    'pandas_version': pandas.__version__,
    'torch_version': torch.__version__,
    'xarray_version': xarray.__version__,
}))
PY

cd /data1/home/sunyiq
mv "$STAGING" "$TARGET"
export PYTHONPATH="$TARGET:$BASE:$ORIGINAL_PYTHONPATH"
cd "$TARGET"

echo "=== MATERIALIZE_PROTOCOL ==="
python -u -m src.loss_mechanism_531.prepare_e04_confirmation \
    --data-root "$BASE/data/camels_us" \
    --result-root "$TARGET/results/18_lstm_fair_531/E04_daymet_post2008_objective_confirmation_482" \
    --run-root "$TARGET/runs/e04_daymet_confirmation_482"

python - <<'PY'
import hashlib
import json
import pathlib

root = pathlib.Path('/data1/home/sunyiq/id18_e04_20260809')
record = {
    'experiment_id': 'E04_daymet_post2008_objective_confirmation_482',
    'isolated_root': str(root),
    'base_repository_usage': 'read_only_data_only',
    'shared_conda_environment_modified': False,
    'payload_sha256': '509de349ce6bcb3479bb5872b1a0063fc3b6df472bc9a6b860f86cc3a8cd19bb',
    'vendored_cma_version': '4.4.4',
    'vendored_cma_license': 'BSD-3-Clause',
}
path = root / 'results/18_lstm_fair_531/E04_daymet_post2008_objective_confirmation_482/protocol/deployment.json'
with path.open('x', encoding='utf-8') as handle:
    json.dump(record, handle, indent=2)
    handle.write('\n')
print('deployment_sha256=' + hashlib.sha256(path.read_bytes()).hexdigest())
PY

echo "=== DEPLOYED_FILES ==="
find "$TARGET/results/18_lstm_fair_531/E04_daymet_post2008_objective_confirmation_482/protocol" -maxdepth 2 -type f -print | sort
echo "E04_ISOLATED_DEPLOYMENT_PASS"
