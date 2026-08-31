#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
EVIDENCE="$ROOT/results/31_hydrologic_dynamic_tokens/_patches/eval_scalar_fix_validation_20260831_seq20"
SEQ19_EVIDENCE="$ROOT/results/31_hydrologic_dynamic_tokens/_patches/eval_scalar_fix_20260831_seq19"
FAILED_MANIFEST="$ROOT/results/31_hydrologic_dynamic_tokens/_invocations/id31_DL01_s100_slurm215880/run_manifest.json"
EXPECTED_FAILED_MANIFEST_SHA256=31a5978ab9169b96e23d034b519669c87798b4be54adff83a31c7883fe770350
EXPECTED_REGULARIZATION_SHA256=e8eb71123f99eecccd0316901ace54bd933f8e3565325696c1e0e11ea2b3b027
EXPECTED_TEST_SHA256=45e497b85dad61f70b882a1ec3359b03d1cba2fed624934d1c03d61a467cb435
EXPECTED_CONFIG_SHA256=1f38ed828fb002a0b967c341d0109ff95ead50a7ad241925c5259343a1521b4e
EXPECTED_REGISTRY_SHA256=a7c99e9788f3d6f134f8087d1723c885d77f23e82ab59cba5a57d909e1460867

test -d "$ROOT/.git"
test -d "$SEQ19_EVIDENCE/original"
test ! -e "$EVIDENCE"
mkdir -p "$EVIDENCE"
cd "$ROOT"

test "$(sha256sum neuralhydrology/training/regularization.py | awk '{print $1}')" = \
  "$EXPECTED_REGULARIZATION_SHA256"
test "$(sha256sum test/test_hydrologic_dynamic_token_transformer.py | awk '{print $1}')" = \
  "$EXPECTED_TEST_SHA256"
test "$(sha256sum src/hydrologic_dynamic_tokens/configs/learned_end_to_end_s100.yml | awk '{print $1}')" = \
  "$EXPECTED_CONFIG_SHA256"
test "$(sha256sum src/hydrologic_dynamic_tokens/registry/experiments.csv | awk '{print $1}')" = \
  "$EXPECTED_REGISTRY_SHA256"
test "$(sha256sum "$FAILED_MANIFEST" | awk '{print $1}')" = \
  "$EXPECTED_FAILED_MANIFEST_SHA256"

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final

python - <<'PY' | tee "$EVIDENCE/eval_mode_regression.json"
import json

import torch

from neuralhydrology.modelzoo import get_model
from neuralhydrology.training import get_loss_obj, get_regularization_obj
from neuralhydrology.utils.config import Config
from src.hydrologic_dynamic_tokens.scripts.run_smoke import _synthetic_batch

config = Config("src/hydrologic_dynamic_tokens/configs/learned_end_to_end_s100.yml")
device = torch.device("cpu")
data, shape_contract = _synthetic_batch(config, device)
model = get_model(config).to(device)
model.eval()
regularizers = get_regularization_obj(config)
loss = get_loss_obj(config).to(device)
loss.set_regularization_terms(regularizers)

with torch.no_grad():
    output = model(data)
    regularization_value = regularizers[0]({}, {}, output)
    total_loss, components = loss(output, data)

checks = {
    "full_shape_batch": shape_contract == {
        **shape_contract,
        "batch_size": 4,
        "sequence_length_days": 270,
        "dynamic_input_count": 5,
        "static_attribute_count": 27,
    },
    "diagnostic_shape_is_length_one": list(output["dynamic_token_count_loss"].shape) == [1],
    "regularization_is_scalar": regularization_value.ndim == 0,
    "regularization_component_is_scalar": components["dynamic_token_count"].ndim == 0,
    "total_loss_is_scalar": total_loss.ndim == 0,
    "total_loss_is_finite": bool(torch.isfinite(total_loss).item()),
}
if not all(checks.values()):
    raise AssertionError(checks)
report = {
    "status": "PASS",
    "mode": "evaluation",
    "device": str(device),
    "checks": checks,
    "diagnostic_shape": list(output["dynamic_token_count_loss"].shape),
    "regularization_shape": list(regularization_value.shape),
    "component_shape": list(components["dynamic_token_count"].shape),
    "total_loss_shape": list(total_loss.shape),
    "total_loss": float(total_loss.item()),
    "shape_contract": shape_contract,
}
print(json.dumps(report, indent=2, sort_keys=True))
PY

python -m src.hydrologic_dynamic_tokens.scripts.audit_configs \
  2>&1 | tee "$EVIDENCE/config_audit.log"

python - <<'PY' | tee "$EVIDENCE/source_integrity_DL01.json"
import json
from src.hydrologic_dynamic_tokens.scripts.run_development import capture_source_integrity

print(json.dumps(capture_source_integrity("DL01"), indent=2, sort_keys=True))
PY

squeue -u sunyiq -h -o '%i|%j|%T|%R' | tee "$EVIDENCE/squeue_before_retry.txt"
if squeue -u sunyiq -h -o '%j' | grep -Fxq 'id31_development'; then
  echo "A concurrent ID31 development job is already present" >&2
  exit 1
fi

sha256sum "$FAILED_MANIFEST" > "$EVIDENCE/failed_manifest.sha256"
find results/31_hydrologic_dynamic_tokens/DL01 -maxdepth 3 -type f \
  -printf '%TY-%Tm-%TdT%TH:%TM:%TS%Tz %s %p\n' | sort > "$EVIDENCE/failed_run_inventory.txt"
sha256sum \
  neuralhydrology/training/regularization.py \
  test/test_hydrologic_dynamic_token_transformer.py \
  src/hydrologic_dynamic_tokens/configs/learned_end_to_end_s100.yml \
  src/hydrologic_dynamic_tokens/registry/experiments.csv > "$EVIDENCE/validated.sha256"

date -Is > "$EVIDENCE/VALIDATION_COMPLETE"
echo "ID31_EVAL_SCALAR_FIX_VALIDATION_PASS"
