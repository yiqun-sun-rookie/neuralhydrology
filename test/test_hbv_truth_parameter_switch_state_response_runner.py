import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from hbv_multilead_joint_uncertainty.scripts.run_g3_truth_parameter_switch_state_response_causal_control import (
    DEFAULT_CONFIG,
    PROJECT_ROOT,
    _require_unused_output,
    _source_arrays,
    _validate_config,
)


def _config():
    return json.loads(Path(DEFAULT_CONFIG).read_text(encoding="utf-8"))


def test_config_freezes_state_only_matched_control():
    config = _config()
    _validate_config(config)
    assert config["status"] == "frozen_before_run"
    assert config["response_days"] == 30
    assert config["switch_boundaries_zero_based"] == [180, 360]
    assert config["only_changed_factor"] == (
        "true parameter vector used for matched state propagation: "
        "continue old versus switch to new"
    )
    assert config["observed_discharge_read"] is False
    assert config["forecast_executed"] is False
    assert config["state_reset_at_switch"] is False
    assert config["branch_names"] == [
        "continue_old_true_parameters",
        "switch_to_new_true_parameters",
    ]
    assert config["population"] == {
        "matched_block_count": 8,
        "truth_trial_count": 3,
        "switch_count_per_trial": 2,
        "event_count": 48,
        "state_count": 15,
    }


def test_config_rejects_changes_to_the_only_factor_or_forbidden_scope():
    config = _config()
    changed = json.loads(json.dumps(config))
    changed["only_changed_factor"] = "state reset"
    with pytest.raises(ValueError, match="only changed factor"):
        _validate_config(changed)
    for key in ("observed_discharge_read", "forecast_executed", "state_reset_at_switch"):
        changed = json.loads(json.dumps(config))
        changed[key] = True
        with pytest.raises(ValueError, match="forbidden scope"):
            _validate_config(changed)


def test_existing_output_is_rejected(tmp_path):
    output = tmp_path / "existing"
    output.mkdir()
    with pytest.raises(FileExistsError, match="already exists"):
        _require_unused_output(output)


def test_runner_import_does_not_load_forecast_modules():
    environment = os.environ.copy()
    environment["PYTHONPATH"] = "src"
    command = (
        "import importlib,sys;"
        "importlib.import_module('hbv_multilead_joint_uncertainty.scripts."
        "run_g3_truth_parameter_switch_state_response_causal_control');"
        "print(any('forecast' in name for name in sys.modules "
        "if name.startswith('hbv_multilead_joint_uncertainty')))"
    )
    completed = subprocess.run(
        [sys.executable, "-c", command],
        check=True,
        capture_output=True,
        text=True,
        env=environment,
    )
    assert completed.stdout.strip() == "False"


def test_source_loader_requests_only_frozen_state_inputs():
    config = _config()
    requested = []
    truth_path = PROJECT_ROOT / config["sealed_truth_evidence"]["path"]
    scale_path = PROJECT_ROOT / config["frozen_state_scale_evidence"]["path"]
    truth_arrays, scale_arrays = _source_arrays(
        truth_path,
        scale_path,
        config,
        on_read=requested.append,
    )

    assert set(truth_arrays) == {
        "forcing_blocks",
        "warmup_days",
        "truth_states",
        "truth_process_perturbations",
        "truth_parameter_indices",
        "parameter_ids",
        "parameter_vectors",
    }
    assert set(scale_arrays) == {"truth_standard_deviation", "state_names"}
    assert "observed_discharge" not in requested
    assert "truth_discharge" not in requested
