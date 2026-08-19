import copy
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from camels_process_noise_only.contract import (  # noqa: E402
    evaluate_domain_projection,
    evaluate_event,
    load_design_config,
    lognormal_variance,
    score_probabilities,
    select_design_basins,
    truth_candidate_indices,
    validate_design_config,
)
from camels_process_noise_only.runner import (  # noqa: E402
    assign_candidate_process_covariances,
    build_noise_bank,
    generate_truth,
    prepare_output_root,
    run_filter,
    sha256_file,
    verify_registered_input_files,
)
from camels_process_noise_only.verifier import (  # noqa: E402
    apply_success_gate,
    independent_event,
    independent_probability_scores,
    verify_probability_evidence,
)
from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds  # noqa: E402


CONFIG_PATH = (
    REPO_ROOT
    / "src"
    / "camels_process_noise_only"
    / "configs"
    / "camels_process_noise_only_01a_design.json"
)

PARAMETERS = {
    "parTT": 0.0,
    "parCFMAX": 2.0,
    "parCFR": 0.05,
    "parCWH": 0.1,
    "parFC": 200.0,
    "parBETA": 2.0,
    "parLP": 0.7,
    "parK0": 0.3,
    "parK1": 0.1,
    "parUZL": 20.0,
    "parPERC": 1.0,
    "parK2": 0.05,
    "lag_time": 3.0,
}
INITIAL_HYDRO = np.array([0.0, 0.0, 100.0, 5.0, 80.0])


@pytest.fixture
def design_config():
    return load_design_config(CONFIG_PATH)


def test_design_config_contains_exact_approved_contract(design_config):
    assert (
        design_config["configuration_revision"]
        == "01a_machine_precision_domain_tolerance"
    )
    assert design_config["truth"]["candidate_lognormal_sigmas"] == [
        0.01,
        0.02,
        0.04,
    ]
    assert design_config["truth"]["rotation"] == [1, 0, 2, 1, 2, 0, 1]
    assert design_config["truth"]["stage_days"] == 365
    assert design_config["seeds"]["design"] == [0, 1]
    assert design_config["filter"]["interaction_mode"] == "full"
    assert design_config["truth"]["domain_check"]["tolerance_multiplier"] == 32.0
    assert (
        design_config["truth"]["domain_check"][
            "replace_truth_state_with_projection"
        ]
        is False
    )


def test_01a_preserves_every_scientific_design_field(design_config):
    predecessor_path = CONFIG_PATH.with_name(
        "camels_process_noise_only_01_design.json"
    )
    predecessor = json.loads(predecessor_path.read_text(encoding="utf-8"))
    for section in (
        "experiment_id",
        "configuration_status",
        "evidence_scope",
        "inputs",
        "filter",
        "event_rule",
        "probability_metrics",
        "success_gate",
        "bootstrap",
        "seeds",
        "design_selection",
        "prohibited_claims",
    ):
        assert design_config[section] == predecessor[section]
    predecessor_truth = copy.deepcopy(predecessor["truth"])
    predecessor_truth.pop("truth_domain_adjustment_maximum")
    revised_truth = copy.deepcopy(design_config["truth"])
    revised_truth.pop("domain_check")
    assert revised_truth == predecessor_truth


@pytest.mark.parametrize(
    "state,sigma,expected",
    [
        (100.0, 0.01, 100.0**2 * np.expm1(0.01**2)),
        (100.0, 0.02, 100.0**2 * np.expm1(0.02**2)),
        (100.0, 0.04, 100.0**2 * np.expm1(0.04**2)),
        (0.0, 0.02, 0.0),
    ],
)
def test_lognormal_variance_matches_exact_conditional_moment(
    state, sigma, expected
):
    assert lognormal_variance(state, sigma) == pytest.approx(
        expected, rel=1e-15, abs=0.0
    )


@pytest.mark.parametrize(
    "state,sigma,message",
    [
        (-1.0, 0.02, "state"),
        (np.nan, 0.02, "state"),
        (1.0, 0.0, "sigma"),
        (1.0, np.inf, "sigma"),
    ],
)
def test_lognormal_variance_rejects_invalid_inputs(state, sigma, message):
    with pytest.raises(ValueError, match=message):
        lognormal_variance(state, sigma)


@pytest.mark.parametrize(
    "path,value,message",
    [
        (("truth", "candidate_lognormal_sigmas"), [0.01, 0.02, 0.08], "sigmas"),
        (("truth", "stage_days"), 180, "stage_days"),
        (("truth", "rotation"), [0, 1, 2, 0, 2, 1, 0], "rotation"),
        (("seeds", "design"), [0, 2], "design seeds"),
        (("filter", "interaction_mode"), "parameter_grouped", "full"),
        (("truth", "domain_check"), {"tolerance_multiplier": 16.0}, "domain"),
    ],
)
def test_validate_design_config_rejects_contract_drift(
    design_config, path, value, message
):
    changed = copy.deepcopy(design_config)
    changed[path[0]][path[1]] = value
    with pytest.raises(ValueError, match=message):
        validate_design_config(changed)


def test_domain_projection_accepts_registered_roundoff_and_rejects_violation():
    raw = np.array([0.2893299328193164])
    roundoff_projection = np.array([0.2893299328193162])

    accepted = evaluate_domain_projection(
        raw, roundoff_projection, tolerance_multiplier=32.0
    )

    assert accepted.nonzero_difference_count == 1
    assert accepted.violating_component_count == 0
    assert accepted.violated is False
    assert accepted.maximum_absolute_difference == 2.220446049250313e-16
    assert accepted.maximum_tolerance_ratio == pytest.approx(0.03125)

    violation = evaluate_domain_projection(
        raw, raw - 1.0e-12, tolerance_multiplier=32.0
    )
    assert violation.violating_component_count == 1
    assert violation.violated is True


def test_truth_generation_stops_on_domain_difference_above_tolerance(
    design_config, monkeypatch
):
    import camels_process_noise_only.runner as runner_module

    def invalid_projection(state, parameters):
        projected = np.asarray(state, dtype=np.float64).copy()
        projected[1] += 1.0e-6
        return projected

    monkeypatch.setattr(runner_module, "project_hbv_state", invalid_projection)
    days = design_config["truth"]["window_days"]
    zeros = np.zeros(days, dtype=np.float64)
    with pytest.raises(ValueError, match="initial truth state violates"):
        generate_truth(
            parameters=PARAMETERS,
            rain=zeros,
            pet=zeros,
            temperature=zeros,
            initial_hydrologic_state=INITIAL_HYDRO,
            standard_normals=zeros,
            config=design_config,
            parameter_bounds=resolve_hbv_bounds("v5"),
        )


def test_truth_schedule_has_2555_days_and_balanced_post_switch_targets(
    design_config,
):
    truth = truth_candidate_indices(design_config)
    assert truth.shape == (2555,)
    np.testing.assert_array_equal(truth[:365], np.full(365, 1))
    np.testing.assert_array_equal(truth[365:730], np.full(365, 0))
    post_switch_counts = np.bincount(truth[365:], minlength=3)
    np.testing.assert_array_equal(post_switch_counts, np.full(3, 730))


def test_event_rule_ignores_first_90_days_and_passes_fixed_scoring_block(
    design_config,
):
    probabilities = np.full((365, 3), 0.05, dtype=np.float64)
    probabilities[:, 0] = 0.90
    probabilities[90:180] = np.array([0.15, 0.70, 0.15])

    result = evaluate_event(probabilities, true_index=1, config=design_config)

    assert result["passed"] is True
    assert result["true_daily_argmax_days"] == 90
    assert result["mean_true_probability"] == pytest.approx(0.70)
    assert result["mean_margin"] == pytest.approx(0.55)


def test_event_rule_requires_at_least_60_true_argmax_days(design_config):
    probabilities = np.tile(np.array([0.20, 0.60, 0.20]), (365, 1))
    probabilities[90:121] = np.array([0.51, 0.48, 0.01])

    result = evaluate_event(probabilities, true_index=1, config=design_config)

    assert result["true_daily_argmax_days"] == 59
    assert result["mean_true_probability"] >= 0.50
    assert result["passed"] is False


def test_uniform_probabilities_reproduce_registered_probability_baselines(
    design_config,
):
    truth = truth_candidate_indices(design_config)
    probabilities = np.full((len(truth), 3), 1.0 / 3.0)
    log_probabilities = np.full((len(truth), 3), -np.log(3.0))

    scores = score_probabilities(
        probabilities, log_probabilities, truth, design_config
    )

    assert scores["n_days"] == 6 * 185
    assert scores["multiclass_brier"] == pytest.approx(2.0 / 3.0)
    assert scores["true_negative_log_probability"] == pytest.approx(np.log(3.0))
    assert scores["classwise_expected_calibration_error"] == pytest.approx(0.0)


def test_design_basin_selection_is_deterministic_and_balanced(design_config):
    basin_ids = [f"{index + 1:08d}" for index in range(531)]
    parameter_table = pd.DataFrame(
        {
            "basin_id": basin_ids,
            "p_parPERC": np.arange(1.0, 532.0),
            "p_parK2": np.ones(531),
        }
    )
    g1_table = pd.DataFrame(
        {"basin_id": basin_ids, "sigma_obs": np.ones(531)}
    )

    selected = select_design_basins(parameter_table, g1_table, design_config)

    assert len(selected) == 90
    assert selected["basin_id"].nunique() == 90
    assert selected.groupby("proxy_tertile").size().to_dict() == {
        1: 30,
        2: 30,
        3: 30,
    }
    expected_positions = np.rint(np.linspace(0, 176, 30)).astype(int)
    for tertile in (1, 2, 3):
        actual = selected.loc[
            selected["proxy_tertile"] == tertile, "within_tertile_position"
        ].to_numpy()
        np.testing.assert_array_equal(actual, expected_positions)


def test_load_design_config_rejects_non_json_file(tmp_path):
    invalid = tmp_path / "invalid.json"
    invalid.write_text("not-json", encoding="utf-8")
    with pytest.raises(json.JSONDecodeError):
        load_design_config(invalid)


def test_truth_generation_switches_only_positive_lower_groundwater_noise(
    design_config,
):
    days = design_config["truth"]["window_days"]
    zeros = np.zeros(days, dtype=np.float64)
    temperature = np.full(days, 5.0, dtype=np.float64)
    standard_normals = np.zeros(days, dtype=np.float64)

    result = generate_truth(
        parameters=PARAMETERS,
        rain=zeros,
        pet=zeros,
        temperature=temperature,
        initial_hydrologic_state=INITIAL_HYDRO,
        standard_normals=standard_normals,
        config=design_config,
        parameter_bounds=resolve_hbv_bounds("v5"),
    )

    assert result.states.shape == (days, 15)
    assert np.all(result.states[:, 4] > 0.0)
    assert result.truth_domain_violation_count == 0
    assert result.truth_state_replacement_count == 0
    assert result.truth_projection_nonzero_day_count >= 0
    assert result.truth_projection_maximum_absolute_difference >= 0.0
    assert result.truth_projection_maximum_tolerance_ratio <= 1.0
    expected_sigmas = np.asarray(design_config["truth"]["candidate_lognormal_sigmas"])[
        truth_candidate_indices(design_config)
    ]
    np.testing.assert_array_equal(result.applied_sigmas, expected_sigmas)
    np.testing.assert_array_equal(result.standard_normals, standard_normals)
    np.testing.assert_allclose(
        result.states[:, 4],
        result.deterministic_lower_groundwater
        * np.exp(-0.5 * result.applied_sigmas**2),
        rtol=1e-14,
        atol=0.0,
    )


def test_noise_bank_candidates_differ_only_in_process_covariance(design_config):
    bank = build_noise_bank(
        parameters=PARAMETERS,
        initial_hydrologic_state=INITIAL_HYDRO,
        sigma_obs=0.2,
        parameter_bounds=resolve_hbv_bounds("v5"),
        config=design_config,
    )

    assert bank.estimator.interaction_mode == "full"
    assert bank.estimator.parameter_groups == ("fixed-center",) * 3
    assert len(bank.filters) == 3
    for transition in bank.transitions:
        assert transition.parameters == PARAMETERS
    for candidate in bank.filters:
        np.testing.assert_array_equal(
            candidate.observation_covariance, np.array([[0.2**2]])
        )
    np.testing.assert_array_equal(bank.filters[0].state, bank.filters[1].state)
    np.testing.assert_array_equal(
        bank.filters[0].covariance, bank.filters[1].covariance
    )


def test_candidate_process_covariances_match_post_interaction_predictions(
    design_config,
):
    bank = build_noise_bank(
        parameters=PARAMETERS,
        initial_hydrologic_state=INITIAL_HYDRO,
        sigma_obs=0.2,
        parameter_bounds=resolve_hbv_bounds("v5"),
        config=design_config,
    )
    for transition in bank.transitions:
        transition.set_forcing(1.0, 0.1, 5.0)
    bank.estimator.interact()
    predicted_lower = np.array(
        [
            transition(candidate.state.copy())[4]
            for transition, candidate in zip(bank.transitions, bank.filters)
        ]
    )

    variances = assign_candidate_process_covariances(bank, design_config)

    sigmas = np.asarray(design_config["truth"]["candidate_lognormal_sigmas"])
    expected = predicted_lower**2 * np.expm1(sigmas**2)
    np.testing.assert_allclose(variances, expected, rtol=1e-14, atol=0.0)
    for candidate, expected_variance in zip(bank.filters, expected):
        expected_matrix = np.zeros((15, 15), dtype=np.float64)
        expected_matrix[4, 4] = expected_variance
        np.testing.assert_array_equal(candidate.process_covariance, expected_matrix)


def test_short_filter_run_has_finite_normalized_probabilities(design_config):
    bank = build_noise_bank(
        parameters=PARAMETERS,
        initial_hydrologic_state=INITIAL_HYDRO,
        sigma_obs=0.2,
        parameter_bounds=resolve_hbv_bounds("v5"),
        config=design_config,
    )
    days = 8
    rain = np.linspace(0.0, 3.0, days)
    pet = np.full(days, 0.2)
    temperature = np.full(days, 5.0)
    observations = np.linspace(0.1, 0.3, days)

    result = run_filter(
        bank,
        rain=rain,
        pet=pet,
        temperature=temperature,
        observations=observations,
        config=design_config,
    )

    assert result.probabilities.shape == (days, 3)
    assert result.log_probabilities.shape == (days, 3)
    assert result.candidate_predicted_lower_groundwater.shape == (days, 3)
    assert np.all(np.isfinite(result.probabilities))
    assert np.all(np.isfinite(result.log_probabilities))
    np.testing.assert_allclose(
        result.probabilities.sum(axis=1), np.ones(days), rtol=0.0, atol=1e-12
    )
    np.testing.assert_allclose(
        np.exp(result.log_probabilities),
        result.probabilities,
        rtol=1e-13,
        atol=np.finfo(np.float64).tiny,
    )
    sigmas = np.asarray(design_config["truth"]["candidate_lognormal_sigmas"])
    np.testing.assert_allclose(
        result.candidate_process_variances,
        result.candidate_predicted_lower_groundwater**2
        * np.expm1(sigmas[None, :] ** 2),
        rtol=1e-14,
        atol=0.0,
    )


def test_prepare_output_root_refuses_preexisting_path(tmp_path):
    output = tmp_path / "run"
    prepared = prepare_output_root(output)
    assert prepared == output.resolve()
    assert output.is_dir()
    with pytest.raises(FileExistsError, match="already exists"):
        prepare_output_root(output)


def test_registered_input_verifier_checks_every_file_and_coverage(tmp_path):
    basin_id = "00000001"
    input_dir = tmp_path / "inputs"
    input_dir.mkdir()
    forcing = input_dir / "forcing.txt"
    streamflow = input_dir / "streamflow.txt"
    topography = input_dir / "topography.txt"
    loader = input_dir / "loader.py"
    forcing.write_bytes(b"forcing\n")
    streamflow.write_bytes(b"streamflow\n")
    topography.write_bytes(b"topography\n")
    loader.write_bytes(b"loader\n")
    basin_list = tmp_path / "basins.csv"
    pd.DataFrame({"basin_id": [basin_id]}).to_csv(basin_list, index=False)
    coverage = tmp_path / "coverage.csv"
    pd.DataFrame(
        {
            "basin_id": [basin_id],
            "n_days": [2555],
            "first_date": ["1989-10-01"],
            "last_date": ["1996-09-28"],
            "all_required_forcing_finite": [True],
        }
    ).to_csv(coverage, index=False)
    manifest = tmp_path / "manifest.csv"
    rows = []
    for category, path, row_basin_id in (
        ("maurer_forcing", forcing, basin_id),
        ("usgs_streamflow", streamflow, basin_id),
        ("camels_topography", topography, ""),
        ("forcing_loader_source", loader, ""),
    ):
        rows.append(
            {
                "category": category,
                "basin_id": row_basin_id,
                "relative_path": path.relative_to(tmp_path).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
        )
    pd.DataFrame(rows).to_csv(manifest, index=False)
    config = {
        "inputs": {
            "forcing_input_manifest": manifest.relative_to(tmp_path).as_posix(),
            "forcing_input_manifest_sha256": sha256_file(manifest),
            "forcing_coverage_table": coverage.relative_to(tmp_path).as_posix(),
            "forcing_coverage_table_sha256": sha256_file(coverage),
        },
        "truth": {
            "window_start": "1989-10-01",
            "window_end": "1996-09-28",
            "window_days": 2555,
        },
        "design_selection": {
            "basin_list": basin_list.relative_to(tmp_path).as_posix(),
            "basin_list_sha256": sha256_file(basin_list),
        },
    }

    evidence = verify_registered_input_files(tmp_path, config)

    assert evidence["manifest_row_count"] == 4
    assert evidence["coverage_basin_count"] == 1
    forcing.write_bytes(b"forcinG\n")
    with pytest.raises(ValueError, match="file SHA-256 changed"):
        verify_registered_input_files(tmp_path, config)


def test_independent_verifier_reproduces_event_rule(design_config):
    probabilities = np.tile(np.array([0.15, 0.70, 0.15]), (365, 1))
    probabilities[:90] = np.array([0.90, 0.05, 0.05])

    result = independent_event(probabilities, true_index=1, config=design_config)

    assert result["passed"] is True
    assert result["mean_true_probability"] == pytest.approx(0.70)
    assert result["mean_margin"] == pytest.approx(0.55)
    assert result["true_daily_argmax_days"] == 90


def test_independent_probability_scores_reproduce_uniform_baselines(
    design_config,
):
    truth = truth_candidate_indices(design_config)
    probabilities = np.full((len(truth), 3), 1.0 / 3.0)
    logs = np.full_like(probabilities, -np.log(3.0))

    result = independent_probability_scores(
        probabilities, logs, truth, design_config
    )

    assert result["n_days"] == 1110
    assert result["multiclass_brier"] == pytest.approx(2.0 / 3.0)
    assert result["true_negative_log_probability"] == pytest.approx(np.log(3.0))
    assert result["classwise_expected_calibration_error"] == pytest.approx(0.0)


def test_probability_verifier_rejects_normalization_and_log_mismatch():
    probabilities = np.array([[0.2, 0.3, 0.5], [0.1, 0.2, 0.7]])
    logs = np.log(probabilities)
    valid = verify_probability_evidence(probabilities, logs, tolerance=1e-12)
    assert valid["maximum_probability_sum_error"] <= 1e-12
    assert valid["maximum_probability_log_reconstruction_error"] <= 1e-15

    wrong_sum = probabilities.copy()
    wrong_sum[0, 0] += 0.01
    with pytest.raises(ValueError, match="sum"):
        verify_probability_evidence(wrong_sum, logs, tolerance=1e-12)

    wrong_logs = logs.copy()
    wrong_logs[1, 2] += 0.1
    with pytest.raises(ValueError, match="log"):
        verify_probability_evidence(probabilities, wrong_logs, tolerance=1e-12)


def test_success_gate_requires_every_registered_condition(design_config):
    passing = {
        "overall_event_pass_rate": 0.85,
        "direction_pass_rates": {
            "1->0": 0.75,
            "0->2": 0.75,
            "2->1": 0.75,
            "1->2": 0.75,
            "2->0": 0.75,
            "0->1": 0.75,
        },
        "overall_event_pass_rate_interval": {"lower": 0.76, "upper": 0.90},
        "direction_pass_rate_intervals": {
            direction: {"lower": 0.61, "upper": 0.85}
            for direction in ("1->0", "0->2", "2->1", "1->2", "2->0", "0->1")
        },
        "seed_event_agreement": 0.85,
        "multiclass_brier": 0.55,
        "multiclass_brier_interval": {"lower": 0.50, "upper": 0.60},
        "true_negative_log_probability": 0.90,
        "true_negative_log_probability_interval": {
            "lower": 0.80,
            "upper": 1.00,
        },
        "classwise_expected_calibration_error": 0.08,
    }

    passed = apply_success_gate(passing, design_config)
    assert passed["scientific_status"] == "passed"
    assert all(passed["conditions"].values())

    failing = copy.deepcopy(passing)
    failing["direction_pass_rates"]["0->1"] = 0.69
    failed = apply_success_gate(failing, design_config)
    assert failed["scientific_status"] == "not_passed"
    assert failed["conditions"]["each_direction_event_pass_rate"] is False
