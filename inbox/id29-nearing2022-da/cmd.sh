#!/bin/bash
# ID29 seq=192: one-factor scheduler-resource correction for the repeated partial numerical audit.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
AUDITOR="$ROOT/src/29_nearing2022_da_ar/scripts/audit_partial_registered_results.py"
FAILED_WRAPPER="$ROOT/src/29_nearing2022_da_ar/hpc/run_partial_registered_results_audit.slurm"
PREFLIGHT="$ROOT/results/29_nearing2022_da_ar/formal_closure/partial_registered_results_audit_slurm_preflight_20260811.json"
WRAPPER="$ROOT/src/29_nearing2022_da_ar/hpc/run_partial_registered_results_audit_attempt2.slurm"
TEST="$ROOT/test/test_nearing2022_partial_audit_attempt2_slurm.py"
AMENDMENT="$ROOT/results/29_nearing2022_da_ar/formal_closure/partial_registered_results_audit_resource_amendment_01_20260811.json"
FAILED_FINAL="$DIAGNOSTIC_ROOT/partial_numerical_audit_seq191_v1"
FAILED_RECEIPT="$DIAGNOSTIC_ROOT/partial_numerical_audit_seq191_submission.json"
FINAL="$DIAGNOSTIC_ROOT/partial_numerical_audit_seq192_v1"
SUBMISSION_RECEIPT="$DIAGNOSTIC_ROOT/partial_numerical_audit_seq192_submission.json"
TMP=
trap 'test -z "$TMP" || rm -f "$TMP"' EXIT

deploy_gzip() {
  target=$1
  expected_bytes=$2
  expected_sha=$3
  mkdir -p "$(dirname "$target")"
  if test -e "$target"; then
    test -f "$target"
    test ! -L "$target"
    test "$(stat -c '%s' "$target")" = "$expected_bytes"
    test "$(sha256sum "$target" | awk '{print $1}')" = "$expected_sha"
    echo "already_matching|$target"
    return
  fi
  TMP="$target.tmp.seq192.$$"
  test ! -e "$TMP"
  base64 --decode | gzip -dc > "$TMP"
  test "$(stat -c '%s' "$TMP")" = "$expected_bytes"
  test "$(sha256sum "$TMP" | awk '{print $1}')" = "$expected_sha"
  chmod 0644 "$TMP"
  ln "$TMP" "$target"
  rm -f "$TMP"
  TMP=
  test -f "$target"
  test ! -L "$target"
  test "$(sha256sum "$target" | awk '{print $1}')" = "$expected_sha"
  echo "deployed_additively|$target"
}

echo "=== PRESERVED ATTEMPT-1 FAILURE GATE ==="
date --iso-8601=seconds
test -f "$AUDITOR"
test -f "$FAILED_WRAPPER"
test -f "$PREFLIGHT"
test ! -L "$AUDITOR"
test ! -L "$FAILED_WRAPPER"
test ! -L "$PREFLIGHT"
test "$(stat -c '%s' "$AUDITOR")" = 9859
test "$(sha256sum "$AUDITOR" | awk '{print $1}')" = 7c99332b785a2a088961b51e6085fada72294ce4f8e98ed05663818660f35725
test "$(stat -c '%s' "$FAILED_WRAPPER")" = 4483
test "$(sha256sum "$FAILED_WRAPPER" | awk '{print $1}')" = f8aa12391c58358b943ff14f7599a82bdc99952a1b3c4855d23c3578c481963c
test "$(stat -c '%s' "$PREFLIGHT")" = 3691
test "$(sha256sum "$PREFLIGHT" | awk '{print $1}')" = a1159f0896685c799ec3a3f4a8dc38e8177cecf26eb5754de8e44743fd7443fc
test ! -e "$FAILED_FINAL"
test ! -e "$FAILED_RECEIPT"
test "$(find "$DIAGNOSTIC_ROOT" -maxdepth 1 -name 'partial_numerical_audit_seq191_v1.preparing-*' -print -quit)" = ""
test "$(squeue -h -n N22-partial-audit -o '%i')" = ""

echo "=== ATTEMPT-2 PRE-SUBMISSION GATE ==="
test ! -e "$FINAL"
test ! -e "$SUBMISSION_RECEIPT"
test "$(find "$DIAGNOSTIC_ROOT" -maxdepth 1 -name 'partial_numerical_audit_seq192_v1.preparing-*' -print -quit)" = ""
test "$(squeue -h -n N22-part-audit2 -o '%i')" = ""

deploy_gzip "$WRAPPER" \
  4481 5c5598b6644693f4993339d79f219824a2415493889f27a9e0e45fe3de8ec724 <<'PAYLOAD'
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
PAYLOAD

deploy_gzip "$TEST" \
  1718 4feffd3efa7963e0d14dfb0e94642d5aca3cff36253b09f091898509d72253d1 <<'PAYLOAD'
H4sIAAAAAAACCp1V32/TMBB+z19hmYclUlNIEBOb1IeyFYaEaNUVgQTIchOnsRQ7mX+MFcT/ztlJllZqUbe+9Oy7++67+64uF02tDCqpLiu+DgpVC9RQ4w6It74FHIMgWM4Wc7Kcz1do4q9CQgpeMUKisWK6ru5ZGI0bqpg0+nvyM5h+uf64mi8hesh8ibBWGXbf6QWRjCouN+mrNCU5JVR5h84Ub4z2NrU5NwRADacVUWzDtWGK5WBqWxk9brY4eD/9+Gl2Tb4up4vFzNULAwSfp1UtmzZAWfmfesQTGuvKKoGDKDha05+6ur19sHbvdPV7+xQOhBrDRGPSgUwQ5KxAhunBSbKSyg3TpJbVlggmarUFnDvrg2ROOAhHDa8l4TkIx802jC49j4KCuDl0tj9e0JrmxLAHEzKZ1Tl0M8HWFPFbHPm8vjRknpoiayVoxX/7co99KdZUNGMh/pymsRtH7BtP8Qg9XsGE2ttDSMPhEcsHuc+zZjx6Wvpe1mn8sGZ3yYVv0VsJjgYfAg9yLjASdGLHZ1iAkOv6gWgnu8wYvnRAo7MROuJLRmedlFoz+P3vlph0ezGwenH7brq6ukFxDOs1Sc4//JCOIz68j1bDMuqsZLmtmCIQQGFg/Wa6jZTsF6mtaazpN9FtzhO2qWO9TwxDFwZx6cH2wnoVpRVM8QysVvtWCXKf4INpgNrOLu5n5+WBay65sCLOatFUzMD162MIG1iXyaaxx8npNTVZedyvBIpVse8/NPY1l7kmVrbPQd62WCvinv3njnkHAtK6P5CxLmn65jzsHv8WZb0FNmEUjUv2kHN4jkDa3TYKPPu2mF2t4JXp8sjtzRRgJn92q/wd5vgPWr5vF7YGAAA=
PAYLOAD

deploy_gzip "$AMENDMENT" \
  4952 86b2018066cc5676d2759b1dd19cf3a34d4bb62fd013602d9d2aa63dc857eee4 <<'PAYLOAD'
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
PAYLOAD

echo "=== EXACT PAYLOAD AND STATIC GATE ==="
sha256sum "$AUDITOR" "$FAILED_WRAPPER" "$PREFLIGHT" "$WRAPPER" "$TEST" "$AMENDMENT"
bash -n "$WRAPPER"
test "$(grep -c '^#SBATCH --mem' "$WRAPPER" || true)" -eq 0
test "$(grep -c '^#SBATCH --gres=gpu' "$WRAPPER" || true)" -eq 0
grep -Fq 'partial_numerical_audit_seq192_v1' "$WRAPPER"
grep -Fq -- '--mailbox-sequence 192 --minimum-complete 13' "$WRAPPER"

echo "=== SUBMIT ISOLATED CPU AUDIT ATTEMPT 2 ==="
RAW_JOB_ID=$(sbatch --parsable "$WRAPPER")
JOB_ID=${RAW_JOB_ID%%;*}
test "$(printf '%s' "$JOB_ID" | tr -cd '0-9')" = "$JOB_ID"
test -n "$JOB_ID"
export JOB_ID SUBMISSION_RECEIPT AUDITOR FAILED_WRAPPER PREFLIGHT WRAPPER TEST AMENDMENT
python - <<'PY'
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path

root = Path('/data1/home/sunyiq/nearing2022_da')
receipt = Path(os.environ['SUBMISSION_RECEIPT'])
if receipt.exists():
    raise FileExistsError(f'Refusing to overwrite submission receipt: {receipt}')


def record(environment_name):
    path = Path(os.environ[environment_name])
    payload = path.read_bytes()
    return {
        'path': path.relative_to(root).as_posix(),
        'bytes': len(payload),
        'sha256': hashlib.sha256(payload).hexdigest(),
    }


payload = {
    'schema': 'nearing2022-partial-registered-results-audit-submission-v2',
    'created_at': datetime.now().astimezone().isoformat(timespec='seconds'),
    'mailbox_sequence': 192,
    'slurm_job_id': os.environ['JOB_ID'],
    'sbatch_command': (
        'sbatch --parsable '
        'src/29_nearing2022_da_ar/hpc/run_partial_registered_results_audit_attempt2.slurm'
    ),
    'dependencies': [],
    'minimum_complete_coordinates': 13,
    'single_factor_change': {
        'before': '#SBATCH --mem=16G',
        'after': 'scheduler default memory',
        'scientific_code_changed': False,
    },
    'preserved_attempt_1_failure': {
        'mailbox_sequence': 191,
        'command_commit': '9d725b386bdcf0eb5a5503db684edfdd8c4ff413',
        'result_commit': '72c372da5d2c8fcd3152016b2efbd848d44df0f6',
        'result_bytes': 1684,
        'result_sha256': '742336f2df4b665cc9c9a3edd4125da1456247464dca28b92414e3729c0d48e5',
        'job_created': False,
        'submission_receipt_written': False,
        'audit_output_written': False,
        'scheduler_error': 'Memory specification can not be satisfied',
    },
    'gpu_requested': False,
    'registered_matrix_modified': False,
    'frozen_acceptance_modified': False,
    'files': [
        record(name)
        for name in ('AUDITOR', 'FAILED_WRAPPER', 'PREFLIGHT', 'WRAPPER', 'TEST', 'AMENDMENT')
    ],
}
temporary = receipt.with_name(f'{receipt.name}.tmp-seq192-{os.getpid()}')
if temporary.exists():
    raise FileExistsError(f'Refusing stale receipt temporary path: {temporary}')
temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8')
os.link(temporary, receipt)
temporary.unlink()
print(json.dumps(payload, sort_keys=True))
PY

test -f "$SUBMISSION_RECEIPT"
test ! -L "$SUBMISSION_RECEIPT"
sha256sum "$SUBMISSION_RECEIPT"
scontrol show job -o "$JOB_ID"

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "partial_audit_attempt2_job_id=$JOB_ID"
echo "gpu_requested=false"
echo "registered_matrix_modified=false"
echo "frozen_acceptance_modified=false"
