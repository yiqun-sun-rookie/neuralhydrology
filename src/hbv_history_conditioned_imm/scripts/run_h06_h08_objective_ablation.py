"""Run registered no-regularizer transition-objective ablations H06-H08."""

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
from hbv_history_conditioned_imm.scripts.run_h05_stronger_parameter_switch_capability import (
    load_h05_config,
)


PROJECT_ROOT = PACKAGE_ROOT.parents[1]
DEFAULT_CONFIG_PATH = (
    PACKAGE_ROOT / "configs" / "h06_joint_no_transition_regularization_v01.json"
)
EXPECTED_LOSS_WEIGHTS: Mapping[str, Mapping[str, float]] = {
    "h06_joint_no_transition_regularization_v01": {
        "normalized_multilead_flow_mse": 1.0,
        "observation_negative_log_evidence": 0.1,
        "transition_kl_from_base": 0.0,
        "transition_temporal_smoothness": 0.0,
    },
    "h07_forecast_only_no_transition_regularization_v01": {
        "normalized_multilead_flow_mse": 1.0,
        "observation_negative_log_evidence": 0.0,
        "transition_kl_from_base": 0.0,
        "transition_temporal_smoothness": 0.0,
    },
    "h08_evidence_only_no_transition_regularization_v01": {
        "normalized_multilead_flow_mse": 0.0,
        "observation_negative_log_evidence": 0.1,
        "transition_kl_from_base": 0.0,
        "transition_temporal_smoothness": 0.0,
    },
}


def load_objective_ablation_config(
    path: str | Path,
    *,
    project_root: str | Path = PROJECT_ROOT,
) -> dict[str, Any]:
    """Expand a pinned H06-H08 objective specification into the full H05 setup."""

    specification_path = Path(path).resolve()
    with specification_path.open("r", encoding="utf-8") as handle:
        specification = json.load(handle)
    required = {
        "experiment_id",
        "status",
        "scientific_question",
        "claim_boundary",
        "result_relative_path",
        "source_h05_config",
        "loss",
    }
    missing = required - set(specification)
    if missing:
        raise ValueError(
            f"objective-ablation specification is missing fields: {sorted(missing)}"
        )
    experiment_id = str(specification["experiment_id"])
    if experiment_id not in EXPECTED_LOSS_WEIGHTS:
        raise ValueError(f"unexpected objective-ablation identifier: {experiment_id}")
    if specification["loss"] != EXPECTED_LOSS_WEIGHTS[experiment_id]:
        raise ValueError(f"registered loss weights changed for {experiment_id}")
    expected_result_path = (
        "results/23_hbv_multilead_joint_uncertainty/" + experiment_id
    )
    if specification["result_relative_path"] != expected_result_path:
        raise ValueError(f"unexpected result path for {experiment_id}")

    root = Path(project_root).resolve()
    source_specification = specification["source_h05_config"]
    source = (root / str(source_specification["path"])).resolve()
    if _sha256(source) != str(source_specification["sha256"]):
        raise ValueError("H05 source config hash mismatch")

    config = deepcopy(load_h05_config(source))
    for name in (
        "experiment_id",
        "status",
        "scientific_question",
        "claim_boundary",
        "result_relative_path",
    ):
        config[name] = specification[name]
    config["loss"].update(specification["loss"])
    config["objective_ablation_specification"] = specification
    return config


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH))
    parser.add_argument("--project-root", default=str(PROJECT_ROOT))
    arguments = parser.parse_args()
    root = Path(arguments.project_root).resolve()
    config = load_objective_ablation_config(
        arguments.config,
        project_root=root,
    )
    print(run_parameter_switch_capability(config, project_root=root))


if __name__ == "__main__":
    main()
