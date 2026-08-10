#!/bin/bash
# ID29 seq=122: audit storage capacity for all 660 frozen hyperparameter outputs; read-only.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315

echo "=== FILESYSTEM CAPACITY ==="
df -B1 "$ROOT"
du -sb "$ROOT/closure_20260810"
echo "=== USER QUOTA IF CONFIGURED ==="
quota -s 2>&1 || true

echo "=== HYPERPARAMETER STORAGE PROJECTION ==="
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python - <<'PY'
import json
from pathlib import Path

import pandas as pd

root = Path('/data1/home/sunyiq/nearing2022_da')
registry_root = root / 'src/29_nearing2022_da_ar/registry'
evaluations = pd.read_csv(registry_root / 'evaluation_registry.csv', keep_default_na=False, dtype=str)
hyper = pd.read_csv(registry_root / 'assimilation_hyperparameter_registry.csv', keep_default_na=False, dtype=str)

def tree_bytes(path):
    return sum(item.stat().st_size for item in path.rglob('*') if item.is_file())

def record(path):
    return {'path': str(path), 'bytes': path.stat().st_size}

completed_rows = evaluations.loc[evaluations['slurm_job_id'].isin(['202222_6', '202222_7'])]
samples = []
estimates = []
for _, row in completed_rows.iterrows():
    run = Path(row['run_dir'])
    run = run if run.is_absolute() else root / run
    assert run.is_dir(), run
    result = run / row['result_file']
    assert result.is_file(), result
    fixed_paths = [run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log']
    assert all(path.is_file() for path in fixed_paths)
    train_data = run / 'train_data'
    assert train_data.is_dir()
    fixed_bytes = sum(path.stat().st_size for path in fixed_paths) + tree_bytes(train_data)
    test_bytes = tree_bytes(run / 'test')
    total_bytes = tree_bytes(run)
    assert fixed_bytes + test_bytes == total_bytes
    estimated_53_basin_bytes = fixed_bytes + round(test_bytes * 53 / 531)
    estimates.append(estimated_53_basin_bytes)
    samples.append({
        'eval_id': row['eval_id'],
        'run': str(run),
        'full_531_basin_total_bytes': total_bytes,
        'fixed_bytes': fixed_bytes,
        'test_tree_bytes': test_bytes,
        'result': record(result),
        'estimated_53_basin_total_bytes': estimated_53_basin_bytes,
    })

assert len(samples) == 2
estimates.sort()
median_estimate = estimates[len(estimates) // 2]
existing_hyper_dirs = [path for path in (root / 'closure_20260810/evaluations/hyperparameter_search').glob('*') if path.is_dir()] \
    if (root / 'closure_20260810/evaluations/hyperparameter_search').is_dir() else []
print(json.dumps({
    'samples': samples,
    'hyperparameter_rows': len(hyper),
    'hyperparameter_basin_count': 53,
    'existing_hyperparameter_directories': len(existing_hyper_dirs),
    'median_estimated_bytes_per_53_basin_directory': median_estimate,
    'estimated_660_directory_bytes': median_estimate * len(hyper),
    'two_x_conservative_bytes': 2 * median_estimate * len(hyper),
    'projection_limit': 'Scales the completed test tree linearly from 531 to 53 basins and keeps copied checkpoint, scaler, config, and log bytes fixed; hyperparameter settings can change log and result sizes.',
}, sort_keys=True))
PY

echo "=== ACTIVE FAILURE STATES ==="
FAILURES=$(sacct -n -P -j "$JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$FAILURES"
test -z "$FAILURES"

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
