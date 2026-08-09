#!/bin/bash
# ID18 seq=6: final read-only pre-sbatch audit. No sbatch.
set -eo pipefail

TARGET=/data1/home/sunyiq/id18_e04_20260809
BASE=/data1/home/sunyiq/neuralhydrology
RESULT=$TARGET/results/18_lstm_fair_531/E04_daymet_post2008_objective_confirmation_482

echo "=== TARGET_AND_QUEUE ==="
date -Is
test -d "$TARGET"
test -f "$RESULT/protocol/preflight.json"
squeue -u "$USER" -o "%.10i %.18j %.10P %.9T %.11M %.6D %R" 2>&1 | head -30
sinfo -p hgpu2p -o "%.10P %.6a %.10l %.6D %.6t %N" 2>&1

echo "=== FROZEN_HASH_AUDIT ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONPATH="$TARGET:$BASE:${PYTHONPATH:-}"
cd "$TARGET"
python - <<'PY'
import hashlib
import json
import pathlib

import cma

root = pathlib.Path('/data1/home/sunyiq/id18_e04_20260809')
result = root / 'results/18_lstm_fair_531/E04_daymet_post2008_objective_confirmation_482'
preflight_path = result / 'protocol/preflight.json'
preflight = json.loads(preflight_path.read_text(encoding='utf-8'))
bad_sources = []
for item in preflight['source_files']:
    path = root / item['path']
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != item['sha256']:
        bad_sources.append(item['path'])
bad_configs = []
for item in preflight['generated_configs']:
    path = result / item['path']
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != item['sha256']:
        bad_configs.append(item['path'])
loaded = pathlib.Path(cma.__file__).resolve()
assert root in loaded.parents, loaded
assert cma.__version__ == '4.4.4'
formal_completion_files = sorted(str(path.relative_to(root)) for path in result.glob('**/completion.json'))
assert not bad_sources, bad_sources
assert not bad_configs, bad_configs
assert not formal_completion_files, formal_completion_files
print(json.dumps({
    'source_file_count': len(preflight['source_files']),
    'source_hash_mismatches': bad_sources,
    'generated_config_count': len(preflight['generated_configs']),
    'config_hash_mismatches': bad_configs,
    'formal_completion_files': formal_completion_files,
    'cma_version': cma.__version__,
    'cma_file': str(loaded),
    'preflight_sha256': hashlib.sha256(preflight_path.read_bytes()).hexdigest(),
}, indent=2))
PY

echo "=== SLURM_SCRIPTS ==="
for script in "$TARGET"/src/loss_mechanism_531/hpc/e04_*.slurm; do
    bash -n "$script"
    grep -E '^#SBATCH (-p|--exclude|--cpus-per-task|--gres|-t|-o|-e)' "$script"
done

echo "E04_PRE_SBATCH_AUDIT_PASS"
