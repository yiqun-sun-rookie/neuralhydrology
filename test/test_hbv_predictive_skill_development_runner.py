"""Tests for the immutable predictive-skill development screen."""

from __future__ import annotations

import hashlib
import importlib
import json
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
RUNNER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "run_g3_predictive_skill_development"
)


def _config(experiment_id="g3_predictive_skill_development_test"):
    return {
        "experiment_id": experiment_id,
        "classification": "development_screen",
        "scenario": "parameter_switch",
        "purpose": "screen rolling predictive skill on sealed old blocks",
        "design_doc": (
            "docs/plans/"
            "2026-07-27-id23-predictive-skill-readout-design.md"
        ),
        "implementation_plan": (
            "docs/plans/"
            "2026-07-27-id23-predictive-skill-readout.md"
        ),
        "forecast_contract": {
            "model_transition_during_forecast": "identity",
            "candidate_probabilities_during_forecast": (
                "fixed_at_final_assimilation_posterior"
            ),
            "cross_candidate_state_mixing_during_forecast": False,
        },
        "readout_rule": {
            "1": "final_full_posterior_weighted",
            "3": "minimum_latest_completed_same_lead_mse",
            "7": "minimum_latest_completed_same_lead_mse",
            "window": 30,
            "tie_break": "first_candidate",
        },
        "lead_days": [1, 3, 7],
        "expected_block_count": 8,
        "expected_truth_count": 3,
        "factor_transition_stay_probability": 0.98,
        "primary_candidate_method_name": "parameter_only",
        "selected_process_id": "process_2",
        "development_gates": {
            "one_day_maximum_absolute_difference": 1e-12,
            "three_day_maximum_rmse_harm_fraction": 0.01,
            "seven_day_minimum_rmse_improvement_fraction": 0.01,
        },
        "sealed_ideal_input_evidence": {
            "path": "ideal.npz",
            "sha256": "0" * 64,
        },
        "sealed_baseline_evidence": {
            "path": "baseline.npz",
            "sha256": "1" * 64,
        },
        "parameter_source": {"path": "parameters.csv", "sha256": "2" * 64},
        "process_noise_source": {
            "path": "process.csv",
            "sha256": "3" * 64,
            "selected_process_id": "process_2",
        },
        "observation_noise_source": {
            "path": "observation.csv",
            "sha256": "4" * 64,
        },
        "protected_paths": [],
        "scope_limit": "old sealed development blocks only",
    }


def _write_config(path: Path, config: dict) -> None:
    path.write_text(
        json.dumps(config, indent=2, sort_keys=True),
        encoding="utf-8",
    )


@pytest.mark.parametrize(
    ("mutation", "match"),
    [
        (
            lambda config: config["forecast_contract"].__setitem__(
                "model_transition_during_forecast", "markov"
            ),
            "forecast contract",
        ),
        (
            lambda config: config["readout_rule"].__setitem__("window", 29),
            "readout rule",
        ),
        (
            lambda config: config["development_gates"].__setitem__(
                "seven_day_minimum_rmse_improvement_fraction", 0.0
            ),
            "development gates",
        ),
        (
            lambda config: config.__setitem__("expected_block_count", 32),
            "block count",
        ),
    ],
)
def test_fixed_development_contract_rejects_drift(mutation, match):
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    mutation(config)

    with pytest.raises(ValueError, match=match):
        runner._validate_config_contract(config)


def _screen_arrays():
    truth = np.zeros((2, 3, 3), dtype=np.float64)
    full = np.broadcast_to([2.0, 4.0, 10.0], truth.shape).copy()
    none = np.broadcast_to([2.1, 4.1, 9.5], truth.shape).copy()
    skill = np.broadcast_to([2.0, 4.02, 8.8], truth.shape).copy()
    selected = np.zeros((2, 3, 3), dtype=np.int64)
    selected[..., 0] = -1
    predictive_optimum = np.zeros_like(selected)
    true_candidate = np.zeros((2, 3), dtype=np.int64)
    return (
        skill,
        full,
        none,
        truth,
        selected,
        predictive_optimum,
        true_candidate,
    )


def test_development_summary_applies_the_fixed_rmse_gates():
    runner = importlib.import_module(RUNNER_MODULE)
    (
        skill,
        full,
        none,
        truth,
        selected,
        predictive_optimum,
        true_candidate,
    ) = _screen_arrays()

    summary, arrays = runner._summarize_development(
        skill_forecasts=skill,
        full_forecasts=full,
        none_forecasts=none,
        truth_forecasts=truth,
        selected_candidate_indices=selected,
        predictive_optimum_indices=predictive_optimum,
        true_candidate_indices=true_candidate,
        integrity_cross_checks={"passed": True},
        gates={
            "one_day_maximum_absolute_difference": 1e-12,
            "three_day_maximum_rmse_harm_fraction": 0.01,
            "seven_day_minimum_rmse_improvement_fraction": 0.01,
        },
    )

    assert summary["development_decision"] == "advance_to_new_formal_design"
    assert all(summary["gates"].values())
    np.testing.assert_allclose(
        summary["rmse"]["predictive_skill"],
        [2.0, 4.02, 8.8],
    )
    assert (
        summary["relative_rmse_percent"]["predictive_skill_minus_full"][1]
        == pytest.approx(0.5)
    )
    assert (
        summary["relative_rmse_percent"]["predictive_skill_minus_none"][2]
        < -7.0
    )
    assert set(arrays) >= {
        "squared_error_predictive_skill",
        "squared_error_full",
        "squared_error_none",
    }


@pytest.mark.parametrize(
    "mutation",
    [
        lambda values: values[0].__setitem__((0, 0, 0), 2.1),
        lambda values: values[0].__setitem__((slice(None), slice(None), 1), 4.2),
        lambda values: values[0].__setitem__((slice(None), slice(None), 2), 9.45),
    ],
)
def test_any_failed_development_gate_stops_formal_progression(mutation):
    runner = importlib.import_module(RUNNER_MODULE)
    values = list(_screen_arrays())
    mutation(values)

    summary, _ = runner._summarize_development(
        skill_forecasts=values[0],
        full_forecasts=values[1],
        none_forecasts=values[2],
        truth_forecasts=values[3],
        selected_candidate_indices=values[4],
        predictive_optimum_indices=values[5],
        true_candidate_indices=values[6],
        integrity_cross_checks={"passed": True},
        gates=_config()["development_gates"],
    )

    assert summary["development_decision"] == "stop_no_formal_experiment"
    assert not all(summary["gates"].values())


def _fake_payload():
    summary, evidence = importlib.import_module(
        RUNNER_MODULE
    )._summarize_development(
        skill_forecasts=_screen_arrays()[0],
        full_forecasts=_screen_arrays()[1],
        none_forecasts=_screen_arrays()[2],
        truth_forecasts=_screen_arrays()[3],
        selected_candidate_indices=_screen_arrays()[4],
        predictive_optimum_indices=_screen_arrays()[5],
        true_candidate_indices=_screen_arrays()[6],
        integrity_cross_checks={"passed": True},
        gates=_config()["development_gates"],
    )
    evidence["lead_days"] = np.asarray([1, 3, 7])
    return {
        "summary": summary,
        "evidence": evidence,
        "cross_checks": {"passed": True},
        "input_hashes": {
            "ideal_input_evidence_sha256": "0" * 64,
            "baseline_evidence_sha256": "1" * 64,
            "parameter_snapshot_sha256": "2" * 64,
            "process_snapshot_sha256": "3" * 64,
            "observation_snapshot_sha256": "4" * 64,
        },
    }


def test_runner_packages_immutable_development_evidence(tmp_path, monkeypatch):
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    config_path = tmp_path / "config.json"
    _write_config(config_path, config)
    output = tmp_path / config["experiment_id"]
    monkeypatch.setattr(
        runner,
        "_execute_development",
        lambda root, configured: _fake_payload(),
    )
    monkeypatch.setattr(
        runner,
        "_source_snapshot",
        lambda root, destination: destination.mkdir(),
    )

    summary = runner.run(REPO_ROOT, config_path, output)

    assert summary["integrity_status"] == "passed"
    assert output.is_dir()
    assert (output / "summary.json").is_file()
    with np.load(output / "evidence.npz", allow_pickle=False) as evidence:
        assert "squared_error_predictive_skill" in evidence.files
    checksums = json.loads(
        (output / "checksums.json").read_text(encoding="utf-8")
    )
    for relative, expected in checksums.items():
        actual = hashlib.sha256((output / relative).read_bytes()).hexdigest()
        assert actual == expected

    with pytest.raises(FileExistsError, match="overwrite"):
        runner.run(REPO_ROOT, config_path, output)
