#!/bin/bash
# ID29 seq=169: submit the two immutable all-531 direct-raw repair audits.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
V1="$ROOT/src/29_nearing2022_da_ar/scripts/audit_training_data_port.py"
V2="$ROOT/src/29_nearing2022_da_ar/scripts/audit_training_data_port_v2.py"
PROTOCOL="$DIAGNOSTIC_ROOT/warmup_target_paired_retraining_protocol.json"
AMENDMENT="$DIAGNOSTIC_ROOT/warmup_target_paired_retraining_protocol_amendment_01.json"
DATA_SLURM="$ROOT/src/29_nearing2022_da_ar/hpc/run_author_v13_training_data_port_all531_v2.slurm"
MASK_SLURM="$ROOT/src/29_nearing2022_da_ar/hpc/run_author_v13_warmup_isolation_all531_v2.slurm"
FAILED_STAGING="$DIAGNOSTIC_ROOT/author_v13_training_data_port_all531.preparing-202506"
FAILED_AUDIT="$FAILED_STAGING/audit.json"
FAILED_STDOUT="$FAILED_STAGING/audit_stdout.json"
DATA_FINAL="$DIAGNOSTIC_ROOT/author_v13_training_data_port_all531_v2"
MASK_FINAL="$DIAGNOSTIC_ROOT/author_v13_warmup_isolation_all531_v2"
RECEIPT="$DIAGNOSTIC_ROOT/warmup_target_repair_submission_01.json"
RECEIPT_TEMP="$RECEIPT.preparing-seq169"

assert_sha256() {
  local path=$1
  local expected=$2
  test -f "$path"
  local actual
  actual=$(sha256sum "$path" | awk '{print $1}')
  test "$actual" = "$expected"
  echo "sha256=$actual|path=$path"
}

test ! -e "$DATA_FINAL"
test ! -e "$MASK_FINAL"
test ! -e "$RECEIPT"
test ! -e "$RECEIPT_TEMP"
if compgen -G "$DATA_FINAL.preparing-*" >/dev/null; then
  echo "unexpected version-2 data-audit staging directory" >&2
  exit 1
fi
if compgen -G "$MASK_FINAL.preparing-*" >/dev/null; then
  echo "unexpected version-2 mask-audit staging directory" >&2
  exit 1
fi
test -z "$(squeue -h -n N22-data-port-v2)"
test -z "$(squeue -h -n N22-mask-iso-v2)"

FAILED_STATE=$(sacct -n -X -j 202506 --format=State,ExitCode -P | awk -F'|' 'NF {print $1"|"$2; exit}')
DEPENDENCY_FAILED_STATE=$(squeue -h -j 202507 -o '%T|%r' | awk 'NF {print; exit}')
test "$FAILED_STATE" = 'FAILED|1:0'
test "$DEPENDENCY_FAILED_STATE" = 'PENDING|DependencyNeverSatisfied'

assert_sha256 "$V1" 5f7d49c4899aeb0ffb1d097cffd98cfe86393f86b5849a153d3074094744eb85
assert_sha256 "$V2" 51b9091c928a8b514f0be6e81ab5afd304bda654e3dc63a6cb27746e3dee3233
assert_sha256 "$PROTOCOL" 16bdf57bcbf3afd335e91107bc908330e86ac7fa20db60cbf54ee30b1ab321c1
assert_sha256 "$AMENDMENT" a21bae28a26f5797e96232628fdc139f5ffd1e54e31ee2032a7805acb0785ef5
assert_sha256 "$DATA_SLURM" 7805e78942a9d512075deb1f546a230d4fe20f04a7efd837a8507ada9e4a493e
assert_sha256 "$MASK_SLURM" 9d8d2c890e6ec8a28be30e674ea05c3c90a8926ba0e4e80bf088386879127053
assert_sha256 "$FAILED_AUDIT" 3f5fe1e597a2d8cee36dffac4426a178075d8828eae560c585fe7727d2a4aa30
assert_sha256 "$FAILED_STDOUT" a577a8ec870a4f2a100643b3d6cfc49a29a00d19384bee888590b9cee3112336

DATA_SUBMISSION=$(sbatch --parsable --dependency=afterany:202222 "$DATA_SLURM")
DATA_JOB=${DATA_SUBMISSION%%;*}
test -n "$DATA_JOB"
MASK_SUBMISSION=$(sbatch --parsable --dependency="afterok:$DATA_JOB" "$MASK_SLURM")
MASK_JOB=${MASK_SUBMISSION%%;*}
test -n "$MASK_JOB"

DATA_JOB_RECORD=$(scontrol show job -o "$DATA_JOB")
MASK_JOB_RECORD=$(scontrol show job -o "$MASK_JOB")

python - "$RECEIPT_TEMP" "$DATA_JOB" "$MASK_JOB" "$FAILED_STATE" "$DEPENDENCY_FAILED_STATE" \
  "$V1" "$V2" "$PROTOCOL" "$AMENDMENT" "$DATA_SLURM" "$MASK_SLURM" \
  "$FAILED_AUDIT" "$FAILED_STDOUT" "$DATA_JOB_RECORD" "$MASK_JOB_RECORD" <<'PY'
from datetime import datetime
import hashlib
import json
from pathlib import Path
import sys
from zoneinfo import ZoneInfo


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


receipt_path = Path(sys.argv[1])
data_job = sys.argv[2]
mask_job = sys.argv[3]
failed_state = sys.argv[4]
dependency_failed_state = sys.argv[5]
v1, v2, protocol, amendment, data_slurm, mask_slurm, failed_audit, failed_stdout = map(Path, sys.argv[6:14])
data_job_record = sys.argv[14]
mask_job_record = sys.argv[15]

receipt = {
    'schema': 'nearing2022-warmup-target-entry-repair-submission-v1',
    'created_at': datetime.now(ZoneInfo('Asia/Singapore')).isoformat(),
    'registered_matrix_modified': False,
    'jobs': {
        'training_data_port_v2': {
            'slurm_job_id': data_job,
            'dependency_requested': 'afterany:202222',
            'script': str(data_slurm),
            'script_sha256': digest(data_slurm),
            'output': 'results/29_nearing2022_da_ar/formal_closure/diagnostics/author_v13_training_data_port_all531_v2',
            'scheduler_record_at_submission': data_job_record,
        },
        'warmup_target_isolation_v2': {
            'slurm_job_id': mask_job,
            'dependency_requested': f'afterok:{data_job}',
            'script': str(mask_slurm),
            'script_sha256': digest(mask_slurm),
            'output': 'results/29_nearing2022_da_ar/formal_closure/diagnostics/author_v13_warmup_isolation_all531_v2',
            'scheduler_record_at_submission': mask_job_record,
        },
    },
    'source_bindings': {
        'version_1_audit_sha256': digest(v1),
        'version_2_audit_sha256': digest(v2),
        'original_protocol_sha256': digest(protocol),
        'protocol_amendment_01_sha256': digest(amendment),
        'preserved_failed_audit_sha256': digest(failed_audit),
        'preserved_failed_stdout_sha256': digest(failed_stdout),
    },
    'preserved_failed_jobs': {
        '202506': failed_state,
        '202507': dependency_failed_state,
    },
    'resource_boundary': {
        'data_audit_waits_for_complete_evaluation_array': '202222',
        'mask_audit_waits_for_successful_data_audit': data_job,
        'additional_gpu_concurrency_before_202222_finishes': 0,
    },
    'claim_boundary': (
        'Submission proves nothing by itself. The all-531 direct pre-normalization raw-target gate and the '
        'single-mask isolation remain unknown until both immutable jobs complete and their receipts pass.'
    ),
}
receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n', encoding='utf-8')
print(json.dumps(receipt, sort_keys=True))
PY

test -f "$RECEIPT_TEMP"
mv "$RECEIPT_TEMP" "$RECEIPT"
sha256sum "$RECEIPT"
squeue -h -j "$DATA_JOB,$MASK_JOB" -o '%i|%j|%T|%r|%E'
echo "data_job_id=$DATA_JOB"
echo "mask_job_id=$MASK_JOB"
echo "receipt=$RECEIPT"
