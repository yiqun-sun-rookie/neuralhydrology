import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from hbv_multilead_joint_uncertainty.scripts.run_g3_fixed_process_state_interaction_global_posterior_audit import (
    DEFAULT_CONFIG,
    _require_unused_output,
    _validate_config,
)


def _config():
    return json.loads(Path(DEFAULT_CONFIG).read_text(encoding="utf-8"))


def test_config_freezes_the_single_changed_factor_and_complete_population():
    config = _config()
    _validate_config(config)
    assert config["status"] == "frozen_before_run"
    assert config["interaction_modes"] == {
        "fully_interacting_multiple_model_global_posterior_state": "full",
        "noninteracting_multiple_filter_global_posterior_state_control": "none",
    }
    assert config["forecast_executed"] is False
    assert config["time_since_truth_switch_grouping_used"] is False
    assert config["assimilation_days"] == 540
    assert config["state_count"] == 15
    assert config["only_changed_factor"] == (
        "state and covariance interaction mixing before each observation update: "
        "full versus none"
    )
    assert len(config["sealed_ideal_evidence"]["sha256"]) == 64


def test_config_rejects_probability_or_global_combination_changes():
    config = _config()
    changed = json.loads(json.dumps(config))
    changed["fixed_factors"]["probability_prediction"] = "changed"
    with pytest.raises(ValueError, match="fixed factors"):
        _validate_config(changed)
    changed = json.loads(json.dumps(config))
    changed["fixed_factors"]["global_posterior_combination"] = "changed"
    with pytest.raises(ValueError, match="fixed factors"):
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
        "run_g3_fixed_process_state_interaction_global_posterior_audit');"
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
