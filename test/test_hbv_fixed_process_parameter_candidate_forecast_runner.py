import json
from pathlib import Path

import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.scripts.run_g3_fixed_process_parameter_candidate_controlled_forecast import (
    DEFAULT_CONFIG,
    _build_truth_forecasts,
    _require_unused_output,
    _validate_frozen_config,
)


def _config():
    return json.loads(Path(DEFAULT_CONFIG).read_text(encoding="utf-8"))


def test_frozen_config_accepts_only_the_controlled_one_versus_three_contract():
    config = _config()
    _validate_frozen_config(config)

    changed = json.loads(json.dumps(config))
    changed["fixed_process_id"] = "process_1"
    with pytest.raises(ValueError, match="process_2"):
        _validate_frozen_config(changed)

    changed = json.loads(json.dumps(config))
    changed["fixed_forecast_parameter_id"] = "equifinal_diverse_1"
    with pytest.raises(ValueError, match="trained_center"):
        _validate_frozen_config(changed)


def test_existing_output_directory_is_rejected_before_any_execution(tmp_path):
    output = tmp_path / "already_exists"
    output.mkdir()
    with pytest.raises(FileExistsError, match="already exists"):
        _require_unused_output(output)


def test_truth_forecasts_use_exact_target_indices_without_origin_day_leakage():
    truth = np.arange(20, dtype=np.float64).reshape(1, 2, 10)
    targets = np.asarray([[1, 3], [4, 7]], dtype=np.int64)
    selected = _build_truth_forecasts(truth, targets)
    assert selected.shape == (1, 2, 2, 2)
    np.testing.assert_array_equal(selected[0, 0], [[1.0, 3.0], [4.0, 7.0]])
    np.testing.assert_array_equal(selected[0, 1], [[11.0, 13.0], [14.0, 17.0]])
