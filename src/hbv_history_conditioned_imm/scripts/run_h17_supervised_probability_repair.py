"""Run one frozen supervised probability repair without authorizing H18."""

from __future__ import annotations

import argparse
from copy import deepcopy
import json
from pathlib import Path
from typing import Any, Mapping

from hbv_history_conditioned_imm.scripts.run_h01_end_to_end_smoke import _sha256
from hbv_history_conditioned_imm.scripts.run_h17_supervised_probability_upper_bound import (
    load_h17_config,
    run_h17_probability_upper_bound,
)


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = (
    PACKAGE_ROOT / "configs/h17a_shared_hazard_supervised_probability_v01.json"
)
H17E_EXPERIMENT_ID = (
    "h17e_monotone_piecewise_linear_age_risk_supervised_probability_v01"
)
H17F_EXPERIMENT_ID = (
    "h17f_monotone_piecewise_age_risk_learning_rate_0p075_"
    "supervised_probability_v01"
)
EXPECTED_REPAIRS = {
    "h17a_shared_hazard_supervised_probability_v01": {
        "attempt_number": 1,
        "changed_factors": ["network.output_parameterization"],
        "network_output_parameterization": "shared_hazard",
        "training_objective": "active_row_brier",
        "training_weighting": "uniform",
    },
    "h17b_active_row_cross_entropy_supervised_probability_v01": {
        "attempt_number": 2,
        "changed_factors": ["training.objective"],
        "network_output_parameterization": "full_matrix",
        "training_objective": "active_row_cross_entropy",
        "training_weighting": "uniform",
    },
    "h17c_age_source_balanced_supervised_probability_v01": {
        "attempt_number": 3,
        "changed_factors": ["training.sample_weighting"],
        "network_output_parameterization": "full_matrix",
        "training_objective": "active_row_brier",
        "training_weighting": "sqrt_inverse_age_source_frequency",
    },
    "h17d_explicit_causal_duration_cross_entropy_supervised_probability_v01": {
        "attempt_number": 4,
        "changed_factors": ["network.transition_architecture"],
        "transition_architecture": "explicit_causal_duration",
        "training_objective": "active_row_cross_entropy",
        "training_weighting": "uniform",
    },
    "h17d_explicit_causal_duration_cross_entropy_supervised_probability_v02": {
        "attempt_number": 4,
        "implementation_revision": 2,
        "supersedes_implementation_failure": (
            "h17d_explicit_causal_duration_cross_entropy_"
            "supervised_probability_v01"
        ),
        "changed_factors": ["network.transition_architecture"],
        "transition_architecture": "explicit_causal_duration",
        "training_objective": "active_row_cross_entropy",
        "training_weighting": "uniform",
    },
    H17E_EXPERIMENT_ID: {
        "attempt_number": 5,
        "changed_factors": ["network.age_risk_representation"],
        "transition_architecture": "explicit_causal_duration",
        "age_risk_representation": "monotone_piecewise_linear",
        "training_objective": "active_row_cross_entropy",
        "training_weighting": "uniform",
    },
    H17F_EXPERIMENT_ID: {
        "attempt_number": 6,
        "changed_factors": ["training.learning_rate"],
        "transition_architecture": "explicit_causal_duration",
        "age_risk_representation": "monotone_piecewise_linear",
        "training_objective": "active_row_cross_entropy",
        "training_weighting": "uniform",
        "optimizer": "AdamW",
        "baseline_learning_rate": 0.003,
        "learning_rate": 0.075,
        "weight_decay": 0.0001,
        "epochs": 60,
    },
}
EXPLICIT_DURATION_REPAIR_IDS = {
    "h17d_explicit_causal_duration_cross_entropy_supervised_probability_v01",
    "h17d_explicit_causal_duration_cross_entropy_supervised_probability_v02",
    "h17e_monotone_piecewise_linear_age_risk_supervised_probability_v01",
}
REPAIR_RESULT_FILES = (
    "repair_contract.json",
    "static_reference.json",
    "evaluation_role_audit.json",
    "source_integrity_audit.json",
    "source_manifest.json",
    "source_snapshot.zip",
)

DURATION_RESULT_FILES = (
    "duration_contract.json",
    "duration_causality_audit.json",
    "duration_state_audit.json",
    "stratified_metrics.json",
)


def _load_h17f_learning_rate_repair(
    declaration: Mapping[str, Any],
    *,
    root: Path,
) -> dict[str, Any]:
    """Resolve H17F from the frozen, independently verified H17E snapshot."""

    required = {
        "experiment_id",
        "base_config",
        "baseline_age_risk_repair",
        "result_relative_path",
        "repair_contract",
        "duration_contract",
        "source_snapshot_files",
    }
    if required - set(declaration):
        raise ValueError("H17F learning-rate repair declaration is incomplete")

    base_specification = declaration["base_config"]
    base_path = (root / str(base_specification["path"])).resolve()
    if (
        not base_path.is_file()
        or _sha256(base_path) != str(base_specification["sha256"])
    ):
        raise ValueError("frozen H17E base configuration hash mismatch")
    base = json.loads(base_path.read_text(encoding="utf-8"))
    if base.get("experiment_id") != H17E_EXPERIMENT_ID:
        raise ValueError("H17F learning-rate repair must use H17E as its baseline")

    baseline = declaration["baseline_age_risk_repair"]
    if not isinstance(baseline, Mapping):
        raise ValueError("H17F requires the frozen H17E baseline evidence")
    baseline_declaration_specification = baseline.get("declaration", {})
    baseline_snapshot_specification = baseline.get("config_snapshot", {})
    baseline_declaration_path = (
        root / str(baseline_declaration_specification.get("path", ""))
    ).resolve()
    baseline_snapshot_path = (
        root / str(baseline_snapshot_specification.get("path", ""))
    ).resolve()
    baseline_result = (root / str(baseline.get("result_directory", ""))).resolve()
    if (
        baseline.get("experiment_id") != H17E_EXPERIMENT_ID
        or not baseline_declaration_path.is_file()
        or _sha256(baseline_declaration_path)
        != str(baseline_declaration_specification.get("sha256", ""))
        or not baseline_snapshot_path.is_file()
        or _sha256(baseline_snapshot_path)
        != str(baseline_snapshot_specification.get("sha256", ""))
        or baseline_snapshot_path != base_path
        or _sha256(baseline_result / "checksums.json")
        != str(baseline.get("checksums_sha256", ""))
        or _sha256(baseline_result / "independent_verification.json")
        != str(baseline.get("independent_verification_sha256", ""))
    ):
        raise ValueError("frozen H17E baseline evidence hash mismatch")
    baseline_independent = json.loads(
        (baseline_result / "independent_verification.json").read_text("utf-8")
    )
    if baseline_independent.get("verified") is not True:
        raise ValueError("frozen H17E baseline was not independently verified")

    contract = declaration["repair_contract"]
    expected = EXPECTED_REPAIRS[H17F_EXPERIMENT_ID]
    for name, value in expected.items():
        if contract.get(name) != value:
            raise ValueError(f"repair contract differs from frozen {name}")
    if (
        contract.get("attempt_order_frozen_before_training") is not True
        or contract.get("baseline_experiment_id") != H17E_EXPERIMENT_ID
        or contract.get("warm_start") is not False
        or contract.get("h17b_recurrent_checkpoint_loaded") is not False
        or contract.get("h18_authorized") is not False
        or contract.get("fresh_reserved_confirmation_required_after_diagnostic_pass")
        is not True
    ):
        raise ValueError("H17F learning-rate repair lifecycle contract is invalid")

    duration = declaration["duration_contract"]
    if duration != base.get("duration_contract"):
        raise ValueError("H17F duration contract differs from frozen H17E")
    frozen_training = {
        "batch_size_blocks": 24,
        "checkpoint_selection": "minimum validation active-row oracle Brier",
        "epochs": 60,
        "gradient_clip_norm": 1.0,
        "history_network_initialization_seeds": [1710101, 1710102, 1710103],
        "learning_rate": 0.003,
        "objective": "active_row_cross_entropy",
        "optimizer": "AdamW",
        "sample_weighting": "uniform",
        "static_matrix_initialization_seed": 1710001,
        "test_read_policy": "after static and all recurrent checkpoints are frozen",
        "weight_decay": 0.0001,
    }
    if base.get("training") != frozen_training:
        raise ValueError("H17E training factors differ from their frozen values")
    if (
        base.get("experiment_kind") != "supervised_probability_repair"
        or base.get("network", {}).get("transition_architecture")
        != "explicit_causal_duration"
        or base.get("network", {}).get("age_risk_representation")
        != "monotone_piecewise_linear"
        or base.get("network", {}).get("piecewise_knot_count") != 31
        or base.get("capability_gates", {}).get(
            "minimum_each_history_seed_relative_oracle_brier_reduction_vs_static"
        )
        != 0.5
        or base.get("capability_gates", {}).get(
            "minimum_each_history_seed_relative_hazard_mae_reduction_vs_static"
        )
        != 0.5
    ):
        raise ValueError("H17E scientific factors differ from their frozen values")

    result_relative_path = str(declaration["result_relative_path"])
    if (
        H17F_EXPERIMENT_ID not in result_relative_path
        or result_relative_path == str(base.get("result_relative_path", ""))
    ):
        raise ValueError("H17F result path is not isolated")

    config = deepcopy(base)
    config["experiment_id"] = H17F_EXPERIMENT_ID
    config["status"] = "registered_supervised_repair"
    config["result_relative_path"] = result_relative_path
    config["scientific_question"] = (
        "Can changing only the AdamW learning rate from 0.003 to 0.075 let the "
        "frozen monotone piecewise-linear age-risk representation clear both "
        "supervised probability-error gates?"
    )
    config["claim_boundary"] = (
        "This is a one-time optimization-scale stress test, not a tuned or "
        "guaranteed learning rate. The previously inspected H16 test split is "
        "development-diagnostic only; final-reserve confirmation and H18 remain "
        "unauthorized."
    )
    config["repair_contract"] = deepcopy(contract)
    config["duration_contract"] = deepcopy(duration)
    config["baseline_age_risk_repair"] = deepcopy(baseline)
    config["source_snapshot_files"] = list(declaration["source_snapshot_files"])
    config["training"]["learning_rate"] = float(contract["learning_rate"])

    for section in (
        "base_parameters",
        "capability_gates",
        "closed_loop_gradient_contract",
        "controls",
        "data",
        "filter",
        "loss",
        "method_contract",
        "network",
        "normalization",
        "parameter_candidates",
        "supervision_contract",
    ):
        if config.get(section) != base.get(section):
            raise ValueError(f"H17F changed frozen scientific section {section}")
    candidate_training = deepcopy(config["training"])
    candidate_training["learning_rate"] = base["training"]["learning_rate"]
    if candidate_training != base["training"]:
        raise ValueError("H17F changed a training factor other than learning rate")
    return config


def _load_explicit_duration_repair(
    declaration: Mapping[str, Any],
    *,
    root: Path,
) -> dict[str, Any]:
    """Resolve H17D from the frozen, independently verified H17B snapshot."""

    experiment_id = str(declaration["experiment_id"])
    required = {
        "experiment_id",
        "base_config",
        "baseline_repair",
        "result_relative_path",
        "repair_contract",
        "duration_contract",
        "source_snapshot_files",
    }
    if experiment_id.startswith("h17e_"):
        required.add("baseline_duration_repair")
    if required - set(declaration):
        raise ValueError("explicit duration repair declaration is incomplete")
    base_specification = declaration["base_config"]
    base_path = (root / str(base_specification["path"])).resolve()
    if (
        not base_path.is_file()
        or _sha256(base_path) != str(base_specification["sha256"])
    ):
        raise ValueError("frozen H17B base configuration hash mismatch")
    base = json.loads(base_path.read_text(encoding="utf-8"))
    if base.get("experiment_id") != (
        "h17b_active_row_cross_entropy_supervised_probability_v01"
    ):
        raise ValueError("explicit duration repair must use H17B as its baseline")

    baseline = declaration["baseline_repair"]
    declaration_specification = baseline["declaration"]
    baseline_declaration_path = (
        root / str(declaration_specification["path"])
    ).resolve()
    baseline_result = (root / str(baseline["result_directory"])).resolve()
    if (
        baseline.get("experiment_id")
        != "h17b_active_row_cross_entropy_supervised_probability_v01"
        or not baseline_declaration_path.is_file()
        or _sha256(baseline_declaration_path)
        != str(declaration_specification["sha256"])
        or _sha256(baseline_result / "checksums.json")
        != str(baseline["checksums_sha256"])
        or _sha256(baseline_result / "independent_verification.json")
        != str(baseline["independent_verification_sha256"])
    ):
        raise ValueError("frozen H17B baseline evidence hash mismatch")
    independent = json.loads(
        (baseline_result / "independent_verification.json").read_text("utf-8")
    )
    if independent.get("verified") is not True:
        raise ValueError("frozen H17B baseline was not independently verified")

    baseline_duration = declaration.get("baseline_duration_repair")
    if experiment_id.startswith("h17e_"):
        if not isinstance(baseline_duration, Mapping):
            raise ValueError("monotone repair requires the frozen H17D baseline")
        duration_declaration = (
            root / str(baseline_duration["declaration"]["path"])
        ).resolve()
        duration_result = (
            root / str(baseline_duration["result_directory"])
        ).resolve()
        if (
            baseline_duration.get("experiment_id")
            != "h17d_explicit_causal_duration_cross_entropy_supervised_probability_v02"
            or not duration_declaration.is_file()
            or _sha256(duration_declaration)
            != str(baseline_duration["declaration"]["sha256"])
            or _sha256(duration_result / "checksums.json")
            != str(baseline_duration["checksums_sha256"])
            or _sha256(duration_result / "independent_verification.json")
            != str(baseline_duration["independent_verification_sha256"])
        ):
            raise ValueError("frozen H17D baseline evidence hash mismatch")
        duration_independent = json.loads(
            (duration_result / "independent_verification.json").read_text("utf-8")
        )
        if duration_independent.get("verified") is not True:
            raise ValueError("frozen H17D baseline was not independently verified")

    contract = declaration["repair_contract"]
    expected = EXPECTED_REPAIRS[experiment_id]
    for name, value in expected.items():
        if contract.get(name) != value:
            raise ValueError(f"repair contract differs from frozen {name}")
    if (
        contract.get("attempt_order_frozen_before_training") is not True
        or contract.get("warm_start") is not False
        or contract.get("h17b_recurrent_checkpoint_loaded") is not False
        or contract.get("h18_authorized") is not False
    ):
        raise ValueError("explicit duration repair lifecycle contract is invalid")
    expected_baseline_id = (
        "h17d_explicit_causal_duration_cross_entropy_supervised_probability_v02"
        if experiment_id.startswith("h17e_")
        else "h17b_active_row_cross_entropy_supervised_probability_v01"
    )
    if contract.get("baseline_experiment_id") != expected_baseline_id:
        raise ValueError("explicit duration repair baseline identifier is invalid")
    if (
        base.get("experiment_kind") != "supervised_probability_repair"
        or base["training"].get("objective") != "active_row_cross_entropy"
        or base["training"].get("sample_weighting") != "uniform"
        or base["network"].get("output_parameterization") != "full_matrix"
    ):
        raise ValueError("H17B baseline factors differ from their frozen values")

    duration = declaration["duration_contract"]
    forbidden_true_inputs = (
        "true_mode_input",
        "true_age_input",
        "switch_label_input",
        "target_probability_input",
        "block_identifier_input",
        "random_seed_input",
    )
    if (
        int(duration.get("candidate_count", 0)) != 3
        or int(duration.get("maximum_age", 0)) != 300
        or int(duration.get("hazard_hidden_size", 0)) != 16
        or float(duration.get("maximum_logit_correction", 0.0)) != 2.0
        or duration.get("day_zero_scored") is not False
        or duration.get("hard_argmax_reset") is not False
        or any(duration.get(name) is not False for name in forbidden_true_inputs)
    ):
        raise ValueError("explicit duration contract differs from its frozen values")
    if experiment_id != (
        "h17d_explicit_causal_duration_cross_entropy_supervised_probability_v01"
    ) and (
        float(duration.get("minimum_differentiable_mode_probability", 0.0))
        != 1e-12
        or duration.get("rare_mode_gradient_rule")
        != (
            "preserve the exact forward conditional-age distribution but "
            "detach its recursion gradient below the probability floor"
        )
    ):
        raise ValueError("duration numerical-stability contract is invalid")
    if experiment_id.startswith("h17e_") and (
        duration.get("age_risk_representation")
        != "monotone_piecewise_linear"
        or int(duration.get("piecewise_knot_count", 0)) != 31
        or duration.get("piecewise_knot_positions")
        != "uniform from age 1 through maximum age inclusive"
        or duration.get("piecewise_interpolation_space")
        != "transition logit correction"
        or duration.get("piecewise_monotonicity")
        != "nondecreasing by ordered bounded knots"
        or duration.get("knot_selection_inputs")
        != ["maximum_age", "piecewise_knot_count"]
        or duration.get("development_diagnostic_targets_used_for_knot_selection")
        is not False
        or duration.get("final_reserved_targets_used_for_knot_selection")
        is not False
    ):
        raise ValueError("monotone piecewise age-risk contract is invalid")

    config = deepcopy(base)
    config["experiment_id"] = experiment_id
    config["status"] = "registered_supervised_repair"
    config["result_relative_path"] = str(declaration["result_relative_path"])
    config["scientific_question"] = (
        "Can replacing only the smooth age-risk network with a monotone "
        "piecewise-linear age-risk representation clear both supervised "
        "probability-error gates?"
        if experiment_id.startswith("h17e_")
        else (
            "Can an explicit causal mode-duration belief, with every H17B "
            "training factor fixed, clear both supervised probability-error gates?"
        )
    )
    config["claim_boundary"] = (
        "The previously inspected H16 test split is development-diagnostic only. "
        "A pass must be confirmed once on a previously unread reserved set; H18 "
        "remains unauthorized."
    )
    config["repair_contract"] = deepcopy(contract)
    config["duration_contract"] = deepcopy(duration)
    config["baseline_repair"] = deepcopy(baseline)
    if isinstance(baseline_duration, Mapping):
        config["baseline_duration_repair"] = deepcopy(baseline_duration)
    config["source_snapshot_files"] = list(declaration["source_snapshot_files"])
    config["network"]["transition_architecture"] = str(
        contract["transition_architecture"]
    )
    config["network"]["maximum_age"] = int(duration["maximum_age"])
    config["network"]["hazard_hidden_size"] = int(duration["hazard_hidden_size"])
    config["network"]["minimum_differentiable_mode_probability"] = float(
        duration.get("minimum_differentiable_mode_probability", 1e-12)
    )
    if experiment_id.startswith("h17e_"):
        config["network"]["age_risk_representation"] = str(
            duration["age_risk_representation"]
        )
        config["network"]["piecewise_knot_count"] = int(
            duration["piecewise_knot_count"]
        )
    config["capability_gates"][
        "minimum_permitted_duration_state_effect_on_transition"
    ] = 0.0
    config["required_result_files"] = list(
        dict.fromkeys(
            [*config["required_result_files"], *DURATION_RESULT_FILES]
        )
    )
    return config


def load_supervised_probability_repair_config(
    path: str | Path,
    *,
    project_root: str | Path,
) -> dict[str, Any]:
    """Resolve a lean repair declaration against the immutable H17 config."""

    root = Path(project_root).resolve()
    declaration_path = Path(path).resolve()
    declaration = json.loads(declaration_path.read_text(encoding="utf-8"))
    experiment_id = str(declaration.get("experiment_id", ""))
    if experiment_id not in EXPECTED_REPAIRS:
        raise ValueError("unexpected supervised probability repair identifier")
    if experiment_id == H17F_EXPERIMENT_ID:
        return _load_h17f_learning_rate_repair(declaration, root=root)
    if experiment_id in EXPLICIT_DURATION_REPAIR_IDS:
        return _load_explicit_duration_repair(declaration, root=root)
    required = {
        "experiment_id",
        "base_config",
        "result_relative_path",
        "repair_contract",
        "source_h17_static_reference",
        "source_snapshot_files",
    }
    if required - set(declaration):
        raise ValueError("supervised probability repair declaration is incomplete")
    base_specification = declaration["base_config"]
    base_path = (root / str(base_specification["path"])).resolve()
    if (
        not base_path.is_file()
        or _sha256(base_path) != str(base_specification["sha256"])
    ):
        raise ValueError("frozen H17 base configuration hash mismatch")
    base = load_h17_config(base_path)
    expected = EXPECTED_REPAIRS[experiment_id]
    contract = declaration["repair_contract"]
    for name, value in expected.items():
        if contract.get(name) != value:
            raise ValueError(f"repair contract differs from frozen {name}")
    if contract.get("attempt_order_frozen_before_training") is not True:
        raise ValueError("repair attempt order was not frozen before training")
    if contract.get("h18_authorized") is not False:
        raise ValueError("repair declaration cannot authorize H18")

    config = deepcopy(base)
    config["experiment_id"] = experiment_id
    config["experiment_kind"] = "supervised_probability_repair"
    config["result_relative_path"] = str(declaration["result_relative_path"])
    config["scientific_question"] = (
        "Can this single-factor supervised repair clear both original H17 "
        "probability-error gates for every frozen recurrent initialization seed?"
    )
    config["claim_boundary"] = (
        "The previously inspected H16 test split is development-diagnostic only. "
        "A pass requires one fresh reserved confirmation before it can be called "
        "a solved supervised repair; H18 remains unauthorized."
    )
    config["repair_contract"] = deepcopy(contract)
    config["source_h17_static_reference"] = deepcopy(
        declaration["source_h17_static_reference"]
    )
    config["source_snapshot_files"] = list(declaration["source_snapshot_files"])
    config["network"]["output_parameterization"] = str(
        contract["network_output_parameterization"]
    )
    config["training"]["objective"] = str(contract["training_objective"])
    config["training"]["sample_weighting"] = str(contract["training_weighting"])
    config["required_result_files"] = list(config["required_result_files"]) + list(
        REPAIR_RESULT_FILES
    )
    if contract["training_weighting"] != "uniform":
        config["required_result_files"].append("weighting_audit.json")

    if tuple(config["training"]["history_network_initialization_seeds"]) != (
        1710101,
        1710102,
        1710103,
    ):
        raise ValueError("repair seeds differ from frozen H17")
    if int(config["training"]["epochs"]) != 60:
        raise ValueError("repair training budget differs from frozen H17")
    gates = config["capability_gates"]
    if (
        float(
            gates[
                "minimum_each_history_seed_relative_oracle_brier_reduction_vs_static"
            ]
        )
        != 0.5
        or float(
            gates[
                "minimum_each_history_seed_relative_hazard_mae_reduction_vs_static"
            ]
        )
        != 0.5
    ):
        raise ValueError("repair success gates differ from frozen H17")
    return config


def run_supervised_probability_repair(
    declaration: Mapping[str, Any],
    *,
    project_root: str | Path,
    maximum_new_history_seeds: int | None = None,
    maximum_new_history_epochs: int | None = None,
) -> Path:
    return run_h17_probability_upper_bound(
        declaration,
        project_root=project_root,
        maximum_new_history_seeds=maximum_new_history_seeds,
        maximum_new_history_epochs=maximum_new_history_epochs,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH))
    parser.add_argument("--project-root", default=str(PACKAGE_ROOT.parents[1]))
    parser.add_argument("--maximum-new-history-seeds", type=int)
    parser.add_argument("--maximum-new-history-epochs", type=int)
    arguments = parser.parse_args()
    config = load_supervised_probability_repair_config(
        arguments.config,
        project_root=arguments.project_root,
    )
    output = run_supervised_probability_repair(
        config,
        project_root=arguments.project_root,
        maximum_new_history_seeds=arguments.maximum_new_history_seeds,
        maximum_new_history_epochs=arguments.maximum_new_history_epochs,
    )
    print(output, flush=True)


if __name__ == "__main__":
    main()
