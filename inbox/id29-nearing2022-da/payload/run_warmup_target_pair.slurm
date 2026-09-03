#!/bin/bash
#SBATCH --job-name=N22-warm-pair
#SBATCH --partition=hgpu4,hgpu8,hgpu2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002,ngu101
#SBATCH --array=0-1%1
#SBATCH --time=3-12:00:00
#SBATCH --output=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs/%x_%A_%a.out
#SBATCH --error=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs/%x_%A_%a.err

set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAIR_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
DATA_AUDIT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/author_v13_training_data_port_all531_v2"
MASK_AUDIT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/author_v13_warmup_isolation_all531_v2"
PROTOCOL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_target_paired_retraining_protocol.json"
ANALYSIS_CONTRACT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_target_paired_analysis_contract.json"
PREPARE="$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py"
SCORER="$ROOT/src/29_nearing2022_da_ar/scripts/score_reproduction_matrix.py"
SELF="$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm"
EXPECTED_PROTOCOL_SHA256=16bdf57bcbf3afd335e91107bc908330e86ac7fa20db60cbf54ee30b1ab321c1
EXPECTED_ANALYSIS_SHA256=5bb3da898bba8b01b290a2a3efe70a943235fd103e9913711d19a6290869a114
EXPECTED_PREPARE_SHA256=31f856df60b0daacea873386880581f975480c842fae0d605a5abe4b40a1b664
EXPECTED_SCORER_SHA256=f7f67ce1968ce080083c33fb8ee9e2fd58c485acba28edce8fb3913c2885dfcc

case "${SLURM_ARRAY_TASK_ID:?Submit as the frozen 0-1 array}" in
  0)
    ARM=control
    EXPERIMENT_ID=N22-DIAG-WARMUP-CONTROL-S0-R1
    FINAL="$PAIR_ROOT/control_seed0_repeat1"
    ;;
  1)
    ARM=masked
    EXPERIMENT_ID=N22-DIAG-WARMUP-MASKED-S0-R1
    FINAL="$PAIR_ROOT/masked_seed0_repeat1"
    ;;
  *)
    echo "Unsupported array task ${SLURM_ARRAY_TASK_ID}" >&2
    exit 2
    ;;
esac

WORK="$PAIR_ROOT/.${ARM}.preparing-${SLURM_ARRAY_JOB_ID}-${SLURM_ARRAY_TASK_ID}"
FINAL_WORK="$PAIR_ROOT/.${ARM}.completed-work-${SLURM_ARRAY_JOB_ID}-${SLURM_ARRAY_TASK_ID}"
test ! -e "$FINAL"
test ! -e "$WORK"
test ! -e "$FINAL_WORK"
test -d "$DATA_AUDIT"
test -d "$MASK_AUDIT"
test -f "$PROTOCOL"
test -f "$ANALYSIS_CONTRACT"
test -f "$PREPARE"
test -f "$SCORER"
test -f "$SELF"
test "$(sha256sum "$PROTOCOL" | awk '{print $1}')" = "$EXPECTED_PROTOCOL_SHA256"
test "$(sha256sum "$ANALYSIS_CONTRACT" | awk '{print $1}')" = "$EXPECTED_ANALYSIS_SHA256"
test "$(sha256sum "$PREPARE" | awk '{print $1}')" = "$EXPECTED_PREPARE_SHA256"
test "$(sha256sum "$SCORER" | awk '{print $1}')" = "$EXPECTED_SCORER_SHA256"

for JOB in 202510 202511; do
  STATE=$(sacct -n -X -P -j "$JOB" --format=State | awk -F'|' 'NF {print $1; exit}')
  EXIT_CODE=$(sacct -n -X -P -j "$JOB" --format=ExitCode | awk -F'|' 'NF {print $1; exit}')
  test "$STATE" = COMPLETED
  test "$EXIT_CODE" = 0:0
done
MAIN_JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315
FAILURES=$(sacct -n -P -j "$MAIN_JOBS" --format=JobIDRaw,State,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $2 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$FAILURES"
# 2026-09-03 repair: the original assertion `test -z "$FAILURES"` is permanently
# unsatisfiable. Several jobs in MAIN_JOBS ended TIMEOUT (202214, 202215 tasks and
# their array descendants); their coordinates were afterwards rerun successfully
# under new job ids, and TIMEOUT records are immutable history. The guard's intent
# -- "the upstream registered matrix is clean" -- is now asserted directly against
# the registry, which is strictly stronger: missing_total == 0 implies no
# coordinate is absent, whereas the job-id list only ever covered 13 job numbers.
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python - "$ROOT" <<'REGISTRYGUARD'
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "src/29_nearing2022_da_ar/scripts"))
from verify_registered_closure import audit_registered_closure

registry = root / "src/29_nearing2022_da_ar/registry"
aggregation = root / "closure_20260810/aggregation"
closure = audit_registered_closure(
    root,
    registry / "experiment_registry.csv",
    registry / "evaluation_registry.csv",
    registry / "assimilation_hyperparameter_registry.csv",
    aggregation / "evaluations",
    aggregation / "hyperparameters",
)
missing = len(closure["missing"])
print(f"registered_missing_total={missing}")
if missing:
    raise SystemExit(f"registered matrix incomplete: {missing} missing coordinates")
REGISTRYGUARD

mkdir -p "$PAIR_ROOT" "$ROOT/closure_20260810/logs"
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-4}"

python "$PREPARE" \
  --repo-root "$ROOT" \
  --protocol "$PROTOCOL" \
  --data-audit-dir "$DATA_AUDIT" \
  --mask-audit-dir "$MASK_AUDIT" \
  --arm "$ARM" \
  --work-root "$WORK" \
  --receipt "$WORK/preparation_receipt.json"

EXECUTION_ROOT="$WORK/execution_root"
TRAIN_CONFIG="$WORK/training_config.yml"
TRAIN_PARENT="$WORK/training_outputs"
test -d "$EXECUTION_ROOT/neuralhydrology"
test -f "$TRAIN_CONFIG"
ln -s "$ROOT/data" "$EXECUTION_ROOT/data"
ln -s "$ROOT/src" "$EXECUTION_ROOT/src"

cd "$EXECUTION_ROOT"
python - "$EXECUTION_ROOT" <<'PY'
from pathlib import Path
import sys

expected = (Path(sys.argv[1]) / 'neuralhydrology').resolve()
import neuralhydrology
actual = Path(neuralhydrology.__file__).resolve().parent
if actual != expected:
    raise RuntimeError(f'Isolated training imported {actual}, expected {expected}')
print(f'isolated_runtime={actual}')
PY

echo "started=$(date --iso-8601=seconds)"
echo "arm=$ARM"
echo "experiment_id=$EXPERIMENT_ID"
echo "host=$(hostname)"
nvidia-smi --query-gpu=name,uuid,driver_version,memory.total --format=csv,noheader
python -m neuralhydrology.nh_run train --config-file "$TRAIN_CONFIG" --gpu 0

mapfile -t TRAIN_RUNS < <(
  find "$TRAIN_PARENT" -mindepth 1 -maxdepth 1 -type d -name "${EXPERIMENT_ID}_*_ep30" -print | sort
)
test "${#TRAIN_RUNS[@]}" -eq 1
TRAIN_RUN=${TRAIN_RUNS[0]}
test -f "$TRAIN_RUN/config.yml"
test -f "$TRAIN_RUN/model_epoch030.pt"
test -f "$TRAIN_RUN/output.log"
test -f "$TRAIN_RUN/train_data/train_data_scaler.yml"

EVAL_RUN="$WORK/evaluation_test_holdout_1.0"
python - "$TRAIN_RUN" "$EVAL_RUN" <<'PY'
from pathlib import Path
import shutil
import sys

import yaml

source = Path(sys.argv[1])
target = Path(sys.argv[2])
if target.exists():
    raise FileExistsError(f'Refusing existing evaluation directory: {target}')
target.mkdir()
shutil.copy2(source / 'model_epoch030.pt', target / 'model_epoch030.pt')
shutil.copytree(source / 'train_data', target / 'train_data')
config = yaml.safe_load((source / 'config.yml').read_text(encoding='utf-8'))
holdout = config.get('random_holdout_from_dynamic_features')
if not isinstance(holdout, dict) or len(holdout) != 1:
    raise ValueError('Training configuration must contain exactly one random-holdout feature')
feature = next(iter(holdout))
holdout[feature]["missing_fraction"] = 1.0
config['experiment_name'] = f"{config['experiment_name']}_test_holdout_1.0"
config['run_dir'] = str(target.parent)
(target / 'config.yml').write_text(
    yaml.safe_dump(config, sort_keys=False, allow_unicode=True, width=120),
    encoding='utf-8',
    newline='\n',
)
PY

cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python - "$ROOT" <<'PY'
from pathlib import Path
import sys

expected = Path(sys.argv[1]).resolve() / 'neuralhydrology'
import neuralhydrology
actual = Path(neuralhydrology.__file__).resolve().parent
if actual != expected:
    raise RuntimeError(f'Current evaluation imported {actual}, expected {expected}')
print(f'current_evaluator={actual}')
PY
python -m neuralhydrology.nh_run evaluate --run-dir "$EVAL_RUN" --period test --epoch 30 --gpu 0
EVAL_RESULT="$EVAL_RUN/test/model_epoch030/test_results.p"
test -f "$EVAL_RESULT"
test ! -e "$TRAIN_RUN/test"
cp -a "$EVAL_RUN/test" "$TRAIN_RUN/test"
cp "$EVAL_RUN/config.yml" "$TRAIN_RUN/evaluation_test_holdout_1.0.yml"

SIMULATION_RESULT=$(python - "$ROOT" <<'PY'
from pathlib import Path
import sys

import pandas as pd

root = Path(sys.argv[1])
scripts = root / 'src/29_nearing2022_da_ar/scripts'
sys.path.insert(0, str(scripts))
from prepare_evaluation_run import resolve_source_run

registry = pd.read_csv(
    root / 'src/29_nearing2022_da_ar/registry/experiment_registry.csv',
    keep_default_na=False,
    dtype=str,
)
run = resolve_source_run(root, registry, 'N22-TS-SIM-S0')
result = run / 'test/model_epoch030/test_results.p'
if not result.is_file():
    raise FileNotFoundError(result)
print(result)
PY
)
python "$SCORER" \
  --simulation-results "$SIMULATION_RESULT" \
  --candidate-results "$TRAIN_RUN/test/model_epoch030/test_results.p" \
  --label "$EXPERIMENT_ID" \
  --expected-basins 531 \
  --per-basin-out "$TRAIN_RUN/per_basin_metrics.csv" \
  --median-out "$TRAIN_RUN/median_metrics.csv"

mkdir "$TRAIN_RUN/provenance"
cp "$WORK/preparation_receipt.json" "$TRAIN_RUN/provenance/"
cp "$WORK/runtime_manifest.json" "$TRAIN_RUN/provenance/"
cp "$TRAIN_CONFIG" "$TRAIN_RUN/provenance/derived_training_config.yml"
cp "$EXECUTION_ROOT/neuralhydrology/datasetzoo/basedataset.py" \
  "$TRAIN_RUN/provenance/runtime_basedataset.py"
cp "$PROTOCOL" "$TRAIN_RUN/provenance/"
cp "$ANALYSIS_CONTRACT" "$TRAIN_RUN/provenance/"
cp "$PREPARE" "$TRAIN_RUN/provenance/"
cp "$SCORER" "$TRAIN_RUN/provenance/"
cp "$SELF" "$TRAIN_RUN/provenance/"

python - "$ARM" "$TRAIN_RUN" "$SIMULATION_RESULT" "$PROTOCOL" "$ANALYSIS_CONTRACT" \
  "$PREPARE" "$SCORER" "$SELF" "$FINAL_WORK" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import platform
import sys

import numpy
import pandas
import scipy
import torch
import xarray

arm = sys.argv[1]
run = Path(sys.argv[2])
simulation = Path(sys.argv[3])
protocol = Path(sys.argv[4])
analysis_contract = Path(sys.argv[5])
prepare = Path(sys.argv[6])
scorer = Path(sys.argv[7])
slurm = Path(sys.argv[8])
preserved_work = Path(sys.argv[9])

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

gpu = os.popen('nvidia-smi --query-gpu=name,uuid,driver_version --format=csv,noheader').read().strip()
receipt = {
    'schema': 'nearing2022-warmup-target-paired-arm-receipt-v1',
    'arm': arm,
    'slurm_array_job_id': os.environ['SLURM_ARRAY_JOB_ID'],
    'slurm_array_task_id': os.environ['SLURM_ARRAY_TASK_ID'],
    'node': os.environ.get('SLURMD_NODENAME'),
    'gpu': gpu,
    'runtime': {
        'python': platform.python_version(),
        'torch': torch.__version__,
        'cuda': torch.version.cuda,
        'cudnn': str(torch.backends.cudnn.version()),
        'numpy': numpy.__version__,
        'pandas': pandas.__version__,
        'scipy': scipy.__version__,
        'xarray': xarray.__version__,
    },
    'protocol_sha256': digest(protocol),
    'analysis_contract_sha256': digest(analysis_contract),
    'prepare_script_sha256': digest(prepare),
    'scorer_script_sha256': digest(scorer),
    'slurm_script_sha256': digest(slurm),
    'training_config_sha256': digest(run / 'config.yml'),
    'checkpoint_sha256': digest(run / 'model_epoch030.pt'),
    'training_scaler_sha256': digest(run / 'train_data/train_data_scaler.yml'),
    'training_log_sha256': digest(run / 'output.log'),
    'evaluation_result_sha256': digest(run / 'test/model_epoch030/test_results.p'),
    'per_basin_metrics_sha256': digest(run / 'per_basin_metrics.csv'),
    'median_metrics_sha256': digest(run / 'median_metrics.csv'),
    'simulation_reference': str(simulation),
    'simulation_reference_sha256': digest(simulation),
    'preserved_work_after_publication': str(preserved_work),
    'training_runtime_isolated': True,
    'evaluation_uses_current_runtime': True,
    'test_holdout': 1.0,
    'registered_matrix_modified': False,
}
(run / 'runtime_receipt.json').write_text(
    json.dumps(receipt, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n'
)
PY

python - "$TRAIN_RUN" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
manifest_path = root / 'artifact_manifest.json'
if manifest_path.exists():
    raise FileExistsError(manifest_path)
files = []
for path in sorted(root.rglob('*'), key=lambda item: item.as_posix()):
    if path.is_file() and path != manifest_path:
        files.append({
            'path': path.relative_to(root).as_posix(),
            'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        })
manifest = {
    'schema': 'nearing2022-warmup-target-paired-arm-manifest-v1',
    'file_count': len(files),
    'total_bytes': sum(item['bytes'] for item in files),
    'files': files,
}
manifest_path.write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n'
)
PY

test ! -e "$FINAL"
mv "$TRAIN_RUN" "$FINAL"
mv "$WORK" "$FINAL_WORK"
echo "final=$FINAL"
echo "preserved_work=$FINAL_WORK"
sha256sum "$FINAL/artifact_manifest.json" "$FINAL/runtime_receipt.json" \
  "$FINAL/model_epoch030.pt" "$FINAL/test/model_epoch030/test_results.p" \
  "$FINAL/per_basin_metrics.csv" "$FINAL/median_metrics.csv"
echo "finished=$(date --iso-8601=seconds)"
