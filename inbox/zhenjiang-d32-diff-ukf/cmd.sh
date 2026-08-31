#!/bin/bash
set -euo pipefail

EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r2"
TRAINING_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
RUN_ROOT="${EVALUATION_ROOT}/run"
TRAINING_RUN_ROOT="${TRAINING_ROOT}/run"
INPUT_ROOT="${TRAINING_ROOT}/inputs/pre2024-v1"
TIDE_MODEL="${TRAINING_RUN_ROOT}/results/modeling/wusongkou_astronomical_tide_v1_validation/tide_model.json"

export PYTHONDONTWRITEBYTECODE=1
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
cd "${RUN_ROOT}"
export PYTHONPATH="${TRAINING_RUN_ROOT}/scripts/modeling:${RUN_ROOT}/scripts/analysis:${TRAINING_RUN_ROOT}/scripts/astronomical_tide:${TRAINING_RUN_ROOT}/third_party:${PYTHONPATH:-}"

python - "${TRAINING_ROOT}" "${INPUT_ROOT}" "${TIDE_MODEL}" "${EVALUATION_ROOT}" <<'PY'
from pathlib import Path
import hashlib
import json
import platform
import sys

import numpy as np

from water_level_joint_encoder_decoder_v2 import load_joint_water_level_data


training_root = Path(sys.argv[1]).resolve()
input_root = Path(sys.argv[2]).resolve()
tide_model = Path(sys.argv[3]).resolve()
evaluation_root = Path(sys.argv[4]).resolve()


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


print("DIAGNOSTIC_TIME_RUNTIME=python:%s numpy:%s platform:%s" % (
    sys.version.replace("\n", " "), np.__version__, platform.platform()
))
source_documents = []
for seed in (17, 29, 43):
    attempt = (
        training_root / "runs" / "formal"
        / ("ZHD32-DUKF-S%d-V1" % seed) / "attempt_001"
    )
    data_path = attempt / "data_identity.json"
    run_path = attempt / "run_identity.json"
    data = json.loads(data_path.read_text())
    run = json.loads(run_path.read_text())
    source_documents.append(data)
    print("TRAINING_DATA_IDENTITY seed=%d sha256=%s keys=%s" % (
        seed, sha256(data_path), sorted(data)
    ))
    print("TRAINING_TARGET_MEAN seed=%d present=%s value=%r" % (
        seed, "target_mean_m" in data, data.get("target_mean_m")
    ))
    print("TRAINING_TARGET_SCALE seed=%d value=%r" % (
        seed, data.get("target_standard_deviation_m")
    ))
    print("TRAINING_ENVIRONMENT seed=%d value=%s" % (
        seed, json.dumps(run.get("environment"), sort_keys=True)
    ))

if not all(document == source_documents[0] for document in source_documents[1:]):
    raise SystemExit("training data identity documents differ across seeds")

partial_run = (
    evaluation_root / "smoke" / "ZHD32-DUKF-DEV-EVAL-S17-V1"
    / "attempt_001.partial" / "run_identity.json"
)
print("FAILED_EVALUATION_RUN_IDENTITY sha256=%s value=%s" % (
    sha256(partial_run), partial_run.read_text().strip()
))

data = load_joint_water_level_data(
    input_dir=input_root,
    tide_model_path=tide_model,
)
mean32 = np.asarray(data.normalization.target_mean_m, dtype=np.float32)
scale32 = np.asarray(
    data.normalization.target_standard_deviation_m, dtype=np.float32
)
mean64 = mean32.astype(np.float64)
scale64 = scale32.astype(np.float64)
print("CURRENT_TARGET_MEAN_REPR=%r" % mean64.tolist())
print("CURRENT_TARGET_MEAN_FLOAT32_BITS=%r" % mean32.view(np.uint32).tolist())
print("CURRENT_TARGET_SCALE_REPR=%r" % scale64.tolist())
print("CURRENT_TARGET_SCALE_FLOAT32_BITS=%r" % scale32.view(np.uint32).tolist())
print("CURRENT_TARGET_SCALE_EQUALS_TRAINING=%s" % (
    scale64.tolist()
    == source_documents[0].get("target_standard_deviation_m")
))
print("CURRENT_INPUT_IDENTITIES_EQUAL_TRAINING=%s" % (
    [vars(row) for row in data.input_content_identities]
    == source_documents[0].get("input_content_identities")
))
print("CURRENT_ASTRONOMICAL_IDENTITIES_EQUAL_TRAINING=%s" % (
    [vars(row) for row in data.astronomical_dependency_identities]
    == source_documents[0].get("astronomical_dependency_identities")
))

reference_paths = sorted(
    training_root.glob("run/results/modeling/**/normalization_statistics.json")
)
print("NORMALIZATION_REFERENCE_COUNT=%d" % len(reference_paths))
for path in reference_paths:
    reference = json.loads(path.read_text())
    if "target_mean_m" not in reference:
        continue
    reference_mean = np.asarray(reference["target_mean_m"], dtype=np.float32)
    reference_scale = np.asarray(
        reference["target_standard_deviation_m"], dtype=np.float32
    )
    print("NORMALIZATION_REFERENCE path=%s sha256=%s mean_bits_equal=%s scale_bits_equal=%s" % (
        path,
        sha256(path),
        bool(np.array_equal(reference_mean.view(np.uint32), mean32.view(np.uint32))),
        bool(np.array_equal(reference_scale.view(np.uint32), scale32.view(np.uint32))),
    ))

print("NORMALIZATION_SCHEMA_DIAGNOSIS=PASS")
PY
