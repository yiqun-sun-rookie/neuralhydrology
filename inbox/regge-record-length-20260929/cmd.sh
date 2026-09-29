#!/bin/bash
set -eo pipefail

sequence=23
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
CAPSULE=$ROOT/deploy/formal_calibration_capsule_003
PYTHON=$ROOT/runtime_probe_005/bin/python
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH=$CAPSULE/project/python

"$PYTHON" -B - <<'PY'
import json
import platform

import numpy as np

from regge_record_length_study import calibration
from regge_record_length_study.common import array_sha256

contract, core, noise = calibration._load_sealed_core()
config = contract.proposed_config()
generated = noise.build_noise_design(config["noise_design"]["seed"])
canonical = calibration._canonical_design(
    calibration.CANONICAL_NOISE_DESIGN,
    file_sha256=calibration.CANONICAL_NOISE_FILE_SHA256,
    array_sha256_expected=calibration.NOISE_DESIGN_SHA256,
    shape=(128, 5),
    label="noise",
)

# Every candidate is nonnegative, so unsigned IEEE-754 bit distance is exact.
generated_bits = generated.view(np.uint64)
canonical_bits = canonical.view(np.uint64)
steps = np.where(
    generated_bits >= canonical_bits,
    generated_bits - canonical_bits,
    canonical_bits - generated_bits,
)
different = generated != canonical
indices = np.argwhere(different)
distribution = {
    str(int(step)): int(np.count_nonzero(steps[different] == step))
    for step in np.unique(steps[different])
}
largest = sorted(
    (
        {
            "row": int(row),
            "column": int(column),
            "canonical": float(canonical[row, column]),
            "generated": float(generated[row, column]),
            "absolute_difference": float(abs(generated[row, column] - canonical[row, column])),
            "float64_steps": int(steps[row, column]),
        }
        for row, column in indices
    ),
    key=lambda item: (-item["float64_steps"], item["row"], item["column"]),
)[:20]
result = {
    "python": platform.python_version(),
    "numpy": np.__version__,
    "generated_array_sha256": array_sha256(generated),
    "canonical_array_sha256": array_sha256(canonical),
    "shape": list(generated.shape),
    "different_value_count": int(np.count_nonzero(different)),
    "maximum_float64_steps": int(steps.max()),
    "step_distribution_for_different_values": distribution,
    "largest_differences": largest,
    "generated_finite": bool(np.isfinite(generated).all()),
    "generated_within_declared_bounds": bool(
        np.all(generated[:, :4] > 0.0)
        and np.all(generated[32:, 4] > 0.0)
        and np.all(generated[1:32, 4] == 0.0)
    ),
    "canonical_bytes_were_not_modified": array_sha256(canonical) == calibration.NOISE_DESIGN_SHA256,
}
print(json.dumps(result, indent=2, sort_keys=True))
PY
