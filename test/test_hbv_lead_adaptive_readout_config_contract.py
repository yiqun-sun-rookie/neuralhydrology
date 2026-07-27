"""Frozen configuration contract for the independent readout confirmation."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
EXPERIMENT_ID = "g3_lead_adaptive_readout_param_switch_v01"
CONFIG_PATH = (
    REPO_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "configs"
    / f"{EXPERIMENT_ID}.json"
)
CONFIG_DIRECTORY = CONFIG_PATH.parent
REGISTRY_PATH = CONFIG_DIRECTORY / "g3_experiment_registry.csv"
DESIGN_PATH = (
    "docs/plans/"
    "2026-07-27-id23-lead-adaptive-posterior-readout-design.md"
)
IMPLEMENTATION_PATH = (
    "docs/plans/"
    "2026-07-27-id23-lead-adaptive-posterior-readout.md"
)


def _load_config():
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def _sha256(relative_path):
    return hashlib.sha256((REPO_ROOT / relative_path).read_bytes()).hexdigest()


def test_config_freezes_method_forecast_and_retention_contracts():
    config = _load_config()

    assert config["experiment_id"] == EXPERIMENT_ID
    assert config["scenario"] == "parameter_switch"
    assert config["design_doc"] == DESIGN_PATH
    assert config["implementation_plan"] == IMPLEMENTATION_PATH
    assert config["forecast_contract"] == {
        "model_transition_during_forecast": "identity",
        "candidate_probabilities_during_forecast": (
            "fixed_at_final_assimilation_posterior"
        ),
        "cross_candidate_state_mixing_during_forecast": False,
    }
    assert config["readout_rule_by_lead"] == {
        "1": "uniform",
        "3": "highest_posterior",
        "7": "highest_posterior",
    }
    assert config["comparison_methods"] == [
        "lead_adaptive",
        "full_posterior",
        "none_posterior",
        "uniform",
        "oracle",
    ]
    assert config["retention_thresholds"] == {
        "minimum_meaningful_rmse_fraction": 0.01,
        "minimum_highest_posterior_selection_accuracy": 0.95,
        "multiday_leads": [3, 7],
    }
    assert config["retention_gates"] == {
        "none_at_least_one_material_improvement": (
            "at least one lead has paired 95% interval upper bound below "
            "the 1% RMSE improvement MSE boundary"
        ),
        "none_all_leads_no_material_harm": (
            "every lead has paired 95% interval upper bound at or below "
            "the 1% RMSE harm MSE boundary"
        ),
        "multiday_composite_improves": (
            "the normalized 3-day and 7-day MSE composite 95% interval "
            "upper bound is below zero"
        ),
        "highest_posterior_selection_accuracy": (
            "final highest-posterior true-candidate accuracy is at least 0.95"
        ),
        "full_comparison": (
            "at least one lead materially improves and every lead has no "
            "material harm versus current full posterior weighting"
        ),
        "retain_only_if_all_gates_pass": True,
        "no_post_confirmation_tuning": True,
    }


def test_config_uses_new_32_block_seed_families_and_shared_bootstrap():
    config = _load_config()
    blocks = config["matched_blocks"]

    assert len(blocks) == 32
    assert [block["block_id"] for block in blocks] == [
        f"g3_readout_confirmation_block_{number:02d}"
        for number in range(1, 33)
    ]
    assert [block["forcing_seed"] for block in blocks] == list(
        range(7311001, 7311033)
    )
    assert [block["process_noise_seed"] for block in blocks] == list(
        range(7312001, 7312033)
    )
    assert [block["observation_noise_seed"] for block in blocks] == list(
        range(7313001, 7313033)
    )
    all_seeds = [
        value
        for block in blocks
        for value in (
            block["forcing_seed"],
            block["process_noise_seed"],
            block["observation_noise_seed"],
        )
    ]
    all_seeds.append(config["bootstrap"]["seed"])
    assert len(set(all_seeds)) == 97
    assert config["bootstrap"] == {
        "unit": "matched_block",
        "replicates": 20000,
        "seed": 7314001,
        "shared_resample_indices_across_leads": True,
    }

    target_seed_set = set(all_seeds)
    collisions = []
    for other_path in CONFIG_DIRECTORY.glob("*.json"):
        if other_path == CONFIG_PATH:
            continue
        text = other_path.read_text(encoding="utf-8")
        for seed in target_seed_set:
            if str(seed) in text:
                collisions.append((other_path.name, seed))
    assert collisions == []


def test_config_keeps_scientific_inputs_and_synthetic_setting_unchanged():
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
            "0ff9a34b0dd863e99e40038b0876d78"
            "1561a0a1e9d371a81ee3b8fafff6ef3c8"
        ),
        "source_basin_id": "12143600",
    }
    for source_name in (
        "parameter_source",
        "process_noise_source",
        "observation_noise_source",
    ):
        source = config[source_name]
        assert _sha256(source["path"]) == source["sha256"]
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
    assert config["resource_pilot"]["sha256"] == _sha256(
        config["resource_pilot"]["source"]
    )


def test_config_protects_every_existing_g3_artifact_and_its_own_contract():
    config = _load_config()
    protected = config["protected_paths"]

    assert len(protected) == len(set(protected))
    existing_result_names = {
        path.name
        for path in (
            REPO_ROOT / "results" / "23_hbv_multilead_joint_uncertainty"
        ).iterdir()
        if path.name.startswith("g3_")
        or path.name
        in {
            "g2_spacing_inputs_v01",
            "formal_contract_sixteen_v05",
            "three_stage_switching_resource_pilot_v01",
        }
        if not path.name.startswith(EXPERIMENT_ID)
    }
    protected_result_names = {
        Path(value).name
        for value in protected
        if value.startswith(
            "results/23_hbv_multilead_joint_uncertainty/"
        )
    }
    assert existing_result_names <= protected_result_names
    assert DESIGN_PATH in protected
    assert IMPLEMENTATION_PATH in protected
    assert (
        "src/hbv_multilead_joint_uncertainty/configs/"
        f"{EXPERIMENT_ID}.json"
    ) in protected
    for relative_path in protected:
        assert (REPO_ROOT / relative_path).exists(), relative_path


def test_registry_has_one_exact_completed_row():
    with REGISTRY_PATH.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    matching = [row for row in rows if row["exp_id"] == EXPERIMENT_ID]

    assert len(matching) == 1
    assert matching[0] == {
        "exp_id": EXPERIMENT_ID,
        "type": "independent forecast readout confirmation",
        "hypothesis": (
            "Lead-specific use of the final posterior improves forecasts "
            "without changing assimilation interaction"
        ),
        "base_config": f"{EXPERIMENT_ID}.json",
        "changed_factor": (
            "1-day uniform candidate averaging and 3-day 7-day "
            "highest-posterior candidate selection"
        ),
        "fixed_factors": (
            "candidate filters full interaction assimilation truth schedule "
            "noise levels and frozen forecast contract"
        ),
        "seeds": "7311001-7314001",
        "status": "completed",
        "run_dir": (
            "results/23_hbv_multilead_joint_uncertainty/"
            f"{EXPERIMENT_ID}"
        ),
        "best_checkpoint": "not applicable",
        "metrics_path": "summary.json",
        "paper_name": "G3 lead-adaptive posterior readout confirmation",
        "notes": (
            "Formal package and independent recomputation passed; all "
            "retention gates failed; rule rejected; no post-confirmation tuning"
        ),
    }
