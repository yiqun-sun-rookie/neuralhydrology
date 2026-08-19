import math
import sys
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

import camels_switch_confirmation.g2_switch_confirmation as g2_module  # noqa: E402
from camels_switch_confirmation.g2_switch_confirmation import (  # noqa: E402
    PARAMETER_STATE_MAPPING_MODE,
    STATE_INTERACTION_MODE,
    _allocate_pairwise_path_audit,
    _atomic_save_npz,
    _build_bank,
    _direct_nested_diagnostics,
    _finalize_pairwise_path_audit,
    _generate_truth,
    _record_pairwise_path_audit,
    assign_common_process_covariance,
    build_filter_observation_covariance,
    build_filter_process_covariance,
    build_state_dependent_lower_groundwater_covariance,
    classify_basin_verdict,
    validate_parameter_interaction_contract,
)
from hbv_joint_uncertainty.imm import (  # noqa: E402
    InteractingMultipleModel,
    PairwisePathMultipleModel,
    normalize_log_weights,
)
from hbv_joint_uncertainty.hbv_adapter import advance_state  # noqa: E402
from hbv_joint_uncertainty.hbv_state_mapping import (  # noqa: E402
    remap_parfc_moments,
    remap_parfc_state,
)
from hbv_joint_uncertainty.preflight import (  # noqa: E402
    ForcingTransition,
    build_process_covariance,
    project_hbv_state,
)
from hbv_joint_uncertainty.sigma_filter import ScaledSigmaPoints  # noqa: E402


PARAMETERS = {
    "parFC": 200.0,
    "parCWH": 0.1,
    "parUZL": 5.0,
    "parPERC": 1.0,
    "parK2": 0.05,
}


FULL_PARAMETERS = {
    "parTT": 0.0,
    "parCFMAX": 3.0,
    "parCFR": 0.05,
    "parCWH": 0.1,
    "parFC": 200.0,
    "parBETA": 2.0,
    "parLP": 0.7,
    "parK0": 0.2,
    "parK1": 0.1,
    "parUZL": 5.0,
    "parPERC": 1.0,
    "parK2": 0.05,
    "lag_time": 3.0,
}


def _parameter_members():
    return [
        dict(FULL_PARAMETERS),
        {**FULL_PARAMETERS, "parFC": 100.0},
        {**FULL_PARAMETERS, "parFC": 400.0},
    ]


def test_atomic_save_npz_refuses_existing_target(tmp_path):
    target = tmp_path / "task.npz"
    target.write_bytes(b"existing evidence")

    with pytest.raises(FileExistsError, match="task output already exists"):
        _atomic_save_npz(target, values=np.array([1.0]))

    assert target.read_bytes() == b"existing evidence"


def test_atomic_save_npz_replaces_only_its_new_temporary_file(tmp_path):
    target = tmp_path / "task.npz"

    _atomic_save_npz(target, values=np.array([1.0, 2.0]))

    with np.load(target) as arrays:
        np.testing.assert_array_equal(arrays["values"], np.array([1.0, 2.0]))
    assert not target.with_suffix(".tmp.npz").exists()


def test_generate_truth_records_actual_daily_parfc_without_changing_truth_q(
    monkeypatch,
):
    import hbv_joint_uncertainty.hbv_adapter as adapter_module

    members = [
        {"parFC": 100.0, "lag_time": 1.0},
        {"parFC": 50.0, "lag_time": 2.0},
        {"parFC": 200.0, "lag_time": 3.0},
    ]
    rain = np.zeros(g2_module.WINDOW_DAYS)
    pet = np.zeros_like(rain)
    temperature = np.zeros_like(rain)
    initial = np.asarray([0.0, 0.0, 0.0, 0.0, 10.0])

    def fake_advance(state, _rain, _pet, _temperature, parameters, bounds):
        del bounds
        advanced = np.asarray(state, dtype=np.float64).copy()
        advanced[4] += parameters["parFC"] / 1000.0
        return advanced

    def fake_discharge(state, lag_time):
        return float(state[4] + lag_time)

    monkeypatch.setattr(adapter_module, "advance_state", fake_advance)
    monkeypatch.setattr(g2_module, "rising_routed_discharge", fake_discharge)

    def legacy_truth_q(seed):
        rng = np.random.default_rng(seed)
        state = np.zeros(g2_module.N_STATE, dtype=np.float64)
        state[:g2_module.N_HYDRO] = initial
        values = np.zeros(g2_module.WINDOW_DAYS, dtype=np.float64)
        day = 0
        for member_index in g2_module.ROTATION:
            parameters = members[member_index]
            for _ in range(g2_module.STAGE_DAYS):
                state = fake_advance(
                    state,
                    rain[day],
                    pet[day],
                    temperature[day],
                    parameters,
                    bounds={},
                )
                state[4] *= np.exp(
                    rng.normal(
                        -0.5 * g2_module.SLZ_LOGNORMAL_SIGMA ** 2,
                        g2_module.SLZ_LOGNORMAL_SIGMA,
                    )
                )
                values[day] = fake_discharge(state, parameters["lag_time"])
                day += 1
        return values

    expected_q = legacy_truth_q(12345)
    expected_parfc = np.concatenate([
        np.full(g2_module.STAGE_DAYS, members[index]["parFC"])
        for index in g2_module.ROTATION
    ])

    truth_q, truth_parfc, switch_days, clips = _generate_truth(
        members,
        rain,
        pet,
        temperature,
        initial,
        np.random.default_rng(12345),
        bounds={},
    )

    np.testing.assert_array_equal(truth_q, expected_q)
    np.testing.assert_array_equal(truth_parfc, expected_parfc)
    assert switch_days == [
        (stage * g2_module.STAGE_DAYS, member_index)
        for stage, member_index in enumerate(g2_module.ROTATION[1:], start=1)
    ]
    assert clips == 0


def test_direct_nested_diagnostics_fold_signed_zero_and_count_float_spacing():
    nested = np.asarray([0.0, 1.0, -1.0])
    direct = np.asarray([
        -0.0,
        np.nextafter(1.0, np.inf),
        np.nextafter(-1.0, -np.inf),
    ])

    absolute, relative, ulp_distance = _direct_nested_diagnostics(
        direct,
        nested,
    )

    np.testing.assert_array_equal(ulp_distance, np.asarray([0, 1, 1]))
    np.testing.assert_array_equal(absolute == 0.0, np.asarray([True, False, False]))
    np.testing.assert_array_equal(
        relative,
        absolute / np.maximum(1.0, np.maximum(np.abs(direct), np.abs(nested))),
    )

def test_all_hydrologic_states_matches_existing_process_covariance():
    expected = build_process_covariance(PARAMETERS, 1e-7)
    actual = build_filter_process_covariance(
        PARAMETERS, 1e-7, "all_hydrologic_states"
    )

    np.testing.assert_array_equal(actual, expected)


def test_lower_groundwater_only_preserves_only_existing_lower_groundwater_variance():
    all_states = build_process_covariance(PARAMETERS, 1e-7)
    lower_groundwater_only = build_filter_process_covariance(
        PARAMETERS, 1e-7, "lower_groundwater_state_only"
    )

    expected = np.zeros_like(all_states)
    expected[4, 4] = all_states[4, 4]
    np.testing.assert_array_equal(lower_groundwater_only, expected)
    assert np.count_nonzero(lower_groundwater_only) == 1


def test_unknown_process_covariance_structure_is_rejected():
    with pytest.raises(ValueError, match="process covariance structure"):
        build_filter_process_covariance(PARAMETERS, 1e-7, "unknown")


def test_state_dependent_covariance_matches_lognormal_first_two_moments():
    actual = build_state_dependent_lower_groundwater_covariance(100.0, 1.0)
    expected = np.zeros((15, 15), dtype=np.float64)
    expected[4, 4] = 100.0**2 * np.expm1(0.02**2)

    np.testing.assert_allclose(actual, expected, rtol=1e-14, atol=0.0)
    assert np.count_nonzero(actual) == 1


def test_state_dependent_covariance_multiplier_scales_variance_and_allows_zero_state():
    base = build_state_dependent_lower_groundwater_covariance(80.0, 1.0)
    quarter = build_state_dependent_lower_groundwater_covariance(80.0, 0.25)
    zero = build_state_dependent_lower_groundwater_covariance(0.0, 4.0)

    np.testing.assert_allclose(quarter, 0.25 * base, rtol=1e-14, atol=0.0)
    np.testing.assert_array_equal(zero, np.zeros((15, 15)))


@pytest.mark.parametrize(
    ("state", "multiplier", "message"),
    [(-1.0, 1.0, "lower-groundwater state"),
     (1.0, 0.0, "process-variance multiplier"),
     (np.nan, 1.0, "lower-groundwater state")],
)
def test_state_dependent_covariance_rejects_invalid_inputs(state, multiplier, message):
    with pytest.raises(ValueError, match=message):
        build_state_dependent_lower_groundwater_covariance(state, multiplier)


def test_filter_observation_covariance_multiplier_scales_variance_not_sigma():
    actual = build_filter_observation_covariance(0.5, 2.0)

    np.testing.assert_array_equal(actual, np.array([[0.5]]))


@pytest.mark.parametrize(
    ("sigma", "multiplier", "message"),
    [(0.0, 1.0, "observation sigma"),
     (1.0, -1.0, "observation-variance multiplier")],
)
def test_filter_observation_covariance_rejects_invalid_inputs(sigma, multiplier, message):
    with pytest.raises(ValueError, match=message):
        build_filter_observation_covariance(sigma, multiplier)


def test_assign_common_process_covariance_copies_one_matrix_to_every_filter():
    estimator = SimpleNamespace(filters=[SimpleNamespace(), SimpleNamespace()])
    covariance = build_state_dependent_lower_groundwater_covariance(80.0, 1.0)

    assign_common_process_covariance(estimator, covariance)

    np.testing.assert_array_equal(estimator.filters[0].process_covariance, covariance)
    np.testing.assert_array_equal(estimator.filters[1].process_covariance, covariance)
    assert estimator.filters[0].process_covariance is not estimator.filters[1].process_covariance


@pytest.mark.parametrize(
    ("events_total", "events_passed", "expected"),
    [
        (6, 5, "not_evaluated_incomplete_design_seeds"),
        (12, 12, "pass"),
        (12, 8, "partial"),
        (12, 7, "fail"),
    ],
)
def test_basin_verdict_does_not_label_single_seed_smoke_as_failure(
    events_total,
    events_passed,
    expected,
):
    assert classify_basin_verdict(events_total, events_passed) == expected


def test_legacy_bank_defaults_keep_parameter_grouping_and_direct_projection():
    init_hydro = np.array([0.0, 0.0, 160.0, 20.0, 30.0])
    members = _parameter_members()

    estimator, _ = _build_bank(
        members,
        init_hydro,
        sigma_obs=0.1,
        bounds={"parFC": (50.0, 1000.0)},
    )

    assert estimator.interaction_mode == STATE_INTERACTION_MODE == "parameter_grouped"
    assert estimator.parameter_state_mapping == PARAMETER_STATE_MAPPING_MODE == "legacy_projection"
    assert estimator.pairwise_moment_transform is None
    assert estimator.filters[1].state[2] == 100.0
    assert estimator.filters[1].state[3] == 20.0
    common_process_covariance = build_process_covariance(members[0], 1e-4)
    for candidate, parameters in zip(estimator.filters, members):
        raw_state = np.zeros(15, dtype=np.float64)
        raw_state[:5] = init_hydro
        expected_state = project_hbv_state(raw_state, parameters)
        expected_scales = np.maximum(np.abs(expected_state), 1.0)
        expected_covariance = np.diag((0.001 * expected_scales) ** 2)
        np.testing.assert_array_equal(candidate.state, expected_state)
        np.testing.assert_array_equal(candidate.covariance, expected_covariance)
        np.testing.assert_array_equal(
            candidate.process_covariance,
            common_process_covariance,
        )
        np.testing.assert_array_equal(
            candidate.observation_covariance,
            np.array([[0.1**2]]),
        )


def test_legacy_forcing_transition_without_custom_projector_matches_old_formula():
    parameters = dict(FULL_PARAMETERS)
    raw_state = np.array(
        [10.0, 2.0, 250.0, 20.0, 30.0, *np.linspace(1.0, 10.0, 10)],
        dtype=np.float64,
    )
    forcing = (12.0, 2.0, 5.0)
    transition = ForcingTransition(parameters)
    transition.set_forcing(*forcing)

    expected = project_hbv_state(
        advance_state(
            project_hbv_state(raw_state, parameters),
            *forcing,
            parameters,
        ),
        parameters,
    )
    actual = transition(raw_state)

    np.testing.assert_array_equal(actual, expected)


def test_corrected_bank_uses_full_interaction_and_conservative_initialization():
    init_hydro = np.array([0.0, 0.0, 160.0, 20.0, 30.0])

    estimator, transitions = _build_bank(
        _parameter_members(),
        init_hydro,
        sigma_obs=0.1,
        bounds={"parFC": (50.0, 1000.0)},
        interaction_mode="full",
        parameter_state_mapping="conservative_parfc",
    )

    assert estimator.interaction_mode == "full"
    assert estimator.parameter_state_mapping == "conservative_parfc"
    assert estimator.pairwise_moment_transform is not None
    assert all(transition.state_projector is not None for transition in transitions)
    half_capacity_state = estimator.filters[1].state
    assert half_capacity_state[2] == pytest.approx(100.0, abs=1e-12)
    assert half_capacity_state[3] == pytest.approx(80.0, abs=1e-12)
    assert half_capacity_state[:5].sum() == pytest.approx(init_hydro.sum(), abs=1e-12)
    common_state = np.zeros(15, dtype=np.float64)
    common_state[:5] = init_hydro
    common_scales = np.maximum(np.abs(common_state), 1.0)
    common_covariance = np.diag((0.001 * common_scales) ** 2)
    expected_half_state, expected_half_covariance = remap_parfc_moments(
        common_state,
        common_covariance,
        _parameter_members()[0],
        _parameter_members()[1],
        ScaledSigmaPoints(15),
    )
    np.testing.assert_allclose(
        estimator.filters[1].state,
        expected_half_state,
        rtol=0.0,
        atol=1e-12,
    )
    np.testing.assert_allclose(
        estimator.filters[1].covariance,
        expected_half_covariance,
        rtol=0.0,
        atol=1e-12,
    )

    prior_probabilities = estimator.interact()
    assert prior_probabilities.sum() == pytest.approx(1.0, abs=1e-15)
    for candidate, parameters in zip(estimator.filters, _parameter_members()):
        assert candidate.state[2] <= parameters["parFC"] + 1e-10
        assert candidate.state[:5].sum() == pytest.approx(init_hydro.sum(), abs=1e-9)
        assert np.linalg.eigvalsh(candidate.covariance).min() >= -1e-10


def test_build_bank_passes_the_same_model_evidence_scorer_to_both_methods():
    scorer = lambda result: result.log_likelihood
    common = dict(
        members=_parameter_members(),
        init_hydro=np.array([0.0, 0.0, 160.0, 20.0, 30.0]),
        sigma_obs=0.1,
        bounds={"parFC": (50.0, 1000.0)},
        parameter_state_mapping="conservative_parfc",
        model_evidence_scorer=scorer,
    )

    full_estimator, _ = _build_bank(interaction_mode="full", **common)
    path_estimator, _ = _build_bank(
        interaction_mode="pairwise_path_postcollapse",
        **common,
    )

    assert full_estimator.model_evidence_scorer is scorer
    assert path_estimator.model_evidence_scorer is scorer


def test_full_interaction_with_legacy_projection_is_an_isolated_diagnostic_arm():
    estimator, transitions = _build_bank(
        _parameter_members(),
        np.array([0.0, 0.0, 160.0, 20.0, 30.0]),
        sigma_obs=0.1,
        bounds={"parFC": (50.0, 1000.0)},
        interaction_mode="full",
        parameter_state_mapping="legacy_projection",
    )

    assert estimator.interaction_mode == "full"
    assert estimator.parameter_state_mapping == "legacy_projection"
    assert estimator.pairwise_moment_transform is None
    assert all(transition.state_projector is None for transition in transitions)


def test_conservative_mapping_requires_full_interaction():
    with pytest.raises(ValueError, match="requires full interaction"):
        _build_bank(
            _parameter_members(),
            np.array([0.0, 0.0, 80.0, 20.0, 30.0]),
            sigma_obs=0.1,
            bounds={"parFC": (50.0, 1000.0)},
            interaction_mode="parameter_grouped",
            parameter_state_mapping="conservative_parfc",
        )


@pytest.mark.parametrize(
    ("old_capacity", "new_capacity"),
    [(200.0, 100.0), (100.0, 400.0)],
)
@pytest.mark.parametrize(
    ("rain", "pet", "temperature"),
    [(0.0, 0.0, 5.0), (25.0, 2.0, 8.0), (10.0, 1.0, -3.0)],
)
def test_truth_boundary_step_matches_explicit_conservative_mapping(
    old_capacity,
    new_capacity,
    rain,
    pet,
    temperature,
):
    old_parameters = {**FULL_PARAMETERS, "parFC": old_capacity}
    new_parameters = {**FULL_PARAMETERS, "parFC": new_capacity}
    state = np.array(
        [10.0, 0.5, 160.0, 20.0, 30.0, *np.linspace(1.0, 10.0, 10)],
        dtype=np.float64,
    )

    direct = advance_state(
        state,
        rain,
        pet,
        temperature,
        new_parameters,
    )
    mapped = remap_parfc_state(state, old_parameters, new_parameters)
    explicit = advance_state(
        mapped,
        rain,
        pet,
        temperature,
        new_parameters,
    )

    np.testing.assert_allclose(explicit, direct, rtol=0.0, atol=1e-12)


def test_pairwise_path_bank_requires_conservative_mapping_and_preserves_old_builders():
    with pytest.raises(ValueError, match="requires conservative"):
        validate_parameter_interaction_contract(
            "pairwise_path_postcollapse",
            "legacy_projection",
        )

    path_estimator, _ = _build_bank(
        _parameter_members(),
        np.array([0.0, 0.0, 160.0, 20.0, 30.0]),
        sigma_obs=0.1,
        bounds={"parFC": (50.0, 1000.0)},
        interaction_mode="pairwise_path_postcollapse",
        parameter_state_mapping="conservative_parfc",
    )
    legacy_estimator, _ = _build_bank(
        _parameter_members(),
        np.array([0.0, 0.0, 160.0, 20.0, 30.0]),
        sigma_obs=0.1,
        bounds={"parFC": (50.0, 1000.0)},
    )
    full_estimator, _ = _build_bank(
        _parameter_members(),
        np.array([0.0, 0.0, 160.0, 20.0, 30.0]),
        sigma_obs=0.1,
        bounds={"parFC": (50.0, 1000.0)},
        interaction_mode="full",
        parameter_state_mapping="conservative_parfc",
    )

    assert isinstance(path_estimator, PairwisePathMultipleModel)
    assert len(path_estimator.filters) == 3
    assert path_estimator.interaction_mode == "pairwise_path_postcollapse"
    assert path_estimator.parameter_state_mapping == "conservative_parfc"
    assert path_estimator.hypothesis_collapse_timing == "after_observation"
    assert path_estimator.recursive_probability_representation == "ordinary_float"
    assert isinstance(legacy_estimator, InteractingMultipleModel)
    assert isinstance(full_estimator, InteractingMultipleModel)
    assert not hasattr(legacy_estimator, "hypothesis_collapse_timing")
    assert not hasattr(full_estimator, "recursive_probability_representation")


def test_pairwise_path_two_days_map_each_cross_hypothesis_once(monkeypatch):
    import hbv_joint_uncertainty.hbv_state_mapping as mapping_module

    original = mapping_module.remap_parfc_moments
    calls = []

    def recorded(source_mean, source_covariance, source_parameters,
                 destination_parameters, sigma_points):
        calls.append((source_parameters["parFC"], destination_parameters["parFC"]))
        return original(
            source_mean,
            source_covariance,
            source_parameters,
            destination_parameters,
            sigma_points,
        )

    monkeypatch.setattr(mapping_module, "remap_parfc_moments", recorded)
    estimator, transitions = _build_bank(
        _parameter_members()[:2],
        np.array([0.0, 0.0, 160.0, 20.0, 30.0]),
        sigma_obs=0.1,
        bounds={"parFC": (50.0, 1000.0)},
        interaction_mode="pairwise_path_postcollapse",
        parameter_state_mapping="conservative_parfc",
    )
    calls.clear()

    for observation in (1.0, 1.5):
        for transition in transitions:
            transition.set_forcing(0.0, 0.0, 5.0)
        estimator.step(np.array([observation]))

    center_capacity = _parameter_members()[0]["parFC"]
    half_capacity = _parameter_members()[1]["parFC"]
    assert calls.count((center_capacity, half_capacity)) == 2
    assert calls.count((half_capacity, center_capacity)) == 2
    assert (half_capacity, half_capacity) not in calls
    assert (center_capacity, center_capacity) not in calls


def test_pairwise_path_audit_shapes_reconstruct_probabilities_and_ordinary_recursion():
    estimator, transitions = _build_bank(
        _parameter_members(),
        np.array([0.0, 0.0, 160.0, 20.0, 30.0]),
        sigma_obs=0.1,
        bounds={"parFC": (50.0, 1000.0)},
        interaction_mode="pairwise_path_postcollapse",
        parameter_state_mapping="conservative_parfc",
    )
    audit = _allocate_pairwise_path_audit(
        n_days=2,
        n_candidates=3,
        n_state=15,
        n_observation=1,
    )
    results = []
    source_snapshots = []
    for day, observation in enumerate((1.0, 1.5)):
        for transition in transitions:
            transition.set_forcing(0.0, 0.0, 5.0)
        source_probabilities = estimator.probabilities.copy()
        source_states = np.asarray([
            candidate.state.copy() for candidate in estimator.filters
        ])
        source_covariances = np.asarray([
            candidate.covariance.copy() for candidate in estimator.filters
        ])
        source_snapshots.append((
            source_probabilities.copy(),
            source_states.copy(),
            source_covariances.copy(),
        ))
        result = estimator.step(np.array([observation]))
        results.append(result)
        _record_pairwise_path_audit(
            audit,
            day,
            source_probabilities,
            source_states,
            source_covariances,
            result,
        )
    arrays = _finalize_pairwise_path_audit(audit, estimator)

    assert arrays["path_source_probabilities"].shape == (2, 3)
    assert arrays["path_candidate_prior_probabilities"].shape == (2, 3)
    assert arrays["path_branch_prior_log_probabilities"].shape == (2, 3, 3)
    assert arrays["path_branch_posterior_log_probabilities"].shape == (2, 3, 3)
    assert arrays["path_branch_posterior_probabilities"].shape == (2, 3, 3)
    assert arrays["path_destination_raw_probabilities"].shape == (2, 3)
    assert arrays["path_posterior_probabilities"].shape == (2, 3)
    assert arrays["path_destination_raw_conditional_probabilities"].shape == (
        2, 3, 3
    )
    assert arrays["path_destination_conditional_probabilities"].shape == (2, 3, 3)
    assert arrays["path_posterior_log_probabilities"].shape == (2, 3)
    assert arrays["path_branch_active_mask"].shape == (2, 3, 3)
    assert arrays["path_branch_prior_observations"].shape == (2, 3, 3, 1)
    assert arrays["path_branch_innovations"].shape == (2, 3, 3, 1)
    assert arrays["path_branch_innovation_covariances"].shape == (2, 3, 3, 1, 1)
    assert arrays["path_branch_prior_states"].shape == (2, 3, 3, 15)
    assert arrays["path_branch_posterior_states"].shape == (2, 3, 3, 15)
    assert arrays["path_branch_prior_covariances"].shape == (2, 3, 3, 15, 15)
    assert arrays["path_branch_posterior_covariances"].shape == (2, 3, 3, 15, 15)
    assert arrays["path_source_states"].shape == (2, 3, 15)
    assert arrays["path_source_covariances"].shape == (2, 3, 15, 15)
    assert arrays["path_destination_states"].shape == (2, 3, 15)
    assert arrays["path_destination_covariances"].shape == (2, 3, 15, 15)
    assert arrays["path_combined_states"].shape == (2, 15)
    assert arrays["path_combined_covariances"].shape == (2, 15, 15)
    assert arrays["path_direct_states"].shape == (2, 15)
    assert arrays["path_direct_covariances"].shape == (2, 15, 15)
    np.testing.assert_array_equal(
        arrays["path_initial_probabilities"],
        source_snapshots[0][0],
    )
    np.testing.assert_array_equal(
        arrays["path_initial_states"],
        source_snapshots[0][1],
    )
    np.testing.assert_array_equal(
        arrays["path_initial_covariances"],
        source_snapshots[0][2],
    )
    np.testing.assert_array_equal(
        arrays["path_source_probabilities"][1],
        results[0].posterior_probabilities,
    )
    np.testing.assert_array_equal(
        arrays["path_source_states"][1],
        arrays["path_destination_states"][0],
    )
    np.testing.assert_array_equal(
        arrays["path_source_covariances"][1],
        arrays["path_destination_covariances"][0],
    )
    for day, result in enumerate(results):
        prior_branch_probabilities = normalize_log_weights(
            arrays["path_branch_prior_log_probabilities"][day].reshape(-1)
        ).reshape(3, 3)
        posterior_branch_probabilities = arrays[
            "path_branch_posterior_probabilities"
        ][day]
        np.testing.assert_allclose(
            prior_branch_probabilities.sum(axis=0),
            arrays["path_candidate_prior_probabilities"][day],
            rtol=0.0,
            atol=1e-15,
        )
        np.testing.assert_array_equal(
            posterior_branch_probabilities,
            result.branch_posterior_probabilities,
        )
        np.testing.assert_array_equal(
            arrays["path_destination_raw_probabilities"][day],
            result.destination_raw_probabilities,
        )
        np.testing.assert_array_equal(
            arrays["path_posterior_probabilities"][day],
            result.posterior_probabilities,
        )
        np.testing.assert_array_equal(
            arrays["path_posterior_log_probabilities"][day],
            result.posterior_log_probabilities,
        )
        np.testing.assert_array_equal(
            arrays["path_destination_raw_conditional_probabilities"][day],
            result.destination_raw_conditional_probabilities,
        )
        np.testing.assert_array_equal(
            arrays["path_destination_conditional_probabilities"][day],
            result.destination_conditional_probabilities,
        )
        np.testing.assert_array_equal(
            arrays["path_branch_active_mask"][day],
            result.branch_active_mask,
        )
        np.testing.assert_array_equal(
            arrays["path_destination_reference_indices"][day],
            result.destination_reference_indices,
        )
        assert arrays["path_global_reference_indices"][day] == (
            result.global_reference_index
        )
        np.testing.assert_array_equal(
            arrays["path_destination_states"][day],
            result.destination_states,
        )
        np.testing.assert_array_equal(
            arrays["path_destination_covariances"][day],
            result.destination_covariances,
        )
        np.testing.assert_array_equal(
            arrays["path_combined_states"][day],
            result.combined_state,
        )
        np.testing.assert_array_equal(
            arrays["path_combined_covariances"][day],
            result.combined_covariance,
        )
        np.testing.assert_array_equal(
            arrays["path_direct_states"][day],
            result.direct_state,
        )
        np.testing.assert_array_equal(
            arrays["path_direct_covariances"][day],
            result.direct_covariance,
        )
        for destination in range(3):
            destination_weights = arrays[
                "path_destination_conditional_probabilities"
            ][day, :, destination]
            active = destination_weights > 0.0
            destination_weights = destination_weights[active]
            branch_states = arrays["path_branch_posterior_states"][
                day, active, destination
            ]
            branch_covariances = arrays["path_branch_posterior_covariances"][
                day, active, destination
            ]
            reconstructed_state = np.sum(
                destination_weights[:, None] * branch_states,
                axis=0,
            )
            differences = branch_states - reconstructed_state
            reconstructed_covariance = np.sum(
                destination_weights[:, None, None]
                * (
                    branch_covariances
                    + np.einsum("ni,nj->nij", differences, differences)
                ),
                axis=0,
            )
            np.testing.assert_allclose(
                arrays["path_destination_states"][day, destination],
                reconstructed_state,
                rtol=0.0,
                atol=1e-12,
            )
            np.testing.assert_allclose(
                arrays["path_destination_covariances"][day, destination],
                reconstructed_covariance,
                rtol=0.0,
                atol=1e-11,
            )

        global_weights = arrays["path_posterior_probabilities"][day]
        destination_states = arrays["path_destination_states"][day]
        destination_covariances = arrays["path_destination_covariances"][day]
        reconstructed_state = np.sum(
            global_weights[:, None] * destination_states,
            axis=0,
        )
        differences = destination_states - reconstructed_state
        reconstructed_covariance = np.sum(
            global_weights[:, None, None]
            * (
                destination_covariances
                + np.einsum("ni,nj->nij", differences, differences)
            ),
            axis=0,
        )
        np.testing.assert_allclose(
            arrays["path_combined_states"][day],
            reconstructed_state,
            rtol=0.0,
            atol=1e-12,
        )
        np.testing.assert_allclose(
            arrays["path_combined_covariances"][day],
            reconstructed_covariance,
            rtol=0.0,
            atol=1e-11,
        )
        np.testing.assert_array_equal(
            arrays["path_direct_nested_state_absolute_differences"][day],
            np.abs(result.direct_state - result.combined_state),
        )
        np.testing.assert_array_equal(
            arrays["path_direct_nested_covariance_absolute_differences"][day],
            np.abs(result.direct_covariance - result.combined_covariance),
        )
    expected_second_prior = np.log(results[0].posterior_probabilities)[:, None]
    expected_second_prior = expected_second_prior + np.log(
        arrays["path_transition_matrix"]
    )
    np.testing.assert_allclose(
        arrays["path_branch_prior_log_probabilities"][1],
        expected_second_prior,
        rtol=0.0,
        atol=1e-15,
    )
    np.testing.assert_array_equal(
        arrays["path_direct_nested_state_max_abs_difference"],
        np.max(
            arrays["path_direct_nested_state_absolute_differences"],
            axis=1,
        ),
    )
    np.testing.assert_array_equal(
        arrays["path_direct_nested_covariance_max_abs_difference"],
        np.max(
            arrays["path_direct_nested_covariance_absolute_differences"],
            axis=(1, 2),
        ),
    )
    assert arrays["path_recursive_probability_representation"].item() == "ordinary_float"
    assert arrays["path_hypothesis_collapse_timing"].item() == "after_observation"
    assert arrays["path_initial_snapshot_timing"].item() == "before_day_0_step"
    assert arrays["path_branch_flatten_order"].item() == (
        "source_major_destination_minor"
    )
    assert arrays["path_reference_selection"].item() == (
        "maximum_weight_then_lowest_original_index"
    )
    assert arrays["path_unique_global_moment_role"].item() == (
        "authoritative_nested_destination_mixture"
    )
    assert arrays["path_direct_global_moment_role"].item() == (
        "nonblocking_diagnostic_only"
    )
    np.testing.assert_array_equal(
        arrays["path_branch_flatten_indices"],
        np.asarray([
            [0, 0], [0, 1], [0, 2],
            [1, 0], [1, 1], [1, 2],
            [2, 0], [2, 1], [2, 2],
        ]),
    )
    np.testing.assert_array_equal(
        arrays["path_transition_axis_order"],
        np.asarray(["source_candidate", "destination_candidate"]),
    )
    np.testing.assert_array_equal(
        arrays["path_initial_state_axis_order"],
        np.asarray(["candidate", "state"]),
    )
    np.testing.assert_array_equal(
        arrays["path_source_state_axis_order"],
        np.asarray(["day", "source_candidate", "state"]),
    )
    np.testing.assert_array_equal(
        arrays["path_destination_reference_index_axis_order"],
        np.asarray(["day", "destination_candidate"]),
    )
    np.testing.assert_array_equal(
        arrays["path_global_reference_index_axis_order"],
        np.asarray(["day"]),
    )
    np.testing.assert_array_equal(
        arrays["path_direct_covariance_axis_order"],
        np.asarray(["day", "state_row", "state_column"]),
    )
    np.testing.assert_array_equal(
        arrays["path_innovation_covariance_axis_order"],
        np.asarray([
            "day",
            "source_candidate",
            "destination_candidate",
            "observation_row",
            "observation_column",
        ]),
    )


def test_pairwise_path_audit_allocates_frozen_03b_weight_and_diagnostic_arrays():
    audit = _allocate_pairwise_path_audit(2, 3, 4, 1)

    expected_shapes = {
        "path_initial_probabilities": (3,),
        "path_initial_states": (3, 4),
        "path_initial_covariances": (3, 4, 4),
        "path_branch_posterior_probabilities": (2, 3, 3),
        "path_destination_raw_probabilities": (2, 3),
        "path_posterior_probabilities": (2, 3),
        "path_destination_raw_conditional_probabilities": (2, 3, 3),
        "path_destination_conditional_probabilities": (2, 3, 3),
        "path_posterior_log_probabilities": (2, 3),
        "path_destination_reference_indices": (2, 3),
        "path_global_reference_indices": (2,),
        "path_direct_states": (2, 4),
        "path_direct_covariances": (2, 4, 4),
        "path_direct_nested_state_absolute_differences": (2, 4),
        "path_direct_nested_state_relative_differences": (2, 4),
        "path_direct_nested_state_ulp_distances": (2, 4),
        "path_direct_nested_covariance_absolute_differences": (2, 4, 4),
        "path_direct_nested_covariance_relative_differences": (2, 4, 4),
        "path_direct_nested_covariance_ulp_distances": (2, 4, 4),
    }
    for name, shape in expected_shapes.items():
        assert audit[name].shape == shape


def test_pairwise_path_audit_does_not_call_production_probability_or_mixture_helpers(
    monkeypatch,
):
    import hbv_joint_uncertainty.imm as imm_module

    estimator, transitions = _build_bank(
        _parameter_members(),
        np.array([0.0, 0.0, 160.0, 20.0, 30.0]),
        sigma_obs=0.1,
        bounds={"parFC": (50.0, 1000.0)},
        interaction_mode="pairwise_path_postcollapse",
        parameter_state_mapping="conservative_parfc",
    )
    for transition in transitions:
        transition.set_forcing(0.0, 0.0, 5.0)
    source_probabilities = estimator.probabilities.copy()
    source_states = np.asarray([
        candidate.state.copy() for candidate in estimator.filters
    ])
    source_covariances = np.asarray([
        candidate.covariance.copy() for candidate in estimator.filters
    ])
    result = estimator.step(np.asarray([1.0]))
    audit = _allocate_pairwise_path_audit(1, 3, 15, 1)
    monkeypatch.setattr(
        imm_module,
        "normalize_log_weights_with_logs",
        lambda *_args, **_kwargs: pytest.fail(
            "audit must not call the production probability normalizer"
        ),
    )
    monkeypatch.setattr(
        imm_module,
        "_mixture_moments",
        lambda *_args, **_kwargs: pytest.fail(
            "audit must not call the production mixture helper"
        ),
    )

    _record_pairwise_path_audit(
        audit,
        0,
        source_probabilities,
        source_states,
        source_covariances,
        result,
    )

    np.testing.assert_array_equal(
        audit["path_branch_posterior_probabilities"][0],
        result.branch_posterior_probabilities,
    )


@pytest.mark.parametrize(
    "missing_field",
    [
        "branch_posterior_probabilities",
        "destination_states",
        "combined_state",
        "direct_state",
        "destination_reference_indices",
    ],
)
def test_pairwise_path_audit_rejects_missing_frozen_result_fields(missing_field):
    estimator, transitions = _build_bank(
        _parameter_members(),
        np.array([0.0, 0.0, 160.0, 20.0, 30.0]),
        sigma_obs=0.1,
        bounds={"parFC": (50.0, 1000.0)},
        interaction_mode="pairwise_path_postcollapse",
        parameter_state_mapping="conservative_parfc",
    )
    for transition in transitions:
        transition.set_forcing(0.0, 0.0, 5.0)
    source_probabilities = estimator.probabilities.copy()
    source_states = np.asarray([
        candidate.state.copy() for candidate in estimator.filters
    ])
    source_covariances = np.asarray([
        candidate.covariance.copy() for candidate in estimator.filters
    ])
    result = estimator.step(np.asarray([1.0]))
    incomplete = SimpleNamespace(**result.__dict__)
    delattr(incomplete, missing_field)
    audit = _allocate_pairwise_path_audit(1, 3, 15, 1)

    with pytest.raises(AttributeError, match=missing_field):
        _record_pairwise_path_audit(
            audit,
            0,
            source_probabilities,
            source_states,
            source_covariances,
            incomplete,
        )


def test_pairwise_path_audit_saves_production_direct_moments_without_recombining():
    weights = np.asarray([
        0.019808803552550328,
        0.045204153394487794,
        0.23249692857685336,
        0.04022889003603264,
        0.008321490140938408,
        0.1078618398255359,
        0.025216945922034464,
        0.5045389652933723,
        0.01632198325819476,
    ])
    states = np.asarray([
        -1397.400401178109,
        -345.34825180330625,
        679.4776662464966,
        -79.29085820279444,
        816.4045210312361,
        -383.0400246313723,
        734.0695630237582,
        -445.01609224578254,
        891.0641387535546,
    ])
    covariances = np.asarray([
        2427.929111804098,
        394549.42141217843,
        1223.026793240322,
        174074.99389096542,
        65.00594790960302,
        1438.2299093571846,
        3099.4885404908996,
        548.3532051113182,
        21590.542280777863,
    ])
    branch_logs = np.log(weights).reshape(3, 3)
    normalized_weights = normalize_log_weights(branch_logs.reshape(-1))
    combined_state = math.fsum(
        float(weight * state)
        for weight, state in zip(normalized_weights, states)
    )
    combined_covariance = math.fsum(
        float(
            weight
            * (covariance + (state - combined_state) ** 2)
        )
        for weight, state, covariance in zip(
            normalized_weights,
            states,
            covariances,
        )
    )
    ordinary_covariance = 0.0
    for weight, state, covariance in zip(
        normalized_weights,
        states,
        covariances,
    ):
        ordinary_covariance += float(
            weight * (covariance + (state - combined_state) ** 2)
        )
    assert abs(ordinary_covariance - combined_covariance) > 1e-11
    branch_probabilities = normalized_weights.reshape(3, 3)
    destination_raw_probabilities = branch_probabilities.sum(axis=0)
    posterior_probabilities = (
        destination_raw_probabilities / destination_raw_probabilities.sum()
    )
    raw_conditional_probabilities = (
        branch_probabilities / destination_raw_probabilities[None, :]
    )
    conditional_probabilities = (
        raw_conditional_probabilities
        / raw_conditional_probabilities.sum(axis=0, keepdims=True)
    )
    branches = []
    for source in range(3):
        row = []
        for destination in range(3):
            index = 3 * source + destination
            row.append(SimpleNamespace(
                log_likelihood=0.0,
                prior_observation=np.zeros(1),
                innovation=np.zeros(1),
                innovation_covariance=np.eye(1),
                prior_state=np.asarray([states[index]]),
                posterior_state=np.asarray([states[index]]),
                prior_covariance=np.asarray([[covariances[index]]]),
                posterior_covariance=np.asarray([[covariances[index]]]),
            ))
        branches.append(row)
    result = SimpleNamespace(
        prior_probabilities=np.full(3, 1.0 / 3.0),
            branch_prior_log_probabilities=branch_logs,
            branch_posterior_log_probabilities=branch_logs,
            branch_posterior_probabilities=branch_probabilities,
            destination_raw_probabilities=destination_raw_probabilities,
            posterior_probabilities=posterior_probabilities,
            posterior_log_probabilities=np.log(posterior_probabilities),
            destination_raw_conditional_probabilities=(
                raw_conditional_probabilities
            ),
            destination_conditional_probabilities=conditional_probabilities,
            branch_active_mask=np.ones((3, 3), dtype=bool),
            destination_reference_indices=np.argmax(
                conditional_probabilities,
                axis=0,
            ),
            global_reference_index=int(np.argmax(posterior_probabilities)),
            branch_results=branches,
        destination_states=np.zeros((3, 1)),
        destination_covariances=np.zeros((3, 1, 1)),
            combined_state=np.asarray([combined_state]),
            combined_covariance=np.asarray([[combined_covariance]]),
            direct_state=np.asarray([combined_state]),
            direct_covariance=np.asarray([[combined_covariance]]),
    )
    audit = _allocate_pairwise_path_audit(1, 3, 1, 1)

    _record_pairwise_path_audit(
        audit,
        0,
        np.full(3, 1.0 / 3.0),
        np.zeros((3, 1)),
        np.zeros((3, 1, 1)),
        result,
    )

    assert audit["path_direct_nested_state_max_abs_difference"][0] <= 1e-12
    assert audit["path_direct_nested_covariance_max_abs_difference"][0] <= 1e-11
    np.testing.assert_array_equal(
        audit["path_direct_states"][0],
        result.direct_state,
    )
    np.testing.assert_array_equal(
        audit["path_direct_covariances"][0],
        result.direct_covariance,
    )


def test_pairwise_path_audit_marks_inactive_paths_and_old_mode_emits_no_path_fields():
    estimator, transitions = _build_bank(
        _parameter_members()[:2],
        np.array([0.0, 0.0, 80.0, 20.0, 30.0]),
        sigma_obs=0.1,
        bounds={"parFC": (50.0, 1000.0)},
        interaction_mode="pairwise_path_postcollapse",
        parameter_state_mapping="conservative_parfc",
    )
    estimator.transition_matrix = np.eye(2)
    estimator.log_transition_matrix = np.array(
        [[0.0, -np.inf], [-np.inf, 0.0]],
        dtype=np.float64,
    )
    audit = _allocate_pairwise_path_audit(1, 2, 15, 1)
    for transition in transitions:
        transition.set_forcing(0.0, 0.0, 5.0)
    source_probabilities = estimator.probabilities.copy()
    source_states = np.asarray([
        candidate.state.copy() for candidate in estimator.filters
    ])
    source_covariances = np.asarray([
        candidate.covariance.copy() for candidate in estimator.filters
    ])
    result = estimator.step(np.array([1.0]))
    _record_pairwise_path_audit(
        audit,
        0,
        source_probabilities,
        source_states,
        source_covariances,
        result,
    )
    arrays = _finalize_pairwise_path_audit(audit, estimator)
    inactive = ~arrays["path_branch_active_mask"]

    assert np.all(np.isneginf(arrays["path_branch_prior_log_probabilities"][inactive]))
    assert np.all(np.isneginf(arrays["path_branch_posterior_log_probabilities"][inactive]))
    assert np.all(np.isneginf(arrays["path_branch_log_likelihoods"][inactive]))
    assert np.all(arrays["path_branch_posterior_probabilities"][inactive] == 0.0)
    assert np.all(
        arrays["path_destination_raw_conditional_probabilities"][inactive] == 0.0
    )
    assert np.all(
        arrays["path_destination_conditional_probabilities"][inactive] == 0.0
    )
    assert np.all(np.isnan(arrays["path_branch_prior_states"][inactive]))
    assert np.all(np.isnan(arrays["path_branch_posterior_covariances"][inactive]))

    old_estimator, _ = _build_bank(
        _parameter_members(),
        np.array([0.0, 0.0, 80.0, 20.0, 30.0]),
        sigma_obs=0.1,
        bounds={"parFC": (50.0, 1000.0)},
    )
    assert _finalize_pairwise_path_audit(None, old_estimator) == {}
