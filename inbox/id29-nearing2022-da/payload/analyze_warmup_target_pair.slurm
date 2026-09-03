#!/bin/bash
#SBATCH --job-name=N22-warm-analysis
#SBATCH --partition=hgpu4,hgpu8,hgpu2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=02:00:00
#SBATCH --output=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs/%x_%j.out
#SBATCH --error=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs/%x_%j.err

set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAIR_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
CONTROL="$PAIR_ROOT/control_seed0_repeat1"
MASKED="$PAIR_ROOT/masked_seed0_repeat1"
FINAL="$PAIR_ROOT/paired_analysis"
WORK="$PAIR_ROOT/.analysis.preparing-${SLURM_JOB_ID}"
ANALYZER="$ROOT/src/29_nearing2022_da_ar/scripts/analyze_warmup_target_pair.py"
CONTRACT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_target_paired_analysis_contract.json"
PROTOCOL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_target_paired_retraining_protocol.json"
SELF="$ROOT/src/29_nearing2022_da_ar/hpc/analyze_warmup_target_pair.slurm"
EXPECTED_ANALYZER_SHA256=6ea424e02be947cf0823728c437ea7710fa68dc7cee2ac23304e2999e45135a4
EXPECTED_CONTRACT_SHA256=5bb3da898bba8b01b290a2a3efe70a943235fd103e9913711d19a6290869a114
EXPECTED_PROTOCOL_SHA256=16bdf57bcbf3afd335e91107bc908330e86ac7fa20db60cbf54ee30b1ab321c1

test -d "$CONTROL"
test -d "$MASKED"
test ! -e "$FINAL"
test ! -e "$WORK"
test -f "$ANALYZER"
test -f "$CONTRACT"
test -f "$PROTOCOL"
test -f "$SELF"
test "$(sha256sum "$ANALYZER" | awk '{print $1}')" = "$EXPECTED_ANALYZER_SHA256"
test "$(sha256sum "$CONTRACT" | awk '{print $1}')" = "$EXPECTED_CONTRACT_SHA256"
test "$(sha256sum "$PROTOCOL" | awk '{print $1}')" = "$EXPECTED_PROTOCOL_SHA256"

python - "$CONTROL" "$MASKED" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

for expected_arm, root in zip(('control', 'masked'), map(Path, sys.argv[1:])):
    manifest_path = root / 'artifact_manifest.json'
    receipt_path = root / 'runtime_receipt.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
    if receipt['arm'] != expected_arm:
        raise ValueError(f'Expected {expected_arm} receipt, got {receipt["arm"]}')
    if receipt['registered_matrix_modified']:
        raise ValueError(f'{expected_arm} receipt reports a registered-matrix modification')
    if manifest['file_count'] != len(manifest['files']):
        raise ValueError(f'{expected_arm} manifest count mismatch')
    total = 0
    seen = set()
    for item in manifest['files']:
        relative = item['path']
        if relative in seen or Path(relative).is_absolute() or '..' in Path(relative).parts:
            raise ValueError(f'Unsafe or duplicate {expected_arm} manifest path: {relative}')
        seen.add(relative)
        path = root / relative
        if not path.is_file():
            raise FileNotFoundError(path)
        if path.stat().st_size != item['bytes']:
            raise ValueError(f'{expected_arm} byte mismatch: {relative}')
        if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
            raise ValueError(f'{expected_arm} hash mismatch: {relative}')
        total += item['bytes']
    if total != manifest['total_bytes']:
        raise ValueError(f'{expected_arm} manifest total mismatch')
    actual = {
        path.relative_to(root).as_posix()
        for path in root.rglob('*')
        if path.is_file() and path != manifest_path
    }
    if actual != seen:
        raise ValueError(f'{expected_arm} manifest membership mismatch')
PY

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-4}"
mkdir "$WORK"

readarray -t INPUTS < <(python - "$ROOT" <<'PY'
from pathlib import Path
import sys

import pandas as pd

root = Path(sys.argv[1])
scripts = root / 'src/29_nearing2022_da_ar/scripts'
sys.path.insert(0, str(scripts))
from prepare_evaluation_run import resolve_source_run

training = pd.read_csv(
    root / 'src/29_nearing2022_da_ar/registry/experiment_registry.csv',
    keep_default_na=False,
    dtype=str,
)
evaluations = pd.read_csv(
    root / 'src/29_nearing2022_da_ar/registry/evaluation_registry.csv',
    keep_default_na=False,
    dtype=str,
)
simulation = resolve_source_run(root, training, 'N22-TS-SIM-S0') / 'test/model_epoch030/test_results.p'
rows = evaluations.loc[evaluations['eval_id'] == 'N22-EVAL-TS-AR-L01-TR000-TE100-S0']
if len(rows) != 1:
    raise ValueError(f'Expected one frozen registered evaluation row, found {len(rows)}')
row = rows.iloc[0]
registered_run = Path(row['run_dir'])
registered_run = registered_run if registered_run.is_absolute() else root / registered_run
registered = registered_run / row['result_file']
for path in (simulation, registered):
    if not path.is_file():
        raise FileNotFoundError(path)
print(simulation)
print(registered)
PY
)
test "${#INPUTS[@]}" -eq 2
SIMULATION=${INPUTS[0]}
REGISTERED=${INPUTS[1]}
CONTROL_RESULT="$CONTROL/test/model_epoch030/test_results.p"
MASKED_RESULT="$MASKED/test/model_epoch030/test_results.p"
test -f "$CONTROL_RESULT"
test -f "$MASKED_RESULT"

python "$ANALYZER" \
  --simulation "$SIMULATION" \
  --registered "$REGISTERED" \
  --control "$CONTROL_RESULT" \
  --masked "$MASKED_RESULT" \
  --contract "$CONTRACT" \
  --per-basin-out "$WORK/per_basin.csv" \
  --decision-out "$WORK/decision.json" > "$WORK/analysis_stdout.json"
python "$ANALYZER" \
  --simulation "$SIMULATION" \
  --registered "$REGISTERED" \
  --control "$CONTROL_RESULT" \
  --masked "$MASKED_RESULT" \
  --contract "$CONTRACT" \
  --per-basin-out "$WORK/verify_per_basin.csv" \
  --decision-out "$WORK/verify_decision.json" > "$WORK/verification_stdout.json"
cmp "$WORK/per_basin.csv" "$WORK/verify_per_basin.csv"
cmp "$WORK/decision.json" "$WORK/verify_decision.json"
cp "$ANALYZER" "$WORK/"
cp "$CONTRACT" "$WORK/"
cp "$PROTOCOL" "$WORK/"
cp "$SELF" "$WORK/"

python - "$WORK" "$SIMULATION" "$REGISTERED" "$CONTROL_RESULT" "$MASKED_RESULT" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import platform
import sys

import numpy
import pandas
import scipy

work = Path(sys.argv[1])
input_paths = {
    'simulation': Path(sys.argv[2]),
    'registered': Path(sys.argv[3]),
    'control': Path(sys.argv[4]),
    'masked': Path(sys.argv[5]),
}

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

decision = json.loads((work / 'decision.json').read_text(encoding='utf-8'))
receipt = {
    'schema': 'nearing2022-warmup-target-paired-analysis-receipt-v1',
    'slurm_job_id': os.environ['SLURM_JOB_ID'],
    'node': os.environ.get('SLURMD_NODENAME'),
    'runtime': {
        'python': platform.python_version(),
        'numpy': numpy.__version__,
        'pandas': pandas.__version__,
        'scipy': scipy.__version__,
    },
    'inputs': {
        name: {'path': str(path), 'bytes': path.stat().st_size, 'sha256': digest(path)}
        for name, path in input_paths.items()
    },
    'analyzer_sha256': digest(work / 'analyze_warmup_target_pair.py'),
    'contract_sha256': digest(work / 'warmup_target_paired_analysis_contract.json'),
    'protocol_sha256': digest(work / 'warmup_target_paired_retraining_protocol.json'),
    'slurm_script_sha256': digest(work / 'analyze_warmup_target_pair.slurm'),
    'per_basin_sha256': digest(work / 'per_basin.csv'),
    'decision_sha256': digest(work / 'decision.json'),
    'independent_rerun_byte_identical': True,
    'decision_status': decision['status'],
    'registered_matrix_modified': False,
}
(work / 'runtime_receipt.json').write_text(
    json.dumps(receipt, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n'
)
PY

python - "$WORK" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
manifest_path = root / 'artifact_manifest.json'
files = []
for path in sorted(root.rglob('*'), key=lambda item: item.as_posix()):
    if path.is_file() and path != manifest_path:
        files.append({
            'path': path.relative_to(root).as_posix(),
            'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        })
manifest = {
    'schema': 'nearing2022-warmup-target-paired-analysis-manifest-v1',
    'file_count': len(files),
    'total_bytes': sum(item['bytes'] for item in files),
    'files': files,
}
manifest_path.write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n'
)
PY

test ! -e "$FINAL"
mv "$WORK" "$FINAL"
echo "final=$FINAL"
sha256sum "$FINAL/artifact_manifest.json" "$FINAL/runtime_receipt.json" \
  "$FINAL/per_basin.csv" "$FINAL/decision.json"
cat "$FINAL/decision.json"
