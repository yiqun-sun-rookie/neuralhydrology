#!/bin/bash
# ID29 seq=160: submit an all-531 one-factor warmup-target isolation after job 202506.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
SOURCE_SCRIPTS="$ROOT/src/29_nearing2022_da_ar/scripts"
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
HELPER_SOURCE="$DIAGNOSTIC_ROOT/audit_training_data_port.py"
HELPER_TARGET="$SOURCE_SCRIPTS/audit_training_data_port.py"
ISOLATION_SCRIPT="$SOURCE_SCRIPTS/audit_warmup_target_isolation.py"
PROTOCOL="$DIAGNOSTIC_ROOT/warmup_target_paired_retraining_protocol.json"
SLURM_SCRIPT="$DIAGNOSTIC_ROOT/run_author_v13_warmup_isolation_all531.slurm"
UPSTREAM_FINAL="$DIAGNOSTIC_ROOT/author_v13_training_data_port_all531"
FINAL="$DIAGNOSTIC_ROOT/author_v13_warmup_isolation_all531"
EXPECTED_HELPER_SHA256=5f7d49c4899aeb0ffb1d097cffd98cfe86393f86b5849a153d3074094744eb85
EXPECTED_ISOLATION_SHA256=9f898a80aafb4e207bb56fd095125e9d5d092ec8c96af4d6010bdaeb36a27f8c
EXPECTED_PROTOCOL_SHA256=16bdf57bcbf3afd335e91107bc908330e86ac7fa20db60cbf54ee30b1ab321c1

mkdir -p "$SOURCE_SCRIPTS" "$DIAGNOSTIC_ROOT" "$ROOT/closure_20260810/logs"
test -f "$HELPER_SOURCE"
test "$(sha256sum "$HELPER_SOURCE" | awk '{print $1}')" = "$EXPECTED_HELPER_SHA256"
if test -e "$HELPER_TARGET"; then
  test "$(sha256sum "$HELPER_TARGET" | awk '{print $1}')" = "$EXPECTED_HELPER_SHA256"
else
  TEMP_HELPER="$HELPER_TARGET.preparing-$$"
  cp "$HELPER_SOURCE" "$TEMP_HELPER"
  test "$(sha256sum "$TEMP_HELPER" | awk '{print $1}')" = "$EXPECTED_HELPER_SHA256"
  mv "$TEMP_HELPER" "$HELPER_TARGET"
fi

test ! -e "$ISOLATION_SCRIPT"
TEMP_ISOLATION="$ISOLATION_SCRIPT.preparing-$$"
base64 -d <<'PAYLOAD' | gzip -d > "$TEMP_ISOLATION"
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
PAYLOAD
test "$(sha256sum "$TEMP_ISOLATION" | awk '{print $1}')" = "$EXPECTED_ISOLATION_SHA256"
mv "$TEMP_ISOLATION" "$ISOLATION_SCRIPT"

test ! -e "$PROTOCOL"
TEMP_PROTOCOL="$PROTOCOL.preparing-$$"
base64 -d <<'PAYLOAD' | gzip -d > "$TEMP_PROTOCOL"
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
PAYLOAD
test "$(sha256sum "$TEMP_PROTOCOL" | awk '{print $1}')" = "$EXPECTED_PROTOCOL_SHA256"
mv "$TEMP_PROTOCOL" "$PROTOCOL"

test ! -e "$SLURM_SCRIPT"
test ! -e "$FINAL"
TEMP_SLURM="$SLURM_SCRIPT.preparing-$$"
cat > "$TEMP_SLURM" <<'SLURM'
#!/bin/bash
#SBATCH --job-name=N22-mask-iso-531
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
SOURCE_SCRIPTS="$ROOT/src/29_nearing2022_da_ar/scripts"
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
HELPER="$SOURCE_SCRIPTS/audit_training_data_port.py"
ISOLATION_SCRIPT="$SOURCE_SCRIPTS/audit_warmup_target_isolation.py"
PROTOCOL="$DIAGNOSTIC_ROOT/warmup_target_paired_retraining_protocol.json"
SLURM_SCRIPT="$DIAGNOSTIC_ROOT/run_author_v13_warmup_isolation_all531.slurm"
UPSTREAM_FINAL="$DIAGNOSTIC_ROOT/author_v13_training_data_port_all531"
FINAL="$DIAGNOSTIC_ROOT/author_v13_warmup_isolation_all531"
WORK="$FINAL.preparing-$SLURM_JOB_ID"

test ! -e "$FINAL"
test ! -e "$WORK"
test -f "$UPSTREAM_FINAL/audit.json"
test -f "$UPSTREAM_FINAL/diagnostic_receipt.json"
test -f "$HELPER"
test -f "$ISOLATION_SCRIPT"
test -f "$PROTOCOL"
mkdir "$WORK"
cp "$HELPER" "$WORK/audit_training_data_port.py"
cp "$ISOLATION_SCRIPT" "$WORK/audit_warmup_target_isolation.py"
cp "$PROTOCOL" "$WORK/warmup_target_paired_retraining_protocol.json"
cp "$SLURM_SCRIPT" "$WORK/run_author_v13_warmup_isolation_all531.slurm"

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python "$ISOLATION_SCRIPT" \
  --repo-root "$ROOT" \
  --basin-count 531 \
  --unmasked-evidence "$UPSTREAM_FINAL/audit.json" \
  --output "$WORK/audit.json" > "$WORK/audit_stdout.json"

python - "$WORK/audit.json" "$UPSTREAM_FINAL/audit.json" "$UPSTREAM_FINAL/diagnostic_receipt.json" \
  "$HELPER" "$ISOLATION_SCRIPT" "$PROTOCOL" "$SLURM_SCRIPT" "$WORK/diagnostic_receipt.json" <<'PY'
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

audit_path = Path(sys.argv[1])
upstream_audit_path = Path(sys.argv[2])
upstream_receipt_path = Path(sys.argv[3])
helper_path = Path(sys.argv[4])
isolation_path = Path(sys.argv[5])
protocol_path = Path(sys.argv[6])
slurm_path = Path(sys.argv[7])
receipt_path = Path(sys.argv[8])

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

audit = json.loads(audit_path.read_text(encoding='utf-8'))
comparison = audit['author_vs_current_masked']
if audit['scope']['basin_count'] != 531 or comparison['basins_compared'] != 531:
    raise ValueError('All-531 warmup isolation did not use exactly 531 basins')
if comparison['bitwise_identical_normalized_dynamic_input_basins'] != 531:
    raise ValueError('Masked-current and author normalized dynamic inputs differ')
if comparison['bitwise_identical_static_attribute_basins'] != 531:
    raise ValueError('Masked-current and author static attributes differ')
if not comparison['metadata_identical'] or not comparison['finite_target_mask_identical']:
    raise ValueError('Masked-current and author dataset structure or finite-target mask differs')
for key in (
    'masked_minus_author_target_center',
    'masked_minus_author_target_scale',
    'maximum_absolute_common_raw_target_difference',
    'maximum_absolute_target_standard_deviation_difference',
):
    if comparison[key] != 0.0:
        raise ValueError(f'Expected exact zero for {key}, got {comparison[key]}')
if comparison['per_basin_target_standard_deviations_within_1e_6'] != 531:
    raise ValueError('Not all per-basin target standard deviations match')
if not audit['conclusion']['single_mask_restores_released_training_data_for_scope']:
    raise ValueError('Single-mask restoration conclusion did not pass')
if audit['one_factor_contract']['other_installed_source_files_modified'] != 0:
    raise ValueError('Isolation changed an installed source file')
if audit['source_binding']['unmasked_evidence_sha256'] != digest(upstream_audit_path):
    raise ValueError('Isolation is not bound to the completed upstream all-531 audit')

gpu = os.popen('nvidia-smi --query-gpu=name,uuid,driver_version --format=csv,noheader').read().strip()
receipt = {
    'schema': 'nearing2022-author-v13-warmup-isolation-all531-receipt-v1',
    'slurm_job_id': os.environ['SLURM_JOB_ID'],
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
    'audit_sha256': digest(audit_path),
    'upstream_audit_sha256': digest(upstream_audit_path),
    'upstream_receipt_sha256': digest(upstream_receipt_path),
    'helper_script_sha256': digest(helper_path),
    'isolation_script_sha256': digest(isolation_path),
    'paired_retraining_protocol_sha256': digest(protocol_path),
    'slurm_script_sha256': digest(slurm_path),
    'single_mask_restores_released_training_data_for_531_basins': True,
    'registered_matrix_modified': False,
    'scientific_boundary': (
        'This establishes all-531 data-tensor and scaling causality for the single warmup mask. It does not quantify '
        'the trained-checkpoint or paper-metric effect; the preregistered paired retraining remains required.'
    ),
}
receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n', encoding='utf-8')
print(json.dumps(receipt, sort_keys=True))
PY

sha256sum "$WORK/audit.json" "$WORK/audit_stdout.json" "$WORK/diagnostic_receipt.json" \
  "$WORK/audit_training_data_port.py" "$WORK/audit_warmup_target_isolation.py" \
  "$WORK/warmup_target_paired_retraining_protocol.json" \
  "$WORK/run_author_v13_warmup_isolation_all531.slurm"
mv "$WORK" "$FINAL"
echo "final=$FINAL"
SLURM

bash -n "$TEMP_SLURM"
mv "$TEMP_SLURM" "$SLURM_SCRIPT"
test "$(sha256sum "$ISOLATION_SCRIPT" | awk '{print $1}')" = "$EXPECTED_ISOLATION_SHA256"
test "$(sha256sum "$PROTOCOL" | awk '{print $1}')" = "$EXPECTED_PROTOCOL_SHA256"

JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315,202506
FAILURES=$(sacct -n -P -j "$JOBS" --format=JobIDRaw,State,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $2 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$FAILURES"
test -z "$FAILURES"

JOB_ID=$(sbatch --parsable --dependency=afterok:202506 "$SLURM_SCRIPT")
test -n "$JOB_ID"
echo "helper=$HELPER_TARGET"
echo "helper_sha256=$(sha256sum "$HELPER_TARGET" | awk '{print $1}')"
echo "isolation_script=$ISOLATION_SCRIPT"
echo "isolation_script_sha256=$(sha256sum "$ISOLATION_SCRIPT" | awk '{print $1}')"
echo "protocol=$PROTOCOL"
echo "protocol_sha256=$(sha256sum "$PROTOCOL" | awk '{print $1}')"
echo "slurm_script=$SLURM_SCRIPT"
echo "slurm_script_sha256=$(sha256sum "$SLURM_SCRIPT" | awk '{print $1}')"
echo "dependency=afterok:202506"
echo "job_id=$JOB_ID"
scontrol show job -o "$JOB_ID"

echo "=== CURRENT DEPENDENCY CHAIN ==="
sacct -n -P -j 202222_10,202222_11,202506,"$JOB_ID" --format=JobID,JobName,State,ExitCode,Elapsed,Start,End,NodeList
squeue -h -j 202222_10,202222_11,202506,"$JOB_ID" -o '%i|%T|%M|%l|%R|%j' | sort

echo "=== REGISTERED ARTIFACT SAFETY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
