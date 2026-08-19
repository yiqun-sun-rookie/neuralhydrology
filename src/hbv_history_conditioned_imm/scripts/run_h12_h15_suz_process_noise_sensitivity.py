"""Run H12-H15 matched upper-zone process-noise sensitivity tests."""

from __future__ import annotations

import argparse
import json
from copy import deepcopy
from pathlib import Path
from typing import Any, Mapping

from hbv_history_conditioned_imm.scripts.run_h01_end_to_end_smoke import _sha256
from hbv_history_conditioned_imm.scripts.run_h04_parameter_switch_capability import (
    PACKAGE_ROOT,
    run_parameter_switch_capability,
)
from hbv_history_conditioned_imm.scripts.run_h06_h08_objective_ablation import (
    load_objective_ablation_config,
)


PROJECT_ROOT = PACKAGE_ROOT.parents[1]
DEFAULT_CONFIG_PATH = (
    PACKAGE_ROOT / "configs" / "h14_suz_assumed_filter_process_sd_1p0_v01.json"
)
EXPECTED_STANDARD_DEVIATIONS: Mapping[str, float] = {
    "h12_suz_assumed_filter_process_sd_0p1_v01": 0.1,
    "h13_suz_assumed_filter_process_sd_0p3_v01": 0.3,
    "h14_suz_assumed_filter_process_sd_1p0_v01": 1.0,
    "h15_suz_assumed_filter_process_sd_3p0_v01": 3.0,
}
DIRECT_COMPENSATION_CRITERION: Mapping[str, Any] = {
    "matched_experiment_id": "h14_suz_assumed_filter_process_sd_1p0_v01",
    "ordered_filter_process_standard_deviations": [0.1, 0.3, 1.0, 3.0],
    "minimum_wrong_to_correct_mean_absolute_suz_correction_ratio": 1.10,
    "minimum_wrong_candidate_mean_absolute_suz_error_reduction": 0.10,
    "require_strictly_increasing_wrong_candidate_mean_absolute_suz_correction": True,
}


def load_suz_process_noise_config(
    path: str | Path,
    *,
    project_root: str | Path = PROJECT_ROOT,
) -> dict[str, Any]:
    """Expand one pinned H12-H15 specification from the frozen H08 setup."""

    specification_path = Path(path).resolve()
    with specification_path.open("r", encoding="utf-8") as handle:
        specification = json.load(handle)
    required = {
        "experiment_id",
        "status",
        "scientific_question",
        "claim_boundary",
        "result_relative_path",
        "source_h08_config",
        "truth_process_state_name",
        "truth_process_standard_deviation",
        "truth_requires_zero_projection",
        "assumed_filter_process_state_name",
        "assumed_filter_process_standard_deviation",
        "direct_compensation_criterion",
    }
    missing = required - set(specification)
    if missing:
        raise ValueError(
            f"upper-zone process-noise specification is missing fields: {sorted(missing)}"
        )
    experiment_id = str(specification["experiment_id"])
    if experiment_id not in EXPECTED_STANDARD_DEVIATIONS:
        raise ValueError(
            f"unexpected upper-zone process-noise experiment identifier: {experiment_id}"
        )
    expected_deviation = EXPECTED_STANDARD_DEVIATIONS[experiment_id]
    if float(specification["assumed_filter_process_standard_deviation"]) != float(
        expected_deviation
    ):
        raise ValueError(f"registered filter-noise value changed for {experiment_id}")
    if (
        specification["truth_process_state_name"] != "SUZ"
        or specification["assumed_filter_process_state_name"] != "SUZ"
    ):
        raise ValueError("truth and filter process state must both be SUZ")
    if float(specification["truth_process_standard_deviation"]) != 1.0:
        raise ValueError("truth process standard deviation must remain exactly 1.0")
    if specification["truth_requires_zero_projection"] is not False:
        raise ValueError("upper-zone Gaussian truth must retain physical projection")
    if specification["direct_compensation_criterion"] != DIRECT_COMPENSATION_CRITERION:
        raise ValueError("registered direct-compensation criterion changed")
    expected_result_path = (
        "results/23_hbv_multilead_joint_uncertainty/" + experiment_id
    )
    if specification["result_relative_path"] != expected_result_path:
        raise ValueError(f"unexpected result path for {experiment_id}")

    root = Path(project_root).resolve()
    source_specification = specification["source_h08_config"]
    source = (root / str(source_specification["path"])).resolve()
    if _sha256(source) != str(source_specification["sha256"]):
        raise ValueError("H08 source config hash mismatch")

    config = deepcopy(load_objective_ablation_config(source, project_root=root))
    for name in (
        "experiment_id",
        "status",
        "scientific_question",
        "claim_boundary",
        "result_relative_path",
    ):
        config[name] = specification[name]
    config["data"].pop(
        "fixed_lower_groundwater_process_standard_deviation", None
    )
    config["data"].update(
        {
            "fixed_process_state_name": "SUZ",
            "fixed_process_standard_deviation": 1.0,
            "require_zero_projection": False,
        }
    )
    config["filter"].pop(
        "assumed_lower_groundwater_process_standard_deviation", None
    )
    config["filter"].update(
        {
            "assumed_process_state_name": "SUZ",
            "assumed_process_standard_deviation": float(expected_deviation),
        }
    )
    config["capability_gates"].pop(
        "maximum_absolute_projection_adjustment", None
    )
    config["capability_gates"][
        "projection_adjustments_must_be_confined_to_process_state"
    ] = True
    config["suz_process_noise_sensitivity_specification"] = specification
    return config


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH))
    parser.add_argument("--project-root", default=str(PROJECT_ROOT))
    arguments = parser.parse_args()
    root = Path(arguments.project_root).resolve()
    config = load_suz_process_noise_config(arguments.config, project_root=root)
    print(run_parameter_switch_capability(config, project_root=root))


if __name__ == "__main__":
    main()
