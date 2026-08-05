import csv
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_ROOT = (
    REPO_ROOT / "src" / "hbv_multilead_joint_uncertainty" / "configs"
)


def _json(name: str) -> dict:
    return json.loads((CONFIG_ROOT / name).read_text(encoding="utf-8"))


def test_completed_state_audit_scope_correction_maps_archived_key_to_global_posterior():
    correction = _json(
        "g3_fixed_process_parameter_candidate_complete_state_audit_v01."
        "scope_correction_20260801.json"
    )
    assert correction["historical_config_immutable"] is True
    assert correction["standard_method_output"] == (
        "fully_interacting_multiple_model_global_posterior_state"
    )
    assert correction["archived_state_key_roles"][
        "three_parameter_candidates_combined_state"
    ] == "fully_interacting_multiple_model_global_posterior_state"
    assert correction["model_conditioned_subfilter_states_are_final_outputs"] is False
    assert correction["mechanism_attribution_allowed"] is False
    assert correction["sealed_evidence_unchanged"] is True


def test_completed_forecast_scope_correction_uses_one_global_posterior_origin():
    correction = _json(
        "g3_fixed_process_parameter_candidate_controlled_forecast_v01."
        "scope_correction_20260801.json"
    )
    assert correction["historical_config_immutable"] is True
    assert correction["standard_method_output"] == (
        "fully_interacting_multiple_model_global_posterior_state"
    )
    assert correction["model_conditioned_subfilter_trajectories_used"] is False
    assert correction["mechanism_attribution_allowed"] is False


def test_frozen_interaction_audit_changes_only_state_interaction_and_scores_global_posteriors():
    config = _json(
        "g3_fixed_process_state_interaction_global_posterior_audit_v01.json"
    )
    assert config["status"] == "frozen_before_run"
    assert config["forecast_executed"] is False
    assert config["time_since_truth_switch_grouping_used"] is False
    assert set(config["interaction_modes"].values()) == {"full", "none"}
    assert config["state_methods"] == [
        "fully_interacting_multiple_model_global_posterior_state",
        "noninteracting_multiple_filter_global_posterior_state_control",
    ]
    assert config["fixed_factors"]["global_posterior_combination"] == (
        "posterior-probability weighted in both methods"
    )
    assert "Model-conditioned subfilter posterior states are internal diagnostics" in (
        config["published_state_rule"]
    )


def test_registry_records_overall_method_comparisons_and_completed_interaction_audit():
    registry_path = CONFIG_ROOT / "g3_experiment_registry.csv"
    with registry_path.open(encoding="utf-8", newline="") as handle:
        rows = {row["exp_id"]: row for row in csv.DictReader(handle)}

    state_row = rows[
        "g3_fixed_process_parameter_candidate_complete_state_audit_v01"
    ]
    assert "standard fully interacting three-parameter-model" in state_row["hypothesis"]
    assert "does not isolate candidate count or state interaction" in state_row["notes"]

    completed = rows[
        "g3_fixed_process_state_interaction_global_posterior_audit_v01"
    ]
    assert completed["status"] == "completed"
    assert completed["changed_factor"] == (
        "state and covariance interaction mixing full versus none"
    )
    assert "complete-state decision is inconclusive" in completed["notes"]
    assert completed["metrics_path"] == "independent_verification.json"


def test_active_handoff_names_the_standard_final_state_and_internal_subfilter_boundary():
    handoff = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "HANDOFF_20260801_COMPLETE_STATE_PARAMETER_CONTROL.md"
    ).read_text(encoding="utf-8")
    assert "唯一的全局后验状态" in handoff
    assert "子滤波器状态可以用于内部诊断" in handoff
    assert "不能把`45.028%`单独归因" in handoff
    assert "整体优劣无法确定" in handoff
    assert "独立复算最大绝对差为`0`" in handoff
