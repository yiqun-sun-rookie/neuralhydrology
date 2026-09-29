#!/bin/bash
set -eo pipefail

sequence=24
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
CAPSULE=$ROOT/deploy/formal_calibration_capsule_003
PYTHON=$ROOT/runtime_probe_005/bin/python
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH=$CAPSULE/project/python

"$PYTHON" -B - <<'PY'
import json

import numpy as np

from regge_record_length_study.common import array_sha256

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
    records.append({
        "count": count,
        "dimensions": dimensions,
        "random_sha256": array_sha256(random_values),
        "before_permutation_sha256": array_sha256(before_permutation),
        "permutation_sha256": [array_sha256(value) for value in permutations],
        "unit_design_sha256": array_sha256(unit),
    })
print(json.dumps(records, indent=2, sort_keys=True))
PY
