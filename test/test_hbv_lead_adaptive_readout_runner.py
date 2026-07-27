"""Runner and evidence-package tests for the lead-adaptive confirmation."""

from __future__ import annotations

import hashlib
import importlib
import json
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
RUNNER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "run_g3_lead_adaptive_readout"
)


def _config(experiment_id="g3_lead_adaptive_runner_test"):
    blocks = []
    for index in range(32):
        number = index + 1
        blocks.append(
            {
                "block_id": f"confirmation_{number:02d}",
                "forcing_seed": 4401000 + number,
                "process_noise_seed": 4402000 + number,
                "observation_noise_seed": 4403000 + number,
            }
        )
    return {
        "experiment_id": experiment_id,
        "scenario": "parameter_switch",
        "purpose": "independent lead-adaptive confirmation",
        "design_doc": (
            "docs/plans/"
            "2026-07-27-id23-lead-adaptive-posterior-readout-design.md"
        ),
        "implementation_plan": (
            "docs/plans/"
            "2026-07-27-id23-lead-adaptive-posterior-readout.md"
        ),
        "forecast_contract": {
            "model_transition_during_forecast": "identity",
            "candidate_probabilities_during_forecast": (
                "fixed_at_final_assimilation_posterior"
            ),
            "cross_candidate_state_mixing_during_forecast": False,
        },
        "readout_rule_by_lead": {
            "1": "uniform",
            "3": "highest_posterior",
            "7": "highest_posterior",
        },
        "comparison_methods": [
            "lead_adaptive",
            "full_posterior",
            "none_posterior",
            "uniform",
            "oracle",
        ],
        "matched_blocks": blocks,
        "lead_days": [1, 3, 7],
        "bootstrap": {
            "unit": "matched_block",
            "replicates": 20000,
            "seed": 4404001,
        },
        "retention_thresholds": {
            "minimum_meaningful_rmse_fraction": 0.01,
            "minimum_highest_posterior_selection_accuracy": 0.95,
            "multiday_leads": [3, 7],
        },
        "protected_paths": [],
        "scope_limit": "synthetic parameter-switch confirmation only",
    }


def _write_config(path, config):
    path.write_text(
        json.dumps(config, indent=2, sort_keys=True),
        encoding="utf-8",
    )


def test_invalid_forecast_contract_is_rejected_before_scientific_execution(
    tmp_path, monkeypatch
):
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    config["forecast_contract"]["model_transition_during_forecast"] = "markov"
    config_path = tmp_path / "config.json"
    _write_config(config_path, config)
    output = tmp_path / config["experiment_id"]
    called = False

    def forbidden(*args, **kwargs):
        nonlocal called
        called = True
        raise AssertionError("scientific execution must not start")

    monkeypatch.setattr(runner, "_execute_confirmation", forbidden)

    with pytest.raises(ValueError, match="forecast contract"):
        runner.run(REPO_ROOT, config_path, output)

    assert called is False
    assert not output.exists()
    assert not output.with_name(output.name + ".preregistered.json").exists()


@pytest.mark.parametrize(
    "existing_suffix",
    ("", ".incomplete", ".preregistered.json", ".preregistered.json.incomplete"),
)
def test_runner_refuses_every_existing_evidence_marker_before_config_read(
    tmp_path, existing_suffix
):
    runner = importlib.import_module(RUNNER_MODULE)
    output = tmp_path / "g3_lead_adaptive_runner_test"
    marker = output.with_name(output.name + existing_suffix)
    if existing_suffix in ("", ".incomplete"):
        marker.mkdir()
    else:
        marker.write_text("occupied", encoding="utf-8")

    with pytest.raises(FileExistsError, match="overwrite"):
        runner.run(REPO_ROOT, tmp_path / "missing.json", output)


@pytest.mark.parametrize(
    ("mutation", "match"),
    [
        (
            lambda config: config["readout_rule_by_lead"].__setitem__(
                "1", "highest_posterior"
            ),
            "readout rule",
        ),
        (
            lambda config: config["matched_blocks"].__setitem__(
                31, config["matched_blocks"][0].copy()
            ),
            "block",
        ),
        (
            lambda config: config["matched_blocks"][31].__setitem__(
                "forcing_seed", config["matched_blocks"][0]["forcing_seed"]
            ),
            "seed",
        ),
        (
            lambda config: config["bootstrap"].__setitem__(
                "seed", config["matched_blocks"][0]["forcing_seed"]
            ),
            "seed",
        ),
        (
            lambda config: config["bootstrap"].__setitem__("replicates", 19999),
            "20000",
        ),
    ],
)
def test_frozen_confirmation_contract_rejects_drift(mutation, match):
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    mutation(config)

    with pytest.raises(ValueError, match=match):
        runner._validate_config_contract(config)


def _fake_result_and_driver():
    blocks, truths, methods, leads, candidates, assimilation_days = 2, 3, 2, 3, 3, 4
    final_probabilities = np.broadcast_to(
        np.asarray([0.1, 0.8, 0.1]),
        (blocks, truths, candidates),
    ).copy()
    candidate_predictions = np.empty(
        (blocks, truths, leads, candidates), dtype=np.float64
    )
    candidate_predictions[..., 0] = [1.0, 2.0, 3.0]
    candidate_predictions[..., 1] = [4.0, 5.0, 6.0]
    candidate_predictions[..., 2] = [7.0, 8.0, 9.0]
    full = np.einsum(
        "btc,btlc->btl",
        final_probabilities,
        candidate_predictions,
    )
    stored_candidates = np.zeros(
        (blocks, truths, methods, leads, candidates), dtype=np.float64
    )
    stored_candidates[:, :, 1] = candidate_predictions
    stored_probabilities = np.zeros(
        (
            blocks,
            truths,
            methods,
            assimilation_days,
            candidates,
        ),
        dtype=np.float64,
    )
    stored_probabilities[:, :, 1, -1] = final_probabilities
    result = SimpleNamespace(
        method_names=("open_loop", "parameter_only"),
        method_candidate_counts=np.asarray([1, 3]),
        method_candidate_predictions=stored_candidates,
        method_assimilation_probabilities=stored_probabilities,
        method_predictions=np.stack([np.zeros_like(full), full], axis=2),
        schedule=SimpleNamespace(
            primary_method_name="parameter_only",
            primary_candidate_indices=np.ones(
                (truths, assimilation_days), dtype=np.int64
            ),
        ),
    )
    truth_forecasts = np.zeros_like(full)
    driver = {
        "forecasts": {
            "full": full.copy(),
            "none": full + 2.0,
            "static": full + 3.0,
            "oracle": full - 1.0,
        },
        "truth_forecasts": truth_forecasts,
        "true_candidate_labels": np.ones(
            (truths, assimilation_days), dtype=np.int64
        ),
    }
    return result, driver, candidate_predictions, final_probabilities


def test_derivation_uses_only_final_posterior_and_full_candidate_forecasts():
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    config["bootstrap"]["replicates"] = 100
    result, driver, candidate_predictions, final_probabilities = (
        _fake_result_and_driver()
    )

    derived = runner._derive_confirmation(result, driver, config)

    expected = np.empty((2, 3, 3), dtype=np.float64)
    expected[..., 0] = np.mean(candidate_predictions[..., 0, :], axis=-1)
    expected[..., 1] = candidate_predictions[..., 1, 1]
    expected[..., 2] = candidate_predictions[..., 2, 1]
    np.testing.assert_allclose(
        derived["forecasts"]["lead_adaptive"], expected, rtol=0.0, atol=1e-15
    )
    np.testing.assert_array_equal(
        derived["forecasts"]["full_posterior"], driver["forecasts"]["full"]
    )
    np.testing.assert_array_equal(
        derived["forecasts"]["none_posterior"], driver["forecasts"]["none"]
    )
    np.testing.assert_allclose(
        derived["forecasts"]["uniform"],
        np.mean(candidate_predictions, axis=-1),
        rtol=0.0,
        atol=0.0,
    )
    np.testing.assert_array_equal(
        derived["full_final_probabilities"], final_probabilities
    )
    np.testing.assert_array_equal(derived["selected_candidate_indices"], 1)
    assert derived["cross_checks"]["full_baseline_reconstruction_max_abs"] <= 1e-12
    assert derived["cross_checks"]["readout_reconstruction_max_abs"] == 0.0
    assert derived["cross_checks"]["readout_uses_future_observations"] is False


def _fake_execution_payload():
    arrays = {
        "block_ids": np.asarray(["b01"]),
        "forcing_seeds": np.asarray([1]),
        "process_noise_seeds": np.asarray([2]),
        "observation_noise_seeds": np.asarray([3]),
        "lead_days": np.asarray([1, 3, 7]),
        "truth_forecasts": np.zeros((1, 1, 3)),
        "full_posterior_forecasts": np.ones((1, 1, 3)),
        "full_candidate_forecasts": np.ones((1, 1, 3, 3)),
        "full_final_probabilities": np.asarray([[[0.1, 0.8, 0.1]]]),
        "none_posterior_forecasts": np.full((1, 1, 3), 2.0),
        "uniform_forecasts": np.ones((1, 1, 3)),
        "oracle_forecasts": np.zeros((1, 1, 3)),
        "lead_adaptive_forecasts": np.ones((1, 1, 3)),
        "lead_adaptive_weights": np.asarray(
            [[[[1 / 3, 1 / 3, 1 / 3], [0, 1, 0], [0, 1, 0]]]]
        ),
        "selected_candidate_indices": np.asarray([[1]]),
        "true_candidate_indices": np.asarray([[1]]),
        "bootstrap_indices": np.zeros((2, 1), dtype=np.int64),
    }
    return {
        "evidence": arrays,
        "result_summary": {
            "rmse": {
                method: [1.0, 1.0, 1.0]
                for method in (
                    "lead_adaptive",
                    "full_posterior",
                    "none_posterior",
                    "uniform",
                    "oracle",
                )
            },
            "retention_gates": {"retain": False},
        },
        "cross_checks": {
            "passed": True,
            "full_baseline_reconstruction_max_abs": 0.0,
            "readout_reconstruction_max_abs": 0.0,
            "readout_uses_future_observations": False,
        },
        "resource_preflight": {"passed": True},
        "input_snapshots": {
            "parameter_vectors.csv": b"parameter\n",
            "process_noise_covariances.csv": b"process\n",
            "observation_noise.csv": b"observation\n",
        },
        "input_hashes": {
            "parameter_snapshot_sha256": hashlib.sha256(b"parameter\n").hexdigest(),
            "process_snapshot_sha256": hashlib.sha256(b"process\n").hexdigest(),
            "observation_snapshot_sha256": hashlib.sha256(
                b"observation\n"
            ).hexdigest(),
        },
    }


def test_runner_packages_preregistered_evidence_without_overwrite(
    tmp_path, monkeypatch
):
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    config_path = tmp_path / "config.json"
    _write_config(config_path, config)
    output = tmp_path / config["experiment_id"]
    payload = _fake_execution_payload()
    monkeypatch.setattr(
        runner,
        "_execute_confirmation",
        lambda root, configured, blocks: payload,
    )

    summary = runner.run(REPO_ROOT, config_path, output)

    assert summary["integrity_status"] == "passed"
    assert summary["retention_decision"] == "reject"
    assert output.is_dir()
    assert not output.with_name(output.name + ".incomplete").exists()
    outer_preregistration = output.with_name(
        output.name + ".preregistered.json"
    )
    assert outer_preregistration.read_bytes() == (
        output / "preregistration.json"
    ).read_bytes()
    assert (output / "source_snapshot").is_dir()
    with np.load(output / "evidence.npz", allow_pickle=False) as evidence:
        assert set(payload["evidence"]) <= set(evidence.files)
    checksums = json.loads(
        (output / "checksums.json").read_text(encoding="utf-8")
    )
    packaged_files = {
        path.relative_to(output).as_posix()
        for path in output.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    }
    assert set(checksums) == packaged_files
    for relative, expected_hash in checksums.items():
        actual_hash = hashlib.sha256((output / relative).read_bytes()).hexdigest()
        assert actual_hash == expected_hash

    with pytest.raises(FileExistsError, match="overwrite"):
        runner.run(REPO_ROOT, config_path, output)


def test_failed_execution_leaves_only_incomplete_evidence_and_failure_record(
    tmp_path, monkeypatch
):
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    config_path = tmp_path / "config.json"
    _write_config(config_path, config)
    output = tmp_path / config["experiment_id"]

    def fail(*args, **kwargs):
        raise RuntimeError("deliberate scientific failure")

    monkeypatch.setattr(runner, "_execute_confirmation", fail)

    with pytest.raises(RuntimeError, match="deliberate"):
        runner.run(REPO_ROOT, config_path, output)

    incomplete = output.with_name(output.name + ".incomplete")
    assert not output.exists()
    assert incomplete.is_dir()
    failure = json.loads(
        (incomplete / "failure.json").read_text(encoding="utf-8")
    )
    assert failure["exception_type"] == "RuntimeError"
    assert failure["message"] == "deliberate scientific failure"
    assert (incomplete / "config_snapshot.json").is_file()
    assert (incomplete / "preregistration.json").is_file()
