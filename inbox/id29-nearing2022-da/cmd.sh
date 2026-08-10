#!/bin/bash
# ID29 seq=144: repair seq 143's nounset/Conda activation conflict and finish the read-only compatibility preflight.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
ARCHIVE="$ROOT/results/29_nearing2022_da_ar/formal_closure/author_source_archives/zenodo-7063259-grey-nearing-neuralhydrology-public-v.1.3.0.zip"
SOURCE_RUN="$ROOT/results/29_nearing2022_da_ar/nearing2022_autoregression_lead1_holdout0.0_seed0_2026_0808_1648_ep30"
CURRENT_EVAL="$ROOT/closure_20260810/evaluations/time_split/autoregression/N22-EVAL-TS-AR-L01-TR000-TE100-S0"
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

test -f "$ARCHIVE"
test -f "$SOURCE_RUN/config.yml"
test -f "$SOURCE_RUN/model_epoch030.pt"
test -f "$SOURCE_RUN/train_data/train_data_scaler.yml"
test -f "$CURRENT_EVAL/config.yml"
test -f "$CURRENT_EVAL/model_epoch030.pt"
test -f "$CURRENT_EVAL/test/model_epoch030/test_results.p"

source ~/miniconda3/etc/profile.d/conda.sh

echo "=== ENVIRONMENT VERSION PROBES ==="
cat > "$TEMP_ROOT/probe_versions.py" <<'PY'
import importlib
import json
import platform
import sys

packages = ['torch', 'numpy', 'pandas', 'scipy', 'xarray', 'neuralhydrology']
versions = {}
for name in packages:
    try:
        module = importlib.import_module(name)
        versions[name] = getattr(module, '__version__', 'no___version__')
    except Exception as exc:
        versions[name] = f'{type(exc).__name__}: {exc}'
print(json.dumps({'python': sys.version.replace('\n', ' '), 'platform': platform.platform(), 'packages': versions},
                 sort_keys=True))
PY

for environment in neuralhydrology nh_clean nh_final knet_clean; do
  echo "--- environment=$environment ---"
  set +e
  conda run --no-capture-output -n "$environment" python "$TEMP_ROOT/probe_versions.py"
  status=$?
  set -e
  echo "probe_exit_code=$status"
done

echo "=== EXTRACT AUTHOR V1.3 SOURCE TO EPHEMERAL DIRECTORY ==="
python - "$ARCHIVE" "$TEMP_ROOT" <<'PY'
from pathlib import Path
import sys
import zipfile

archive = Path(sys.argv[1])
target = Path(sys.argv[2])
with zipfile.ZipFile(archive) as handle:
    handle.extractall(target)
print(target / 'grey-nearing-neuralhydrology-public-a4c284b')
PY
AUTHOR_SRC="$TEMP_ROOT/grey-nearing-neuralhydrology-public-a4c284b"
test -f "$AUTHOR_SRC/neuralhydrology/nh_run.py"

echo "=== AUTHOR CLI IMPORT PROBES ==="
for environment in neuralhydrology nh_clean nh_final; do
  echo "--- environment=$environment ---"
  set +e
  PYTHONPATH="$AUTHOR_SRC" conda run --no-capture-output -n "$environment" \
    python -m neuralhydrology.nh_run --help 2>&1 | head -80
  status=${PIPESTATUS[0]}
  set -e
  echo "author_cli_exit_code=$status"
done

echo "=== CURRENT CHECKPOINT AND RESULT FORMAT ==="
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python - <<'PY'
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import pickle

import torch
import yaml

root = Path('/data1/home/sunyiq/nearing2022_da')
source = root / 'results/29_nearing2022_da_ar/nearing2022_autoregression_lead1_holdout0.0_seed0_2026_0808_1648_ep30'
evaluation = root / 'closure_20260810/evaluations/time_split/autoregression/N22-EVAL-TS-AR-L01-TR000-TE100-S0'

def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

source_config = yaml.safe_load((source / 'config.yml').read_text(encoding='utf-8'))
evaluation_config = yaml.safe_load((evaluation / 'config.yml').read_text(encoding='utf-8'))
state = torch.load(source / 'model_epoch030.pt', map_location='cpu')
state_dict = state.get('model_state_dict', state) if isinstance(state, dict) else state
result_path = evaluation / 'test/model_epoch030/test_results.p'
with result_path.open('rb') as handle:
    results = pickle.load(handle)
first_basin = sorted(results)[0]
first = results[first_basin]
payload = {
    'source_config_sha256': digest(source / 'config.yml'),
    'evaluation_config_sha256': digest(evaluation / 'config.yml'),
    'source_checkpoint_sha256': digest(source / 'model_epoch030.pt'),
    'evaluation_checkpoint_sha256': digest(evaluation / 'model_epoch030.pt'),
    'checkpoint_identical': digest(source / 'model_epoch030.pt') == digest(evaluation / 'model_epoch030.pt'),
    'checkpoint_top_type': type(state).__name__,
    'checkpoint_top_keys': sorted(state) if isinstance(state, dict) else None,
    'state_dict_keys': sorted(state_dict),
    'source_config_keys': sorted(source_config),
    'evaluation_config_keys': sorted(evaluation_config),
    'evaluation_holdout': evaluation_config['random_holdout_from_dynamic_features'],
    'result_sha256': digest(result_path),
    'result_top_type': type(results).__name__,
    'result_basin_count': len(results),
    'first_basin': first_basin,
    'first_basin_type': type(first).__name__,
    'first_basin_keys': sorted(first) if isinstance(first, dict) else None,
}
if isinstance(first, dict):
    payload['first_basin_value_types'] = {key: type(value).__name__ for key, value in first.items()}
    payload['first_basin_value_shapes'] = {
        key: list(value.shape) if hasattr(value, 'shape') else None for key, value in first.items()
    }
print(json.dumps(payload, sort_keys=True, default=str))
PY

echo "=== REGISTERED ARTIFACT SAFETY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
