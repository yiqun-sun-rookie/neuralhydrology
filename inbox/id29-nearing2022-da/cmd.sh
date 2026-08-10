#!/bin/bash
# ID29 seq=158: deploy the frozen training-data port audit and submit an isolated all-531-basin diagnostic.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
DEPLOYED_SCRIPT="$DIAGNOSTIC_ROOT/audit_training_data_port.py"
SLURM_SCRIPT="$DIAGNOSTIC_ROOT/run_author_v13_training_data_port_all531.slurm"
FINAL="$DIAGNOSTIC_ROOT/author_v13_training_data_port_all531"
SOURCE_RUN="$ROOT/results/29_nearing2022_da_ar/nearing2022_autoregression_lead1_holdout0.0_seed0_2026_0808_1648_ep30"
EXPECTED_SCRIPT_SHA256=5f7d49c4899aeb0ffb1d097cffd98cfe86393f86b5849a153d3074094744eb85

mkdir -p "$DIAGNOSTIC_ROOT" "$ROOT/closure_20260810/logs"
test ! -e "$DEPLOYED_SCRIPT"
test ! -e "$SLURM_SCRIPT"
test ! -e "$FINAL"
test -f "$SOURCE_RUN/config.yml"
test -f "$SOURCE_RUN/train_data/train_data_scaler.yml"

TEMP_SCRIPT="$DEPLOYED_SCRIPT.preparing-$$"
test ! -e "$TEMP_SCRIPT"
base64 -d <<'PAYLOAD' | gzip -d > "$TEMP_SCRIPT"
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
PAYLOAD
test "$(sha256sum "$TEMP_SCRIPT" | awk '{print $1}')" = "$EXPECTED_SCRIPT_SHA256"
mv "$TEMP_SCRIPT" "$DEPLOYED_SCRIPT"

TEMP_SLURM="$SLURM_SCRIPT.preparing-$$"
test ! -e "$TEMP_SLURM"
cat > "$TEMP_SLURM" <<'SLURM'
#!/bin/bash
#SBATCH --job-name=N22-data-port-531
#SBATCH --partition=hgpu4,hgpu8,hgpu2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH --time=02:00:00
#SBATCH --output=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs/%x_%j.out
#SBATCH --error=/data1/home/sunyiq/nearing2022_da/closure_20260810/logs/%x_%j.err

set -eo pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
DIAGNOSTIC_SCRIPT="$DIAGNOSTIC_ROOT/audit_training_data_port.py"
SLURM_SCRIPT="$DIAGNOSTIC_ROOT/run_author_v13_training_data_port_all531.slurm"
FINAL="$DIAGNOSTIC_ROOT/author_v13_training_data_port_all531"
WORK="$FINAL.preparing-$SLURM_JOB_ID"
SOURCE_RUN="$ROOT/results/29_nearing2022_da_ar/nearing2022_autoregression_lead1_holdout0.0_seed0_2026_0808_1648_ep30"
FROZEN_CONFIG="$ROOT/src/29_nearing2022_da_ar/configs/full_reproduction/time_split/autoregression/lead_1_holdout_0.0_seed_0.yml"
FROZEN_BASINS="$ROOT/src/29_nearing2022_da_ar/basin_lists/531_basin_list.txt"

test ! -e "$FINAL"
test ! -e "$WORK"
test -f "$DIAGNOSTIC_SCRIPT"
test -f "$SOURCE_RUN/config.yml"
test -f "$SOURCE_RUN/train_data/train_data_scaler.yml"
mkdir "$WORK"
cp "$DIAGNOSTIC_SCRIPT" "$WORK/audit_training_data_port.py"
cp "$SLURM_SCRIPT" "$WORK/run_author_v13_training_data_port_all531.slurm"

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python "$DIAGNOSTIC_SCRIPT" \
  --repo-root "$ROOT" \
  --basin-count 531 \
  --output "$WORK/audit.json" > "$WORK/audit_stdout.json"

python - "$WORK/audit.json" "$SOURCE_RUN/train_data/train_data_scaler.yml" "$WORK/diagnostic_receipt.json" \
  "$DIAGNOSTIC_SCRIPT" "$SLURM_SCRIPT" "$FROZEN_CONFIG" "$FROZEN_BASINS" "$SOURCE_RUN/config.yml" <<'PY'
import hashlib
import json
from pathlib import Path
import os
import sys

import yaml

audit_path = Path(sys.argv[1])
registered_scaler_path = Path(sys.argv[2])
receipt_path = Path(sys.argv[3])
diagnostic_script_path = Path(sys.argv[4])
slurm_script_path = Path(sys.argv[5])
frozen_config_path = Path(sys.argv[6])
frozen_basins_path = Path(sys.argv[7])
source_config_path = Path(sys.argv[8])

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

audit = json.loads(audit_path.read_text(encoding='utf-8'))
scaler = yaml.safe_load(registered_scaler_path.read_text(encoding='utf-8'))
registered_center = float(
    scaler['xarray_feature_center']['data_vars']['QObs(mm/d)']['data']
)
registered_scale = float(
    scaler['xarray_feature_scale']['data_vars']['QObs(mm/d)']['data']
)
current_center = float(audit['target_scaler']['current_center'])
current_scale = float(audit['target_scaler']['current_scale'])

if audit['scope']['basin_count'] != 531:
    raise ValueError('Full training-data audit did not use 531 basins')
if audit['inputs']['basins_with_bitwise_identical_normalized_dynamic_inputs'] != 531:
    raise ValueError('Released and current normalized dynamic inputs differ')
if audit['inputs']['basins_with_bitwise_identical_static_attributes'] != 531:
    raise ValueError('Released and current static attributes differ')
if not audit['source']['author_masks_warmup_targets']:
    raise ValueError('Released source warmup-target mask was not detected')
if audit['source']['current_masks_warmup_targets']:
    raise ValueError('Current source unexpectedly contains the released warmup-target mask')
if audit['conclusion']['training_data_port_is_exact_for_this_scope']:
    raise ValueError('Expected the known training-target path mismatch')
if not audit['raw_targets_after_inverse_scaling']['common_values_within_1e_5']:
    raise ValueError('Raw targets disagree beyond inverse-scaling tolerance')
if audit['raw_targets_after_inverse_scaling']['current_finite_author_missing'] <= 0:
    raise ValueError('No current-only warmup targets were observed')
if current_center != registered_center or current_scale != registered_scale:
    raise ValueError(
        'The formal source-run scaler is not byte-value-equivalent to the current full-cohort audit: '
        f'current=({current_center}, {current_scale}), registered=({registered_center}, {registered_scale})'
    )

receipt = {
    'schema': 'nearing2022-author-v13-training-data-port-all531-receipt-v1',
    'slurm_job_id': os.environ['SLURM_JOB_ID'],
    'node': os.environ.get('SLURMD_NODENAME'),
    'audit_sha256': digest(audit_path),
    'diagnostic_script_sha256': digest(diagnostic_script_path),
    'slurm_script_sha256': digest(slurm_script_path),
    'frozen_config_sha256': digest(frozen_config_path),
    'frozen_basin_list_sha256': digest(frozen_basins_path),
    'registered_source_config_sha256': digest(source_config_path),
    'registered_source_scaler_sha256': digest(registered_scaler_path),
    'registered_target_center': registered_center,
    'registered_target_scale': registered_scale,
    'current_audit_target_center': current_center,
    'current_audit_target_scale': current_scale,
    'registered_source_scaler_matches_current_audit': True,
    'scientific_boundary': (
        'The full-cohort audit proves that the formal run used the current warmup-inclusive target scaler and that '
        'this differs from the released v1.3.0 training-data path. It does not quantify the checkpoint or paper-score '
        'effect without an isolated author-consistent retraining.'
    ),
}
receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n', encoding='utf-8')
print(json.dumps(receipt, sort_keys=True))
PY

sha256sum "$WORK/audit.json" "$WORK/audit_stdout.json" "$WORK/diagnostic_receipt.json" \
  "$WORK/audit_training_data_port.py" "$WORK/run_author_v13_training_data_port_all531.slurm"
mv "$WORK" "$FINAL"
echo "final=$FINAL"
SLURM

bash -n "$TEMP_SLURM"
mv "$TEMP_SLURM" "$SLURM_SCRIPT"
test "$(sha256sum "$DEPLOYED_SCRIPT" | awk '{print $1}')" = "$EXPECTED_SCRIPT_SHA256"

FAILURES=$(sacct -n -P -j 202214,202215,202216,202222,202226,202227,202228,202229,202230,202238 \
  --format=JobIDRaw,State,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $2 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$FAILURES"
test -z "$FAILURES"

JOB_ID=$(sbatch --parsable --dependency=afterany:202222_10:202222_11 "$SLURM_SCRIPT")
test -n "$JOB_ID"
echo "diagnostic_script=$DEPLOYED_SCRIPT"
echo "diagnostic_script_sha256=$(sha256sum "$DEPLOYED_SCRIPT" | awk '{print $1}')"
echo "slurm_script=$SLURM_SCRIPT"
echo "slurm_script_sha256=$(sha256sum "$SLURM_SCRIPT" | awk '{print $1}')"
echo "dependency=afterany:202222_10:202222_11"
echo "job_id=$JOB_ID"
scontrol show job -o "$JOB_ID"

echo "=== REGISTERED ARTIFACT SAFETY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
