import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from hbv_multilead_joint_uncertainty.scripts.run_g3_fixed_process_parameter_candidate_complete_state_audit import (
    DEFAULT_CONFIG,
    _require_unused_output,
    _validate_config,
)


def _config():
    return json.loads(Path(DEFAULT_CONFIG).read_text(encoding="utf-8"))


def test_config_freezes_process_days_and_all_fifteen_states():
    config = _config()
    _validate_config(config)
    changed = json.loads(json.dumps(config))
    changed["fixed_process_id"] = "process_1"
    with pytest.raises(ValueError, match="process_2"):
        _validate_config(changed)
    changed = json.loads(json.dumps(config))
    changed["state_count"] = 5
    with pytest.raises(ValueError, match="fifteen"):
        _validate_config(changed)


def test_existing_output_is_rejected(tmp_path):
    output = tmp_path / "existing"
    output.mkdir()
    with pytest.raises(FileExistsError, match="already exists"):
        _require_unused_output(output)


def test_runner_import_does_not_load_a_forecast_module():
    environment = os.environ.copy()
    environment["PYTHONPATH"] = "src"
    command = (
        "import importlib,sys;"
        "importlib.import_module('hbv_multilead_joint_uncertainty.scripts."
        "run_g3_fixed_process_parameter_candidate_complete_state_audit');"
        "print('hbv_multilead_joint_uncertainty.deterministic_unique_state_forecast'"
        " in sys.modules)"
    )
    completed = subprocess.run(
        [sys.executable, "-c", command],
        check=True,
        capture_output=True,
        text=True,
        env=environment,
    )
    assert completed.stdout.strip() == "False"
