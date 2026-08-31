#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/id31-hydrologic-dynamic-tokens/id31_eval_scalar_fix_20260831_v03.tar.gz
EVIDENCE="$ROOT/results/31_hydrologic_dynamic_tokens/_patches/eval_scalar_fix_20260831_seq19"
STAGE="$EVIDENCE/stage"
EXPECTED_PAYLOAD_SHA256=a8cab1267afd6f978b72fa744a1e6c0740ab82065ec62b1e558ac6d4b9b82893
OLD_REGULARIZATION_SHA256=24a1312de194684808ff0f508f89237b758336e026efd27f6f37b30565d5e926
OLD_TEST_SHA256=65dfad4ee9b12dc05f35566b181355520cced3bb8a5aa080ba8175aa45118e2e
NEW_REGULARIZATION_SHA256=e8eb71123f99eecccd0316901ace54bd933f8e3565325696c1e0e11ea2b3b027
NEW_TEST_SHA256=45e497b85dad61f70b882a1ec3359b03d1cba2fed624934d1c03d61a467cb435
EXPECTED_CONFIG_SHA256=1f38ed828fb002a0b967c341d0109ff95ead50a7ad241925c5259343a1521b4e
EXPECTED_REGISTRY_SHA256=a7c99e9788f3d6f134f8087d1723c885d77f23e82ab59cba5a57d909e1460867

test -d "$ROOT/.git"
test -f "$PAYLOAD"
test ! -e "$EVIDENCE"
test "$(sha256sum "$PAYLOAD" | awk '{print $1}')" = "$EXPECTED_PAYLOAD_SHA256"

python - "$PAYLOAD" <<'PY'
import sys
import tarfile

expected = [
    "neuralhydrology/training/regularization.py",
    "test/test_hydrologic_dynamic_token_transformer.py",
]
with tarfile.open(sys.argv[1], "r:gz") as archive:
    members = archive.getmembers()
    names = [member.name for member in members]
    if names != expected:
        raise ValueError(f"Unexpected payload members: {names!r}")
    if not all(member.isfile() for member in members):
        raise ValueError("Every payload member must be a regular file")
print("PAYLOAD_MEMBERS_PASS", names)
PY

mkdir -p "$STAGE" "$EVIDENCE/original"
tar -xzf "$PAYLOAD" -C "$STAGE"
test "$(sha256sum "$STAGE/neuralhydrology/training/regularization.py" | awk '{print $1}')" = \
  "$NEW_REGULARIZATION_SHA256"
test "$(sha256sum "$STAGE/test/test_hydrologic_dynamic_token_transformer.py" | awk '{print $1}')" = \
  "$NEW_TEST_SHA256"

cd "$ROOT"
test "$(sha256sum neuralhydrology/training/regularization.py | awk '{print $1}')" = \
  "$OLD_REGULARIZATION_SHA256"
test "$(sha256sum test/test_hydrologic_dynamic_token_transformer.py | awk '{print $1}')" = \
  "$OLD_TEST_SHA256"
test "$(sha256sum src/hydrologic_dynamic_tokens/configs/learned_end_to_end_s100.yml | awk '{print $1}')" = \
  "$EXPECTED_CONFIG_SHA256"
test "$(sha256sum src/hydrologic_dynamic_tokens/registry/experiments.csv | awk '{print $1}')" = \
  "$EXPECTED_REGISTRY_SHA256"

cp --preserve=mode,timestamps neuralhydrology/training/regularization.py \
  "$EVIDENCE/original/regularization.py"
cp --preserve=mode,timestamps test/test_hydrologic_dynamic_token_transformer.py \
  "$EVIDENCE/original/test_hydrologic_dynamic_token_transformer.py"
sha256sum "$EVIDENCE/original/regularization.py" \
  "$EVIDENCE/original/test_hydrologic_dynamic_token_transformer.py" > "$EVIDENCE/original.sha256"

install -m 0644 "$STAGE/neuralhydrology/training/regularization.py" \
  neuralhydrology/training/regularization.py.seq19.tmp
install -m 0644 "$STAGE/test/test_hydrologic_dynamic_token_transformer.py" \
  test/test_hydrologic_dynamic_token_transformer.py.seq19.tmp
mv neuralhydrology/training/regularization.py.seq19.tmp neuralhydrology/training/regularization.py
mv test/test_hydrologic_dynamic_token_transformer.py.seq19.tmp test/test_hydrologic_dynamic_token_transformer.py

test "$(sha256sum neuralhydrology/training/regularization.py | awk '{print $1}')" = \
  "$NEW_REGULARIZATION_SHA256"
test "$(sha256sum test/test_hydrologic_dynamic_token_transformer.py | awk '{print $1}')" = \
  "$NEW_TEST_SHA256"
test "$(sha256sum src/hydrologic_dynamic_tokens/configs/learned_end_to_end_s100.yml | awk '{print $1}')" = \
  "$EXPECTED_CONFIG_SHA256"
test "$(sha256sum src/hydrologic_dynamic_tokens/registry/experiments.csv | awk '{print $1}')" = \
  "$EXPECTED_REGISTRY_SHA256"

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final

python -m pytest -q \
  test/test_hydrologic_dynamic_token_transformer.py::test_dynamic_token_count_regularization_remains_scalar_during_evaluation \
  2>&1 | tee "$EVIDENCE/regression_test.log"

python -m pytest -q \
  test/test_hydrologic_dynamic_token_transformer.py \
  test/test_hydrologic_dynamic_tokenizer.py \
  test/test_hydrologic_dynamic_token_configs.py \
  test/test_modern_transformer_moe.py \
  2>&1 | tee "$EVIDENCE/focused_tests.log"

python -m src.hydrologic_dynamic_tokens.scripts.audit_configs \
  2>&1 | tee "$EVIDENCE/config_audit.log"

python - <<'PY' | tee "$EVIDENCE/source_integrity_DL01.json"
import json
from src.hydrologic_dynamic_tokens.scripts.run_development import capture_source_integrity

print(json.dumps(capture_source_integrity("DL01"), indent=2, sort_keys=True))
PY

sha256sum \
  neuralhydrology/training/regularization.py \
  test/test_hydrologic_dynamic_token_transformer.py \
  src/hydrologic_dynamic_tokens/configs/learned_end_to_end_s100.yml \
  src/hydrologic_dynamic_tokens/registry/experiments.csv \
  "$PAYLOAD" > "$EVIDENCE/deployed.sha256"

date -Is > "$EVIDENCE/DEPLOYMENT_COMPLETE"
echo "ID31_EVAL_SCALAR_FIX_DEPLOYMENT_PASS"
