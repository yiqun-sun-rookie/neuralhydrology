"""Deterministically generate the twenty frozen G2 development configurations.

Template semantics mirror candidate_likelihood_parameter_switch_development_v05
exactly (decision rules, integrity gates, bootstrap replicates, forcing shape);
only the frozen G2 grid coordinates vary: spacing-multiplier parameter source,
stage lengths, reference days, paired per-row block seeds, and per-cell
bootstrap seed. Refuses to overwrite any existing configuration file.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.g2_curve_design import (  # noqa: E402
    ADAPTATION_DAYS,
    BUDGET_STAGE_LENGTHS,
    DEVELOPMENT_BOOTSTRAP_SEED_BASE,
    WARMUP_DAYS,
    development_block_seeds,
    development_experiment_id,
    grid_cells,
)
from hbv_multilead_joint_uncertainty.scripts.run_synthetic_truth_validation import (  # noqa: E402
    _sha256,
)

INPUTS_DIR = "results/23_hbv_multilead_joint_uncertainty/g2_spacing_inputs_v01"
CONFIG_DIR = REPO_ROOT / "src/hbv_multilead_joint_uncertainty/configs"
PROCESS_SOURCE = {
    "path": (
        "results/23_hbv_multilead_joint_uncertainty/formal_contract_sixteen_v05/"
        "process_noise_covariances.csv"
    ),
    "sha256": "b95b637a40c0a6f1f15d8b81739f35ac60a8ae3d85aa3872ad47ada17c8684d2",
    "source_basin_id": "12143600",
    "process_ids": ["process_0", "process_1", "process_2"],
    "selected_process_id": "process_2",
}
OBSERVATION_SOURCE = {
    "path": (
        "results/23_hbv_multilead_joint_uncertainty/formal_contract_sixteen_v05/"
        "observation_noise.csv"
    ),
    "sha256": "f358c77b655285b348604266af43dfcd7b875ea756145f6d9b33c8853a5d8955",
    "source_basin_id": "12143600",
}


def _cell_config(cell: dict, parameter_path: str, parameter_sha: str, protected: list[str]) -> dict:
    stage_length = int(cell["stage_length"])
    multiplier = float(cell["multiplier"])
    row_index = BUDGET_STAGE_LENGTHS.index(stage_length)
    return {
        "experiment_id": development_experiment_id(multiplier, stage_length),
        "dataset_role": "development",
        "scenario": "parameter_switch",
        "purpose": (
            "G2 identification-time curve development cell: measure how many "
            "assimilation cycles after a truth switch the true parameter candidate "
            "needs to become stably top-ranked, at spacing multiplier "
            f"{multiplier} and per-stage cycle budget {stage_length}."
        ),
        "g2_grid": {
            "design_doc": "docs/plans/2026-07-22-g2-identification-time-curve-design.md",
            "cell_number": int(cell["cell_number"]),
            "spacing_multiplier": multiplier,
            "stage_length_days": stage_length,
            "budget_row_index": row_index,
        },
        "diagnostic_contract": {
            "candidate_filters_assimilate_observations_independently": True,
            "candidate_state_interaction_used": False,
            "candidate_probability_transition_used": False,
            "candidate_probability_update_used": False,
            "daily_likelihood_definition": (
                "Scalar Gaussian predictive observation log likelihood before the "
                "same-day observation update."
            ),
            "cumulative_likelihood_definition": (
                "Sum of daily log likelihoods reset at the first scored day of each stage."
            ),
            "strict_ranking_rule": (
                "Every wrong candidate with likelihood greater than or equal to the "
                "true candidate ranks ahead of the true candidate."
            ),
        },
        "parameter_source": {
            "path": parameter_path,
            "sha256": parameter_sha,
            "source_basin_id": "12143600",
            "parameter_ids": [
                "equifinal_diverse_1",
                "trained_center",
                "equifinal_diverse_2",
            ],
        },
        "process_noise_source": dict(PROCESS_SOURCE),
        "observation_noise_source": dict(OBSERVATION_SOURCE),
        "matched_blocks": development_block_seeds(row_index),
        "forcing": {
            "warmup_days": WARMUP_DAYS,
            "reference_total_days": WARMUP_DAYS + 3 * stage_length + 7,
            "rain_shape": 0.8,
            "rain_scale": 4,
        },
        "stage_lengths": [stage_length, stage_length, stage_length],
        "adaptation_days_excluded_per_stage": ADAPTATION_DAYS,
        "stable_final_scoring_days": 5,
        "initial_covariance_fraction": 0.001,
        "bootstrap": {
            "unit": "synthetic_block",
            "replicates": 20000,
            "seed": DEVELOPMENT_BOOTSTRAP_SEED_BASE + int(cell["cell_number"]),
        },
        "decision_rules": {
            "stable_identifiable_fraction_minimum": 2.0 / 3.0,
            "stable_fraction_block_bootstrap_lower_strict_minimum": 0.5,
            "median_final_margin_strict_minimum": 0,
            "switching_stage_numbers": [2, 3],
            "stage_one_decides_scientific_status": False,
        },
        "integrity_gates": {
            "truth_process_perturbation_reconstruction_maximum_absolute_error": 0,
            "observation_reconstruction_maximum_absolute_error": 0,
            "innovation_reconstruction_maximum_absolute_error": 1e-12,
            "log_likelihood_reconstruction_maximum_absolute_error": 1e-12,
            "score_reconstruction_maximum_absolute_error": 1e-12,
        },
        "protected_paths": protected,
        "scope_limit": (
            "Development evidence only, one G2 grid cell. Three complete parameter "
            "candidates at one spacing multiplier are compared with process covariance "
            "fixed at process_2; candidate filters assimilate the same observations "
            "independently with no state interaction, probability transition, or "
            "probability update. The spacing multiplier also rescales the truth "
            "trajectory, and longer budgets stretch the seasonal forcing cycle "
            "(declared interpretation boundaries in the design doc)."
        ),
    }


def main() -> None:
    inputs = REPO_ROOT / INPUTS_DIR
    manifest = json.loads((inputs / "manifest.json").read_text(encoding="utf-8"))
    config_names = [
        development_experiment_id(cell["multiplier"], cell["stage_length"]) + ".json"
        for cell in grid_cells()
    ]
    protected = [
        "results/23_hbv_multilead_joint_uncertainty/formal_contract_sixteen_v05",
        INPUTS_DIR,
        "docs/plans/2026-07-22-g2-identification-time-curve-design.md",
        *(
            f"src/hbv_multilead_joint_uncertainty/configs/{name}"
            for name in config_names
        ),
    ]
    existing = [name for name in config_names if (CONFIG_DIR / name).exists()]
    if existing:
        raise FileExistsError(f"refusing to overwrite existing configs: {existing}")

    by_multiplier = {
        float(entry["multiplier"]): (name, entry["sha256"])
        for name, entry in manifest["files"].items()
    }
    for cell in grid_cells():
        file_name, sha = by_multiplier[float(cell["multiplier"])]
        parameter_path = f"{INPUTS_DIR}/{file_name}"
        if _sha256(REPO_ROOT / parameter_path) != sha:
            raise RuntimeError(f"sealed input checksum mismatch: {parameter_path}")
        config = _cell_config(cell, parameter_path, sha, protected)
        target = CONFIG_DIR / (config["experiment_id"] + ".json")
        target.write_text(
            json.dumps(config, indent=2) + "\n", encoding="utf-8", newline="\n"
        )
    print(f"wrote {len(config_names)} development configs")


if __name__ == "__main__":
    main()
