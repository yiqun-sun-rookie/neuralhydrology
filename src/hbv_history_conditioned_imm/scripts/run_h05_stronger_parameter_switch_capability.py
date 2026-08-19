"""Run the registered stronger-spacing H05 parameter-switch capability test."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from hbv_history_conditioned_imm.scripts.run_h01_end_to_end_smoke import _sha256
from hbv_history_conditioned_imm.scripts.run_h04_parameter_switch_capability import (
    PACKAGE_ROOT,
    run_parameter_switch_capability,
)


DEFAULT_CONFIG_PATH = (
    PACKAGE_ROOT / "configs" / "h05_stronger_parameter_switch_capability_v01.json"
)


def load_h05_config(path: str | Path) -> dict[str, Any]:
    with Path(path).open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    required = {
        "experiment_id",
        "result_relative_path",
        "source_h04_config",
        "base_parameter_source",
        "base_parameters",
        "parameter_candidates",
        "data",
        "seeds",
        "filter",
        "forecast",
        "network",
        "training",
        "loss",
        "capability_gates",
        "required_result_files",
    }
    missing = required - set(config)
    if missing:
        raise ValueError(f"H05 configuration is missing fields: {sorted(missing)}")
    if config["experiment_id"] != "h05_stronger_parameter_switch_capability_v01":
        raise ValueError("unexpected H05 experiment identifier")
    return config


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH))
    parser.add_argument("--project-root", default=str(PACKAGE_ROOT.parents[1]))
    arguments = parser.parse_args()
    root = Path(arguments.project_root).resolve()
    config = load_h05_config(arguments.config)
    source = (root / str(config["source_h04_config"]["path"])).resolve()
    if _sha256(source) != str(config["source_h04_config"]["sha256"]):
        raise ValueError("H05 source H04 config hash mismatch")
    print(run_parameter_switch_capability(config, project_root=root))


if __name__ == "__main__":
    main()
