from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
V01_EXPERIMENT_ID = "g3_state_weight_factorial_param_switch_v01"
V02_EXPERIMENT_ID = "g3_state_weight_factorial_param_switch_v02"
V03_EXPERIMENT_ID = "g3_state_weight_factorial_param_switch_v03"
V01_CONFIG_PATH = (
    REPO_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "configs"
    / f"{V01_EXPERIMENT_ID}.json"
)
V02_CONFIG_PATH = (
    REPO_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "configs"
    / f"{V02_EXPERIMENT_ID}.json"
)
V03_CONFIG_PATH = (
    REPO_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "configs"
    / f"{V03_EXPERIMENT_ID}.json"
)
REGISTRY_PATH = (
    REPO_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "configs"
    / "g3_experiment_registry.csv"
)

EXPECTED_CANDIDATE_ORDER = [
    "equifinal_diverse_1__process_2",
    "trained_center__process_2",
    "equifinal_diverse_2__process_2",
]
EXPECTED_COMBINATIONS = [
    "full_states_full_weights",
    "full_states_none_weights",
    "none_states_full_weights",
    "none_states_none_weights",
]
EXPECTED_EXISTING_PROTECTED_PATHS = [
    "results/23_hbv_multilead_joint_uncertainty/g3_ideal_gate_param_switch_v01",
    "results/23_hbv_multilead_joint_uncertainty/g3_phase2_interaction_value_param_switch_v01",
    "results/23_hbv_multilead_joint_uncertainty/g3_forecast_weight_drift_param_switch_v01",
    "results/23_hbv_multilead_joint_uncertainty/g3_drift_candidate_paths_verification_v01",
    "results/23_hbv_multilead_joint_uncertainty/g3_corrected_forecast_param_switch_v01",
    "results/23_hbv_multilead_joint_uncertainty/g3_corrected_forecast_param_switch_v01.preregistered.json",
    "results/23_hbv_multilead_joint_uncertainty/g3_highest_posterior_forecast_param_switch_v01",
    "results/23_hbv_multilead_joint_uncertainty/g3_highest_posterior_forecast_param_switch_v01.preregistered.json",
    "results/23_hbv_multilead_joint_uncertainty/g2_spacing_inputs_v01",
    "results/23_hbv_multilead_joint_uncertainty/g3_ideal_inputs_v01",
    "results/23_hbv_multilead_joint_uncertainty/formal_contract_sixteen_v05",
    "results/23_hbv_multilead_joint_uncertainty/three_stage_switching_resource_pilot_v01",
    "docs/plans/2026-07-23-g3-ideal-experiment-gate-design.md",
    "docs/plans/2026-07-23-g3-ideal-gate-closure.md",
    "docs/plans/2026-07-23-g3-phase2-interaction-value-comparison-design.md",
    "docs/plans/2026-07-23-g3-phase2-closure.md",
    "docs/plans/2026-07-24-g3-forecast-weight-drift-design.md",
    "docs/plans/2026-07-24-g3-forecast-weight-drift-closure.md",
    "docs/plans/2026-07-25-g3-corrected-forecast-comparison-design.md",
    "docs/plans/2026-07-25-g3-corrected-forecast-comparison.md",
    "docs/plans/2026-07-25-g3-corrected-forecast-comparison-closure.md",
    "docs/plans/2026-07-26-g3-highest-posterior-forecast-design.md",
    "docs/plans/2026-07-26-g3-highest-posterior-forecast.md",
    "docs/plans/2026-07-26-g3-highest-posterior-forecast-closure.md",
    "docs/plans/2026-07-26-g3-state-weight-factorial-forecast-design.md",
    "docs/plans/2026-07-26-g3-state-weight-factorial-forecast-design-amendment-01.md",
    "docs/plans/2026-07-26-g3-state-weight-factorial-forecast.md",
    "src/hbv_multilead_joint_uncertainty/configs/g3_ideal_gate_param_switch_v01.json",
    "src/hbv_multilead_joint_uncertainty/configs/g3_phase2_interaction_value_param_switch_v01.json",
    "src/hbv_multilead_joint_uncertainty/configs/g3_forecast_weight_drift_param_switch_v01.json",
    "src/hbv_multilead_joint_uncertainty/configs/g3_drift_candidate_paths_verification_v01.json",
    "src/hbv_multilead_joint_uncertainty/configs/g3_corrected_forecast_param_switch_v01.json",
    "src/hbv_multilead_joint_uncertainty/configs/g3_highest_posterior_forecast_param_switch_v01.json",
]
EXPECTED_CONFIG_PROTECTED_PATH = (
    "src/hbv_multilead_joint_uncertainty/configs/"
    "g3_state_weight_factorial_param_switch_v01.json"
)
EXPECTED_RECOVERY_PROTECTED_PATHS = [
    (
        "results/23_hbv_multilead_joint_uncertainty/"
        "g3_state_weight_factorial_param_switch_v01.preregistered.json"
    ),
    (
        "results/23_hbv_multilead_joint_uncertainty/"
        "g3_state_weight_factorial_param_switch_v01.formal.stdout.log"
    ),
    (
        "results/23_hbv_multilead_joint_uncertainty/"
        "g3_state_weight_factorial_param_switch_v01.formal.stderr.log"
    ),
    (
        "results/23_hbv_multilead_joint_uncertainty/"
        "g3_state_weight_factorial_param_switch_v01.failed.json"
    ),
    "docs/plans/2026-07-26-g3-state-weight-factorial-v01-failure.md",
    (
        "src/hbv_multilead_joint_uncertainty/configs/"
        "g3_state_weight_factorial_param_switch_v02.json"
    ),
]
EXPECTED_PACKAGING_RECOVERY_PROTECTED_PATHS = [
    (
        "results/23_hbv_multilead_joint_uncertainty/"
        "g3_state_weight_factorial_param_switch_v02.preregistered.json"
    ),
    (
        "results/23_hbv_multilead_joint_uncertainty/"
        "g3_state_weight_factorial_param_switch_v02.formal.stdout.log"
    ),
    (
        "results/23_hbv_multilead_joint_uncertainty/"
        "g3_state_weight_factorial_param_switch_v02.formal.stderr.log"
    ),
    (
        "results/23_hbv_multilead_joint_uncertainty/"
        "g3_state_weight_factorial_param_switch_v02.incomplete"
    ),
    (
        "results/23_hbv_multilead_joint_uncertainty/"
        "g3_state_weight_factorial_param_switch_v02.failed.json"
    ),
    "docs/plans/2026-07-26-g3-state-weight-factorial-v02-failure.md",
    (
        "src/hbv_multilead_joint_uncertainty/configs/"
        "g3_state_weight_factorial_param_switch_v03.json"
    ),
]


def _load_config(path: Path = V01_CONFIG_PATH) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def test_state_weight_factorial_config_freezes_scientific_contract():
    config = _load_config()

    assert config["experiment_id"] == V01_EXPERIMENT_ID
    assert config["scenario"] == "parameter_switch"
    assert (
        config["design_doc"]
        == "docs/plans/2026-07-26-g3-state-weight-factorial-forecast-design.md"
    )
    assert (
        config["design_amendment"]
        == "docs/plans/2026-07-26-g3-state-weight-factorial-forecast-design-amendment-01.md"
    )
    assert (
        config["implementation_plan"]
        == "docs/plans/2026-07-26-g3-state-weight-factorial-forecast.md"
    )
    assert config["primary_candidate_method_name"] == "parameter_only"
    assert config["candidate_order"] == EXPECTED_CANDIDATE_ORDER

    assert config["sealed_ideal_input_evidence"] == {
        "path": (
            "results/23_hbv_multilead_joint_uncertainty/"
            "g3_ideal_gate_param_switch_v01/evidence.npz"
        ),
        "sha256": (
            "77f84d793f18a72972e5af5f2ac4ed7"
            "67645471e37da31c612ab995ecf4bbf67"
        ),
    }
    assert config["sealed_forecast_reference_evidence"] == {
        "path": (
            "results/23_hbv_multilead_joint_uncertainty/"
            "g3_highest_posterior_forecast_param_switch_v01/evidence.npz"
        ),
        "sha256": (
            "05aaaeb49ee621eeaee5acd7dd326480"
            "054bc8416222cbcafee1ac4d9269a835"
        ),
    }
    assert config["forecast_contract"] == {
        "model_transition_during_forecast": "identity",
        "candidate_probabilities_during_forecast": (
            "fixed_at_final_assimilation_posterior"
        ),
        "cross_candidate_state_mixing_during_forecast": False,
    }
    assert config["assimilation_modes"] == ["full", "none"]
    assert config["combination_names"] == EXPECTED_COMBINATIONS

    assert config["bootstrap"] == {
        "unit": "matched_block",
        "replicates": 20000,
        "seed": 3310757,
        "shared_resample_indices_across_leads": True,
        "minimum_rmse_fraction": 0.01,
    }
    assert config["decision_rules"] == {
        "comparison_baselines": {
            "main_weight_effect": "none_states_none_weights",
            "weight_effect_review": "full_states_none_weights",
            "main_candidate_forecast_distribution_effect": (
                "none_states_none_weights"
            ),
            "candidate_forecast_distribution_effect_review": (
                "none_states_full_weights"
            ),
            "complete_difference": "none_states_none_weights",
            "wrong_candidate_comparison": "true_candidate_forecast",
        },
        "minimum_meaningful_root_mean_square_error_fraction": 0.01,
        "practical_equivalence_lower_mse_multiplier": -0.0199,
        "practical_equivalence_upper_mse_multiplier": 0.0201,
        "zero_wrong_candidate_denominator_policy": "fail_formal_statistics",
    }


def test_state_weight_factorial_config_freezes_inputs_resources_and_checks():
    config = _load_config()

    assert config["parameter_source"] == {
        "path": (
            "results/23_hbv_multilead_joint_uncertainty/"
            "g2_spacing_inputs_v01/parameter_vectors_m80.csv"
        ),
        "sha256": (
            "845d5bbd70e9f5dc373de1d01303a33d"
            "9c59932ec05901eb8c2c901ca505a292"
        ),
        "source_basin_id": "12143600",
        "parameter_ids": [
            "equifinal_diverse_1",
            "trained_center",
            "equifinal_diverse_2",
        ],
    }
    assert config["process_noise_source"] == {
        "path": (
            "results/23_hbv_multilead_joint_uncertainty/"
            "formal_contract_sixteen_v05/process_noise_covariances.csv"
        ),
        "sha256": (
            "b95b637a40c0a6f1f15d8b81739f35a"
            "c60a8ae3d85aa3872ad47ada17c8684d2"
        ),
        "source_basin_id": "12143600",
        "process_ids": ["process_0", "process_1", "process_2"],
        "selected_process_id": "process_2",
    }
    assert config["observation_noise_source"] == {
        "path": (
            "results/23_hbv_multilead_joint_uncertainty/"
            "g3_ideal_inputs_v01/observation_noise_low.csv"
        ),
        "sha256": (
            "0ff9a34b0dd863e99e40038b0876d781"
            "561a0a1e9d371a81ee3b8fafff6ef3c8"
        ),
        "source_basin_id": "12143600",
    }
    assert len(config["matched_blocks"]) == 8
    for index, block in enumerate(config["matched_blocks"], start=1):
        assert block == {
            "block_id": f"g3_ideal_block_{index:02d}",
            "forcing_seed": 3301000 + index,
            "process_noise_seed": 3302000 + index,
            "observation_noise_seed": 3303000 + index,
        }
    assert config["forcing"] == {
        "warmup_days": 45,
        "reference_total_days": 592,
        "rain_shape": 0.8,
        "rain_scale": 4.0,
    }
    assert config["stage_lengths"] == [180, 180, 180]
    assert config["lead_days"] == [1, 3, 7]
    assert config["initial_covariance_fraction"] == 0.001
    assert config["factor_transition_stay_probability"] == 0.98
    assert config["resource_pilot"] == {
        "source": (
            "results/23_hbv_multilead_joint_uncertainty/"
            "three_stage_switching_resource_pilot_v01/"
            "resource_pilot_measurements.json"
        ),
        "sha256": (
            "38e2d86f5989b897540515515c7b5a87"
            "74fb5fa854f957c28b3fbe53d18d409c"
        ),
        "block_count": 1,
        "truth_trial_count": 3,
        "elapsed_seconds": 11.424556999991182,
        "observed_peak_resident_memory_growth_bytes": 38359040,
        "abort_when_preflight_safe_to_run_is_false": True,
    }
    assert config["cross_check_contract"] == {
        "direct_arrays": {"rtol": 0.0, "atol": 0.0},
        "weighted_reconstructions": {"rtol": 0.0, "atol": 1e-12},
        "save_maximum_absolute_error": True,
    }
    assert config["interpretation_contract"] == {
        "non_diagonal_combinations": (
            "end_of_assimilation_recomposition_diagnostic_only"
        ),
        "non_diagonal_combinations_are_deployable_methods": False,
        "causal_effect_claimed": False,
        "candidate_forecast_distribution_effect_includes": [
            "terminal_candidate_state_means",
            "terminal_candidate_full_covariances",
            "assimilation_interaction_history",
        ],
    }


def test_state_weight_factorial_config_protects_all_prior_artifacts_and_itself():
    config = _load_config()
    expected = EXPECTED_EXISTING_PROTECTED_PATHS + [
        EXPECTED_CONFIG_PROTECTED_PATH
    ]

    assert len(EXPECTED_EXISTING_PROTECTED_PATHS) == 33
    assert config["protected_paths"] == expected
    assert len(set(config["protected_paths"])) == 34
    for relative_path in config["protected_paths"]:
        assert (REPO_ROOT / relative_path).exists(), relative_path


def test_recovery_config_changes_only_identity_validation_and_governance():
    v01 = _load_config(V01_CONFIG_PATH)
    v02 = _load_config(V02_CONFIG_PATH)

    unchanged_v01 = {
        key: value
        for key, value in v01.items()
        if key not in {"experiment_id", "cross_check_contract", "protected_paths"}
    }
    unchanged_v02 = {
        key: value
        for key, value in v02.items()
        if key
        not in {
            "experiment_id",
            "cross_check_contract",
            "protected_paths",
            "recovery_from_failed_attempt",
        }
    }
    assert unchanged_v02 == unchanged_v01
    assert v02["experiment_id"] == V02_EXPERIMENT_ID
    assert v02["recovery_from_failed_attempt"] == {
        "experiment_id": V01_EXPERIMENT_ID,
        "failure_record": {
            "path": (
                "results/23_hbv_multilead_joint_uncertainty/"
                "g3_state_weight_factorial_param_switch_v01.failed.json"
            ),
            "sha256": (
                "4ac689b4de00275a51caab2f67e1bb4b"
                "dbd2f5d39e6874a8a9fc95a87ef153db"
            ),
        },
        "scientific_contract_changed": False,
        "numerical_validation_changed": True,
        "observed_maximum_absolute_probability_error": (
            1.1102230246251565e-16
        ),
        "forecast_probability_absolute_tolerance": 1e-12,
    }
    failure_record = v02["recovery_from_failed_attempt"]["failure_record"]
    failure_path = REPO_ROOT / failure_record["path"]
    actual_digest = hashlib.sha256(failure_path.read_bytes()).hexdigest()
    assert actual_digest == failure_record["sha256"]
    assert v02["cross_check_contract"] == {
        **v01["cross_check_contract"],
        "forecast_probability_freezing": {"rtol": 0.0, "atol": 1e-12},
    }


def test_recovery_config_protects_failed_attempt_and_itself():
    v01 = _load_config(V01_CONFIG_PATH)
    v02 = _load_config(V02_CONFIG_PATH)
    expected = v01["protected_paths"] + EXPECTED_RECOVERY_PROTECTED_PATHS

    assert v02["protected_paths"] == expected
    assert len(v02["protected_paths"]) == 40
    assert len(set(v02["protected_paths"])) == 40
    for relative_path in v02["protected_paths"]:
        assert (REPO_ROOT / relative_path).exists(), relative_path


def test_packaging_recovery_changes_only_identity_and_governance():
    v02 = _load_config(V02_CONFIG_PATH)
    v03 = _load_config(V03_CONFIG_PATH)
    unchanged_v02 = {
        key: value
        for key, value in v02.items()
        if key
        not in {
            "experiment_id",
            "protected_paths",
            "recovery_from_failed_attempt",
        }
    }
    unchanged_v03 = {
        key: value
        for key, value in v03.items()
        if key
        not in {
            "experiment_id",
            "protected_paths",
            "recovery_from_failed_attempt",
        }
    }

    assert unchanged_v03 == unchanged_v02
    assert v03["experiment_id"] == V03_EXPERIMENT_ID
    assert v03["recovery_from_failed_attempt"] == {
        "experiment_id": V02_EXPERIMENT_ID,
        "failure_record": {
            "path": (
                "results/23_hbv_multilead_joint_uncertainty/"
                "g3_state_weight_factorial_param_switch_v02.failed.json"
            ),
            "sha256": (
                "6b6814cdd7d87fb9238c8d49cee90055"
                "83c63d2bc1c21973ec4131adb102cb3e"
            ),
        },
        "scientific_contract_changed": False,
        "numerical_validation_changed": False,
        "packaging_implementation_changed": True,
        "failed_target_absolute_length": 267,
        "windows_extended_length_paths": True,
    }
    failure_record = v03["recovery_from_failed_attempt"]["failure_record"]
    actual_digest = hashlib.sha256(
        (REPO_ROOT / failure_record["path"]).read_bytes()
    ).hexdigest()
    assert actual_digest == failure_record["sha256"]


def test_packaging_recovery_protects_v02_failure_and_itself():
    v02 = _load_config(V02_CONFIG_PATH)
    v03 = _load_config(V03_CONFIG_PATH)
    expected = v02["protected_paths"] + EXPECTED_PACKAGING_RECOVERY_PROTECTED_PATHS

    assert v03["protected_paths"] == expected
    assert len(v03["protected_paths"]) == 47
    assert len(set(v03["protected_paths"])) == 47
    for relative_path in v03["protected_paths"]:
        assert (REPO_ROOT / relative_path).exists(), relative_path


def _registry_rows(experiment_id: str) -> list[dict[str, str]]:
    with REGISTRY_PATH.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames == [
            "exp_id",
            "type",
            "hypothesis",
            "base_config",
            "changed_factor",
            "fixed_factors",
            "seeds",
            "status",
            "run_dir",
            "best_checkpoint",
            "metrics_path",
            "paper_name",
            "notes",
        ]
        return [row for row in reader if row["exp_id"] == experiment_id]


def test_failed_attempt_registry_row_is_permanent_and_exact():
    assert _registry_rows(V01_EXPERIMENT_ID) == [
        {
            "exp_id": V01_EXPERIMENT_ID,
            "type": "mechanism diagnostic",
            "hypothesis": (
                "Final candidate-weight concentration and assimilation-interaction "
                "candidate forecast distributions jointly explain the absent "
                "forecast advantage"
            ),
            "base_config": f"{V01_EXPERIMENT_ID}.json",
            "changed_factor": (
                "final candidate weights crossed with assimilation-interaction "
                "candidate forecast distributions"
            ),
            "fixed_factors": (
                "exact sealed truth observations candidates assimilation setup "
                "and frozen forecast contract"
            ),
            "seeds": "3301001-3310757",
            "status": "failed",
            "run_dir": (
                "results/23_hbv_multilead_joint_uncertainty/"
                "g3_state_weight_factorial_param_switch_v01"
            ),
            "best_checkpoint": "not applicable",
            "metrics_path": "not produced",
            "paper_name": "G3 state-weight factorial forecast diagnostic",
            "notes": (
                "Formal attempt failed before scientific output because a 1.11e-16 "
                "probability roundoff triggered an over-strict guard; "
                "preregistration and logs retained; recovered as "
                "g3_state_weight_factorial_param_switch_v02"
            ),
        }
    ]


def test_v02_packaging_failure_registry_row_is_permanent_and_exact():
    assert _registry_rows(V02_EXPERIMENT_ID) == [
        {
            "exp_id": V02_EXPERIMENT_ID,
            "type": "mechanism diagnostic",
            "hypothesis": (
                "Final candidate-weight concentration and assimilation-interaction "
                "candidate forecast distributions jointly explain the absent "
                "forecast advantage"
            ),
            "base_config": f"{V02_EXPERIMENT_ID}.json",
            "changed_factor": (
                "final candidate weights crossed with assimilation-interaction "
                "candidate forecast distributions"
            ),
            "fixed_factors": (
                "exact sealed truth observations candidates assimilation setup "
                "and frozen forecast contract"
            ),
            "seeds": "3301001-3310757",
            "status": "failed",
            "run_dir": (
                "results/23_hbv_multilead_joint_uncertainty/"
                "g3_state_weight_factorial_param_switch_v02"
            ),
            "best_checkpoint": "not applicable",
            "metrics_path": "not produced",
            "paper_name": "G3 state-weight factorial forecast diagnostic",
            "notes": (
                "Formal attempt completed calculations but failed during a "
                "267-character source-snapshot copy; incomplete evidence retained "
                "and is not a formal result; recovered as "
                "g3_state_weight_factorial_param_switch_v03"
            ),
        }
    ]


def test_v03_packaging_recovery_registry_has_one_exact_preregistered_row():
    assert _registry_rows(V03_EXPERIMENT_ID) == [
        {
            "exp_id": V03_EXPERIMENT_ID,
            "type": "mechanism diagnostic",
            "hypothesis": (
                "Final candidate-weight concentration and assimilation-interaction "
                "candidate forecast distributions jointly explain the absent "
                "forecast advantage"
            ),
            "base_config": f"{V03_EXPERIMENT_ID}.json",
            "changed_factor": (
                "final candidate weights crossed with assimilation-interaction "
                "candidate forecast distributions"
            ),
            "fixed_factors": (
                "exact sealed truth observations candidates assimilation setup "
                "and frozen forecast contract"
            ),
            "seeds": "3301001-3310757",
            "status": "preregistered",
            "run_dir": (
                "results/23_hbv_multilead_joint_uncertainty/"
                "g3_state_weight_factorial_param_switch_v03"
            ),
            "best_checkpoint": "not applicable",
            "metrics_path": "summary.json",
            "paper_name": "G3 state-weight factorial forecast diagnostic",
            "notes": (
                "Recovery of failed v02 with unchanged scientific contract; "
                "only evidence packaging adds Windows extended-length paths"
            ),
        }
    ]
