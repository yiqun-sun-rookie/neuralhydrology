#!/bin/bash
set -eo pipefail

sequence=25
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
CAPSULE=$ROOT/deploy/formal_calibration_capsule_003
PYTHON=$ROOT/runtime_probe_005/bin/python
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH=$CAPSULE/project/python

"$PYTHON" -B - <<'PY'
import json

import numpy as np

from regge_record_length_study import calibration
from regge_record_length_study.common import array_sha256

_, _, noise = calibration._load_sealed_core()
rng = np.random.default_rng(909001)
records = []
for count, dimensions in ((31, 4), (96, 5)):
    random_values = rng.random((count, dimensions))
    base = np.arange(count, dtype=np.float64)[:, None]
    before_permutation = (base + random_values) / count
    permutations = []
    unit = before_permutation.copy()
    for column in range(dimensions):
        permutation = rng.permutation(count)
        permutations.append(permutation)
        unit[:, column] = unit[permutation, column]
    lower = noise._LOWER[:dimensions]
    upper = noise._UPPER[:dimensions]
    log_lower = np.log(lower)
    log_upper = np.log(upper)
    span = log_upper - log_lower
    exponent = log_lower + unit * span
    result = np.exp(exponent)
    records.append({
        "count": count,
        "dimensions": dimensions,
        "lower_sha256": array_sha256(lower),
        "upper_sha256": array_sha256(upper),
        "log_lower_sha256": array_sha256(log_lower),
        "log_upper_sha256": array_sha256(log_upper),
        "span_sha256": array_sha256(span),
        "unit_design_sha256": array_sha256(unit),
        "exponent_sha256": array_sha256(exponent),
        "result_sha256": array_sha256(result),
    })
print(json.dumps(records, indent=2, sort_keys=True))
PY
