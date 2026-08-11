#!/bin/bash
# ID29 seq=245: deploy and submit the 19-coordinate isolated numerical audit.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
WRAPPER_REL=src/29_nearing2022_da_ar/hpc/run_partial_registered_results_audit_seq245.slurm
TEST_REL=test/test_nearing2022_partial_audit_seq245_slurm.py
PREFLIGHT_REL=results/29_nearing2022_da_ar/formal_closure/partial_registered_results_audit_seq245_preflight_20260812.json
WRAPPER_SHA=d7ef273661f33d9e327dbd8e22a6d5abcd522f4546842aeb4936d0c947cd9836
TEST_SHA=9d4ca1d30615113e06d38fbe6da84cfa20d3a31148eaad30a4c59e864f18c7bd
PREFLIGHT_SHA=23a3dbb7890240c6e1c227f249382db578049c368220c004cea110bbff54763c
AUDITOR_SHA=7c99332b785a2a088961b51e6085fada72294ce4f8e98ed05663818660f35725
REGISTRY_SHA=37b312dbd362399a9771f2233d1e1139ea25d5339d1bbc7a806fa75be30b9215
ACCEPTANCE_SHA=6125cab8935c3ad0ab498865c661c47ea83c837c7627dff2534ba5a5b9185895
FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq245_v1"

deploy_payload() {
  relative=$1
  expected=$2
  target="$ROOT/$relative"
  temporary="$target.preparing-seq245"
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
H4sIAAAAAAAACsVW3W/iOBB/z1/h850ESA0HWdptV5cHrqXbStUWAfchIWQZe5J4lThZ29mWO+3/vkqcFCiBZu/lnhLPx28+PDMekWSpMiiiOorF2hH2+Fmn0glUmqCMmoKBKsaUmshxnNlk+khmj48L5JekLiGBiIGQXl+BTuOv0O31M6pAGr0crpzxHzf3i8cZ8tFW81eEtWK4+HpXRAJVQobewPMIp4SqkqGZEpnR5T/NuTAko8oIGhMFodAGFHCiQOex0f1sg53pbHIzuZ7M56WxroMQ2posT5XZ+r/RdM2Msq2gyuUJ48R6p+GL927U13GuEuz0nL9m4+l08r+5MjrfujKdTW4f7j/eLY47UwG0cyhIVUJjwuJU5wpeyC39IpmCIBZhZIg38C4Gl0OvXxRd4anjcAiQAf0izCIqQ9AklfGGCA7SCLMhhqoQDKGSE5YmWQwGCEtzabq9D6U7mQIODLROVVGn29LoK6CcGHg2XZAs5UKGPs5N4F7iXqnJclXULvJRdYNvasgyHeIf4Miv1fsKspgy6OKf57+PF9d3yHU/p2tX0gT8T57nFslyy7Rc4jP0ttT7JmPbw9ZeoTb5c/zgLubuzdh9GIzcxWTw/tydDwpDzezzQcFuacHeTAFma76tnusmVMTr9NnV8CUHyQBVOE2c1rgdXCmTWhl/KIA7Z6iZ9W7UaelxAE+gkImoRMOrwtFdQuP1N6HEILt1bwiue+i3Cq2J0RrVdRMhRZInbt0BFWoToy1qxzbqcIl32ipVXEhqQONV6XqR2BZyl22zrCBUoDVwtIY4farCOKDWMVCtQZk9WH+33xuGiNCEZbmdIQEVdnQBL+cHPLM456CJDPPhYFQPkKLff2AGVE7t9HGF61tYjIQsMY9IJ5BgJFPzhliREj/M8qOyxblvJ+GRfkPNhdMrsujtQh3rq7NOk+FOkW/0E3IB4V9u7z+NH3Cj3MsrIfMElGA03n8cvg6bU6XX1LDoeI5UglwV7PMPC2EtJNfEREByaV8W/tqRVP3XErDapNinkF+vVX0dUe/8olutQRZlvTGgu71eP4JnLkLQprtXRgGe/D2dXC8mN6TSI/O7sXd+4f+7a+UbPhHq9pXdBi0kU5CANDQmRokwBFX2gGaieFgDwcg6zSWnarPzkFoY5JerYT9OKdfdl5XiVFpsTJUh5G+xlrgi4tVe8Vri8rDwVmV1jkaN0nYZsDInn79G7Z1t5cgs8300vLK7QVky+5FoIcMYSEBZcS1WYj8sS1vinRl1ytRlk27Vsm+7+EqPcl4G9kp4eTJP1vuMbsq73g+3pu6H+KPFXo7sCmlp1/tU4dUSW4CT4Hv9+Db4k6JZBofgdaG/us3DTth3pqYu8cHcqC6f4xUSGt3SWEOzZgJGCaZby1PGIDNUMiAmUqCjNObttXcKPKFGiecmze9yV3bPDA4AAA==
B64

deploy_payload "$PREFLIGHT_REL" "$PREFLIGHT_SHA" <<'B64'
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
B64

test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/scripts/audit_partial_registered_results.py" | awk '{print $1}')" = "$AUDITOR_SHA"
test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/registry/evaluation_registry.csv" | awk '{print $1}')" = "$REGISTRY_SHA"
test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/reference/reproduction_acceptance.json" | awk '{print $1}')" = "$ACCEPTANCE_SHA"
test ! -e "$FINAL"
test "$(find "$(dirname "$FINAL")" -maxdepth 1 -name 'partial_numerical_audit_seq245_v1.preparing-*' -print -quit)" = ""
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
assert preflight["trigger"]["mailbox_sequence"] == 244
assert preflight["trigger"]["target"] == "N22-EVAL-TS-DA-L04-TE075-S0"
assert preflight["trigger"]["registered_complete_coordinates"] == 19
assert preflight["single_factor_change"]["predecessor_complete_coordinates"] == 18
assert preflight["single_factor_change"]["minimum_complete_coordinates"] == 19
assert preflight["single_factor_change"]["added_coordinates"] == [
    "N22-EVAL-TS-DA-L04-TE075-S0"
]
assert preflight["single_factor_change"]["excluded_nodes"] == ["ngu104"]
assert preflight["single_factor_change"]["other_scheduler_resources_changed"] is False
assert preflight["execution_contract"]["minimum_complete_coordinates"] == 19
assert preflight["scientific_boundary"]["numerical_auditor_changed"] is False
assert preflight["scientific_boundary"]["acceptance_thresholds_changed"] is False
wrapper = (root / sys.argv[2]).read_text(encoding="utf-8")
assert "#SBATCH --exclude=ngu104" in wrapper
assert wrapper.count("--mailbox-sequence 245 --minimum-complete 19") == 2
assert "#SBATCH --gres=gpu" not in wrapper and "#SBATCH --mem" not in wrapper
parts = wrapper.split("<<'PY'\n")
blocks = []
for part in parts[1:]:
    block, marker, _ = part.partition("\nPY\n")
    assert marker
    compile(block, "<seq245-slurm-heredoc>", "exec")
    blocks.append(block)
assert len(blocks) == 2
print(json.dumps({
    "deployment_hashes_verified": 3,
    "compiled_python_heredocs": len(blocks),
    "excluded_node": "ngu104",
    "minimum_complete_coordinates": 19,
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
