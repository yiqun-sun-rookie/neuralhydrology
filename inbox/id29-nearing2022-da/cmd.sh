#!/bin/bash
# ID29 seq=143: read-only preflight for an isolated author-v1.3 evaluation of the confirmed TE100 discrepancy.
set -euo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
ARCHIVE="$ROOT/results/29_nearing2022_da_ar/formal_closure/author_source_archives/zenodo-7063259-grey-nearing-neuralhydrology-public-v.1.3.0.zip"
SOURCE_RUN="$ROOT/results/29_nearing2022_da_ar/nearing2022_autoregression_lead1_holdout0.0_seed0_2026_0808_1648_ep30"
CURRENT_EVAL="$ROOT/closure_20260810/evaluations/time_split/autoregression/N22-EVAL-TS-AR-L01-TR000-TE100-S0"

test -f "$ARCHIVE"
test -f "$SOURCE_RUN/config.yml"
test -f "$SOURCE_RUN/model_epoch030.pt"
test -f "$SOURCE_RUN/train_data/train_data_scaler.yml"
test -f "$CURRENT_EVAL/config.yml"
test -f "$CURRENT_EVAL/model_epoch030.pt"
test -f "$CURRENT_EVAL/test/model_epoch030/test_results.p"

echo "=== CONDA ENVIRONMENTS ==="
source ~/miniconda3/etc/profile.d/conda.sh
conda env list

echo "=== AUTHOR V1.3 EVALUATION SOURCE PREFLIGHT ==="
python - <<'PY'
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import zipfile

archive = Path(
    '/data1/home/sunyiq/nearing2022_da/results/29_nearing2022_da_ar/formal_closure/'
    'author_source_archives/zenodo-7063259-grey-nearing-neuralhydrology-public-v.1.3.0.zip'
)
root = 'grey-nearing-neuralhydrology-public-a4c284b/'

with zipfile.ZipFile(archive) as handle:
    names = set(handle.namelist())
    relevant = sorted(
        name
        for name in names
        if name.startswith(root + 'neuralhydrology/')
        and any(token in name.lower() for token in ('evaluation', 'tester', 'nh_run.py', 'config.py'))
        and name.endswith('.py')
    )
    print(json.dumps({'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
                      'relevant_members': relevant}, sort_keys=True))

    requested = [
        root + 'neuralhydrology/nh_run.py',
        root + 'neuralhydrology/evaluation/__init__.py',
        root + 'neuralhydrology/evaluation/tester.py',
        root + 'neuralhydrology/evaluation/basetester.py',
        root + 'neuralhydrology/evaluation/regressiontester.py',
        root + 'neuralhydrology/utils/config.py',
    ]
    patterns = re.compile(
        r'evaluate|run_dir|run-dir|period|epoch|gpu|Tester|test_results|save|metrics|test_basin_file|'
        r'random_holdout|lagged_features|autoregressive_inputs|clip_targets|num_workers|device',
        flags=re.IGNORECASE,
    )
    for member in requested:
        print(f'--- MEMBER {member} present={member in names} ---')
        if member not in names:
            continue
        data = handle.read(member)
        print(f'bytes={len(data)} sha256={hashlib.sha256(data).hexdigest()}')
        text = data.decode('utf-8')
        for number, line in enumerate(text.splitlines(), start=1):
            if patterns.search(line):
                print(f'{number}:{line[:300]}')
PY

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
