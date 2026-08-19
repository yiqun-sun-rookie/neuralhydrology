"""Run H09-H11 common assumed-filter process-noise sensitivity tests."""

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
    PACKAGE_ROOT / "configs" / "h09_common_filter_process_sd_0p1_v01.json"
)
EXPECTED_STANDARD_DEVIATIONS: Mapping[str, float] = {
    "h09_common_filter_process_sd_0p1_v01": 0.1,
    "h10_common_filter_process_sd_0p3_v01": 0.3,
    "h11_common_filter_process_sd_3p0_v01": 3.0,
}
EXPECTED_STATE_COMPENSATION_CRITERION: Mapping[str, Any] = {
    "lower_filter_process_standard_deviations": [0.1, 0.3],
    "baseline_filter_process_standard_deviation": 1.0,
    "higher_filter_process_standard_deviation": 3.0,
    "minimum_relative_fixed_cross_entropy_improvement": 0.01,
    "minimum_relative_high_noise_cross_entropy_increase": 0.01,
    "minimum_relative_history_forecast_improvement": 0.01,
    "minimum_relative_history_oracle_brier_improvement": 0.01,
}


def load_common_process_noise_config(
    path: str | Path,
    *,
    project_root: str | Path = PROJECT_ROOT,
) -> dict[str, Any]:
    """Expand a pinned H09-H11 specification from the frozen H08 setup."""

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
        "truth_process_standard_deviation",
        "assumed_filter_process_standard_deviation",
        "state_compensation_criterion",
    }
    missing = required - set(specification)
    if missing:
        raise ValueError(
            f"filter-noise specification is missing fields: {sorted(missing)}"
        )
    experiment_id = str(specification["experiment_id"])
    if experiment_id not in EXPECTED_STANDARD_DEVIATIONS:
        raise ValueError(f"unexpected filter-noise experiment identifier: {experiment_id}")
    expected_deviation = EXPECTED_STANDARD_DEVIATIONS[experiment_id]
    if float(specification["assumed_filter_process_standard_deviation"]) != float(
        expected_deviation
    ):
        raise ValueError(f"registered filter-noise value changed for {experiment_id}")
    if float(specification["truth_process_standard_deviation"]) != 1.0:
        raise ValueError("truth process standard deviation must remain exactly 1.0")
    if specification["state_compensation_criterion"] != (
        EXPECTED_STATE_COMPENSATION_CRITERION
    ):
        raise ValueError("registered state-compensation criterion changed")
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

    config = deepcopy(
        load_objective_ablation_config(source, project_root=root)
    )
    if float(
        config["data"]["fixed_lower_groundwater_process_standard_deviation"]
    ) != float(specification["truth_process_standard_deviation"]):
        raise ValueError("expanded H08 truth noise differs from the specification")
    for name in (
        "experiment_id",
        "status",
        "scientific_question",
        "claim_boundary",
        "result_relative_path",
    ):
        config[name] = specification[name]
    config["filter"][
        "assumed_lower_groundwater_process_standard_deviation"
    ] = float(expected_deviation)
    config["filter_noise_sensitivity_specification"] = specification
    return config


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH))
    parser.add_argument("--project-root", default=str(PROJECT_ROOT))
    arguments = parser.parse_args()
    root = Path(arguments.project_root).resolve()
    config = load_common_process_noise_config(
        arguments.config,
        project_root=root,
    )
    print(run_parameter_switch_capability(config, project_root=root))


if __name__ == "__main__":
    main()
