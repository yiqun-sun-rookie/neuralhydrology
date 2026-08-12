#!/bin/bash
# ID29 seq=271: deploy and submit the 21-coordinate isolated numerical audit.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
WRAPPER_REL=src/29_nearing2022_da_ar/hpc/run_partial_registered_results_audit_seq271.slurm
TEST_REL=test/test_nearing2022_partial_audit_seq271_slurm.py
PREFLIGHT_REL=results/29_nearing2022_da_ar/formal_closure/partial_registered_results_audit_seq271_preflight_20260812.json
WRAPPER_SHA=a189ff5d925032fa2f3b19ea50d83e36e2ba5f22579478c0118914049fd41833
TEST_SHA=8d2b4f60762b853b03123db2cbe5ad720f6d52bb1c8fc4184640fe2a537b9da4
PREFLIGHT_SHA=636b557d81352c02d9062d3a0f777795cb52022980d683791aeabe64172c795f
AUDITOR_SHA=7c99332b785a2a088961b51e6085fada72294ce4f8e98ed05663818660f35725
REGISTRY_SHA=37b312dbd362399a9771f2233d1e1139ea25d5339d1bbc7a806fa75be30b9215
ACCEPTANCE_SHA=6125cab8935c3ad0ab498865c661c47ea83c837c7627dff2534ba5a5b9185895
FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq271_v1"

deploy_payload() {
  relative=$1
  expected=$2
  target="$ROOT/$relative"
  temporary="$target.preparing-seq271"
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
H4sIAAAAAAAACsVWS2/jNhC+61ewbIHYQOTKQjabLKqDm2g3AYKNYbsPwDAImhxJXEiUlqQ2cYv+90KiFNux7Gh76UniPL55cGY4IityZVBCdZKKtSPs8YvOpROpPEMFNRUDNYwpNYnjOLNw+khmj48LFNSkASGRSIGQ4UiBztNvMBiOCqpAGr0cr5zJb7f3i8cZCtBW82eEtWK4+vrXRAJVQsa+5/uEU0JVzdBMicLo+p+WXBhSUGUETYmCWGgDCjhRoMvU6FGxwc50Ft6GN+F8XhsbOAihrcn61Jht/ztNt8yk2AqqUp4wTqx3Gr76F9cjnZYqw87Q+WM2mU7D/82V9+OtK9NZ+PHh/tPd4rgzDUA/h6JcZTQlLM11qeCF3NMvUiiIUhEnhvief+ldjf1RVXSVp47DIUIG9IswS6iMQZNcphsiOEgjzIYYqmIwhEpOWJ4VKRggLC+lGQw/1O4UCjgw0DpXVZ1uS2OkgHJi4NkMQLKcCxkHuDSRe4WHtSYrVVW7KEDNDb6pIet0iL+Ao6BVHykoUspggH+c/zpZ3Nwh1/2Sr11JMwg++75bJcut0zL28Dl6W+y6y9r2sDVYqYW/Tx7cxdy9nbgP3pW7CD3Pc+e1oQP2hbsIx5bd04K9mgrMFn1fPdfNqEjX+bOr4WsJkgFqcLo4vXHPcKNMWmX8oQI+O0fdrIvrs54eR/AECpmESuTXju4SeucrBTlom0NwPUS/NGhdjN6orpsJKbIyc9sWaFC7GH1Rz2ynjpd4p69yxYWkBjRe1a5Xie0h5/XNsoJYgdbA0RrS/KkJ44DaxkC1BmX2YIPdhu+YIkITVpR2iERU2NkFvB4g8MzSkoMmMi7H3kU7QaqG/44h0Di108cNbmBhMRKyxjwinUGGkczNG2JVSoK4KI/KVueRHYVH+g11F86wyqK/C3Wsr87PugyfVflGPyAXEP7p4/3nyQPulHt5JmSZgRKMpvuvw7dxd6r0mhqWHM+RypCron3+YSGsheSamARIKe3Twl87kqv/WgJWm1QLFQravWqkE+q/uxw0e5BFWW8M6MFwOErgmYsYtBnslVGEwz+n4c0ivCWNHpnfTfx3l8Hfu1b+wSdC3T6z26CFZAoykIamxCgRx6DqHtBMVC9rJBhZ56XkVG12XlILg4J6NxylOeV68LJTnEqLjakxhIIt1hI3RLzaK15LXB4W3qquzvdep7TdBqzMyeevU3tnXTkyyyrTY7sc1CWzH4kWMk6BRJRV12Il9sOytCXemVGnTHlduk3Lvu3iKz3KeR3YK+HlyTxZ7wu6qe96P9yWuh/i9xZ7PbIbpKXd73OFV0tsAU6C7/Xj2+BPihYFHIK3hf7qNg87Yd+ZlrrEB3OjuXyOV0ho9JGmGro1MzBKMN1bnjIGhaGSATGJAp3kKe+vvVPgGTVKPHdp/gvFdp1uDQ4AAA==
B64

deploy_payload "$PREFLIGHT_REL" "$PREFLIGHT_SHA" <<'B64'
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
B64

test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/scripts/audit_partial_registered_results.py" | awk '{print $1}')" = "$AUDITOR_SHA"
test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/registry/evaluation_registry.csv" | awk '{print $1}')" = "$REGISTRY_SHA"
test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/reference/reproduction_acceptance.json" | awk '{print $1}')" = "$ACCEPTANCE_SHA"
test ! -e "$FINAL"
test "$(find "$(dirname "$FINAL")" -maxdepth 1 -name 'partial_numerical_audit_seq271_v1.preparing-*' -print -quit)" = ""
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
assert preflight["trigger"]["mailbox_sequence"] == 270
assert preflight["trigger"]["target"] == "N22-EVAL-TS-DA-L08-TE000-S0"
assert preflight["trigger"]["registered_complete_coordinates"] == 21
assert preflight["single_factor_change"]["predecessor_complete_coordinates"] == 20
assert preflight["single_factor_change"]["minimum_complete_coordinates"] == 21
assert preflight["single_factor_change"]["added_coordinates"] == [
    "N22-EVAL-TS-DA-L08-TE000-S0"
]
assert preflight["single_factor_change"]["excluded_nodes"] == ["ngu104"]
assert preflight["single_factor_change"]["other_scheduler_resources_changed"] is False
assert preflight["execution_contract"]["minimum_complete_coordinates"] == 21
assert preflight["scientific_boundary"]["numerical_auditor_changed"] is False
assert preflight["scientific_boundary"]["acceptance_thresholds_changed"] is False
wrapper = (root / sys.argv[2]).read_text(encoding="utf-8")
assert "#SBATCH --exclude=ngu104" in wrapper
assert wrapper.count("--mailbox-sequence 271 --minimum-complete 21") == 2
assert "#SBATCH --gres=gpu" not in wrapper and "#SBATCH --mem" not in wrapper
parts = wrapper.split("<<'PY'\n")
blocks = []
for part in parts[1:]:
    block, marker, _ = part.partition("\nPY\n")
    assert marker
    compile(block, "<seq271-slurm-heredoc>", "exec")
    blocks.append(block)
assert len(blocks) == 2
print(json.dumps({
    "deployment_hashes_verified": 3,
    "compiled_python_heredocs": len(blocks),
    "excluded_node": "ngu104",
    "minimum_complete_coordinates": 21,
}, sort_keys=True))
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
