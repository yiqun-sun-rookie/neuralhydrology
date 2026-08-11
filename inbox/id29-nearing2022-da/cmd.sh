#!/bin/bash
# ID29 seq=191: deploy and submit the isolated repeated partial numerical audit.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
FINAL="$DIAGNOSTIC_ROOT/partial_numerical_audit_seq191_v1"
SUBMISSION_RECEIPT="$DIAGNOSTIC_ROOT/partial_numerical_audit_seq191_submission.json"
WRAPPER="$ROOT/src/29_nearing2022_da_ar/hpc/run_partial_registered_results_audit.slurm"
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
  TMP="$target.tmp.seq191.$$"
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

echo "=== PRE-SUBMISSION GATE ==="
date --iso-8601=seconds
test ! -e "$FINAL"
test ! -e "$SUBMISSION_RECEIPT"
test "$(find "$DIAGNOSTIC_ROOT" -maxdepth 1 -name 'partial_numerical_audit_seq191_v1.preparing-*' \
  -print -quit)" = ""
test "$(squeue -h -n N22-partial-audit -o '%i')" = ""

deploy_gzip "$ROOT/src/29_nearing2022_da_ar/scripts/audit_partial_registered_results.py" \
  9859 7c99332b785a2a088961b51e6085fada72294ce4f8e98ed05663818660f35725 <<'PAYLOAD'
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
PAYLOAD

deploy_gzip "$WRAPPER" \
  4483 f8aa12391c58358b943ff14f7599a82bdc99952a1b3c4855d23c3578c481963c <<'PAYLOAD'
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
PAYLOAD

deploy_gzip "$ROOT/test/test_nearing2022_partial_audit_slurm.py" \
  2063 33d26494d886c24e74e1dd1b70f4be8e835b4816feee9c011e475f5a56b85936 <<'PAYLOAD'
H4sIAAAAAAAACp1VbW/bNhD+rl9xIwZULix19tBiCaAPwepgxYba8FJ0wDwQtHSyuEkkcyQTB0H++0BRcuxkadH5g2Xf3XP33KtkZzQ5aIRtWrlNZPwbH63c5t7JNqlJd2CECyaDDlbCNclob+4cWpckyXqxWvL1cnkFRW+Rcl7LFjmf5IRWtzeYTnIjCJWzf87+Si4+vf9wtVxDAY/IN8AslSw852dcoSCpdvMf5nNeCS6oV9iSpHG2/y18JR03gpwULSfcSeuQsOKE1rfO5uaOJZ/XF6vV4tsDNSYakFdfCMF7DrltPXUsSZIKa+CtFlVUaEon5wkAgDVYQvGkvnmQ8lDkWKxWl8JJrVJ2zGmMPnhkUxiKN+k9d7ryLT73HeXRe4iThq8IEdYiuZ5THsgigbSgtIOPWuGB76DLcY8lj+7S+IhuCJ0nNRAYkg/jcMqYC6c7WfJbkg6JE9beouX6BqkXpa4zPMzYUKlDPk/q2Cu1d8Y7KGAEHeYg/9tqxXojI+4CFAq4Z7ZssBPsHJi9U65BJ0s2BXbUyU44kvuQn6wlVuwcLkVr8eGITN4T5SHCkE0aiUzHWCd1jbqcUFTc4d6lqEpdSbUrmHd19hObQFFA2kPC59X9RsFXONWB07S3+6+UNupho171HiOVW+maYTtzEtKiTS9li4u9tM4uiDRNoROubAq2Dh2RagdOw6ErbOjGtxXhxRm4JWEMEpeWS6tb4foVMiic2LbIhaq40orvjB8XJhQOChjW90vFHGbx2kvC0PTHwrLABL6DDGHDvr/88PHitw1j00f9SFL5DkmWB7oWr2dnM34zyw2h6Vcxe30MzLJOyHar95nFa4+qRJidzSDLOqlk57us1J1p0SHMfjzGRfezOKzP5PNn8rIzgfrn5frXN8fYDXsijtDT7KKG0JCufBkOC9/eOeSyQuVCtht2Dlfk8Rj08hRuxtU4iUFO1qJ0vBNK1mHanqbQ3YxUI+nTNpwsjmjbtBP0T7hHKk5ArQkeRWOXT1Asy3aEttgZz/ojNmBPbOw2DPvLeuogo/pU/9Vp3kpVWY77kL/Vnkrk4X36P0d4uHS9CyjGN3NuGzF/+y4dbn70Etpo08kkb3BfyR1aN9zHIZ2aLf5YLX6+WrznA47//svF/O274v44ygM75PovXW+Xiw8IAAA=
PAYLOAD

deploy_gzip \
  "$ROOT/results/29_nearing2022_da_ar/formal_closure/partial_registered_results_audit_slurm_preflight_20260811.json" \
  3691 a1159f0896685c799ec3a3f4a8dc38e8177cecf26eb5754de8e44743fd7443fc <<'PAYLOAD'
H4sIAAAAAAAACp1XyZLbNhC9z1egdI01I24SObnmknN8S6VQTaApwgYBugFohnbl31MARW3W2BkfST6+Rr9e8e2BsZUTPQ6wemYrg0DK7PNNnq9HIK9Arwn3ynkklGtCF7R3awhS+bXTgYb1SNhpte/9+pCtPkQ6QQgeJQcfKfNNvl1v6nWWfcyy5zJ7zpvfNvXzZjODnQcfXAQSgpy4sZ5LHLWdUKYHF9pBeY/yiBd2xAj/00gc0Ug0Xk+M0AlLyPCANDE8gA7glTVMWEtSGfDIXpTvGWjNOrJf0TCyGh0bCR0az156NMz3yP6KbrFPtmXOA3n3gSkjdJDK7NN33yvyiMb3l+SdIueZbR3SASVThg2gdGtfmcMvAY1AljWbx9kJCL63pL6mI/LWBiOBptUz+/bAGItSLJLzATypVz5YqTqFcvXMOtAOIw1jq9kTDkLg6MEIfAuIr8p5Zfb8GFWeQvgWOjlBfIRJW5CneNyiolD8k20vYnSN2I+BU3TfXXx7YOzfpIIaRo0DGp9kOHufjmajed/HSDsST3nDL3KTS+BAT06QGr17mn1ZPLsQ75ivj+OUdL/gbiePMeuaumpuPrke8mobDe9E0xRF3u7qCnLY1HWzzdoqw+2mrjqQsMvzphRYdjU2NcpNtd0WdVZvt5uuqHZ5tboS6qfu9KN4omB+4MgctcfEd02++FOWdXH14exNVwNkedFkoqqLqm6bsui6rOx2VdNAnbdSNE1T5ZC1hSjrqpJ5IYpqV4uyzpptIRaDHp0/ORMfntKbS3+ukywd5CIGCb4cON9si8v35/MWhcy3ZVPKut6KvMRdiZmUWbvbdGWLNdZF1ZZ1tu0QsRGbLMNyV3UVVNu2rppiuzol2rFKlBmDjzb/Pgr0ViBm4Wl6wtcRScUUPQaDpkfhDifpf05wakTvJeiQYtN4mlsF92pA7kYd5Yz14rwS7nH8rN9BRTiSlUGk45xbxuMnZ00U65+lwUYGLqzxBMKf63JQRg1h4MLGwvXIz+0vqpotcWzBKeP4iHSBWD2zqsiOiAE9KXEHsjsCBBipJHjkYGL2H13gBC98JJQqOeFSc1GUeoungD/5ezF7/6+j0jFiGDEgeUd24MfsIdQIDm/+aZ3V4WjITc7jAF4J7q1GiuLeITorf8Ol9TwKuLOBBPJYRB0IHzl6cP3tgaMQKNA5S7wL+lhu8yhN7eJ+QnSWBtBcaOsC4dNSqyYMSEqcqxa/ZLtsTo47Bt9KgvwNLJBysQrsS4TV5R2YMlIdlAygeQdKB0qM1amM8RVFSMn7fW7a4MdwbkvvEUAq2BubCuqHYjQZP244aUJ3waHjp7naKQOaW+Jgplii+3nYpuNcJdk8ZCiY1P1OdCkjXWqLXMWl5mzdXVO8hXUe4hoh+azF7U+fMGaSm4bWaiW4VubzDfELKZ9cWmQmFKhGfxe1JCcfwKgO3Q1qDK1Wrk+n5A4G5J3SOFcIJzQw3GT/3VVh6W1pvXBceYe6+26POICO1X61Qxh84WmeCDsMYCLjapx8bw1bD2yMw8ez9wwvtv6yxH7hdnwE59Jpl9bXWREcyl+wetWcl/yOdu/DX4CGMPIRFL0NIhw1iLRicdGDMvyAFPe9//nPgj6L8IuKLbLcqHbqArHc05vNkmRARpl9qv8lo5KOqZcojWeSy74/qx5zG3mPeryLasH13E3Gw+vd7wO8pjGXWDSafarhLF/OdvGe7+OQuSI5ZaVEodyck6uPPTLC4KDVyMDI+Y6xVs7qeFOKFwyaN2HNTq2HJTmZckxbATpdckBOj+yPtI5HeOICZvCFnbtYuroMMLGRrECU6d5jg2dp2Z/iNea8WbLTkPmdGXthXGhQQzQexjhJJQvGK50uQISg2dxkIoBQ2MPMZaIrl9cy0aP4jPJx9fDvw3/zObU3aw4AAA==
PAYLOAD

echo "=== EXACT PAYLOAD AND STATIC GATE ==="
sha256sum \
  "$ROOT/src/29_nearing2022_da_ar/scripts/audit_partial_registered_results.py" \
  "$WRAPPER" \
  "$ROOT/test/test_nearing2022_partial_audit_slurm.py" \
  "$ROOT/results/29_nearing2022_da_ar/formal_closure/partial_registered_results_audit_slurm_preflight_20260811.json"
bash -n "$WRAPPER"
test "$(grep -c '^#SBATCH --gres=gpu' "$WRAPPER" || true)" -eq 0

echo "=== SUBMIT ISOLATED CPU AUDIT ==="
RAW_JOB_ID=$(sbatch --parsable "$WRAPPER")
JOB_ID=${RAW_JOB_ID%%;*}
test "$(printf '%s' "$JOB_ID" | tr -cd '0-9')" = "$JOB_ID"
test -n "$JOB_ID"
export JOB_ID SUBMISSION_RECEIPT WRAPPER
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


def record(path):
    payload = path.read_bytes()
    return {
        'path': path.relative_to(root).as_posix(),
        'bytes': len(payload),
        'sha256': hashlib.sha256(payload).hexdigest(),
    }


paths = [
    root / 'src/29_nearing2022_da_ar/scripts/audit_partial_registered_results.py',
    Path(os.environ['WRAPPER']),
    root / 'test/test_nearing2022_partial_audit_slurm.py',
    root / (
        'results/29_nearing2022_da_ar/formal_closure/'
        'partial_registered_results_audit_slurm_preflight_20260811.json'
    ),
]
payload = {
    'schema': 'nearing2022-partial-registered-results-audit-submission-v1',
    'created_at': datetime.now().astimezone().isoformat(timespec='seconds'),
    'mailbox_sequence': 191,
    'slurm_job_id': os.environ['JOB_ID'],
    'sbatch_command': 'sbatch --parsable src/29_nearing2022_da_ar/hpc/run_partial_registered_results_audit.slurm',
    'dependencies': [],
    'minimum_complete_coordinates': 13,
    'gpu_requested': False,
    'registered_matrix_modified': False,
    'frozen_acceptance_modified': False,
    'files': [record(path) for path in paths],
}
temporary = receipt.with_name(f'{receipt.name}.tmp-seq191-{os.getpid()}')
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
echo "partial_audit_job_id=$JOB_ID"
echo "gpu_requested=false"
echo "registered_matrix_modified=false"
echo "frozen_acceptance_modified=false"
