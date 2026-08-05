"""Contract tests for the daily rolling forecast readout runner."""

from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))
RUNNER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "run_g3_daily_rolling_forecast_readout_development"
)
CONFIG_PATH = (
    REPO_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "configs"
    / "g3_daily_rolling_forecast_readout_development_v01.json"
)


def _config():
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def test_frozen_readout_config_is_accepted():
    runner = importlib.import_module(RUNNER_MODULE)

    runner._validate_config_contract(_config())


@pytest.mark.parametrize(
    ("mutation", "match"),
    (
        (
            lambda config: config["readout_methods"].reverse(),
            "readout methods",
        ),
        (
            lambda config: config["comparison_controls"].pop(),
            "comparison controls",
        ),
        (
            lambda config: config["lead_days"].pop(),
            "lead days",
        ),
        (
            lambda config: config["stage_lengths"].__setitem__(1, 179),
            "stage lengths",
        ),
        (
            lambda config: config["switch_days"].__setitem__(1, 359),
            "switch days",
        ),
        (
            lambda config: config["forecast_contract"].__setitem__(
                "future_discharge_observations_used", True
            ),
            "forecast contract",
        ),
        (
            lambda config: config["bootstrap"].__setitem__(
                "unit", "daily_origin"
            ),
            "bootstrap",
        ),
        (
            lambda config: config["decision_rules"].__setitem__(
                "minimum_meaningful_rmse_fraction", 0.0
            ),
            "decision rules",
        ),
        (
            lambda config: config.__setitem__(
                "expected_candidate_count", 2
            ),
            "candidate count",
        ),
        (
            lambda config: config["numerical_tolerances"].__setitem__(
                "forecast", 1e-3
            ),
            "numerical tolerances",
        ),
    ),
)
def test_readout_contract_rejects_drift(mutation, match):
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    mutation(config)

    with pytest.raises(ValueError, match=match):
        runner._validate_config_contract(config)


def test_runner_refuses_existing_output_before_reading_config(tmp_path):
    runner = importlib.import_module(RUNNER_MODULE)
    output = tmp_path / "existing"
    output.mkdir()

    with pytest.raises(FileExistsError, match="overwrite"):
        runner.run(
            REPO_ROOT,
            tmp_path / "missing.json",
            output,
        )


def test_runner_rejects_output_overlap_with_protected_path(tmp_path):
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    protected = tmp_path / "protected"
    protected.mkdir()
    config["experiment_id"] = "child"
    config["protected_paths"] = [str(protected)]
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    output = protected / config["experiment_id"]

    with pytest.raises(ValueError, match="overlap"):
        runner.run(REPO_ROOT, config_path, output)

    assert not output.exists()
    assert not output.with_name(output.name + ".incomplete").exists()


def test_source_contract_rejects_malformed_sha256():
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    config["sealed_daily_rolling_evidence"]["sha256"] = "short"

    with pytest.raises(ValueError, match="source contract"):
        runner._validate_config_contract(config)
