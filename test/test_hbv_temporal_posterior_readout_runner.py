"""Runner tests for the time-robust posterior-readout confirmation."""

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
    "run_g3_temporal_posterior_readout"
)


def _config(experiment_id="g3_temporal_runner_test"):
    return {
        "experiment_id": experiment_id,
        "scenario": "parameter_switch",
        "purpose": "independent time-robust posterior confirmation",
        "design_doc": (
            "docs/plans/"
            "2026-07-27-id23-temporal-posterior-readout-design.md"
        ),
        "implementation_plan": (
            "docs/plans/"
            "2026-07-27-id23-temporal-posterior-readout.md"
        ),
        "forecast_contract": {
            "model_transition_during_forecast": "identity",
            "candidate_probabilities_during_forecast": (
                "fixed_at_final_assimilation_posterior"
            ),
            "cross_candidate_state_mixing_during_forecast": False,
        },
        "temporal_readout": {
            "window_days": 30,
            "one_day_rule": "final_posterior_weighted",
            "three_and_seven_day_rule": (
                "highest_arithmetic_mean_posterior"
            ),
        },
        "comparison_methods": [
            "temporal_posterior",
            "full_posterior",
            "none_posterior",
        ],
        "matched_block_generation": {
            "count": 96,
            "block_id_prefix": "g3_temporal_confirmation_block_",
            "forcing_seed_start": 7411001,
            "process_noise_seed_start": 7412001,
            "observation_noise_seed_start": 7413001,
        },
        "lead_days": [1, 3, 7],
        "bootstrap": {
            "unit": "matched_block",
            "replicates": 20000,
            "seed": 7414001,
        },
        "retention_thresholds": {
            "minimum_meaningful_rmse_fraction": 0.01,
            "minimum_temporal_selection_accuracy": 0.95,
        },
        "protected_paths": [],
        "scope_limit": "synthetic parameter-switch confirmation only",
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
            lambda c: c["forecast_contract"].__setitem__(
                "model_transition_during_forecast", "markov"
            ),
            "forecast contract",
        ),
        (
            lambda c: c["temporal_readout"].__setitem__(
                "window_days", 29
            ),
            "temporal readout",
        ),
        (
            lambda c: c["matched_block_generation"].__setitem__(
                "count", 95
            ),
            "96",
        ),
        (
            lambda c: c["matched_block_generation"].__setitem__(
                "process_noise_seed_start", 7411001
            ),
            "seed",
        ),
        (
            lambda c: c["bootstrap"].__setitem__(
                "seed", 7411001
            ),
            "seed",
        ),
        (
            lambda c: c["bootstrap"].__setitem__(
                "replicates", 19999
            ),
            "20000",
        ),
    ],
)
def test_frozen_contract_rejects_drift(mutation, match):
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    mutation(config)
    with pytest.raises(ValueError, match=match):
        runner._validate_config_contract(config)


def test_generated_blocks_are_exact_and_unique():
    runner = importlib.import_module(RUNNER_MODULE)
    blocks = runner._generated_blocks(_config())

    assert len(blocks) == 96
    assert blocks[0] == {
        "block_id": "g3_temporal_confirmation_block_001",
        "forcing_seed": 7411001,
        "process_noise_seed": 7412001,
        "observation_noise_seed": 7413001,
    }
    assert blocks[-1] == {
        "block_id": "g3_temporal_confirmation_block_096",
        "forcing_seed": 7411096,
        "process_noise_seed": 7412096,
        "observation_noise_seed": 7413096,
    }
    assert len(
        {
            seed
            for block in blocks
            for key, seed in block.items()
            if key.endswith("_seed")
        }
    ) == 288


def test_expanded_resource_config_does_not_mutate_frozen_config():
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    blocks = runner._generated_blocks(config)

    expanded = runner._with_generated_blocks(config, blocks)

    assert "matched_blocks" not in config
    assert expanded is not config
    assert expanded["matched_blocks"] == list(blocks)


def _fake_result_and_driver():
    blocks, truths, methods, leads, candidates, days = 2, 3, 2, 3, 3, 35
    history = np.broadcast_to(
        np.asarray([0.10, 0.20, 0.70]),
        (blocks, truths, days, candidates),
    ).copy()
    history[:, :, -1] = np.asarray([0.80, 0.15, 0.05])
    candidate_predictions = np.empty(
        (blocks, truths, leads, candidates),
        dtype=np.float64,
    )
    candidate_predictions[..., 0] = [1.0, 2.0, 3.0]
    candidate_predictions[..., 1] = [4.0, 5.0, 6.0]
    candidate_predictions[..., 2] = [7.0, 8.0, 9.0]
    full = np.einsum(
        "btc,btlc->btl",
        history[:, :, -1],
        candidate_predictions,
    )
    stored_candidates = np.zeros(
        (blocks, truths, methods, leads, candidates)
    )
    stored_candidates[:, :, 1] = candidate_predictions
    stored_probabilities = np.zeros(
        (blocks, truths, methods, days, candidates)
    )
    stored_probabilities[:, :, 1] = history
    result = SimpleNamespace(
        method_names=("open_loop", "parameter_only"),
        method_candidate_counts=np.asarray([1, 3]),
        method_candidate_predictions=stored_candidates,
        method_assimilation_probabilities=stored_probabilities,
        schedule=SimpleNamespace(
            primary_method_name="parameter_only",
            primary_candidate_indices=np.full(
                (truths, days),
                2,
                dtype=np.int64,
            ),
        ),
    )
    driver = {
        "forecasts": {
            "full": full.copy(),
            "none": full + 2.0,
            "static": full + 3.0,
            "oracle": candidate_predictions[..., 2],
        },
        "truth_forecasts": np.zeros_like(full),
        "true_candidate_labels": np.full(
            (truths, days),
            2,
            dtype=np.int64,
        ),
    }
    return result, driver, history, candidate_predictions


def test_derivation_uses_probability_history_and_keeps_one_day():
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    config["bootstrap"]["replicates"] = 100
    result, driver, history, candidates = _fake_result_and_driver()

    derived = runner._derive_confirmation(result, driver, config)

    expected = driver["forecasts"]["full"].copy()
    expected[..., 1] = candidates[..., 1, 2]
    expected[..., 2] = candidates[..., 2, 2]
    np.testing.assert_allclose(
        derived["forecasts"]["temporal_posterior"],
        expected,
        rtol=0.0,
        atol=0.0,
    )
    np.testing.assert_array_equal(
        derived["full_probability_history"],
        history,
    )
    np.testing.assert_array_equal(
        derived["selected_candidate_indices"],
        2,
    )
    assert (
        derived["cross_checks"][
            "one_day_maximum_absolute_difference"
        ]
        == 0.0
    )
    assert (
        derived["cross_checks"][
            "readout_reconstruction_maximum_absolute_error"
        ]
        == 0.0
    )
    assert (
        derived["cross_checks"]["readout_uses_future_observations"]
        is False
    )


def _fake_execution_payload():
    return {
        "evidence": {
            "block_ids": np.asarray(["b01"]),
            "forcing_seeds": np.asarray([1]),
            "process_noise_seeds": np.asarray([2]),
            "observation_noise_seeds": np.asarray([3]),
            "lead_days": np.asarray([1, 3, 7]),
            "truth_forecasts": np.zeros((1, 1, 3)),
            "full_probability_history": np.full(
                (1, 1, 30, 3),
                1 / 3,
            ),
            "full_candidate_forecasts": np.ones((1, 1, 3, 3)),
            "full_posterior_forecasts": np.ones((1, 1, 3)),
            "none_posterior_forecasts": np.full((1, 1, 3), 2.0),
            "temporal_posterior_forecasts": np.ones((1, 1, 3)),
            "temporal_weights": np.full((1, 1, 3, 3), 1 / 3),
            "temporal_mean_probabilities": np.full(
                (1, 1, 3),
                1 / 3,
            ),
            "selected_candidate_indices": np.zeros((1, 1), dtype=int),
            "true_candidate_indices": np.zeros((1, 1), dtype=int),
            "bootstrap_indices": np.zeros((2, 1), dtype=int),
        },
        "result_summary": {
            "rmse": {
                method: [1.0, 1.0, 1.0]
                for method in (
                    "temporal_posterior",
                    "full_posterior",
                    "none_posterior",
                )
            },
            "retention_gates": {"retain": False},
        },
        "cross_checks": {
            "passed": True,
            "one_day_maximum_absolute_difference": 0.0,
            "readout_reconstruction_maximum_absolute_error": 0.0,
            "readout_uses_future_observations": False,
        },
        "resource_preflight": {"passed": True},
        "input_snapshots": {
            "parameter_vectors.csv": b"parameter\n",
            "process_noise_covariances.csv": b"process\n",
            "observation_noise.csv": b"observation\n",
        },
        "input_hashes": {
            "parameter_snapshot_sha256": hashlib.sha256(
                b"parameter\n"
            ).hexdigest(),
            "process_snapshot_sha256": hashlib.sha256(
                b"process\n"
            ).hexdigest(),
            "observation_snapshot_sha256": hashlib.sha256(
                b"observation\n"
            ).hexdigest(),
        },
    }


def test_runner_packages_atomic_evidence(tmp_path, monkeypatch):
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    path = tmp_path / "config.json"
    _write_config(path, config)
    output = tmp_path / config["experiment_id"]
    payload = _fake_execution_payload()
    monkeypatch.setattr(
        runner,
        "_execute_confirmation",
        lambda root, configured, blocks: payload,
    )

    summary = runner.run(REPO_ROOT, path, output)

    assert summary["integrity_status"] == "passed"
    assert summary["retention_decision"] == "reject"
    assert output.is_dir()
    assert not output.with_name(output.name + ".incomplete").exists()
    assert output.with_name(
        output.name + ".preregistered.json"
    ).read_bytes() == (output / "preregistration.json").read_bytes()
    with np.load(output / "evidence.npz", allow_pickle=False) as evidence:
        assert set(payload["evidence"]) <= set(evidence.files)
    checksums = json.loads(
        (output / "checksums.json").read_text(encoding="utf-8")
    )
    packaged = {
        path.relative_to(output).as_posix()
        for path in output.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    }
    assert set(checksums) == packaged
    for relative, expected in checksums.items():
        assert hashlib.sha256(
            (output / relative).read_bytes()
        ).hexdigest() == expected


def test_runner_refuses_existing_output_before_reading_config(tmp_path):
    runner = importlib.import_module(RUNNER_MODULE)
    output = tmp_path / "occupied"
    output.mkdir()
    with pytest.raises(FileExistsError, match="overwrite"):
        runner.run(REPO_ROOT, tmp_path / "missing.json", output)
