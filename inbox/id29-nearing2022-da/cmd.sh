#!/bin/bash
# ID29 seq=145: submit an isolated five-basin author-v1.3 evaluation with the confirmed TE100 checkpoint.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
SCRIPT="$DIAGNOSTIC_ROOT/author_v13_same_checkpoint_te100_first5.slurm"
FINAL="$DIAGNOSTIC_ROOT/author_v13_same_checkpoint_te100_first5"
LOG_ROOT="$ROOT/closure_20260810/logs"

test ! -e "$SCRIPT"
test ! -e "$FINAL"
mkdir -p "$DIAGNOSTIC_ROOT" "$LOG_ROOT"
TEMP_SCRIPT="$SCRIPT.preparing-$$"
test ! -e "$TEMP_SCRIPT"

cat > "$TEMP_SCRIPT" <<'SLURM'
#!/bin/bash
#SBATCH --job-name=N22-author-v13-eval
#SBATCH --partition=hgpu4,hgpu8,hgpu2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH --time=01:00:00
#SBATCH --output=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs/%x_%j.out
#SBATCH --error=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs/%x_%j.err

set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
ARCHIVE="$ROOT/results/29_nearing2022_da_ar/formal_closure/author_source_archives/zenodo-7063259-grey-nearing-neuralhydrology-public-v.1.3.0.zip"
SOURCE_RUN="$ROOT/results/29_nearing2022_da_ar/nearing2022_autoregression_lead1_holdout0.0_seed0_2026_0808_1648_ep30"
CURRENT_EVAL="$ROOT/closure_20260810/evaluations/time_split/autoregression/N22-EVAL-TS-AR-L01-TR000-TE100-S0"
FROZEN_BASINS="$ROOT/src/29_nearing2022_da_ar/basin_lists/531_basin_list.txt"
FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/author_v13_same_checkpoint_te100_first5"
WORK="$FINAL.preparing-$SLURM_JOB_ID"
SOURCE_TEMP=$(mktemp -d)
trap 'rm -rf -- "$SOURCE_TEMP"' EXIT

test -f "$ARCHIVE"
test -f "$SOURCE_RUN/config.yml"
test -f "$SOURCE_RUN/model_epoch030.pt"
test -d "$SOURCE_RUN/train_data"
test -f "$CURRENT_EVAL/test/model_epoch030/test_results.p"
test -f "$FROZEN_BASINS"
test ! -e "$FINAL"
test ! -e "$WORK"
mkdir -p "$WORK"

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-4}"

python - "$ARCHIVE" "$SOURCE_TEMP" <<'PY'
from pathlib import Path
import sys
import zipfile

archive = Path(sys.argv[1])
target = Path(sys.argv[2])
with zipfile.ZipFile(archive) as handle:
    handle.extractall(target)
PY
AUTHOR_SOURCE="$SOURCE_TEMP/grey-nearing-neuralhydrology-public-a4c284b"
test -f "$AUTHOR_SOURCE/neuralhydrology/nh_run.py"

cp "$SOURCE_RUN/model_epoch030.pt" "$WORK/model_epoch030.pt"
cp -a "$SOURCE_RUN/train_data" "$WORK/train_data"

python - "$SOURCE_RUN/config.yml" "$WORK/config.yml" "$FROZEN_BASINS" "$WORK/first5_basins.txt" "$WORK" <<'PY'
from pathlib import Path
import sys

import yaml

source_config = Path(sys.argv[1])
target_config = Path(sys.argv[2])
frozen_basin_file = Path(sys.argv[3])
target_basin_file = Path(sys.argv[4])
run_dir = Path(sys.argv[5])

basins = [line.strip() for line in frozen_basin_file.read_text(encoding='utf-8').splitlines() if line.strip()]
selected = basins[:5]
if len(selected) != 5 or len(set(selected)) != 5:
    raise ValueError(f'Expected five unique frozen basins, found {selected}')
target_basin_file.write_text('\n'.join(selected) + '\n', encoding='utf-8', newline='\n')

config = yaml.safe_load(source_config.read_text(encoding='utf-8'))
config['experiment_name'] = 'author_v13_same_checkpoint_te100_first5'
config['run_dir'] = str(run_dir)
config['test_basin_file'] = str(target_basin_file)
config['random_holdout_from_dynamic_features']['QObs(mm/d)_shift1']['missing_fraction'] = 1.0
config['metrics'] = []
config['num_workers'] = 0
config['device'] = 'cuda:0'
config['log_n_figures'] = 0
with target_config.open('w', encoding='utf-8', newline='\n') as handle:
    yaml.safe_dump(config, handle, sort_keys=False, allow_unicode=True, width=120)
PY

cat > "$SOURCE_TEMP/run_author_cli.py" <<'PY'
"""Compatibility launcher that restores one removed Matplotlib type-annotation namespace without editing author code."""
import runpy
import types

import matplotlib as mpl

if not hasattr(mpl.axes, '_subplots'):
    mpl.axes._subplots = types.SimpleNamespace(Axes=mpl.axes.Axes)
runpy.run_module('neuralhydrology.nh_run', run_name='__main__')
PY

echo "started=$(date --iso-8601=seconds)"
echo "diagnostic_scope=author v1.3 evaluation source under the current nh_final runtime"
echo "compatibility_shim=restore matplotlib.axes._subplots.Axes for eager type-annotation evaluation only"
sha256sum "$ARCHIVE" "$SOURCE_RUN/model_epoch030.pt" "$WORK/model_epoch030.pt" \
  "$SOURCE_RUN/train_data/train_data_scaler.yml" "$WORK/train_data/train_data_scaler.yml" \
  "$WORK/config.yml" "$WORK/first5_basins.txt" \
  "$AUTHOR_SOURCE/neuralhydrology/nh_run.py" "$AUTHOR_SOURCE/neuralhydrology/evaluation/tester.py" \
  "$AUTHOR_SOURCE/neuralhydrology/modelzoo/arlstm.py" "$SOURCE_TEMP/run_author_cli.py"
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader

cd "$SOURCE_TEMP"
PYTHONPATH="$AUTHOR_SOURCE" python - "$AUTHOR_SOURCE" <<'PY'
import json
from pathlib import Path
import sys

source = Path(sys.argv[1])
import neuralhydrology
print(json.dumps({'imported_neuralhydrology': str(Path(neuralhydrology.__file__).resolve()),
                  'expected_source': str(source.resolve())}, sort_keys=True))
if source.resolve() not in Path(neuralhydrology.__file__).resolve().parents:
    raise RuntimeError('Author source did not shadow the installed package')
PY

cd "$ROOT"
PYTHONPATH="$AUTHOR_SOURCE" python "$SOURCE_TEMP/run_author_cli.py" evaluate \
  --run-dir "$WORK" --period test --epoch 30 --gpu 0

AUTHOR_RESULT="$WORK/test/model_epoch030/test_results.p"
test -f "$AUTHOR_RESULT"

python - "$ARCHIVE" "$SOURCE_RUN" "$CURRENT_EVAL" "$WORK" "$AUTHOR_RESULT" "$AUTHOR_SOURCE" <<'PY'
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import pickle
import sys

import numpy as np
import torch

archive = Path(sys.argv[1])
source_run = Path(sys.argv[2])
current_eval = Path(sys.argv[3])
work = Path(sys.argv[4])
author_result_path = Path(sys.argv[5])
author_source = Path(sys.argv[6])
current_result_path = current_eval / 'test/model_epoch030/test_results.p'

def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def array_digest(values: np.ndarray) -> str:
    contiguous = np.ascontiguousarray(values)
    return hashlib.sha256(contiguous.tobytes()).hexdigest()

def standalone_nse(obs: np.ndarray, sim: np.ndarray) -> float:
    finite = np.isfinite(obs) & np.isfinite(sim)
    obs = obs[finite].astype(np.float64)
    sim = sim[finite].astype(np.float64)
    denominator = np.sum((obs - np.mean(obs)) ** 2)
    return float(1.0 - np.sum((sim - obs) ** 2) / denominator)

with author_result_path.open('rb') as handle:
    author = pickle.load(handle)
with current_result_path.open('rb') as handle:
    current = pickle.load(handle)

basins = [line.strip() for line in (work / 'first5_basins.txt').read_text(encoding='utf-8').splitlines()
          if line.strip()]
comparisons = []
for basin in basins:
    old_ds = author[basin]['1D']['xr']
    new_ds = current[basin]['1D']['xr']
    old_dates = np.asarray(old_ds['date'].values)
    new_dates = np.asarray(new_ds['date'].values)
    if not np.array_equal(old_dates, new_dates):
        raise ValueError(f'Date mismatch for basin {basin}')
    old_obs = np.asarray(old_ds['QObs(mm/d)_obs'].values).reshape(-1)
    new_obs = np.asarray(new_ds['QObs(mm/d)_obs'].values).reshape(-1)
    old_sim = np.asarray(old_ds['QObs(mm/d)_sim'].values).reshape(-1)
    new_sim = np.asarray(new_ds['QObs(mm/d)_sim'].values).reshape(-1)
    finite_sim = np.isfinite(old_sim) & np.isfinite(new_sim)
    finite_obs = np.isfinite(old_obs) & np.isfinite(new_obs)
    sim_difference = old_sim[finite_sim].astype(np.float64) - new_sim[finite_sim].astype(np.float64)
    obs_difference = old_obs[finite_obs].astype(np.float64) - new_obs[finite_obs].astype(np.float64)
    comparisons.append({
        'basin': basin,
        'dates': int(old_dates.size),
        'common_finite_predictions': int(finite_sim.sum()),
        'prediction_bitwise_identical_equal_nan': bool(np.array_equal(old_sim, new_sim, equal_nan=True)),
        'prediction_max_absolute_difference': float(np.max(np.abs(sim_difference))),
        'prediction_mean_absolute_difference': float(np.mean(np.abs(sim_difference))),
        'author_prediction_sha256': array_digest(old_sim),
        'current_prediction_sha256': array_digest(new_sim),
        'observation_bitwise_identical_equal_nan': bool(np.array_equal(old_obs, new_obs, equal_nan=True)),
        'observation_max_absolute_difference': float(np.max(np.abs(obs_difference))),
        'author_nse': standalone_nse(old_obs, old_sim),
        'current_nse': standalone_nse(new_obs, new_sim),
    })

payload = {
    'schema': 'nearing2022-author-v13-same-checkpoint-evaluation-v1',
    'scientific_scope': 'diagnostic only; not a registered matrix coordinate and not used to select a model',
    'author_source_release': 'Zenodo neuralhydrology-public v1.3.0 root a4c284b',
    'runtime_scope': 'author source evaluated under the same nh_final runtime used by the current reproduction',
    'compatibility_shim': 'restored matplotlib.axes._subplots.Axes for eager type-annotation evaluation only; no author source file changed',
    'archive_sha256': digest(archive),
    'author_source_file_sha256': {
        'nh_run.py': digest(author_source / 'neuralhydrology/nh_run.py'),
        'evaluation/tester.py': digest(author_source / 'neuralhydrology/evaluation/tester.py'),
        'modelzoo/arlstm.py': digest(author_source / 'neuralhydrology/modelzoo/arlstm.py'),
    },
    'checkpoint_sha256': digest(work / 'model_epoch030.pt'),
    'checkpoint_identical_to_registered_source': digest(work / 'model_epoch030.pt') == digest(source_run / 'model_epoch030.pt'),
    'scaler_sha256': digest(work / 'train_data/train_data_scaler.yml'),
    'scaler_identical_to_registered_source': (
        digest(work / 'train_data/train_data_scaler.yml') == digest(source_run / 'train_data/train_data_scaler.yml')
    ),
    'diagnostic_config_sha256': digest(work / 'config.yml'),
    'basin_file_sha256': digest(work / 'first5_basins.txt'),
    'basins': basins,
    'author_result_sha256': digest(author_result_path),
    'current_result_sha256': digest(current_result_path),
    'torch_version': torch.__version__,
    'comparisons': comparisons,
    'all_prediction_arrays_bitwise_identical': all(row['prediction_bitwise_identical_equal_nan'] for row in comparisons),
    'maximum_prediction_absolute_difference': max(row['prediction_max_absolute_difference'] for row in comparisons),
    'all_observation_arrays_bitwise_identical': all(row['observation_bitwise_identical_equal_nan'] for row in comparisons),
    'maximum_nse_absolute_difference': max(abs(row['author_nse'] - row['current_nse']) for row in comparisons),
}
(work / 'diagnostic_receipt.json').write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n',
                                               encoding='utf-8', newline='\n')
print(json.dumps(payload, sort_keys=True))
PY

sha256sum "$AUTHOR_RESULT" "$WORK/diagnostic_receipt.json"
mv "$WORK" "$FINAL"
echo "final=$FINAL"
echo "finished=$(date --iso-8601=seconds)"
SLURM

bash -n "$TEMP_SCRIPT"
mv "$TEMP_SCRIPT" "$SCRIPT"
SCRIPT_SHA256=$(sha256sum "$SCRIPT" | awk '{print $1}')
JOB_ID=$(sbatch --parsable "$SCRIPT")
test -n "$JOB_ID"
echo "script=$SCRIPT"
echo "script_sha256=$SCRIPT_SHA256"
echo "job_id=$JOB_ID"
scontrol show job -o "$JOB_ID"

test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
