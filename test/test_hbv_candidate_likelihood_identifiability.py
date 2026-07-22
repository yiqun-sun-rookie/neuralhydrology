import importlib
import importlib.util
import hashlib
import json
import os
import sys
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))
MODULE_NAME = "hbv_multilead_joint_uncertainty.candidate_likelihood_identifiability"

from hbv_joint_uncertainty.imm import InteractingMultipleModel  # noqa: E402
from hbv_multilead_joint_uncertainty.methods import build_method_definitions  # noqa: E402


BASE_PARAMETERS = {
    "parTT": 0.0,
    "parCFMAX": 3.2,
    "parCFR": 0.04,
    "parCWH": 0.1,
    "parFC": 250.0,
    "parBETA": 2.1,
    "parLP": 0.7,
    "parK0": 0.2,
    "parK1": 0.06,
    "parUZL": 18.0,
    "parPERC": 1.2,
    "parK2": 0.015,
    "lag_time": 3.0,
}


def _contracts():
    parameters = {}
    for index, parameter_id in enumerate(
        ("equifinal_diverse_1", "trained_center", "equifinal_diverse_2")
    ):
        values = BASE_PARAMETERS.copy()
        values["parFC"] += 20.0 * (index - 1)
        values["parK1"] += 0.01 * (index - 1)
        parameters[parameter_id] = values
    covariances = {}
    scales = {}
    for index, process_id in enumerate(("small", "medium", "large")):
        diagonal = np.zeros(15, dtype=np.float64)
        diagonal[:5] = (10.0**index) * np.asarray(
            [1e-3, 1e-5, 1e-3, 1e-4, 1e-3], dtype=np.float64
        )
        covariances[process_id] = np.diag(diagonal)
        scales[process_id] = 10.0 ** (-4 + index)
    return parameters, scales, covariances


def _forcing(seed=8101, days=14):
    rng = np.random.default_rng(seed)
    angle = np.linspace(0.0, 2.0 * np.pi, days)
    return np.column_stack(
        (
            rng.gamma(0.8, 4.0, size=days),
            np.maximum(0.0, 2.0 + np.sin(angle)),
            4.0 + 12.0 * np.sin(angle - np.pi / 2.0),
        )
    )


def test_candidate_likelihood_identifiability_module_is_available():
    assert importlib.util.find_spec(MODULE_NAME) is not None


@pytest.mark.parametrize(
    ("scenario", "truth_count", "candidate_count"),
    [
        ("parameter_switch", 3, 3),
        ("process_noise_switch", 3, 3),
        ("parameter_process_noise_switch", 9, 9),
    ],
)
def test_diagnostic_runs_independent_candidate_filters_without_interaction(
    monkeypatch, scenario, truth_count, candidate_count
):
    module = importlib.import_module(MODULE_NAME)
    parameters, scales, covariances = _contracts()

    def forbidden_interacting_step(*_args, **_kwargs):
        raise AssertionError("candidate likelihood diagnostic called weight interaction")

    monkeypatch.setattr(InteractingMultipleModel, "step", forbidden_interacting_step)
    result = module.run_candidate_likelihood_identifiability(
        forcing_blocks=_forcing()[None, :, :],
        block_ids=("development_block_01",),
        parameter_vectors=parameters,
        process_scales=scales,
        process_covariances=covariances,
        selected_process_id="large",
        scenario=scenario,
        process_noise_seeds=(9101,),
        observation_noise_seeds=(10101,),
        warmup_days=8,
        stage_lengths=(2, 2, 2),
        adaptation_days=1,
        initial_covariance_fraction=0.001,
        observation_standard_deviation=0.05,
    )

    assert result.candidate_count == candidate_count
    assert result.truth_states.shape == (1, truth_count, 6, 15)
    assert result.candidate_daily_log_likelihoods.shape == (
        1,
        truth_count,
        6,
        candidate_count,
    )
    assert result.scored_daily_log_likelihoods.shape == (
        1,
        truth_count,
        3,
        1,
        candidate_count,
    )
    assert np.all(np.isfinite(result.candidate_daily_log_likelihoods))
    assert np.all(result.candidate_innovation_variances > 0.0)
    np.testing.assert_allclose(
        result.candidate_daily_log_likelihoods,
        -0.5
        * (
            np.log(2.0 * np.pi * result.candidate_innovation_variances)
            + np.square(result.candidate_innovations)
            / result.candidate_innovation_variances
        ),
        rtol=1e-12,
        atol=1e-12,
    )


def test_candidate_selection_matches_the_three_frozen_scenarios():
    module = importlib.import_module(MODULE_NAME)
    parameters, scales, covariances = _contracts()
    definitions = build_method_definitions(parameters, scales, covariances, "large")

    assert [
        candidate.candidate_id
        for candidate in module.candidates_for_likelihood_diagnostic(
            definitions, "parameter_switch"
        )
    ] == [candidate.candidate_id for candidate in definitions["parameter_only"]]
    assert [
        candidate.candidate_id
        for candidate in module.candidates_for_likelihood_diagnostic(
            definitions, "process_noise_switch"
        )
    ] == [candidate.candidate_id for candidate in definitions["noise_only"]]
    assert [
        candidate.candidate_id
        for candidate in module.candidates_for_likelihood_diagnostic(
            definitions, "parameter_process_noise_switch"
        )
    ] == [candidate.candidate_id for candidate in definitions["joint"]]


def test_scoring_resets_cumulative_values_and_treats_ties_as_not_first():
    module = importlib.import_module(MODULE_NAME)
    scored = np.asarray(
        [
            [
                [
                    [[2.0, 1.0, 0.0], [0.0, 2.0, 1.0], [3.0, 2.0, 1.0], [2.0, 1.0, 0.0]],
                    [[3.0, 2.0, 0.0], [0.0, 3.0, 0.0], [0.0, 1.0, 0.0], [0.0, 1.0, 0.0]],
                    [[3.0, 2.0, 1.0], [2.0, 1.0, 0.0], [1.0, 0.0, -1.0], [0.0, -1.0, -2.0]],
                ]
            ]
        ],
        dtype=np.float64,
    )
    truth = np.asarray([[0, 1, 2]], dtype=np.int64)

    scores = module.score_candidate_log_likelihoods(
        scored, truth, stable_final_days=2
    )

    np.testing.assert_array_equal(
        scores.true_candidate_daily_ranks[0, 0, 0], np.array([1, 3, 1, 1])
    )
    np.testing.assert_array_equal(
        scores.true_candidate_cumulative_ranks[0, 0, 0], np.array([1, 2, 2, 1])
    )
    np.testing.assert_array_equal(
        scores.cumulative_log_likelihoods[0, 0, 0],
        np.array([[2.0, 1.0, 0.0], [2.0, 3.0, 1.0], [5.0, 5.0, 2.0], [7.0, 6.0, 2.0]]),
    )
    assert scores.first_cumulative_rank_one_day[0, 0, 0] == 1
    assert scores.first_stable_cumulative_rank_one_day[0, 0, 0] == 4
    assert not scores.stable_cumulative_identifiable[0, 0, 0]
    assert scores.first_cumulative_rank_one_day[0, 0, 1] == 2
    assert scores.first_stable_cumulative_rank_one_day[0, 0, 1] == 2
    assert scores.stable_cumulative_identifiable[0, 0, 1]
    assert scores.first_cumulative_rank_one_day[0, 0, 2] == -1
    assert scores.first_stable_cumulative_rank_one_day[0, 0, 2] == -1
    assert not scores.stable_cumulative_identifiable[0, 0, 2]


def test_scoring_rejects_a_truth_index_outside_the_candidate_bank():
    module = importlib.import_module(MODULE_NAME)
    scored = np.zeros((1, 1, 3, 10, 3), dtype=np.float64)

    with pytest.raises(ValueError, match="truth_candidate_indices"):
        module.score_candidate_log_likelihoods(
            scored, np.asarray([[0, 1, 3]], dtype=np.int64), stable_final_days=5
        )


def _synthetic_evaluation_result(stable):
    stable_values = np.asarray(stable, dtype=bool)
    blocks, truths, stages = stable_values.shape
    days = 10
    cumulative_ranks = np.where(stable_values[..., None], 1, 2)
    cumulative_ranks = np.broadcast_to(
        cumulative_ranks, (blocks, truths, stages, days)
    ).copy()
    daily_ranks = cumulative_ranks.copy()
    margins = np.where(stable_values[..., None], 1.0, -1.0)
    margins = np.broadcast_to(margins, (blocks, truths, stages, days)).copy()
    first_stable = np.where(stable_values, 1, -1)
    return SimpleNamespace(
        scenario="parameter_switch",
        block_ids=tuple(f"block_{index:02d}" for index in range(blocks)),
        stable_cumulative_identifiable=stable_values,
        true_candidate_daily_ranks=daily_ranks,
        true_candidate_cumulative_ranks=cumulative_ranks,
        true_candidate_cumulative_margins=margins,
        first_stable_cumulative_rank_one_day=first_stable,
    )


def test_evaluation_requires_both_switching_stages_and_uses_block_bootstrap():
    module = importlib.import_module(MODULE_NAME)
    passing = _synthetic_evaluation_result(np.ones((12, 3, 3), dtype=bool))

    evaluation = module.evaluate_candidate_likelihood_identifiability(
        passing,
        bootstrap_replicates=2000,
        bootstrap_seed=777,
        stable_fraction_minimum=2.0 / 3.0,
        bootstrap_lower_minimum=0.5,
        median_final_margin_minimum=0.0,
    )

    assert [row["stage_number"] for row in evaluation["stage_results"]] == [1, 2, 3]
    assert all(row["stage_passed"] for row in evaluation["stage_results"])
    assert evaluation["switching_stages_passed"]
    assert evaluation["switching_stage_numbers"] == [2, 3]

    failing_stable = np.ones((12, 3, 3), dtype=bool)
    failing_stable[6:, :, 2] = False
    failing = _synthetic_evaluation_result(failing_stable)
    failed_evaluation = module.evaluate_candidate_likelihood_identifiability(
        failing,
        bootstrap_replicates=2000,
        bootstrap_seed=777,
        stable_fraction_minimum=2.0 / 3.0,
        bootstrap_lower_minimum=0.5,
        median_final_margin_minimum=0.0,
    )

    assert failed_evaluation["stage_results"][2]["stable_identifiable_fraction"] == 0.5
    assert not failed_evaluation["stage_results"][2]["stage_passed"]
    assert not failed_evaluation["switching_stages_passed"]


def test_evaluation_does_not_let_stage_one_replace_a_failed_switching_stage():
    module = importlib.import_module(MODULE_NAME)
    stable = np.ones((12, 3, 3), dtype=bool)
    stable[:, :, 1] = False
    result = _synthetic_evaluation_result(stable)

    evaluation = module.evaluate_candidate_likelihood_identifiability(
        result,
        bootstrap_replicates=2000,
        bootstrap_seed=778,
        stable_fraction_minimum=2.0 / 3.0,
        bootstrap_lower_minimum=0.5,
        median_final_margin_minimum=0.0,
    )

    assert evaluation["stage_results"][0]["stage_passed"]
    assert not evaluation["stage_results"][1]["stage_passed"]
    assert not evaluation["switching_stages_passed"]


def test_packaged_likelihood_run_freezes_recomputable_evidence(tmp_path):
    from hbv_multilead_joint_uncertainty.scripts.run_candidate_likelihood_identifiability import (
        run,
    )

    source = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "three_stage_parameter_switch_v02.json"
    )
    config = json.loads(source.read_text(encoding="utf-8"))
    config["experiment_id"] = "candidate_likelihood_packaging_test"
    config["dataset_role"] = "development"
    config["purpose"] = "Packaging test for independent candidate likelihoods."
    config["matched_blocks"] = config["matched_blocks"][:1]
    config["matched_blocks"][0]["block_id"] = "development_block_01"
    config["forcing"]["warmup_days"] = 8
    config["forcing"]["reference_total_days"] = 14
    config["stage_lengths"] = [2, 2, 2]
    config["adaptation_days_excluded_per_stage"] = 1
    config["stable_final_scoring_days"] = 1
    config["bootstrap"] = {
        "unit": "synthetic_block",
        "replicates": 100,
        "seed": 575757,
    }
    config["decision_rules"] = {
        "stable_identifiable_fraction_minimum": 2.0 / 3.0,
        "stable_fraction_block_bootstrap_lower_strict_minimum": 0.5,
        "median_final_margin_strict_minimum": 0.0,
        "switching_stage_numbers": [2, 3],
    }
    config["integrity_gates"] = {
        "truth_process_perturbation_reconstruction_maximum_absolute_error": 0.0,
        "observation_reconstruction_maximum_absolute_error": 0.0,
        "innovation_reconstruction_maximum_absolute_error": 1e-12,
        "log_likelihood_reconstruction_maximum_absolute_error": 1e-12,
        "score_reconstruction_maximum_absolute_error": 1e-12,
    }
    config["protected_paths"] = []
    config["scope_limit"] = "Packaging test only."
    for key in (
        "lead_days",
        "factor_transition_stay_probability",
        "resource_pilot",
    ):
        config.pop(key, None)
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    output = tmp_path / config["experiment_id"]

    summary = run(REPO_ROOT, config_path, output)

    assert summary["integrity_status"] == "passed"
    assert summary["dataset_role"] == "development"
    preregistration = tmp_path / (config["experiment_id"] + ".preregistered.json")
    assert preregistration.is_file()
    assert (output / "evidence.npz").is_file()
    assert (output / "candidate_daily_log_likelihood.csv").is_file()
    assert (output / "trial_stage_identifiability.csv").is_file()
    assert (output / "stage_identifiability.csv").is_file()
    checksums = json.loads((output / "checksums.json").read_text(encoding="utf-8"))
    assert "evidence.npz" in checksums
    assert summary["config_sha256"] == hashlib.sha256(
        (output / "config_snapshot.json").read_bytes()
    ).hexdigest()
    resource = json.loads((output / "resource_preflight.json").read_text(encoding="utf-8"))
    assert resource["safe_to_run"]
    assert resource["universal_memory_threshold_used"] is False
    assert resource["available_physical_memory_bytes"] > 0
    assert "available_commit_memory_bytes" in resource
    with np.load(output / "evidence.npz", allow_pickle=False) as evidence:
        assert evidence["candidate_daily_log_likelihoods"].shape == (1, 3, 6, 3)
        assert evidence["scored_daily_log_likelihoods"].shape == (1, 3, 3, 1, 3)
        assert evidence["first_stable_cumulative_rank_one_day"].shape == (1, 3, 3)

    with pytest.raises(FileExistsError, match="overwrite"):
        run(REPO_ROOT, config_path, output)


def test_source_snapshot_supports_windows_extended_length_targets(tmp_path):
    from hbv_multilead_joint_uncertainty.scripts import (
        run_candidate_likelihood_identifiability as runner,
    )

    destination = tmp_path / ("source_snapshot_" + "x" * 120)

    runner._source_snapshot(REPO_ROOT, destination)

    canonical = (
        Path("\\\\?\\" + str(destination.resolve()))
        if os.name == "nt"
        else destination
    )
    names = {path.name for path in canonical.iterdir()}
    assert (
        "src__hbv_multilead_joint_uncertainty__scripts__"
        "run_process_noise_identification_validation.py"
    ) in names


def test_checksum_manifest_includes_every_extended_length_snapshot_file(tmp_path):
    from hbv_multilead_joint_uncertainty.scripts import (
        run_candidate_likelihood_identifiability as runner,
    )

    evidence = tmp_path / ("candidate_likelihood_evidence_" + "x" * 100)
    snapshot = evidence / "source_snapshot"
    runner._source_snapshot(REPO_ROOT, snapshot)

    checksums = runner._checksums_for_directory(evidence)

    expected_name = (
        "source_snapshot/src__hbv_multilead_joint_uncertainty__scripts__"
        "run_process_noise_identification_validation.py"
    )
    assert expected_name in checksums
    assert len(checksums) == len(tuple(runner._snapshot_source_paths()))


def test_protected_hashes_include_every_extended_length_snapshot_file(tmp_path):
    from hbv_multilead_joint_uncertainty.scripts import (
        run_candidate_likelihood_identifiability as runner,
    )

    protected = tmp_path / ("protected_candidate_likelihood_" + "x" * 100)
    runner._source_snapshot(REPO_ROOT, protected)

    hashes = runner._protected_hashes(tmp_path, [protected.name])

    expected_name = (
        protected.name
        + "/src__hbv_multilead_joint_uncertainty__scripts__"
        "run_process_noise_identification_validation.py"
    )
    assert expected_name in hashes
    assert len(hashes) == len(tuple(runner._snapshot_source_paths()))


@pytest.mark.parametrize(
    "updates",
    [
        {"stable_final_scoring_days": 4},
        {"switching_stage_numbers": [1, 2]},
    ],
)
def test_runner_rejects_config_that_disagrees_with_fixed_decision_code(updates):
    from hbv_multilead_joint_uncertainty.scripts import (
        run_candidate_likelihood_identifiability as runner,
    )

    config = {
        "stable_final_scoring_days": 5,
        "decision_rules": {"switching_stage_numbers": [2, 3]},
    }
    for key, value in updates.items():
        if key == "switching_stage_numbers":
            config["decision_rules"][key] = value
        else:
            config[key] = value

    with pytest.raises(ValueError, match="fixed decision contract"):
        runner._validate_fixed_decision_contract(config)
