#!/bin/bash
# ID29 seq=231: deploy the compute-node role-recorded isolated audit and submit it CPU-only.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
WRAPPER_REL=src/29_nearing2022_da_ar/hpc/run_partial_registered_results_audit_seq231.slurm
TEST_REL=test/test_nearing2022_partial_audit_seq231_slurm.py
PREFLIGHT_REL=results/29_nearing2022_da_ar/formal_closure/partial_registered_results_audit_seq231_preflight_20260811.json
WRAPPER_SHA=f26dd4c5c5b2dd16d64688a44902c5bd1e948c0f96e7912cb75f86cd31f40e43
TEST_SHA=5ee30a1a8fae756e563cbfdb8a78e1068ec260307a6fb89f1cf061de498ba1d5
PREFLIGHT_SHA=708a997c58b5ade928c027c351107c20a01188dd4e8f83dddd432a9ac17ae37c
AUDITOR_SHA=7c99332b785a2a088961b51e6085fada72294ce4f8e98ed05663818660f35725
FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq231_v1"

deploy_payload() {
  relative=$1
  expected=$2
  target="$ROOT/$relative"
  temporary="$target.preparing-seq231"
  mkdir -p "$(dirname "$target")"
  test ! -L "$target"
  if test -e "$target"; then
    cat >/dev/null
    test -f "$target"
    test "$(sha256sum "$target" | awk '{print $1}')" = "$expected"
    echo "already_exact=$relative"
    return
  fi
  test ! -e "$temporary"
  base64 -d | gzip -d > "$temporary"
  test "$(sha256sum "$temporary" | awk '{print $1}')" = "$expected"
  mv "$temporary" "$target"
  test "$(sha256sum "$target" | awk '{print $1}')" = "$expected"
  echo "deployed=$relative"
}

deploy_payload "$WRAPPER_REL" "$WRAPPER_SHA" <<'B64'
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
B64

deploy_payload "$TEST_REL" "$TEST_SHA" <<'B64'
H4sIAAAAAAAACqVWXW/bNhR916/guACWgcm1lSXIiurBa5wlWNAYjrcOMAKCFq8kDhKp8lJZvGH/fZAo+aOVvax7snx5zrmfvJIsSm0syThmuVx70v39HbXyEqMLUnJbH5D2YM5t5nneYjZ/YIuHhyWJGpPPWCJzYGw4MoA6fwZ/OCq5AWVxNXnypr9c3y0fFiQiO+YbQtHEtP4Nf2AKuJEqDcdhyARn3DQHGBtZWmyeeSWkZSU3VvKcGUglWjAgmAGscoujckO9j4vpfD6rHfkeIWTnrvnXuuyee912h1m5A5pKnXDMXGQIn8LzyQjzyhTUG3rzxezm/u6n2+XxYFqB1wWUaFPwnMW5xsrA1vzKuFhpIMllmlkWjsPL8dVkMqq7XEfqeQISYgG3YAOxNgJZrIuyssCUFsCMzgHZGhJtgKmqACNjnjOMdR2xP3zbhGThxZKItI0YGeCC1TYfVKyFVGlEK5sEV3TYwFHxEjNdU2rUSCoBL/6Ann18WPz8pnbJOoiLd+B4iTRoXYafUcuNzbQi9Kwduo7BEcHYncN3+xr7iG1J6+xzsMBiXSlLiVSNowNs245XYTvdQqoKt408KeugLbEXOpAJyUH5nbgUOCTvyOTq7eAYXGlLSr7JNRcrarlJYXevujzo0x7/ywEpDSCYZ0BmM2CJ0X+C2puJAmymBeNKMJsZwEznAr9yQpr+aMPqFUWiblONMOPhxaXfNtmprDcW0B8ORxm8CJkCWv+g9wmd/TafvV/OrlnLY4+30/DiMvpr38vfvYVuZqzprk+DoOAyX+uXAOFTBSoGEp5PSBAUUsmiKoKujGRyRYckikh40ATa0llHp29rge8GJ+dmV9+Dm/08oSc6JZHFZcW0yjeMCyGtfIamMQmXbpuA+NrOtPF9+/jjdPn+tk4fCtqMV18aO1hqAKO0rI5iB3UG5BsSAKFnN3cfpve0vzS45jbOjvs0BQlMctxP8UzcqqE9jnrHvl2ia6mEG/5mRwnJU6VRYlNajCUoKxMZM6nKym5Hf8snUfOOHdV3EP3tq+JUyV3NrZFpCoZEO60VbY306WBenXH15aw9NQN5Pu5Fu33gMPRDGAazX6f3wfIxuJ4G9+Pvg+VsfDEOHse0l92zOrURUnEL6DQnV73Enj36OmJT/vb2IuOpgTpBiWRpKnBFd6sOD2vWWQ+L9l+3Sx1Yp7Rynyja0KcVdQInxQ+u2b+L/2F4WcJR8XKX2t74rXWlBDebmvXZ+tCGxRlXKQhXrxueoyvYqxV5HENpuYphb83/b9W9L5mCWyNf+hT/ATL/PNe4CgAA
B64

deploy_payload "$PREFLIGHT_REL" "$PREFLIGHT_SHA" <<'B64'
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
B64

test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/scripts/audit_partial_registered_results.py" | awk '{print $1}')" = "$AUDITOR_SHA"
test ! -e "$FINAL"
test "$(find "$(dirname "$FINAL")" -maxdepth 1 -name 'partial_numerical_audit_seq231_v1.preparing-*' -print -quit)" = ""
bash -n "$ROOT/$WRAPPER_REL"

python - "$ROOT" "$WRAPPER_REL" "$TEST_REL" "$PREFLIGHT_REL" "$WRAPPER_SHA" "$TEST_SHA" "$PREFLIGHT_SHA" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
rows = list(zip(sys.argv[2:5], sys.argv[5:8]))
for relative, expected in rows:
    path = root / relative
    assert path.is_file() and not path.is_symlink()
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected
preflight = json.loads((root / sys.argv[4]).read_text(encoding="utf-8"))
assert preflight["trigger"]["mailbox_sequence"] == 230
assert preflight["trigger"]["partial_complete_coordinates"] == 18
assert preflight["trigger"]["closure_complete_coordinates"] == 18
assert preflight["trigger"]["role_auditors_agree"] is True
assert preflight["execution_contract"]["compute_node_role_snapshot_before_scoring"] is True
assert preflight["execution_contract"]["minimum_complete_coordinates"] == 18
assert preflight["scientific_boundary"]["numerical_auditor_changed"] is False
assert preflight["scientific_boundary"]["acceptance_thresholds_changed"] is False
wrapper = (root / sys.argv[2]).read_text(encoding="utf-8")
assert wrapper.count("--mailbox-sequence 231 --minimum-complete 18") == 2
assert "role_snapshot.json" in wrapper
assert "#SBATCH --gres=gpu" not in wrapper and "#SBATCH --mem" not in wrapper
print(json.dumps({"deployment_hashes_verified": 3, "minimum_complete": 18}, sort_keys=True))
PY

JOB_ID=$(sbatch --parsable "$ROOT/$WRAPPER_REL")
case "$JOB_ID" in
  ''|*[!0-9]*) echo "Invalid Slurm job id: $JOB_ID" >&2; exit 1 ;;
esac
echo "submitted_job_id=$JOB_ID"
scontrol show job -o "$JOB_ID"
sacct -n -X -P -j "$JOB_ID" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Reason
echo "registered_matrix_modified=false"
echo "frozen_acceptance_modified=false"
